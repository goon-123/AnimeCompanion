import SwiftUI
import Security
import AnimeCore

private struct SeanimeSavedState: Codable {
    var installations: [SeanimeInstallation] = []
    var torBoxKey = ""
    var jobs: [String: Int]? = [:]
    var submissions: [String: TorBoxJob]? = [:]
}
private enum SeanimeKeychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.animecompanion.seanime", kSecAttrAccount as String: "on-device-providers"]
    static func read() throws -> Data? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw ServiceError.message("Seanime settings could not be read. Unlock this device and reopen the app.") }
        return data
    }
    static func save(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw ServiceError.message("Seanime settings could not be saved securely. Previous settings are unchanged.") }
        } else if status != errSecSuccess { throw ServiceError.message("Seanime settings could not be saved securely. Previous settings are unchanged.") }
    }
}

@MainActor
final class SeanimeStore: ObservableObject {
    @Published private var saved = SeanimeSavedState()
    @Published private(set) var revision = UUID()
    @Published var error: String?
    let client: SeanimeClient
    private let preview: Bool
    private var loadFailed = false
    #if DEBUG
    private let previewTransport: SeanimePreviewTransport
    #endif
    init() {
        #if DEBUG
        let transport = SeanimePreviewTransport(); previewTransport = transport
        preview = ProcessInfo.processInfo.arguments.contains("--ui-seanime-preview")
        #else
        preview = false
        #endif
        #if DEBUG
        if preview {
            client = SeanimeClient(transport: transport)
            if ProcessInfo.processInfo.arguments.contains("--ui-stream-picker-preview") {
                // Owned, opt-in test setup. Never reads/writes real Keychain data
                // and still exercises the actual WebKit/TypeScript search path.
                let source = #"class Provider { async search(opts: any): Promise<any[]> { const response = await fetch('https://provider.example/results'); return response.json(); } }"#
                let json = #"{"id":"fixture","name":"On-device fixture","version":"1","type":"anime-torrent-provider","language":"typescript"}"#
                if let manifest = try? JSONDecoder().decode(SeanimeManifest.self, from: Data(json.utf8)) {
                    saved.installations = [SeanimeInstallation(manifestURL:URL(string:"https://provider.example/fixture.json")!,manifest:manifest,source:source,preferences:[:],allowedHosts:["provider.example"],adult:false)]
                    saved.torBoxKey = "synthetic-torbox-key"
                }
            }
            return
        }
        #endif
        client = SeanimeClient()
        do {
            if let data = try SeanimeKeychain.read() { saved = try JSONDecoder().decode(SeanimeSavedState.self, from: data) }
        } catch { loadFailed = true; self.error = "Seanime settings could not be read. Unlock this device and reopen the app; existing saved data has not been replaced." }
    }
    var installations: [SeanimeInstallation] { saved.installations }
    var hasTorBoxKey: Bool { !saved.torBoxKey.isEmpty }
    func torBox() throws -> TorBoxClient {
        #if DEBUG
        if preview { return try TorBoxClient(key: saved.torBoxKey, transport: previewTransport) }
        #endif
        return try TorBoxClient(key: saved.torBoxKey)
    }
    func webDAV() throws -> TorBoxWebDAVClient {
        #if DEBUG
        if preview { return try TorBoxWebDAVClient(key: saved.torBoxKey, transport: previewTransport) }
        #endif
        return try TorBoxWebDAVClient(key: saved.torBoxKey)
    }
    func saveKey(_ key: String) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, (try? TorBoxClient(key: value)) == nil { error = TorBoxError.missingKey.localizedDescription; return false }
        var updated = saved; updated.torBoxKey = value
        if value != saved.torBoxKey { updated.jobs = [:]; updated.submissions = [:] }
        return persist(updated)
    }
    func job(for torrent: SeanimeTorrent) -> TorBoxJob? {
        if let job = saved.submissions?[torrent.id] { return job }
        return saved.jobs?[torrent.id].map { TorBoxJob(torrentID: $0) }
    }
    @discardableResult func recordJob(_ job: TorBoxJob, for torrent: SeanimeTorrent) -> Bool {
        var updated = saved; var jobs = updated.submissions ?? [:]; jobs[torrent.id] = job
        if jobs.count > 256, let oldest = jobs.keys.sorted().first(where: { $0 != torrent.id }) { jobs.removeValue(forKey: oldest) }
        updated.submissions = jobs; updated.jobs?.removeValue(forKey: torrent.id)
        return persist(updated, invalidateSearch: false)
    }
    func forgetJob(for torrent: SeanimeTorrent) {
        var updated = saved; updated.jobs?.removeValue(forKey: torrent.id); updated.submissions?.removeValue(forKey: torrent.id)
        _ = persist(updated, invalidateSearch: false)
    }
    func install(_ candidate: SeanimeInstallation) -> Bool {
        var updated = saved
        if let index = updated.installations.firstIndex(where: { $0.manifestURL == candidate.manifestURL }) {
            let old = updated.installations[index]
            updated.installations[index] = SeanimeInstallation(id: old.id, manifestURL: candidate.manifestURL, manifest: candidate.manifest,
                source: candidate.source, preferences: candidate.preferences, allowedHosts: candidate.allowedHosts, adult: candidate.adult)
        } else { updated.installations.append(candidate) }
        return persist(updated)
    }
    func update(_ installation: SeanimeInstallation) -> Bool {
        var updated = saved
        guard let index = updated.installations.firstIndex(where: { $0.id == installation.id }) else { return false }
        updated.installations[index] = installation; return persist(updated)
    }
    func remove(_ id: UUID) {
        var updated = saved; updated.installations.removeAll { $0.id == id }; _ = persist(updated)
    }
    private func persist(_ state: SeanimeSavedState, invalidateSearch: Bool = true) -> Bool {
        do {
            guard !loadFailed else { throw ServiceError.message("Saved Seanime settings must be readable before they can be changed. Unlock this device and reopen the app.") }
            let data = try JSONEncoder().encode(state)
            guard data.count <= 4_000_000, state.installations.count <= 12 else { throw ServiceError.message("This device’s extension storage limit was reached. Remove an unused extension before adding another.") }
            if !preview { try SeanimeKeychain.save(data) }
            saved = state; if invalidateSearch { revision = UUID() }; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

#if DEBUG
actor SeanimePreviewTransport: HTTPTransport {
    private var added = false
    private var delayedList = false
    private var refreshedDAV = false
    private var downloadReads = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, ["provider.example", "api.torbox.app", "webdav.torbox.app"].contains(url.host ?? "") else { throw SeanimeError.invalidNetwork }
        if url.host == "webdav.torbox.app" { return webDAV(request, url: url) }
        let text: String
        if url.host == "api.torbox.app" {
            if url.path.hasSuffix("createtorrent") {
                if ProcessInfo.processInfo.arguments.contains("--ui-torbox-cache-miss"),
                   String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("name=\"add_only_if_cached\"\r\n\r\ntrue") == true {
                    let json = #"{"success":false,"error":"DIFF_ISSUE","detail":"This torrent is not cached on TorBox. private synthetic-torbox-key","data":null}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!)
                }
                added = true
                text = ProcessInfo.processInfo.arguments.contains("--ui-torbox-queued")
                    ? #"{"success":true,"error":null,"data":{"queued_id":41,"torrent_id":null}}"#
                    : #"{"success":true,"error":false,"data":{"torrent_id":"7"}}"#
            }
            else if url.path.hasSuffix("mylist") {
                if !added && !ProcessInfo.processInfo.arguments.contains("--ui-torbox-already-added") {
                    text = #"{"success":true,"error":null,"data":[]}"#
                } else if !delayedList && ProcessInfo.processInfo.arguments.contains("--ui-torbox-unreadable-files-once") {
                    delayedList = true; text = #"{"success":true,"error":null,"data":"unreadable file list"}"#
                } else if !delayedList && ProcessInfo.processInfo.arguments.contains("--ui-torbox-queued") {
                    delayedList = true; text = #"{"success":true,"error":null,"data":[]}"#
                } else {
                    if ProcessInfo.processInfo.arguments.contains("--ui-torbox-downloading"), downloadReads < 3 {
                        downloadReads += 1
                        text = #"{"success":true,"error":null,"data":[{"id":"7","hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","download_state":"downloading","download_present":false,"download_finished":false,"progress":0.42,"files":[]}]}"#
                        return (Data(text.utf8),HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!)
                    }
                    let files = ProcessInfo.processInfo.arguments.contains("--ui-torbox-single-file")
                        ? #"[{"id":"0","name":"Anime - 01 EN.mkv","size":1000}]"#
                        : #"[{"id":"9","name":"Anime - 09 EN.mkv","short_name":null,"mimetype":null,"size":1000},{"id":"10","name":"Anime - 10 JA.mkv","size":1000},{"id":"14","name":"Anime - 11 JA.mkv","size":1000},{"id":"18","name":"Anime - 12 JA.mkv","size":1000}]"#
                    text = "{\"success\":true,\"error\":null,\"data\":[{\"id\":\"7\",\"hash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"name\":\"Fixture batch\",\"download_present\":true,\"download_finished\":true,\"files\":\(files)}]}"
                }
            }
            else if url.path.hasSuffix("requestdl") {
                // Reproduce the reported authenticated/account-link response.
                // The app should construct its own player permalink instead of
                // trying to classify this response as a public CDN URL.
                return (Data(), HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location":url.absoluteString])!)
            } else { text = #"{"success":true,"error":null,"data":{"id":1}}"# }
        } else if url.path.hasSuffix(".json") {
            let payload: String
            if ProcessInfo.processInfo.arguments.contains("--ui-seanime-timeout") || ProcessInfo.processInfo.arguments.contains("--ui-seanime-spin") {
                payload = "class Provider { search() { while(true){} } }"
            } else if ProcessInfo.processInfo.arguments.contains("--ui-seanime-blocked-host") {
                payload = "class Provider { async search() { const host = ['unapproved', 'example'].join('.'); try { await fetch('https://' + host + '/feed'); } catch {} return []; } }"
            } else {
                payload = #"class Provider { getSettings() { return { supportsAdult: false }; } async search(opts: any): Promise<any[]> { const response = await fetch('https://provider.example/results'); return response.json(); } }"#
            }
            let manifestID = url.deletingPathExtension().lastPathComponent
            let object: [String: Any] = ["id": manifestID, "name": manifestID == "fixture" ? "On-device fixture" : "Another provider", "version": "1", "type": "anime-torrent-provider", "language": "typescript",
                "payload": payload]
            let data = try JSONSerialization.data(withJSONObject: object)
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        } else { text = #"[{"name":"Fixture Anime · Audio: en / ja","infoHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","seeders":42,"formattedSize":"1 GB","episodeNumber":9}]"# }
        return (Data(text.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    private func webDAV(_ request: URLRequest, url: URL) -> (Data, HTTPURLResponse) {
        func response(_ status: Int, _ text: String) -> (Data,HTTPURLResponse) {
            (Data(text.utf8),HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/xml"])!)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-webdav-unauthorized") { return response(401,"private synthetic-torbox-key") }
        let auth = "Basic " + Data("torbox:synthetic-torbox-key".utf8).base64EncodedString()
        guard request.value(forHTTPHeaderField:"Authorization") == auth else { return response(401,"") }
        let path = (URLComponents(url:url,resolvingAgainstBaseURL:false)?.path ?? "").trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        if path == "refresh", request.httpMethod == "GET" {
            refreshedDAV = true
            return ProcessInfo.processInfo.arguments.contains("--ui-webdav-refresh-404") ? response(404,"private synthetic-torbox-key") : response(200,"refreshed")
        }
        guard request.httpMethod == "PROPFIND", request.value(forHTTPHeaderField:"Depth") == "1" else { return response(405,"") }
        func escaped(_ text: String) -> String { text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;") }
        func entry(_ href: String, _ name: String, folder: Bool = false, date: String = "2026-10-14T08:00:00Z") -> String {
            "<d:response><d:href>\(escaped(href))</d:href><d:propstat><d:prop><d:displayname>\(escaped(name))</d:displayname><d:resourcetype>\(folder ? "<d:collection/>" : "")</d:resourcetype><d:getcontentlength>1234567</d:getcontentlength><d:creationdate>\(date)</d:creationdate></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
        }
        let entries: String
        switch path {
        case "":
            entries = entry("/","TorBox",folder:true) + entry("/Fixture%20batch/","Fixture batch",folder:true)
                + entry("/Loose%20Episode.mkv","Loose Episode.mkv",date:"2026-10-15T08:00:00Z") + entry("/Readme.txt","Readme.txt")
                + (refreshedDAV ? entry("/Fresh%20Episode.mkv","Fresh Episode.mkv",date:"2026-10-16T08:00:00Z") : "")
        case "Fixture batch":
            entries = entry("/Fixture%20batch/","Fixture batch",folder:true) + entry("/Fixture%20batch/Extras/","Extras",folder:true)
                + entry("/Fixture%20batch/Episode%2001%20EN.mkv","Episode 01 EN.mkv")
                + entry("/Fixture%20batch/Episode%2002%20JA%20%26%20Friends.mkv","Episode 02 JA & Friends.mkv")
        case "Fixture batch/Extras":
            entries = entry("/Fixture%20batch/Extras/","Extras",folder:true) + entry("/Fixture%20batch/Extras/Sample.mkv","Sample.mkv")
        default: return response(404,"")
        }
        return response(207,"<?xml version=\"1.0\" encoding=\"utf-8\"?><d:multistatus xmlns:d=\"DAV:\">\(entries)</d:multistatus>")
    }
}
#endif
