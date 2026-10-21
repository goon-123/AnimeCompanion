//! Real, bounded bitmap codecs and rectangular canvas copies.
//! Extension-owned image transformations continue to execute in DEX bytecode.
use super::image_io_compat::{read_stream, write_stream, BYTE_LIMIT};
use dexvm::vm::error::JvmError;
use dexvm::vm::object::{ArrayData, Native};
use dexvm::vm::{NatErr, NativeEntry, Vm};
use dexvm::JValue;
use image::{ExtendedColorType, ImageDecoder, ImageEncoder, ImageReader};
use std::io::{Cursor, Write};

type R = Result<JValue, NatErr>;
const BITMAP: &str = "Landroid/graphics/Bitmap;";
const PIXEL_LIMIT: usize = 16_000_000;
const LIVE_PIXEL_LIMIT: usize = 32_000_000;
fn config(vm: &mut Vm, value: JValue) -> Result<(), NatErr> {
    if value.is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    match vm.payload_of(value) {
        Some(Native::Enum { name, .. }) if name == "ARGB_8888" || name == "ARGB_4444" => Ok(()),
        _ => Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/UnsupportedOperationException;",
            "Only ARGB_8888 bitmap storage is implemented",
        ))),
    }
}

fn charge(vm: &mut Vm, pixels: usize) -> Result<(), NatErr> {
    let cost = (pixels / 16 + 1) as i64;
    if pixels > PIXEL_LIMIT || vm.budget <= cost {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    vm.budget -= cost;
    Ok(())
}
fn size(vm: &mut Vm, width: i32, height: i32) -> Result<usize, NatErr> {
    if width <= 0 || height <= 0 {
        return Err(NatErr::Throw(
            vm.err_iae("Bitmap dimensions must be positive"),
        ));
    }
    let count = (width as usize)
        .checked_mul(height as usize)
        .ok_or(NatErr::Fatal(JvmError::BudgetExceeded))?;
    if count > PIXEL_LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    Ok(count)
}
fn dimensions(vm: &mut Vm, bitmap: JValue) -> Result<(i32, i32), NatErr> {
    match bitmap {
        JValue::Obj(id) => match vm.arena.objects[id as usize].native.as_ref() {
            Some(Native::Bitmap { width, height, .. }) => Ok((*width, *height)),
            _ => Err(NatErr::Throw(vm.err_iae("Expected bitmap"))),
        },
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn usable(vm: &mut Vm, bitmap: JValue) -> Result<(i32, i32), NatErr> {
    let (width, height) = dimensions(vm, bitmap)?;
    let count = size(vm, width, height)?;
    if !matches!(&vm.arena.objects[bitmap.as_obj() as usize].native,Some(Native::Bitmap{pixels,..}) if pixels.len()==count)
    {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/IllegalStateException;",
            "Bitmap has been recycled",
        )));
    }
    Ok((width, height))
}
fn reserve(vm: &mut Vm, count: usize) -> Result<(), NatErr> {
    let live: usize = vm
        .arena
        .objects
        .iter()
        .filter_map(|o| match &o.native {
            Some(Native::Bitmap { pixels, .. }) => Some(pixels.len()),
            _ => None,
        })
        .sum();
    if live.saturating_add(count) > LIVE_PIXEL_LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    charge(vm, count)
}
fn allocate(vm: &mut Vm, width: i32, height: i32, pixels: Vec<u32>) -> R {
    vm.alloc_native(
        BITMAP,
        Native::Bitmap {
            width,
            height,
            pixels,
        },
    )
    .map_err(NatErr::Fatal)
}
fn create(vm: &mut Vm, args: &[JValue]) -> R {
    config(vm, args[2])?;
    let (w, h) = (args[0].as_int(), args[1].as_int());
    let n = size(vm, w, h)?;
    reserve(vm, n)?;
    allocate(vm, w, h, vec![0; n])
}
fn width(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(dimensions(vm, args[0])?.0))
}
fn height(vm: &mut Vm, args: &[JValue]) -> R {
    Ok(JValue::Int(dimensions(vm, args[0])?.1))
}
fn recycle(vm: &mut Vm, args: &[JValue]) -> R {
    dimensions(vm, args[0])?;
    if let Some(Native::Bitmap { pixels, .. }) =
        &mut vm.arena.objects[args[0].as_obj() as usize].native
    {
        *pixels = Vec::new();
    }
    Ok(JValue::Null)
}
fn recycled(vm: &mut Vm, args: &[JValue]) -> R {
    dimensions(vm, args[0])?;
    Ok(JValue::Int(i32::from(
        matches!(&vm.arena.objects[args[0].as_obj() as usize].native,Some(Native::Bitmap{pixels,..}) if pixels.is_empty()),
    )))
}
fn get_pixel(vm: &mut Vm, args: &[JValue]) -> R {
    let (w, h) = usable(vm, args[0])?;
    let (x, y) = (args[1].as_int(), args[2].as_int());
    if x < 0 || y < 0 || x >= w || y >= h {
        return Err(NatErr::Throw(vm.err_iae("Pixel outside bitmap")));
    }
    match &vm.arena.objects[args[0].as_obj() as usize].native {
        Some(Native::Bitmap { pixels, .. }) => Ok(JValue::Int(
            pixels[y as usize * w as usize + x as usize] as i32,
        )),
        _ => unreachable!(),
    }
}
fn transfer_pixels(vm: &mut Vm, args: &[JValue], write: bool) -> R {
    let (bw, bh) = usable(vm, args[0])?;
    let (offset, stride, x, y, w, h) = (
        i64::from(args[2].as_int()),
        i64::from(args[3].as_int()),
        i64::from(args[4].as_int()),
        i64::from(args[5].as_int()),
        i64::from(args[6].as_int()),
        i64::from(args[7].as_int()),
    );
    if x < 0
        || y < 0
        || w < 0
        || h < 0
        || x + w > i64::from(bw)
        || y + h > i64::from(bh)
        || stride.abs() < w
    {
        return Err(NatErr::Throw(
            vm.err_iae("Pixel region or stride out of bounds"),
        ));
    }
    if w == 0 || h == 0 {
        return Ok(JValue::Null);
    }
    let array_len = match args[1] {
        JValue::Obj(id) => match &vm.arena.objects[id as usize].native {
            Some(Native::Array(ArrayData::Int(values))) => values.len(),
            _ => return Err(NatErr::Throw(vm.err_npe())),
        },
        _ => return Err(NatErr::Throw(vm.err_npe())),
    };
    let last = offset + (h - 1) * stride;
    if offset.min(last) < 0 || offset.max(last) + w > array_len as i64 {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/ArrayIndexOutOfBoundsException;",
            "Pixel array range out of bounds",
        )));
    }
    charge(vm, (w * h) as usize)?;
    let mut region = Vec::with_capacity((w * h) as usize);
    if write {
        let Some(Native::Array(ArrayData::Int(values))) =
            &vm.arena.objects[args[1].as_obj() as usize].native
        else {
            unreachable!()
        };
        for row in 0..h {
            let start = (offset + row * stride) as usize;
            region.extend_from_slice(&values[start..start + w as usize]);
        }
        let Some(Native::Bitmap { pixels, .. }) =
            &mut vm.arena.objects[args[0].as_obj() as usize].native
        else {
            unreachable!()
        };
        for row in 0..h {
            for col in 0..w {
                pixels[((y + row) * i64::from(bw) + x + col) as usize] =
                    region[(row * w + col) as usize] as u32;
            }
        }
    } else {
        let Some(Native::Bitmap { pixels, .. }) =
            &vm.arena.objects[args[0].as_obj() as usize].native
        else {
            unreachable!()
        };
        for row in 0..h {
            let start = ((y + row) * i64::from(bw) + x) as usize;
            region.extend(pixels[start..start + w as usize].iter().map(|p| *p as i32));
        }
        let Some(Native::Array(ArrayData::Int(values))) =
            &mut vm.arena.objects[args[1].as_obj() as usize].native
        else {
            unreachable!()
        };
        for row in 0..h {
            let start = (offset + row * stride) as usize;
            values[start..start + w as usize]
                .copy_from_slice(&region[(row * w) as usize..((row + 1) * w) as usize]);
        }
    }
    Ok(JValue::Null)
}
fn get_pixels(vm: &mut Vm, args: &[JValue]) -> R {
    transfer_pixels(vm, args, false)
}
fn set_pixels(vm: &mut Vm, args: &[JValue]) -> R {
    transfer_pixels(vm, args, true)
}
fn erase(vm: &mut Vm, args: &[JValue]) -> R {
    let (w, h) = usable(vm, args[0])?;
    charge(vm, w as usize * h as usize)?;
    if let Some(Native::Bitmap { pixels, .. }) =
        &mut vm.arena.objects[args[0].as_obj() as usize].native
    {
        pixels.fill(args[1].as_int() as u32);
    }
    Ok(JValue::Null)
}
fn copy(vm: &mut Vm, args: &[JValue]) -> R {
    let (w, h) = usable(vm, args[0])?;
    config(vm, args[1])?;
    reserve(vm, w as usize * h as usize)?;
    let Some(Native::Bitmap { pixels, .. }) = &vm.arena.objects[args[0].as_obj() as usize].native
    else {
        unreachable!()
    };
    let pixels = pixels.clone();
    allocate(vm, w, h, pixels)
}
fn crop(vm: &mut Vm, args: &[JValue]) -> R {
    let (w, h) = usable(vm, args[0])?;
    let (x, y, cw, ch) = (
        args[1].as_int(),
        args[2].as_int(),
        args[3].as_int(),
        args[4].as_int(),
    );
    let n = size(vm, cw, ch)?;
    if x < 0
        || y < 0
        || i64::from(x) + i64::from(cw) > i64::from(w)
        || i64::from(y) + i64::from(ch) > i64::from(h)
    {
        return Err(NatErr::Throw(vm.err_iae("Crop outside bitmap")));
    }
    reserve(vm, n)?;
    let Some(Native::Bitmap { pixels, .. }) = &vm.arena.objects[args[0].as_obj() as usize].native
    else {
        unreachable!()
    };
    let mut result = Vec::with_capacity(n);
    for row in y..y + ch {
        let start = row as usize * w as usize + x as usize;
        result.extend_from_slice(&pixels[start..start + cw as usize]);
    }
    allocate(vm, cw, ch, result)
}

