import Foundation

/// A small host-generated diagnostic, separate from private guest VM traces.
public struct MangaRuntimeIssue: Decodable, LocalizedError, Equatable, Sendable {
    public let kind: String
    public let api: String?
    public init(kind: String, api: String? = nil) { self.kind = kind; self.api = api }
    public var errorDescription: String? {
        switch kind {
        case "unsupportedAPI":
            let detail = safeAPI.map { " Missing support: \($0)." } ?? ""
            return "This extension needs a runtime API that this build does not support. Update AnimeCompanion to try the latest compatibility fixes." + detail
        case "executionLimit":
            return "This extension exceeded the device’s execution limit. Try again or use another source."
        case "sourceResponse":
            return "This extension could not read the website’s response. Open the source website to check access, then use the session and try again."
        default: return MangaExtensionError.runtimeFailure.errorDescription
        }
    }
    private var safeAPI: String? {
        guard let api, api.utf8.count <= 180,
              ["java.", "kotlin.", "kotlinx.", "android.", "androidx.", "okhttp3.", "okio.", "org.jsoup."].contains(where: api.hasPrefix),
              api.range(of: "^[A-Za-z0-9_$]+(?:\\.[A-Za-z0-9_$]+)+$", options: .regularExpression) != nil else { return nil }
        return api
    }
}
