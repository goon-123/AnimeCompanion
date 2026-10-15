#if DEBUG
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import AnimeCore

/// Offline native checks exercise the production pipeline and phase view.
/// Synthetic images, controls and diagnostics are entirely excluded from Release.
@MainActor
struct ArtworkPerformancePreview: View {
    @StateObject private var model = ArtworkPerformanceModel()
    @State private var retry = 0
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Offline artwork checks").font(.title2)
                ForEach(model.results, id: \.id) { result in
                    Text(result.value).accessibilityIdentifier(result.id)
                }
                Text(model.status).accessibilityIdentifier("artwork-check-status")
                ArtworkPhaseView(url: ArtworkFixtureTransport.retryURL, pointSize: 150, retryToken: retry, pipeline: model.pipeline) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(height: 100)
                        Text("Artwork ready").accessibilityIdentifier("artwork-preview-phase")
                    case .failure:
                        Text("Artwork unavailable").accessibilityIdentifier("artwork-preview-phase")
                        Button("Retry artwork") { retry += 1 }.buttonStyle(.bordered)
                            .accessibilityIdentifier("artwork-preview-retry")
                    default: ProgressView("Loading artwork")
                    }
                }
            }.padding(24).frame(maxWidth: .infinity)
        }.task { await model.run() }
    }
}

@MainActor
private final class ArtworkPerformanceModel: ObservableObject {
    struct Result { let id: String; let value: String }
    let pipeline: ArtworkPipeline
    private let transport: ArtworkFixtureTransport
    @Published private(set) var results: [Result] = []
    @Published private(set) var status = "Running"
    private var started = false
    init() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 1024), format: format)
        let poster = renderer.image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2048, height: 1024))
        }
        let oriented = NSMutableData()
        if let cgImage = poster.cgImage,
           let destination = CGImageDestinationCreateWithData(oriented as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
        transport = ArtworkFixtureTransport(poster: poster.pngData() ?? Data(), oriented: oriented as Data)
        pipeline = ArtworkPipeline(data: ArtworkDataClient(transport: transport))
    }
    func run() async {
        guard !started else { return }; started = true
        do {
            let url = ArtworkFixtureTransport.posterURL
            async let first = pipeline.image(at: url, pixels: 512)
            async let duplicate = pipeline.image(at: url, pixels: 512)
            async let accent = pipeline.accent(at: url)
            let (image, shared, color) = try await (first, duplicate, accent)
            let downloads = await transport.posterDownloads
            record("artwork-shared-downloads", "Shared downloads: \(downloads)")
            record("artwork-small-bitmap", "Bitmap: \(image.image.width) × \(image.image.height)")
            record("artwork-poster-color", color.red > 0.9 && color.green < 0.1 && color.blue < 0.1 ? "Poster color: red" : "Poster color: incorrect")
            let cached = try await pipeline.image(at: url, pixels: 512)
            record("artwork-decoded-reuse", image.image === cached.image && image.image === shared.image ? "Decoded bitmap: reused" : "Decoded bitmap: different")
            await pipeline.clearMemory()
            _ = try await pipeline.image(at: url, pixels: 512)
            record("artwork-memory-clear", "Downloads after clear: \(await transport.posterDownloads)")
            _ = try await pipeline.image(at: url, pixels: 512, refresh: true)
            let bypassed = await transport.lastPosterBypassedCache
            record("artwork-refresh", "Downloads after refresh: \(await transport.posterDownloads), bypass: \(bypassed)")
            let rotated = try await pipeline.image(at: ArtworkFixtureTransport.orientedURL, pixels: 512)
            record("artwork-orientation", "Oriented bitmap: \(rotated.image.width) × \(rotated.image.height)")
            status = "Complete"
        } catch { status = "Failed: \(error.localizedDescription)" }
    }
    private func record(_ id: String, _ value: String) { results.append(Result(id: id, value: value)) }
}

private actor ArtworkFixtureTransport: HTTPTransport {
    static let posterURL = URL(string: "https://artwork.example.test/poster.png")!
    static let orientedURL = URL(string: "https://artwork.example.test/oriented.jpg")!
    static let retryURL = URL(string: "https://artwork.example.test/retry.png")!
    let poster: Data
    let oriented: Data
    private var retryDownloads = 0
    private(set) var posterDownloads = 0
    private(set) var lastPosterBypassedCache = false
    init(poster: Data, oriented: Data) { self.poster = poster; self.oriented = oriented }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw ArtworkError.invalidURL }
        let bytes: Data
        if url == Self.retryURL {
            retryDownloads += 1
            bytes = retryDownloads == 1 ? Data("Invalid image fixture".utf8) : poster
        } else if url == Self.orientedURL { bytes = oriented }
        else if url == Self.posterURL {
            posterDownloads += 1
            lastPosterBypassedCache = request.cachePolicy == .reloadIgnoringLocalCacheData
            bytes = poster
        } else { throw ArtworkError.invalidURL }
        // A small bounded delay lets independent native image/color consumers overlap.
        try await Task.sleep(nanoseconds: 50_000_000)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                            headerFields: ["Content-Type": url == Self.orientedURL ? "image/jpeg" : "image/png", "Cache-Control": "max-age=120"]) else { throw ServiceError.invalidResponse }
        return (bytes, response)
    }
}
#endif