fn decode(vm: &mut Vm, bytes: &[u8]) -> R {
    if bytes.len() > BYTE_LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let mut reader = match ImageReader::new(Cursor::new(bytes)).with_guessed_format() {
        Ok(r) => r,
        Err(_) => return Ok(JValue::Null),
    };
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(65_536);
    limits.max_image_height = Some(65_536);
    limits.max_alloc = Some(128_000_000);
    reader.limits(limits);
    let decoder = match reader.into_decoder() {
        Ok(d) => d,
        Err(image::ImageError::Limits(_)) => return Err(NatErr::Fatal(JvmError::BudgetExceeded)),
        Err(_) => return Ok(JValue::Null),
    };
    let (w, h) = decoder.dimensions();
    let count = size(vm, w as i32, h as i32)?;
    reserve(vm, count)?;
    let image = match image::DynamicImage::from_decoder(decoder) {
        Ok(i) => i,
        Err(image::ImageError::Limits(_)) => return Err(NatErr::Fatal(JvmError::BudgetExceeded)),
        Err(_) => return Ok(JValue::Null),
    };
    let pixels = image
        .to_rgba8()
        .pixels()
        .map(|p| u32::from_be_bytes([p[3], p[0], p[1], p[2]]))
        .collect();
    allocate(vm, w as i32, h as i32, pixels)
}
fn decode_stream(vm: &mut Vm, args: &[JValue]) -> R {
    if args[0].is_null_ref() {
        return Ok(JValue::Null);
    }
    let bytes = read_stream(vm, args[0])?;
    decode(vm, &bytes)
}
fn decode_array(vm: &mut Vm, args: &[JValue]) -> R {
    if args.len() > 3 && !args[3].is_null_ref() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/UnsupportedOperationException;",
            "BitmapFactory.Options decoding is not implemented",
        )));
    }
    let offset = args[1].as_int();
    let length = args[2].as_int();
    let JValue::Obj(array) = args[0] else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    let Some(Native::Array(ArrayData::Byte(bytes))) = &vm.arena.objects[array as usize].native
    else {
        return Err(NatErr::Throw(vm.err_npe()));
    };
    if offset < 0
        || length < 0
        || (offset as usize)
            .checked_add(length as usize)
            .is_none_or(|n| n > bytes.len())
    {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/ArrayIndexOutOfBoundsException;",
            "Invalid image byte range",
        )));
    }
    if length as usize > BYTE_LIMIT {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    let bytes: Vec<u8> = bytes[offset as usize..offset as usize + length as usize]
        .iter()
        .map(|b| *b as u8)
        .collect();
    decode(vm, &bytes)
}

