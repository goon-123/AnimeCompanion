import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum TorBoxWebDAVError: LocalizedError, Equatable {
    case invalidResponse, invalidPath, invalidFile, unauthorized, unavailable, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "TorBox WebDAV returned an unreadable folder listing. Try refreshing the folder."
        case .invalidPath: return "This folder or file is not a valid TorBox WebDAV location."
        case .invalidFile: return "Choose a video file to open in VidHub."
        case .unauthorized: return "TorBox WebDAV rejected the saved API key. Check your key and WebDAV access in TorBox settings."
        case .unavailable: return "Could not connect to TorBox WebDAV. Check your connection and try again."
        case .http(let code): return "TorBox WebDAV returned HTTP \(code). Try refreshing or check your TorBox account."
        }
    }
}

public struct TorBoxWebDAVEntry: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    /// Always credential-free. Authentication is attached only when requesting
    /// a listing or when the user explicitly opens a video in their player.
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public var isVideo: Bool {
        !isDirectory && ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts", "m2ts", "mpg", "mpeg"].contains(url.pathExtension.lowercased())
    }
}

/// TorBox-only, read-only WebDAV browsing. No provider script receives these
/// credentials, and PROPFIND authentication never follows server redirects.
public struct TorBoxWebDAVClient: Sendable {
    public static let root = URL(string: "https://webdav.torbox.app/")!
    private let key: String
    private let transport: any HTTPTransport
    public init(key: String, transport: any HTTPTransport = ProviderHTTPTransport()) throws {
        _ = try TorBoxClient(key: key)
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
    }
    public func list(folder: URL = Self.root) async throws -> [TorBoxWebDAVEntry] {
        let url = try Self.location(folder)
        guard URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.hasSuffix("/") == true else { throw TorBoxWebDAVError.invalidPath }
        let data = try await request(url, method: "PROPFIND")
        guard data.count <= 4_000_000, let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw TorBoxWebDAVError.invalidResponse }
        let delegate = TorBoxDAVParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.validRoot, !delegate.invalid else { throw TorBoxWebDAVError.invalidResponse }
        let parent = try Self.segments(url)
        var seen: Set<URL> = []
        return delegate.items.compactMap { item -> TorBoxWebDAVEntry? in
            guard let href = item.href, !href.contains("\\"),
                  let hrefParts = URLComponents(string: href), (try? Self.pathSegments(hrefParts.percentEncodedPath)) != nil,
                  let relative = URL(string: href, relativeTo: url)?.absoluteURL,
                  let child = try? Self.location(relative), let segments = try? Self.segments(child),
                  segments.count == parent.count + 1, Array(segments.dropLast()) == parent,
                  let filename = segments.last, !(parent.isEmpty && filename == "refresh") else { return nil }
            let directory = item.directory ?? (URLComponents(url: child, resolvingAgainstBaseURL: false)?.percentEncodedPath.hasSuffix("/") == true)
            var components = URLComponents(url: child, resolvingAgainstBaseURL: false)!
            if directory && !components.percentEncodedPath.hasSuffix("/") { components.percentEncodedPath += "/" }
            guard let canonical = components.url, seen.insert(canonical).inserted else { return nil }
            let display = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = display?.isEmpty == false ? display! : filename
            return TorBoxWebDAVEntry(url: canonical, name: name, isDirectory: directory, size: item.size)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.absoluteString < $1.url.absoluteString : order == .orderedAscending
        }
    }
    /// TorBox documents /refresh/ for manually updating its WebDAV index.
    public func refreshIndex() async throws {
        _ = try await request(Self.root.appendingPathComponent("refresh", isDirectory: true), method: "GET", refresh: true)
    }
    /// VidHub receives an authenticated HTTPS file URL only after a Play tap.
    /// Listings, row identifiers, app errors and saved progress never contain it.
    public func playbackURL(for entry: TorBoxWebDAVEntry) throws -> URL {
        guard entry.isVideo else { throw TorBoxWebDAVError.invalidFile }
        let url = try Self.location(entry.url)
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.user = "torbox"; parts.password = key
        guard let authenticated = parts.url else { throw TorBoxWebDAVError.invalidPath }
        return authenticated
    }
    private static func location(_ url: URL) throws -> URL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "webdav.torbox.app",
              parts.port == nil || parts.port == 443, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.percentEncodedPath.hasPrefix("/"),
              parts.percentEncodedPath.utf8.count <= 16_000 else { throw TorBoxWebDAVError.invalidPath }
        _ = try segments(url)
        return url
    }
    private static func segments(_ url: URL) throws -> [String] {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw TorBoxWebDAVError.invalidPath }
        return try pathSegments(parts.percentEncodedPath)
    }
    private static func pathSegments(_ path: String) throws -> [String] {
        return try path.split(separator: "/").map { raw in
            guard let part = String(raw).removingPercentEncoding, !part.isEmpty, part != ".", part != "..",
                  !part.contains("/"), !part.contains("\\"),
                  !part.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw TorBoxWebDAVError.invalidPath }
            return part
        }
    }
    private func request(_ url: URL, method: String, refresh: Bool = false) async throws -> Data {
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpMethod = method
            request.setValue("Basic " + Data("torbox:\(key)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            if method == "PROPFIND" {
                request.setValue("1", forHTTPHeaderField: "Depth")
                request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.setValue("application/xml, text/xml", forHTTPHeaderField: "Accept")
                request.httpBody = Data(#"<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>"#.utf8)
            }
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            if response.statusCode == 401 || response.statusCode == 403 { throw TorBoxWebDAVError.unauthorized }
            // A refresh may redirect back to the root. Acknowledge it without
            // following the redirect or sending credentials to its destination.
            if refresh, [302, 303, 307, 308].contains(response.statusCode) { return Data() }
            guard (200..<300).contains(response.statusCode) else { throw TorBoxWebDAVError.http(response.statusCode) }
            guard data.count <= 4_000_000 else { throw TorBoxWebDAVError.invalidResponse }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as TorBoxWebDAVError { throw error }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw TorBoxWebDAVError.unavailable }
    }
}

