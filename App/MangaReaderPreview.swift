#if DEBUG
import UIKit
import AnimeCore

/// Owned artwork and stories for native UI/image tests. Excluded from Release.
@MainActor
enum MangaReaderPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-webtoon-preview") }
    static let package = "eu.kanade.tachiyomi.extension.en.webtoonpreview"
    static func owns(_ id: String) -> Bool { active && id == package }
    static let runtimeSource = MangaRuntimeSource(index: 0, id: "preview-en", name: "Glass House", language: "en",
        homeURL: "https://webtoon-preview.invalid", supportsLatest: true)
    static let descriptor: MangaExtensionDescriptor = {
        let value: [String: Any] = [
            "name": "Glass House", "packageName": package, "apiVersion": "1.6", "versionCode": 1, "versionName": "1.6.0",
            "apkURL": "https://webtoon-preview.invalid/source.apk", "contentWarning": 0, "sha256": String(repeating: "a", count: 64),
            "sources": [["id": "preview-en", "name": "Glass House", "language": "en", "homeURL": "https://webtoon-preview.invalid"]]
        ]
        return try! JSONDecoder().decode(MangaExtensionDescriptor.self, from: JSONSerialization.data(withJSONObject: value))
    }()
    static var extensionState: MangaExtensionState {
        let inspection = MangaExtensionInspectionPreview.make(package: package, source: runtimeSource)
        var value = MangaExtensionState()
        value.installations = [try! InstalledMangaExtension(descriptor: descriptor, inspection: inspection)]
        return value
    }
    static let titles = ["The Glass Harbor", "Orbit Runner", "Lanterns After Rain", "A Map of Tomorrow", "Silent Tide", "Blue Hour"]
        .enumerated().map { index, title in
            SourceManga(url: "/series/\(index)", title: title, author: "AnimeCompanion Preview", description:
                "An original preview story about a quiet harbor, a missing map, and the lights that appear after the last ferry. Artwork in this preview is drawn by the app for testing.",
                genre: "Adventure, Fantasy, Webtoon", status: 2, thumbnailURL: "https://webtoon-preview.invalid/cover/\(index)")
        }
    static func browse(query: String, page: Int) -> SourceMangaPage {
        SourceMangaPage(mangas: page == 1 ? titles.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } : [], hasNext: false)
    }
    static func book(_ manga: SourceManga) -> MangaBook {
        MangaBook(manga: manga, chapters: (1...4).reversed().map {
            SourceMangaChapter(url: manga.url + "/chapter/\($0)", name: "Chapter \($0)", uploadedAt: 1_790_000_000_000,
                              scanlator: "Owned preview", chapterNumber: Double($0))
        })
    }
    static func pages(_ chapter: SourceMangaChapter) -> [SourceMangaImage] {
        (0..<8).map { SourceMangaImage(index: 30 - $0, url: chapter.url,
            imageURL: "https://webtoon-preview.invalid\(chapter.url)/page/\($0)") }
    }
    private static var failed = Set<String>()
    static func image(_ image: SourceMangaImage) throws -> Data {
        // Keep the failure beyond the initial preload window, so a canceled
        // preload cannot consume the one-shot failure before the retry test.
        if ProcessInfo.processInfo.arguments.contains("--ui-webtoon-failed-page"), image.imageURL.hasSuffix("/page/5"),
           failed.insert(image.imageURL).inserted { throw ArtworkError.invalidData }
        let cover = image.imageURL.contains("/cover/")
        let index = Int(image.imageURL.split(separator: "/").last ?? "0") ?? 0
        let size = CGSize(width: 600, height: cover ? 900 : (index == 0 ? 2400 : 1300))
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true; return f
        }())
        return renderer.pngData { context in
            let cg = context.cgContext
            let palettes: [[UIColor]] = [
                [UIColor(red: 0.08, green: 0.25, blue: 0.35, alpha: 1), UIColor(red: 0.25, green: 0.65, blue: 0.67, alpha: 1)],
                [UIColor(red: 0.12, green: 0.10, blue: 0.31, alpha: 1), UIColor(red: 0.65, green: 0.46, blue: 0.77, alpha: 1)],
                [UIColor(red: 0.36, green: 0.18, blue: 0.17, alpha: 1), UIColor(red: 0.87, green: 0.60, blue: 0.33, alpha: 1)]
            ]
            let colors = palettes[index % palettes.count]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            for panel in 0..<(cover ? 4 : Int(size.height / 350)) {
                let rect = CGRect(x: 34, y: CGFloat(panel) * 350 + 40, width: 532, height: 300)
                cg.setFillColor(UIColor.black.withAlphaComponent(0.20).cgColor); cg.fill(rect)
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor); cg.setLineWidth(2); cg.stroke(rect.insetBy(dx: 14, dy: 14))
                cg.setFillColor(colors[1].withAlphaComponent(0.65).cgColor)
                cg.fillEllipse(in: CGRect(x: 280, y: rect.minY + 30, width: 190, height: 190))
                let text = cover ? titles[index % titles.count].title : "Page \(index + 1) · Panel \(panel + 1)"
                (text as NSString).draw(in: CGRect(x: 62, y: rect.minY + 200, width: 450, height: 90),
                    withAttributes: [.font: UIFont.systemFont(ofSize: cover ? 42 : 28, weight: .bold), .foregroundColor: UIColor.white])
            }
        }
    }
}

private enum MangaExtensionInspectionPreview {
    static func make(package: String, source: MangaRuntimeSource) -> MangaExtensionInspection {
        let data = try! JSONEncoder().encode(source)
        let item = try! JSONSerialization.jsonObject(with: data)
        return try! JSONDecoder().decode(MangaExtensionInspection.self, from:
            JSONSerialization.data(withJSONObject: ["packageName": package, "versionName": "1.6.0", "sources": [item]]))
    }
}
#endif
