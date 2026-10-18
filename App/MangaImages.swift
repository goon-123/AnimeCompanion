import SwiftUI
import ImageIO
import AnimeCore

struct MangaBitmap: @unchecked Sendable {
    let image: CGImage
    var ratio: Double { Double(image.height) / Double(image.width) }
    var cost: Int { image.bytesPerRow * image.height }
}

struct MangaImageKey: Hashable, Sendable {
    let source: String
    let version: String
    let page: SourceMangaImage
}

/// Reader images never enter the anime artwork/account caches. Decode work is
/// off-main, with separate bounded byte/bitmap caches and cancellation coalescing.
actor MangaImagePipeline {
    static let shared = MangaImagePipeline()
    private struct Variant: Hashable, Sendable { let key: MangaImageKey; let width: Int }
    private var bytes = BoundedCache<MangaImageKey, Data>(maximumCount: 64, maximumCost: 32_000_000)
    private var images = BoundedCache<Variant, MangaBitmap>(maximumCount: 32, maximumCost: 64_000_000)
    private let downloads = RequestCoalescer<MangaImageKey, Data>()
    private let decodes = RequestCoalescer<Variant, MangaBitmap>()
    private var generation: UInt64 = 0
    func image(key: MangaImageKey, width: Int, refresh: Bool = false,
               loader: @escaping @Sendable () async throws -> Data) async throws -> MangaBitmap {
        let variant = Variant(key: key, width: [256, 512, 800, 1200, 1600].first { $0 >= width } ?? 1600)
        if refresh {
            generation &+= 1; bytes.remove(key); images.remove { $0.key == key }
        } else if let value = images.value(for: variant) { return value }
        let started = generation
        let data: Data
        if let cached = bytes.value(for: key) { data = cached }
        else {
            data = try await downloads.value(for: key, operation: loader)
            try Task.checkCancellation()
            guard !data.isEmpty, data.count <= 16_000_000 else { throw ArtworkError.tooLarge }
            if generation == started { bytes.insert(data, for: key, cost: data.count, expiresAt: Date().addingTimeInterval(300)) }
        }
        return try await decodes.value(for: variant) { try await self.decode(data, variant: variant, generation: started) }
    }
    private func decode(_ data: Data, variant: Variant, generation started: UInt64) throws -> MangaBitmap {
        try Task.checkCancellation()
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0, width * height <= 100_000_000 else { throw ArtworkError.invalidData }
        // A tall strip must retain its aspect ratio. Bound bitmap area, rather
        // than shrinking its longest edge to a cover-sized thumbnail.
        let scale = min(1, Double(variant.width) / width, sqrt(8_000_000 / (width * height)))
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(max(width, height) * scale)))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else { throw ArtworkError.invalidData }
        try Task.checkCancellation()
        let value = MangaBitmap(image: image)
        if generation == started { images.insert(value, for: variant, cost: value.cost, expiresAt: Date().addingTimeInterval(300)) }
        return value
    }
    func clearMemory() { generation &+= 1; bytes.removeAll(); images.removeAll() }
}

@MainActor
struct MangaCover: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    let title: MangaTitleReference
    var width: CGFloat = 180
    @Environment(\.displayScale) private var scale
    @State private var bitmap: MangaBitmap?
    private var image: SourceMangaImage {
        let raw = title.manga.thumbnailURL
        let url = URL(string: raw, relativeTo: URL(string: title.source.homeURL))?.absoluteURL.absoluteString ?? ""
        return SourceMangaImage(index: 0, imageURL: raw.isEmpty ? "" : url)
    }
    private var key: MangaImageKey { MangaImageKey(source: title.source.id, version: extensions.imageVersion(title.source), page: image) }
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let bitmap { Image(decorative: bitmap.image, scale: scale).resizable().scaledToFill() }
                else {
                    LinearGradient(colors: [Color(red: 0.19, green: 0.23, blue: 0.37), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay { Image(systemName: "book.closed").font(.system(size: max(18, geometry.size.width * 0.18))).foregroundStyle(.white.opacity(0.35)) }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
            .task(id: key) {
                bitmap = nil
                guard !image.imageURL.isEmpty else { return }
                let request = image, source = title.source, requested = key, store = extensions
                do {
                    let value = try await MangaImagePipeline.shared.image(key: requested, width: Int(width * scale)) {
                        try await store.imageData(source, image: request)
                    }
                    guard !Task.isCancelled, requested == key else { return }; bitmap = value
                } catch {}
            }
            .onDisappear { bitmap = nil }
    }
}