private final class TorBoxDAVParser: NSObject, XMLParserDelegate {
    struct Item { var href: String?; var name: String?; var directory: Bool?; var size: Int64? }
    private struct Element { let name: String; let namespace: String?; var text = "" }
    private var stack: [Element] = []
    private var item = Item()
    private var properties = Item()
    private var propertyStatus: Int?
    private var responseStatus: Int?
    private var hasProperties = false
    private var responseCount = 0
    private(set) var items: [Item] = []
    private(set) var validRoot = false
    private(set) var invalid = false
    private var path: String? {
        guard stack.allSatisfy({ $0.namespace == "DAV:" }) else { return nil }
        return stack.map(\.name).joined(separator: "/")
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String:String] = [:]) {
        stack.append(Element(name: elementName, namespace: namespaceURI))
        if stack.count == 1 { validRoot = path == "multistatus"; if !validRoot { invalid = true; parser.abortParsing() } }
        if stack.count > 24 { invalid = true; parser.abortParsing(); return }
        switch path {
        case "multistatus/response":
            responseCount += 1
            if responseCount > 10_000 { invalid = true; parser.abortParsing(); return }
            item = Item(); hasProperties = false; responseStatus = nil
        case "multistatus/response/propstat": properties = Item(); propertyStatus = nil
        case "multistatus/response/propstat/prop/resourcetype": properties.directory = false
        case "multistatus/response/propstat/prop/resourcetype/collection": properties.directory = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let current = stack.last, current.namespace == "DAV:",
              ["href", "status", "displayname", "getcontentlength"].contains(current.name) else { return }
        if stack[stack.count - 1].text.utf8.count + string.utf8.count > 32_000 { invalid = true; parser.abortParsing(); return }
        stack[stack.count - 1].text += string
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { invalid = true; parser.abortParsing(); return }
        self.parser(parser, foundCharacters: text)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = stack.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch path {
        case "multistatus/response/href": item.href = text
        case "multistatus/response/status": responseStatus = Self.status(text)
        case "multistatus/response/propstat/status": propertyStatus = Self.status(text)
        case "multistatus/response/propstat/prop/displayname":
            if !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) { properties.name = text }
        case "multistatus/response/propstat/prop/getcontentlength": properties.size = Int64(text).flatMap { $0 >= 0 ? $0 : nil }
        case "multistatus/response/propstat":
            if let status = propertyStatus, (200..<300).contains(status) {
                hasProperties = true
                if let name = properties.name { item.name = name }
                if let directory = properties.directory { item.directory = directory }
                if let size = properties.size { item.size = size }
            }
        case "multistatus/response":
            if hasProperties, responseStatus.map({ (200..<300).contains($0) }) ?? true { items.append(item) }
        default: break
        }
        if !stack.isEmpty { stack.removeLast() }
    }
    private static func status(_ text: String) -> Int? {
        let parts = text.split(separator: " ")
        return parts.count > 1 && parts[0].hasPrefix("HTTP/") ? Int(parts[1]) : nil
    }
}
