import SwiftUI
import ImageIO
import AnimeCore

// CGImage is immutable after creation. This wrapper is the only unchecked bridge
// between the decoding actor and SwiftUI; mutable UIKit image objects are not shared.
struct ArtworkBitmap: @unchecked Sendable {
    let image: CGImage
    let expiresAt: Date
}

/// Network access and ImageIO decoding run off the main actor. All screens share
/// encoded bytes, while decoded variants are bounded by their actual bitmap cost.
actor ArtworkPipeline {
    static let shared = ArtworkPipeline()
    private struct Key: Hashable, Sendable { let url: URL; let pixels: Int }
    private struct FlightKey: Hashable, Sendable { let image: Key; let refresh: Bool }
    private let data: ArtworkDataClient
    private var cache = BoundedCache<Key, ArtworkBitmap>(maximumCount: 64, maximumCost: 64_000_000)
    private let requests = RequestCoalescer<FlightKey, ArtworkBitmap>()
    private var generation: UInt64 = 0

    init(data: ArtworkDataClient = ArtworkDataClient()) { self.data = data }
    func image(at url: URL, pixels: Int, refresh: Bool = false) async throws -> ArtworkBitmap {
        try Task.checkCancellation()
        let key = Key(url: url, pixels: min(3200, max(128, pixels)))
        if !refresh, let image = cache.value(for: key) { return image }
        return try await requests.value(for: FlightKey(image: key, refresh: refresh)) {
            try await self.decode(key, refresh: refresh)
        }
    }
    private func decode(_ key: Key, refresh: Bool) async throws -> ArtworkBitmap {
        if !refresh, let image = cache.value(for: key) { return image }
        if refresh { generation &+= 1; cache.remove { $0.url == key.url } }
        let started = generation
        let bytes = try await data.image(at: key.url, refresh: refresh)
        try Task.checkCancellation()
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceShouldCacheImmediately: true,
                                kCGImageSourceThumbnailMaxPixelSize: key.pixels]
        guard let source = CGImageSourceCreateWithData(bytes.data as CFData, options),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            await data.discard(key.url)
            throw ArtworkError.invalidData
        }
        try Task.checkCancellation()
        let result = ArtworkBitmap(image: image, expiresAt: bytes.expiresAt)
        if generation == started {
            cache.insert(result, for: key, cost: image.bytesPerRow * image.height, expiresAt: bytes.expiresAt)
        }
        return result
    }
    func clearMemory() async {
        generation &+= 1; cache.removeAll()
        await data.clearMemory()
    }
    func accent(at url: URL) async -> PosterAccent {
        do {
            let bitmap = try await image(at: url, pixels: 128)
            try Task.checkCancellation()
            return PosterColor.sample(bitmap.image) ?? .fallback
        } catch { return .fallback }
    }
}

@MainActor
struct ArtworkPhaseView<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    var pointSize: CGFloat = 320
    var retryToken = 0
    var pipeline = ArtworkPipeline.shared
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @State private var phase = AsyncImagePhase.empty
    @State private var loaded: LoadID?
    @State private var lastRetry = 0

    private struct LoadID: Hashable { let url: URL?; let pixels: Int; let retry: Int }
    private var id: LoadID {
        LoadID(url: url, pixels: ArtworkSizing.pixelLimit(points: Double(pointSize), scale: Double(displayScale)), retry: retryToken)
    }
    var body: some View {
        content(loaded == id ? phase : .empty)
            .task(id: id) {
                let requested = id
                let refresh = lastRetry != retryToken; lastRetry = retryToken
                loaded = requested; phase = .empty
                guard let url = requested.url else { return }
                do {
                    let bitmap = try await pipeline.image(at: url, pixels: requested.pixels, refresh: refresh)
                    guard !Task.isCancelled, loaded == requested else { return }
                    phase = .success(Image(decorative: bitmap.image, scale: displayScale))
                } catch is CancellationError {} catch {
                    guard !Task.isCancelled, loaded == requested else { return }
                    phase = .failure(error)
                }
            }
    }
}

@MainActor
struct ArtworkImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var pointSize: CGFloat = 320
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    var body: some View {
        ArtworkPhaseView(url: url, pointSize: pointSize) { phase in
            if let image = phase.image { content(image) }
            else { placeholder() }
        }
    }
}