#[derive(Default)]
struct Encoded(Vec<u8>, bool);
impl Write for Encoded {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        if self.0.len().saturating_add(bytes.len()) > BYTE_LIMIT {
            self.1 = true;
            return Err(std::io::Error::other("Encoded image exceeds byte limit"));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
fn compress(vm: &mut Vm, args: &[JValue]) -> R {
    let (w, h) = usable(vm, args[0])?;
    let quality = args[2].as_int();
    if !(0..=100).contains(&quality) {
        return Err(NatErr::Throw(vm.err_iae("Quality must be in 0..100")));
    }
    if args[1].is_null_ref() || args[3].is_null_ref() {
        return Err(NatErr::Throw(vm.err_npe()));
    }
    let format = match vm.payload_of(args[1]) {
        Some(Native::Enum { ordinal, .. }) => ordinal,
        _ => -1,
    };
    if format != 0 && format != 1 {
        return Ok(JValue::Int(0));
    }
    charge(vm, w as usize * h as usize)?;
    let Some(Native::Bitmap { pixels, .. }) = &vm.arena.objects[args[0].as_obj() as usize].native
    else {
        unreachable!()
    };
    let mut raw = Vec::with_capacity(pixels.len() * if format == 0 { 3 } else { 4 });
    for p in pixels {
        raw.extend_from_slice(&[(p >> 16) as u8, (p >> 8) as u8, *p as u8]);
        if format == 1 {
            raw.push((p >> 24) as u8);
        }
    }
    let mut output = Encoded::default();
    let result = if format == 0 {
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut output, quality as u8).encode(
            &raw,
            w as u32,
            h as u32,
            ExtendedColorType::Rgb8,
        )
    } else {
        image::codecs::png::PngEncoder::new(&mut output).write_image(
            &raw,
            w as u32,
            h as u32,
            ExtendedColorType::Rgba8,
        )
    };
    if output.1 {
        return Err(NatErr::Fatal(JvmError::BudgetExceeded));
    }
    if result.is_err() {
        return Ok(JValue::Int(0));
    }
    write_stream(vm, args[3], &output.0)?;
    Ok(JValue::Int(1))
}

fn rect(vm: &mut Vm, value: JValue) -> Result<(i64, i64, i64, i64), NatErr> {
    match vm.payload_of(value) {
        Some(Native::Rect {
            left,
            top,
            right,
            bottom,
        }) => Ok((
            i64::from(left),
            i64::from(top),
            i64::from(right),
            i64::from(bottom),
        )),
        _ => Err(NatErr::Throw(vm.err_npe())),
    }
}
fn rect_initialize(vm: &mut Vm, args: &[JValue]) -> R {
    let (left, top, right, bottom) = match args.len() {
        1 => (0, 0, 0, 0),
        2 => {
            let (l, t, r, b) = rect(vm, args[1])?;
            (l as i32, t as i32, r as i32, b as i32)
        }
        _ => (
            args[1].as_int(),
            args[2].as_int(),
            args[3].as_int(),
            args[4].as_int(),
        ),
    };
    vm.arena.objects[args[0].as_obj() as usize].native = Some(Native::Rect {
        left,
        top,
        right,
        bottom,
    });
    Ok(JValue::Null)
}
fn rect_width(vm: &mut Vm, args: &[JValue]) -> R {
    let (l, _, r, _) = rect(vm, args[0])?;
    Ok(JValue::Int((r as i32).wrapping_sub(l as i32)))
}
fn rect_height(vm: &mut Vm, args: &[JValue]) -> R {
    let (_, t, _, b) = rect(vm, args[0])?;
    Ok(JValue::Int((b as i32).wrapping_sub(t as i32)))
}
fn draw(vm: &mut Vm, args: &[JValue]) -> R {
    let (sw, sh) = usable(vm, args[1])?;
    let (target, transform) = match vm.payload_of(args[0]) {
        Some(Native::Canvas {
            bitmap, transform, ..
        }) => (JValue::Obj(bitmap), transform),
        _ => return Err(NatErr::Throw(vm.err_npe())),
    };
    if transform != [1., 0., 0., 1., 0., 0.] || !args[4].is_null_ref() {
        return Err(NatErr::Throw(vm.throwable_of(
            "Ljava/lang/UnsupportedOperationException;",
            "Bitmap rectangle copies require an untransformed canvas and default paint",
        )));
    }
    let (tw, th) = usable(vm, target)?;
    let (sl, st, sr, sb) = if args[2].is_null_ref() {
        (0, 0, i64::from(sw), i64::from(sh))
    } else {
        rect(vm, args[2])?
    };
    let (dl, dt, dr, db) = rect(vm, args[3])?;
    if sl >= sr || st >= sb || dl >= dr || dt >= db {
        return Ok(JValue::Null);
    }
    if sl < 0 || st < 0 || sr > i64::from(sw) || sb > i64::from(sh) {
        return Err(NatErr::Throw(vm.err_iae("Source rectangle outside bitmap")));
    }
    let (left, top, right, bottom) = (
        dl.max(0),
        dt.max(0),
        dr.min(i64::from(tw)),
        db.min(i64::from(th)),
    );
    if left >= right || top >= bottom {
        return Ok(JValue::Null);
    }
    charge(vm, ((right - left) * (bottom - top)) as usize)?;
    // Snapshot only the crop, including when source and destination are equal.
    charge(vm, ((sr - sl) * (sb - st)) as usize)?;
    let Some(Native::Bitmap { pixels, .. }) = &vm.arena.objects[args[1].as_obj() as usize].native
    else {
        unreachable!()
    };
    let mut crop = Vec::with_capacity(((sr - sl) * (sb - st)) as usize);
    for row in st..sb {
        let begin = (row * i64::from(sw) + sl) as usize;
        crop.extend_from_slice(&pixels[begin..begin + (sr - sl) as usize]);
    }
    let Some(Native::Bitmap { pixels, .. }) =
        &mut vm.arena.objects[target.as_obj() as usize].native
    else {
        unreachable!()
    };
    for y in top..bottom {
        for x in left..right {
            let sx = (x - dl) * (sr - sl) / (dr - dl);
            let sy = (y - dt) * (sb - st) / (db - dt);
            let color = crop[(sy * (sr - sl) + sx) as usize];
            let slot = &mut pixels[(y * i64::from(tw) + x) as usize];
            let a = color >> 24;
            if a == 255 {
                *slot = color;
            } else if a != 0 {
                let da = *slot >> 24;
                let out_a = a + (da * (255 - a) + 127) / 255;
                let mut result = out_a << 24;
                for shift in [0, 8, 16] {
                    let c = (((color >> shift) & 255) * a
                        + (((*slot >> shift) & 255) * da * (255 - a) + 127) / 255
                        + out_a / 2)
                        / out_a;
                    result |= c << shift;
                }
                *slot = result;
            }
        }
    }
    Ok(JValue::Null)
}

pub(super) fn install(vm: &mut Vm) -> Result<(), JvmError> {
    let enum_class = vm.ensure_class_by_desc("Ljava/lang/Enum;")?;
    for (class, names) in [
        (
            "Landroid/graphics/Bitmap$Config;",
            &[
                "ALPHA_8",
                "RGB_565",
                "ARGB_4444",
                "ARGB_8888",
                "RGBA_F16",
                "HARDWARE",
                "RGBA_1010102",
            ][..],
        ),
        (
            "Landroid/graphics/Bitmap$CompressFormat;",
            &["JPEG", "PNG", "WEBP", "WEBP_LOSSY", "WEBP_LOSSLESS"][..],
        ),
    ] {
        let id = vm.ensure_class_by_desc(class)?;
        vm.classes[id as usize].superclass = Some(enum_class);
        for (ordinal, name) in names.iter().enumerate() {
            let value = vm.alloc_native(
                class,
                Native::Enum {
                    name: (*name).into(),
                    ordinal: ordinal as i32,
                },
            )?;
            super::multipart_compat::static_value(vm, class, name, class, value)?;
        }
    }
    for (name, sig, f) in [
        (
            "<init>",
            "()V",
            rect_initialize as fn(&mut Vm, &[JValue]) -> R,
        ),
        ("<init>", "(IIII)V", rect_initialize),
        ("<init>", "(Landroid/graphics/Rect;)V", rect_initialize),
        ("set", "(IIII)V", rect_initialize),
        ("set", "(Landroid/graphics/Rect;)V", rect_initialize),
        ("width", "()I", rect_width),
        ("height", "()I", rect_height),
    ] {
        vm.register_native(NativeEntry {
            class: "Landroid/graphics/Rect;",
            name,
            sig,
            instance: true,
            f,
        })?;
    }
    for (name, sig, instance, f) in [
        (
            "createBitmap",
            "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;",
            false,
            create as fn(&mut Vm, &[JValue]) -> R,
        ),
        (
            "createBitmap",
            "(Landroid/graphics/Bitmap;IIII)Landroid/graphics/Bitmap;",
            false,
            crop,
        ),
        ("getWidth", "()I", true, width),
        ("getHeight", "()I", true, height),
        ("getPixel", "(II)I", true, get_pixel),
        ("getPixels", "([IIIIIII)V", true, get_pixels),
        ("setPixels", "([IIIIIII)V", true, set_pixels),
        ("eraseColor", "(I)V", true, erase),
        (
            "copy",
            "(Landroid/graphics/Bitmap$Config;Z)Landroid/graphics/Bitmap;",
            true,
            copy,
        ),
        ("recycle", "()V", true, recycle),
        ("isRecycled", "()Z", true, recycled),
        (
            "compress",
            "(Landroid/graphics/Bitmap$CompressFormat;ILjava/io/OutputStream;)Z",
            true,
            compress,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: BITMAP,
            name,
            sig,
            instance,
            f,
        })?;
    }
    for (name, sig, f) in [
        (
            "decodeStream",
            "(Ljava/io/InputStream;)Landroid/graphics/Bitmap;",
            decode_stream as fn(&mut Vm, &[JValue]) -> R,
        ),
        (
            "decodeByteArray",
            "([BII)Landroid/graphics/Bitmap;",
            decode_array,
        ),
        (
            "decodeByteArray",
            "([BIILandroid/graphics/BitmapFactory$Options;)Landroid/graphics/Bitmap;",
            decode_array,
        ),
    ] {
        vm.register_native(NativeEntry {
            class: "Landroid/graphics/BitmapFactory;",
            name,
            sig,
            instance: false,
            f,
        })?;
    }
    vm.register_native(NativeEntry{class:"Landroid/graphics/Canvas;",name:"drawBitmap",sig:"(Landroid/graphics/Bitmap;Landroid/graphics/Rect;Landroid/graphics/Rect;Landroid/graphics/Paint;)V",instance:true,f:draw})?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rectangle_copies_clip_and_pixel_arrays_support_negative_stride() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let source = allocate(
            &mut vm,
            2,
            2,
            vec![0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff],
        )
        .unwrap();
        let target = allocate(&mut vm, 2, 2, vec![0; 4]).unwrap();
        let canvas = vm
            .alloc_native(
                "Landroid/graphics/Canvas;",
                Native::Canvas {
                    bitmap: target.as_obj(),
                    transform: [1., 0., 0., 1., 0., 0.],
                    stack: vec![],
                },
            )
            .unwrap();
        let dst = vm
            .alloc_native(
                "Landroid/graphics/Rect;",
                Native::Rect {
                    left: -1,
                    top: 0,
                    right: 1,
                    bottom: 2,
                },
            )
            .unwrap();
        draw(&mut vm, &[canvas, source, JValue::Null, dst, JValue::Null]).unwrap();
        assert_eq!(
            get_pixel(&mut vm, &[target, JValue::Int(0), JValue::Int(0)])
                .unwrap()
                .as_int() as u32,
            0xff00ff00
        );
        assert_eq!(
            get_pixel(&mut vm, &[target, JValue::Int(0), JValue::Int(1)])
                .unwrap()
                .as_int() as u32,
            0xffffffff
        );
        let invalid = vm
            .alloc_native(
                "Landroid/graphics/Rect;",
                Native::Rect {
                    left: i32::MIN,
                    top: 0,
                    right: i32::MAX,
                    bottom: 2,
                },
            )
            .unwrap();
        assert!(draw(&mut vm, &[canvas, source, invalid, dst, JValue::Null]).is_err());
        let array = vm
            .alloc_native("[I", Native::Array(ArrayData::Int(vec![0; 4])))
            .unwrap();
        let args = [
            source,
            array,
            JValue::Int(2),
            JValue::Int(-2),
            JValue::Int(0),
            JValue::Int(0),
            JValue::Int(2),
            JValue::Int(2),
        ];
        get_pixels(&mut vm, &args).unwrap();
        assert!(
            matches!(vm.payload_of(array),Some(Native::Array(ArrayData::Int(p))) if p==vec![0xff0000ffu32 as i32,-1,0xffff0000u32 as i32,0xff00ff00u32 as i32])
        );
        let mut set = args;
        set[0] = target;
        set_pixels(&mut vm, &set).unwrap();
        assert_eq!(
            get_pixel(&mut vm, &[target, JValue::Int(1), JValue::Int(1)])
                .unwrap()
                .as_int(),
            -1
        );
        let mut bad = args;
        bad[2] = JValue::Int(-1);
        assert!(get_pixels(&mut vm, &bad).is_err());
        recycle(&mut vm, &[source]).unwrap();
        assert!(draw(&mut vm, &[canvas, source, JValue::Null, dst, JValue::Null]).is_err());
    }
    #[test]
    fn codecs_ranges_recycling_and_overflow_are_real_and_bounded() {
        let mut vm = Vm::new(vec![], Box::new(std::io::sink())).unwrap();
        install(&mut vm).unwrap();
        let mut encoded = Vec::new();
        image::codecs::png::PngEncoder::new(&mut encoded)
            .write_image(
                &[250, 30, 60, 255, 10, 220, 40, 255],
                2,
                1,
                ExtendedColorType::Rgba8,
            )
            .unwrap();
        let mut padded = vec![1, 2, 3];
        padded.extend_from_slice(&encoded);
        padded.push(4);
        let array = vm
            .alloc_native(
                "[B",
                Native::Array(ArrayData::Byte(
                    padded.into_iter().map(|b| b as i8).collect(),
                )),
            )
            .unwrap();
        let bitmap = vm
            .invoke_static(
                "Landroid/graphics/BitmapFactory;",
                "decodeByteArray",
                "([BII)Landroid/graphics/Bitmap;",
                vec![array, JValue::Int(3), JValue::Int(encoded.len() as i32)],
            )
            .unwrap();
        assert_eq!(
            get_pixel(&mut vm, &[bitmap, JValue::Int(0), JValue::Int(0)])
                .unwrap()
                .as_int() as u32,
            0xfffa1e3c
        );
        assert!(decode_array(&mut vm, &[array, JValue::Int(-1), JValue::Int(1)]).is_err());
        for format in [0, 1] {
            let fmt = vm
                .alloc_native(
                    "Landroid/graphics/Bitmap$CompressFormat;",
                    Native::Enum {
                        name: if format == 0 { "JPEG" } else { "PNG" }.into(),
                        ordinal: format,
                    },
                )
                .unwrap();
            let stream = vm
                .alloc_native(
                    "Ljava/io/ByteArrayOutputStream;",
                    Native::ByteArrayOutputStream(vec![]),
                )
                .unwrap();
            assert_eq!(
                compress(&mut vm, &[bitmap, fmt, JValue::Int(90), stream]).unwrap(),
                JValue::Int(1)
            );
            let Some(Native::ByteArrayOutputStream(bytes)) = vm.payload_of(stream) else {
                panic!()
            };
            assert_eq!(image::load_from_memory(&bytes).unwrap().width(), 2);
        }
        assert!(matches!(
            size(&mut vm, i32::MAX, i32::MAX),
            Err(NatErr::Fatal(JvmError::BudgetExceeded))
        ));
        assert!(crop(
            &mut vm,
            &[
                bitmap,
                JValue::Int(i32::MAX),
                JValue::Int(0),
                JValue::Int(2),
                JValue::Int(1)
            ]
        )
        .is_err());
        recycle(&mut vm, &[bitmap]).unwrap();
        assert_eq!(recycled(&mut vm, &[bitmap]).unwrap(), JValue::Int(1));
        assert!(get_pixel(&mut vm, &[bitmap, JValue::Int(0), JValue::Int(0)]).is_err());
        assert!(decode(&mut vm, b"broken image").unwrap().is_null_ref());
    }
}
