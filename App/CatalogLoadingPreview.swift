#if DEBUG
import UIKit
import AnimeCore

/// Owned, delayed artwork makes catalog arrival testable without any public service.
struct CatalogArtworkPreviewTransport: HTTPTransport {
    @MainActor private static var poster: Data?
    @MainActor private static var banner: Data?
    @MainActor private static var visualCards: [String: Data] = [:]
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              url.host == "catalog-preview.invalid" || (["u.livechart.me", "cdn.myanimelist.net"].contains(url.host ?? "") && url.path.hasPrefix("/owned-visuals/")) else { throw ArtworkError.invalidURL }
        try await Task.sleep(for: .milliseconds(350))
        let data = await Self.artwork(url)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=120"]) else { throw ArtworkError.invalidData }
        return (data, response)
    }
    @MainActor private static func artwork(_ url: URL) -> Data {
        if url.path.hasPrefix("/owned-visuals/") { return visualCard(url) }
        let wide = url.path.contains("banner")
        if let cached = wide ? banner : poster { return cached }
        let size = CGSize(width: wide ? 1100 : 600, height: wide ? 450 : 900)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.09, green: 0.16, blue: 0.28, alpha: 1).cgColor,
                          UIColor(red: 0.45, green: 0.33, blue: 0.55, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.25).cgColor); cg.setLineWidth(2)
            for index in 0..<6 {
                let side = CGFloat(index) * 75 + 60
                cg.strokeEllipse(in: CGRect(x: size.width * 0.5 - side / 2, y: size.height * 0.42 - side / 2, width: side, height: side))
            }
            ("CATALOG\nPREVIEW" as NSString).draw(at: CGPoint(x: 44, y: size.height * 0.72), withAttributes: [
                .font: UIFont.systemFont(ofSize: wide ? 35 : 46, weight: .bold), .foregroundColor: UIColor.white
            ])
        }
        if wide { banner = data } else { poster = data }
        return data
    }
    @MainActor private static func visualCard(_ url: URL) -> Data {
        let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-large", with: "")
        if let data = visualCards[name] { return data }
        let colors: [String: UIColor] = ["roxy": .systemBlue, "sylphiette": .systemGreen, "rudeus": .systemYellow, "eris": .systemRed,
                                        "key-visual": .systemPurple, "teaser-visual": .systemTeal]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).pngData { context in
            (colors[name] ?? .systemIndigo).setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            (String(name.prefix(1)).uppercased() as NSString).draw(at: CGPoint(x: 55, y: 110), withAttributes: [
                .font: UIFont.systemFont(ofSize: 300, weight: .black), .foregroundColor: UIColor.white.withAlphaComponent(0.8)])
            ("OWNED PREVIEW\n\(name.replacingOccurrences(of: "-", with: " ").capitalized)" as NSString).draw(at: CGPoint(x: 40, y: 720), withAttributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: UIColor.white])
        }
        visualCards[name] = data
        return data
    }
}
#endif
