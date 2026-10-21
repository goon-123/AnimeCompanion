# Owned image fixtures

These synthetic files contain no source or chapter content. They are shared by
the Rust exact-APK tests and Swift/C/Rust native-bridge tests.

`owned-bands.png`, `.jpg` and `.webp` contain ten horizontal color bands in a
32 × 163 image. Bands 0–8 are 16 pixels high; band 9 is 19 pixels high. From top
to bottom the RGB colors are `(240,32,32)`, `(32,220,32)`, `(32,32,240)`,
`(230,210,32)`, `(210,32,210)`, `(32,210,210)`, `(240,140,32)`, `(140,80,210)`,
`(80,170,100)` and `(180,140,100)`. Pillow generated PNG, lossless WebP and JPEG
with quality 100/subsampling 0 from those pixels. The tests compare decoded
colors with tolerance for the extension's JPEG quality-90 output.

`owned-animation.gif` is a looping 3 × 2 GIF with a red frame for 100 ms and a
blue frame for 200 ms. Tests require byte-for-byte preservation, including its
animation metadata. The `.gz` files wrap the corresponding canonical files
with Python `gzip.compress(data, mtime=0)`.

The published APK decides the strip count and performs the transformation. Test
expectations list source strip starts independently for the 10-, 16- and 8-strip
branches, including the remainder pixels. No Jinman-specific decoder is added
to production code.
