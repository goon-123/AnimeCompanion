import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Memory-only, source-isolated sessions. Never uses Safari's or the app's
/// shared cookie store; a source's cookies only go to matching HTTPS origins.
public final class MangaSourceCookieJar: @unchecked Sendable {
    public static let shared = MangaSourceCookieJar()
    public static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
    private let lock = NSLock()
    private var sessions: [String: [HTTPCookie]] = [:]
    public init() {}
    public func cookies(source: String) -> [HTTPCookie] {
        lock.lock(); defer { lock.unlock() }
        return (sessions[source] ?? []).filter { $0.expiresDate.map { $0 > Date() } ?? true }
    }
    public func replace(source: String, cookies: [HTTPCookie]) {
        lock.lock(); defer { lock.unlock() }
        sessions[source] = bounded(cookies)
    }
    /// Import browser changes without reverting a later native HTTP update or
    /// deletion. `initial` must be the exact snapshot returned by `cookies` at
    /// browser load; unchanged immutable cookie references identify conflicts.
    public func reconcileBrowser(source: String, initial: [HTTPCookie], cookies: [HTTPCookie]) {
        lock.lock(); defer { lock.unlock() }
        let incoming = Dictionary(bounded(cookies).map { (CookieKey($0), $0) }, uniquingKeysWith: { _, value in value })
        let previous = Dictionary(initial.map { (CookieKey($0), $0) }, uniquingKeysWith: { _, value in value })
        var current = sessions[source] ?? []
        for key in Set(previous.keys).union(incoming.keys) {
            let existing = current.first { CookieKey($0) == key }
            guard existing === previous[key] else { continue }
            current.removeAll { CookieKey($0) == key }
            if let value = incoming[key] { current.append(value) }
        }
        sessions[source] = Array(current.filter { $0.expiresDate.map { $0 > Date() } ?? true }.suffix(256))
    }
    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String
        init(_ cookie: HTTPCookie) {
            name = cookie.name; domain = cookie.domain.lowercased(); path = cookie.path
        }
    }
    private func bounded(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        Array(cookies.compactMap(normalized).filter {
            !$0.domain.isEmpty && $0.domain.utf8.count <= 253 && $0.value.utf8.count <= 16_384
        }.suffix(256))
    }
    public func clear(source: String) { lock.lock(); sessions.removeValue(forKey: source); lock.unlock() }
    public func header(source: String, url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        let path = encodedPath.isEmpty ? "/" : encodedPath
        let matched = cookies(source: source).filter { cookie in
            let domain = cookie.domain.lowercased()
            let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let domainMatches = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = path == cookiePath || (path.hasPrefix(cookiePath) &&
                (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
            return domainMatches && pathMatches
        }.sorted { $0.path.count > $1.path.count }
        guard !matched.isEmpty else { return nil }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    public func receive(source: String, url: URL, headers: [String: String]) {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return }
        let incoming = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain.contains(".") && (host == domain || host.hasSuffix("." + domain))
        }
        lock.lock(); defer { lock.unlock() }
        var current = sessions[source] ?? []
        for cookie in incoming {
            current.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if let cookie = normalized(cookie) { current.append(cookie) }
        }
        sessions[source] = Array(current.suffix(256))
    }
    private func normalized(_ cookie: HTTPCookie) -> HTTPCookie? {
        // swift-corelibs Foundation retains Max-Age without applying it to
        // expiresDate. Normalize explicitly, including deletion and its RFC
        // precedence over Expires; keep one absolute expiry in both transports.
        if let value = cookie.properties?[.maximumAge], let seconds = TimeInterval(String(describing: value)) {
            guard seconds.isFinite, seconds > 0, var properties = cookie.properties else { return nil }
            properties[.expires] = Date().addingTimeInterval(min(seconds, 3_153_600_000))
            properties.removeValue(forKey: .maximumAge)
            return HTTPCookie(properties: properties)
        }
        return cookie.expiresDate.map({ $0 > Date() }) ?? true ? cookie : nil
    }
    public static func merging(explicit: String?, session: String) -> String {
        guard let explicit, !explicit.isEmpty else { return session }
        func name(_ part: Substring) -> String {
            part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
        }
        let names = Set(explicit.split(separator: ";").map(name))
        let additions = session.split(separator: ";").filter { !names.contains(name($0)) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return ([explicit] + additions).joined(separator: "; ")
    }
}
