import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TorBoxWebDAVTests: XCTestCase {
    private let key = "synthetic-webdav-key"
    private func xml(_ entries: String) -> String { "<?xml version=\"1.0\" encoding=\"utf-8\"?><d:multistatus xmlns:d=\"DAV:\">\(entries)</d:multistatus>" }
    private func resource(_ href: String, name: String? = nil, directory: Bool = false, extra: String = "") -> String {
        func escape(_ value: String) -> String { value.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;") }
        let display = name.map { "<d:displayname>\(escape($0))</d:displayname>" } ?? ""
        return "<d:response><d:href>\(escape(href))</d:href><d:propstat><d:prop>\(display)<d:resourcetype>\(directory ? "<d:collection/>" : "")</d:resourcetype><d:getcontentlength>1234567</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>\(extra)</d:response>"
    }
    func testRootListingShowsFoldersAndFlattenedVideosWithoutListingItself() async throws {
        let body = xml(resource("/",directory:true) + resource("/Episode%2010.mkv") + resource("/Folder/",directory:true)
                       + resource("/Episode%202.mkv") + resource("/notes.txt") + resource("/refresh/",directory:true))
        let transport = WebDAVTestTransport([(207,body)])
        let entries = try await TorBoxWebDAVClient(key:key,transport:transport).list()
        XCTAssertEqual(entries.map(\.name),["Folder","Episode 2.mkv","Episode 10.mkv","notes.txt"])
        XCTAssertTrue(entries[0].isDirectory); XCTAssertTrue(entries[1].isVideo); XCTAssertFalse(entries[3].isVideo)
        XCTAssertEqual(entries[1].size,1234567)
        let requests = await transport.requests
        XCTAssertEqual(requests.count,1); XCTAssertEqual(requests[0].httpMethod,"PROPFIND")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"Depth"),"1")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"Authorization"),"Basic " + Data("torbox:\(key)".utf8).base64EncodedString())
        XCTAssertEqual(requests[0].url?.absoluteString,"https://webdav.torbox.app/")
        XCTAssertFalse(requests[0].url!.absoluteString.contains(key))
    }
    func testNestedNamespacePropertiesRelativeHrefsAndLiteralPercentFilenames() async throws {
        let failedProperty = "<d:propstat><d:prop><d:displayname>Wrong name</d:displayname></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>"
        let body = xml(resource("/Batch%20folder/",directory:true)
                       + resource("episode%2520name.mkv", extra:failedProperty)
                       + resource("Extras",directory:true) + resource("Episode%20%26%20%E5%A4%8F.mkv",name:"Episode & 夏.mkv")
                       + resource("https://webdav.torbox.app/Batch%20folder/episode%2520name.mkv"))
        let transport = WebDAVTestTransport([(207,body)])
        let client = try TorBoxWebDAVClient(key:key,transport:transport)
        let entries = try await client.list(folder:URL(string:"https://webdav.torbox.app/Batch%20folder/")!)
        XCTAssertEqual(entries.count,3)
        XCTAssertEqual(entries.first?.url.absoluteString,"https://webdav.torbox.app/Batch%20folder/Extras/")
        let literal = try XCTUnwrap(entries.first { $0.name == "episode%20name.mkv" })
        XCTAssertTrue(literal.url.absoluteString.contains("episode%2520name.mkv"))
        XCTAssertTrue(entries.contains { $0.name == "Episode & 夏.mkv" })
        XCTAssertFalse(entries.contains { $0.name == "Wrong name" })
    }
    func testFolderScopeRejectsForeignHostsCredentialsTraversalAndDeepDescendants() async throws {
        let unsafe = ["https://other.example/Batch/evil.mkv", "//other.example/Batch/evil.mkv", "../evil.mkv",
                      "/Other/evil.mkv", "/Batch/deeper/evil.mkv", "/Batch/%2E%2E/evil.mkv", "/Batch/one%2Ftwo.mkv",
                      "/Batch/one%5Ctwo.mkv", "/Batch/control%0A.mkv", "/Batch/evil.mkv?token=private", "/Batch/evil.mkv#fragment",
                      "https://user:private@webdav.torbox.app/Batch/evil.mkv", "http://webdav.torbox.app/Batch/evil.mkv"]
        let body = xml(unsafe.map { resource($0) }.joined() + resource("/Batch/Good.mkv"))
        let entries = try await TorBoxWebDAVClient(key:key,transport:WebDAVTestTransport([(207,body)]))
            .list(folder:URL(string:"https://webdav.torbox.app/Batch/")!)
        XCTAssertEqual(entries.map(\.name),["Good.mkv"])
    }
    func testAuthenticatedWebDAVFileSurvivesBothVidHubBuildersWithoutChangingTheListingURL() async throws {
        let secret = "synthetic+/@:=%&key"
        let body = xml(resource("/Batch/",directory:true) + resource("/Batch/Episode%2002%20%26%20%E5%A4%8F.mkv"))
        let transport = WebDAVTestTransport([(207,body)])
        let client = try TorBoxWebDAVClient(key:secret,transport:transport)
        let entries = try await client.list(folder:URL(string:"https://webdav.torbox.app/Batch/")!)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertNil(entry.url.user); XCTAssertNil(entry.url.password)
        let url = try client.playbackURL(for:entry)
        let parts = try XCTUnwrap(URLComponents(url:url,resolvingAgainstBaseURL:false))
        XCTAssertEqual(parts.user,"torbox"); XCTAssertEqual(parts.password,secret); XCTAssertEqual(parts.host,"webdav.torbox.app")
        XCTAssertTrue(url.absoluteString.contains("Episode%2002%20%26%20%E5%A4%8F.mkv"))
        let stream = try JSONDecoder().decode(StremioStream.self,from:JSONSerialization.data(withJSONObject:["url":url.absoluteString,"behaviorHints":["filename":entry.name]]))
        let pending = PendingPlayback(episode:PlaybackEpisode(animeID:123,episode:2),title:"Episode 2")
        for launch in [try VidHubPlayback.launchURL(stream:stream,pending:pending),try VidHubPlayback.untrackedLaunchURL(stream:stream,title:entry.name)] {
            let destination = URLComponents(url:launch,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "url" }?.value
            XCTAssertEqual(destination,url.absoluteString)
        }
        let requests = await transport.requests; XCTAssertEqual(requests.count,1,"Playing a selected WebDAV file must not create or resolve a torrent")
    }
    func testOnlyTheFixedWebDAVOriginCanReceiveAuthentication() async throws {
        let transport = WebDAVTestTransport([]), client = try TorBoxWebDAVClient(key:key,transport:transport)
        for text in ["https://other.example/", "http://webdav.torbox.app/", "https://webdav.torbox.app:8443/", "https://user:pass@webdav.torbox.app/", "https://webdav.torbox.app/?token=private"] {
            do { _ = try await client.list(folder:URL(string:text)!); XCTFail("Expected invalid path") }
            catch { XCTAssertEqual(error as? TorBoxWebDAVError,.invalidPath) }
            let entry = TorBoxWebDAVEntry(url:URL(string:text + "video.mkv")!,name:"video.mkv",isDirectory:false,size:nil)
            XCTAssertThrowsError(try client.playbackURL(for:entry))
        }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        for entry in [TorBoxWebDAVEntry(url:TorBoxWebDAVClient.root,name:"Root",isDirectory:true,size:nil),
                      TorBoxWebDAVEntry(url:TorBoxWebDAVClient.root.appendingPathComponent("Readme.url"),name:"Readme.url",isDirectory:false,size:nil)] {
            XCTAssertThrowsError(try client.playbackURL(for:entry))
        }
    }
    func testHTTPAndMalformedXMLFailuresStaySanitized() async throws {
        for (status,body,expected) in [
            (401,"private \(key)",TorBoxWebDAVError.unauthorized), (403,"private \(key)",.unauthorized),
            (302,"private \(key)",.http(302)), (429,"private \(key)",.http(429)),
            (207,"<d:multistatus xmlns:d=\"DAV:\"><d:response>",.invalidResponse),
            (200,"<html>private \(key)</html>",.invalidResponse),
            (207,"<!DOCTYPE d:multistatus [<!ENTITY secret SYSTEM \"https://other.example/private\">]>" + xml("&secret;"),.invalidResponse),
            (207,"<multistatus xmlns=\"other\"/>",.invalidResponse)
        ] {
            do { _ = try await TorBoxWebDAVClient(key:key,transport:WebDAVTestTransport([(status,body)])).list(); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? TorBoxWebDAVError,expected); XCTAssertFalse(error.localizedDescription.contains(key)); XCTAssertFalse(error.localizedDescription.contains("https://")) }
        }
    }
    func testExplicitRefreshThenBrowseUsesOnlyReadRequestsAndNeverFollowsRedirects() async throws {
        let transport = WebDAVTestTransport([(303,""),(207,xml(resource("/Fresh.mkv")))])
        let client = try TorBoxWebDAVClient(key:key,transport:transport)
        try await client.refreshIndex()
        let entries = try await client.list(); XCTAssertEqual(entries.map(\.name),["Fresh.mkv"])
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod),["GET","PROPFIND"])
        XCTAssertEqual(requests[0].url?.absoluteString,"https://webdav.torbox.app/refresh/")
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "webdav.torbox.app" })
    }
    func testExternalPlayerPermalinkUsesExactReadyFileAndDoesNotResolveReturnedAccountLinks() async throws {
        let json = #"{"id":123456789,"download_present":true,"download_finished":true,"files":[{"id":0,"name":"Episode 1.mkv"},{"id":5,"name":"Episode 2.mkv"},{"id":8,"name":"readme.txt"}]}"#
        let torrent = try JSONDecoder().decode(TorBoxTorrent.self,from:Data(json.utf8))
        let transport = WebDAVTestTransport([]), client = try TorBoxClient(key:"synthetic+private-key",transport:transport)
        for fileID in [0,5] {
            let url = try client.playbackURL(torrent:torrent,fileID:fileID)
            let parts = try XCTUnwrap(URLComponents(url:url,resolvingAgainstBaseURL:false))
            XCTAssertEqual(parts.host,"api.torbox.app"); XCTAssertEqual(parts.path,"/v1/api/torrents/requestdl")
            XCTAssertEqual(parts.queryItems?.first { $0.name == "token" }?.value,"synthetic+private-key")
            XCTAssertTrue(parts.percentEncodedQuery!.contains("%2B"))
            XCTAssertEqual(parts.queryItems?.first { $0.name == "torrent_id" }?.value,"123456789")
            XCTAssertEqual(parts.queryItems?.first { $0.name == "file_id" }?.value,String(fileID))
            XCTAssertEqual(parts.queryItems?.first { $0.name == "redirect" }?.value,"true")
            XCTAssertNil(parts.queryItems?.first { $0.name == "zip_link" })
            let stream = try JSONDecoder().decode(StremioStream.self,from:JSONSerialization.data(withJSONObject:["url":url.absoluteString]))
            let launch = try VidHubPlayback.untrackedLaunchURL(stream:stream,title:"Selected file")
            XCTAssertEqual(URLComponents(url:launch,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "url" }?.value,url.absoluteString)
        }
        XCTAssertThrowsError(try client.playbackURL(torrent:torrent,fileID:8))
        let waiting = try JSONDecoder().decode(TorBoxTorrent.self,from:Data(json.replacingOccurrences(of:"\"download_finished\":true",with:"\"download_finished\":false").utf8))
        XCTAssertThrowsError(try client.playbackURL(torrent:waiting,fileID:0))
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
}

private actor WebDAVTestTransport: HTTPTransport {
    var responses: [(Int,String)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Int,String)]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
        let reply = responses.removeFirst()
        return (Data(reply.1.utf8),HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:nil,headerFields:nil)!)
    }
}
