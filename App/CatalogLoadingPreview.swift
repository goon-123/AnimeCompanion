#if DEBUG
import UIKit
import AnimeCore

/// Owned, delayed artwork makes catalog arrival testable without any public service.
struct CatalogArtworkPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.host == "catalog-preview.invalid" else { throw ArtworkError.invalidURL }
        try await Task.sleep(for: .milliseconds(350))
        let data = await Self.artwork(url)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=120"]) else { throw ArtworkError.invalidData }
        return (data, response)
    }
    @MainActor private static func artwork(_ url: URL) -> Data {
        let wide = url.path.contains("banner")
        let size = CGSize(width: wide ? 1100 : 600, height: wide ? 450 : 900)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
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
    }
}
#endif
