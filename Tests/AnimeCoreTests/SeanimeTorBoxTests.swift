import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SeanimeTorBoxTests: XCTestCase {
    private let manifest = #"{"id":"fixture","name":"Provider","version":"1.0","language":"typescript","type":"anime-torrent-provider","payloadURI":"https://source.example/provider.ts","userConfig":{"requiresConfig":false,"fields":[{"name":"apiUrl","type":"text","default":"https://feed.example/json"}]}}"#
    private let ready = #"{"id":7,"name":"Batch","download_state":"cached","download_present":true,"download_finished":true,"files":[{"id":9,"name":"Anime - 09 EN.mkv"},{"id":10,"name":"Anime - 10 JA.mkv"},{"id":11,"name":"readme.txt"}]}"#
    private let magnet = "magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&dn=Anime%20%26%20Friends"
    private let key = "synthetic-torbox-test-key"
    private func torrent(_ json: String? = nil) throws -> TorBoxTorrent { try JSONDecoder().decode(TorBoxTorrent.self, from: Data((json ?? ready).utf8)) }
    private func result(_ data: String) -> String { "{\"success\":true,\"error\":null,\"data\":\(data)}" }

    func testSeanimeManifestAndTypeScriptPayloadAreFetchedWithoutExecution() async throws {
        let source = "class Provider { search() { throw new Error('not executed while installing'); } }"
        let transport = SeanimeTestTransport([(200, manifest), (200, source)])
        let value = try await SeanimeClient(transport: transport).inspect("https://manifest.example/private.json?key=a%2Bb")
        XCTAssertEqual(value.manifest.type, "anime-torrent-provider"); XCTAssertEqual(value.source, source)
        XCTAssertEqual(value.preferences["apiUrl"], "https://feed.example/json")
        XCTAssertEqual(value.allowedHosts, ["feed.example", "manifest.example", "source.example"])
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.host! }, ["manifest.example", "source.example"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }
    func testInlinePayloadInstallsAndOtherPluginTypesAreNotMisreportedAsSupported() async throws {
        for type in ["anime-torrent-provider", "plugin", "manga-provider", "onlinestream-provider"] {
            let object: [String: Any] = ["id":"fixture", "name":"Provider", "version":"1", "language":"javascript", "type":type, "payload":"class Provider {}"]
            let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
            let client = SeanimeClient(transport: SeanimeTestTransport([(200,json)]))
            do { let value = try await client.inspect("https://manifest.example/provider.json"); XCTAssertEqual(type, "anime-torrent-provider"); XCTAssertEqual(value.source, "class Provider {}") }
            catch { XCTAssertNotEqual(type, "anime-torrent-provider"); XCTAssertEqual(error as? SeanimeError, .unsupportedType) }
        }
    }
    func testInvalidManifestSourceAndNonHTTPSPayloadFail() async throws {
        for json in [#"{"name":"Not enough"}"#, manifest.replacingOccurrences(of: "typescript", with: "python"), manifest.replacingOccurrences(of: "https://source.example/provider.ts", with: "file:///private/source.ts")] {
            do { _ = try await SeanimeClient(transport: SeanimeTestTransport([(200,json)])).inspect("https://manifest.example/provider.json"); XCTFail("Expected rejection") }
            catch { XCTAssertTrue(error is SeanimeError) }
        }
    }
    func testNetworkPolicyRejectsPrivateAndAmbiguousAddressesAndCredentials() {
        for url in ["https://127.0.0.1/x", "https://10.1.2.3/x", "https://[::1]/x", "https://localhost/x", "https://host.local/x", "https://2130706433/x", "https://0x7f.0x0.0x0.0x1/x", "https://foo..example/x", "https://user:secret@feed.example/x", "http://feed.example/x", "file:///private/x", "https://feed.example:4433/x", "https://feed.example/x#token"] {
            XCTAssertThrowsError(try SeanimeNetworkPolicy.httpsURL(url), url)
        }
        XCTAssertNoThrow(try SeanimeNetworkPolicy.httpsURL("https://feed.example/x?token=a%2Bb"))
    }
    func testAllowedHostMustMatchExactlyNotBySuffix() {
        XCTAssertThrowsError(try SeanimeNetworkPolicy.validate("https://feed.example.evil.example/x", hosts: ["feed.example"]))
        XCTAssertThrowsError(try SeanimeNetworkPolicy.validate("https://evil.feed.example/x", hosts: ["feed.example"]))
        XCTAssertNoThrow(try SeanimeNetworkPolicy.validate("https://feed.example/x", hosts: ["FEED.EXAMPLE"]))
    }
    func testProviderResponseAndStatusDoNotReceiveTorBoxAuthentication() async throws {
        let transport = SeanimeTestTransport([(403,"private provider diagnostic")])
        let value = try await SeanimeClient(transport: transport).fetch("https://feed.example/search?q=anime", hosts: ["feed.example"])
        XCTAssertEqual(value.1, 403)
        let requests = await transport.requests
        XCTAssertEqual(requests.count,1); XCTAssertNil(requests[0].value(forHTTPHeaderField:"Authorization"))
        XCTAssertEqual(requests[0].httpMethod,"GET")
    }
    func testRedirectedOrOversizedProviderResponsesAreRejected() async throws {
        for response in [(302,"redirect"), (200,String(repeating:"x",count:4_000_001))] {
            do { _ = try await SeanimeClient(transport: SeanimeTestTransport([response])).fetch("https://feed.example/feed",hosts:["feed.example"]); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? SeanimeError,.unavailable) }
        }
    }
    func testConfiguredSourceSnapshotAndPreferencesRoundTripWithoutSilentUpdate() async throws {
        let value = try await SeanimeClient(transport: SeanimeTestTransport([(200,manifest),(200,"class Provider {}")])).inspect("https://manifest.example/p.json")
        var edited = value; edited.enabled = false; edited.preferences["apiUrl"] = "https://custom.example"; edited.adult = true
        let restored = try JSONDecoder().decode(SeanimeInstallation.self,from:JSONEncoder().encode(edited))
        XCTAssertEqual(restored.id,value.id); XCTAssertEqual(restored.source,"class Provider {}")
        XCTAssertFalse(restored.enabled); XCTAssertTrue(restored.adult)
        XCTAssertEqual(restored.preferences["apiUrl"],"https://custom.example")
        XCTAssertFalse(restored.allowedHosts.contains("custom.example"),"Changing a preference must not silently approve a host")
    }
    func testKnownSukebeiManifestReceivesAdultHint() async throws {
        let json = manifest.replacingOccurrences(of:"\"id\":\"fixture\"",with:"\"id\":\"nyaa-sukebei\"")
        let value = try await SeanimeClient(transport:SeanimeTestTransport([(200,json),(200,"class Provider {}")])).inspect("https://manifest.example/p.json")
        XCTAssertTrue(value.adult)
    }
    func testTorrentInfoHashBecomesMagnetWithoutFetchingWebpage() throws {
        let torrent = try JSONDecoder().decode(SeanimeTorrent.self,from:Data(#"{"name":"Anime & Friends","infoHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8))
        let parts = try XCTUnwrap(torrent.magnet.flatMap(URLComponents.init(string:)))
        XCTAssertEqual(parts.queryItems?.first { $0.name=="xt" }?.value,"urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(parts.queryItems?.first { $0.name=="dn" }?.value,"Anime & Friends")
        let bad = try JSONDecoder().decode(SeanimeTorrent.self,from:Data(#"{"name":"No hash","infoHash":"../../bad"}"#.utf8)); XCTAssertNil(bad.magnet)
        let privateLink = try JSONDecoder().decode(SeanimeTorrent.self, from: Data(#"{"name":"Private result","downloadUrl":"https://provider.example/file?key=private-token"}"#.utf8))
        XCTAssertFalse(privateLink.id.contains("private-token")); XCTAssertFalse(privateLink.id.contains("https://"))
    }
    func testTorBoxKeyValidationAndReadOnlyVerify() async throws {
        for key in ["", "abc\nheader", "Bearer token"] { XCTAssertThrowsError(try TorBoxClient(key:key)) }
        let transport = SeanimeTestTransport([(200,result(#"{"id":1}"#))])
        try await TorBoxClient(key:key,transport:transport).verify()
        let requests = await transport.requests
        XCTAssertEqual(requests.count,1); XCTAssertEqual(requests[0].httpMethod,"GET")
        XCTAssertEqual(requests[0].url?.host,"api.torbox.app"); XCTAssertEqual(requests[0].value(forHTTPHeaderField:"Authorization"),"Bearer \(key)")
        XCTAssertFalse(requests[0].url!.absoluteString.contains(key))
    }
    func testExplicitTorBoxAddUsesMultipartAndCachedOnlyWithoutOverridingSeedingSettings() async throws {
        let transport = SeanimeTestTransport([(200,result(#"{"torrent_id":7}"#))])
        let id = try await TorBoxClient(key:key,transport:transport).add(magnet:magnet,cachedOnly:true)
        XCTAssertEqual(id.torrentID,7)
        let requests = await transport.requests, request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod,"POST"); XCTAssertEqual(request.url?.path,"/v1/api/torrents/createtorrent")
        let body = String(data:request.httpBody!,encoding:.utf8)!
        XCTAssertTrue(body.contains(magnet)); XCTAssertTrue(body.contains("name=\"add_only_if_cached\"\r\n\r\ntrue"))
        XCTAssertTrue(body.contains("name=\"allow_zip\"\r\n\r\nfalse")); XCTAssertFalse(body.contains("name=\"seed\"")); XCTAssertFalse(body.contains(key))
    }
    func testInvalidMagnetDoesNotMakeAccountWrite() async throws {
        let transport = SeanimeTestTransport([]), client = try TorBoxClient(key:key,transport:transport)
        for value in ["https://torrent.example/a.torrent", "magnet:?xt=urn:btih:bad", magnet+"\r\nheader"] {
            do { _ = try await client.add(magnet:value,cachedOnly:true); XCTFail("Expected invalid torrent") } catch { XCTAssertEqual(error as? TorBoxError,.invalidTorrent) }
        }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testTorBoxRefreshOnlyReadsExactExistingJobAndHandlesArrayOrObject() async throws {
        for data in [ready,"[\(ready)]"] {
            let transport = SeanimeTestTransport([(200,result(data))])
            let value = try await TorBoxClient(key:key,transport:transport).torrent(id:7)
            XCTAssertEqual(value.id,7); XCTAssertEqual(value.videoFiles.map(\.id),[9,10])
            let requests = await transport.requests
            XCTAssertEqual(requests.count,1); XCTAssertEqual(requests[0].httpMethod,"GET")
            XCTAssertTrue(requests[0].url!.absoluteString.contains("id=7&bypass_cache=true"))
        }
    }
    func testMismatchedTorrentAndDuplicateFileIDsCannotSelectAnotherVideo() async throws {
        for data in [ready.replacingOccurrences(of:"\"id\":7",with:"\"id\":8"),ready.replacingOccurrences(of:"\"id\":10",with:"\"id\":9")] {
            do { _ = try await TorBoxClient(key:key,transport:SeanimeTestTransport([(200,result("[\(data)]"))])).torrent(id:7); XCTFail("Expected invalid response") }
            catch { XCTAssertEqual(error as? TorBoxError,.invalidResponse) }
        }
    }
    func testCompletionFlagsNotStatusTextDeterminePlaybackReadiness() throws {
        let value = try torrent(#"{"id":7,"download_state":"completed","download_present":false,"download_finished":true,"files":[]}"#)
        XCTAssertFalse(value.ready)
        XCTAssertTrue(try torrent().ready)
    }
    func testSelectedFileCDNResolutionKeepsTheAPIKeyOutOfTheTemporaryURL() async throws {
        let url = "https://cdn.torbox.app/video/episode10.mkv?token=cdn-only"
        let transport = SeanimeTestTransport([(200,result("\"\(url)\""))])
        let value = try await TorBoxClient(key:key,transport:transport).download(torrent:torrent(),fileID:10)
        XCTAssertEqual(value.absoluteString,url); XCTAssertFalse(value.absoluteString.contains(key))
        let requests = await transport.requests, parts = URLComponents(url:requests[0].url!,resolvingAgainstBaseURL:false)!
        XCTAssertEqual(parts.queryItems?.first { $0.name=="file_id" }?.value,"10")
        XCTAssertEqual(parts.queryItems?.first { $0.name=="token" }?.value,key)
        XCTAssertEqual(parts.queryItems?.first { $0.name=="redirect" }?.value,"true")
        XCTAssertNil(parts.queryItems?.first { $0.name=="zip_link" }, "A selected video must not request the whole torrent as an archive")
    }
    func testSingleFileAndBatchRedirectsPreserveExactSelectionThroughVidHub() async throws {
        let single = #"{"id":120117427,"download_present":true,"download_finished":true,"files":[{"id":0,"name":"Episode 01.mkv"}]}"#
        let batch = #"{"id":120115853,"download_present":true,"download_finished":true,"files":[{"id":0,"name":"Episode 01.mkv"},{"id":1,"name":"Episode 02.mkv"},{"id":5,"name":"Episode 03.mkv"},{"id":8,"name":"Episode 04.mkv"}]}"#
        for (json, fileID, status) in [(single, 0, 307), (batch, 5, 302), (batch, 8, 303), (single, 0, 308)] {
            let cloud = try torrent(json)
            let link = "https://nexus-090.cnam.tb-cdn.io:8443/download/selected-file-\(fileID).mkv?token=cdn%2Bsignature%2Fvalue%3D&filename=Episode%20%26%20Friends.mkv"
            let transport = TorBoxLinkTransport(status: status, headers: ["Location":link], body: "")
            let video = try await TorBoxClient(key:key, transport:transport).download(torrent:cloud, fileID:fileID)
            XCTAssertEqual(video.absoluteString, link)
            let source = try JSONDecoder().decode(StremioStream.self, from: JSONSerialization.data(withJSONObject: ["url":video.absoluteString]))
            let tracked = try VidHubPlayback.launchURL(stream:source, pending:PendingPlayback(episode:PlaybackEpisode(animeID:1,episode:3), title:"Episode 3"))
            let untracked = try VidHubPlayback.untrackedLaunchURL(stream:source,title:"Selected file")
            for launch in [tracked, untracked] {
                let parts = try XCTUnwrap(URLComponents(url:launch,resolvingAgainstBaseURL:false))
                XCTAssertEqual(parts.queryItems?.first { $0.name == "url" }?.value, link, "Do not decode or rebuild a signed CDN URL")
                XCTAssertFalse(launch.absoluteString.contains(key))
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count,1, "Capture the CDN location without following it or adding the torrent again")
            XCTAssertEqual(requests[0].httpMethod,"GET")
            XCTAssertEqual(requests[0].url?.host,"api.torbox.app")
            let query = try XCTUnwrap(URLComponents(url:requests[0].url!,resolvingAgainstBaseURL:false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "torrent_id" }?.value,String(cloud.id))
            XCTAssertEqual(query.first { $0.name == "file_id" }?.value,String(fileID), "Use TorBox's file ID, not the array index")
            XCTAssertEqual(query.first { $0.name == "redirect" }?.value,"true")
            XCTAssertNil(query.first { $0.name == "zip_link" })
        }
    }
    func testJSONPlaybackLinkFallbackAllowsHTTPSCDNPortsWithoutWeakeningProviderPolicy() async throws {
        let link = "https://video.example:8443/episode.mkv?signature=cdn%2Btoken%2Fvalue%3D"
        let data = String(data:try JSONSerialization.data(withJSONObject:["success":true,"data":link]),encoding:.utf8)!
        let transport = TorBoxLinkTransport(status:200,headers:[:],body:data)
        let video = try await TorBoxClient(key:key,transport:transport).download(torrent:torrent(),fileID:10)
        XCTAssertEqual(video.absoluteString,link)
        XCTAssertThrowsError(try SeanimeNetworkPolicy.httpsURL(link), "Extension network restrictions must remain intact")
    }
    func testPlaybackLinkFailuresExplainTheStageWithoutLeakingResponseData() async throws {
        for (status, headers, body, expected) in [
            (307, [String:String](), "private \(key)", TorBoxError.missingPlaybackLink),
            (200, [:], result("null"), .missingPlaybackLink),
            (200, [:], result("\"   \""), .missingPlaybackLink),
            (200, [:], result("{\"private\":\"\(key)\"}"), .playbackResponse),
            (200, [:], "private \(key)", .playbackResponse),
            (307, ["Location":"https://video.example:0/file"], "", .invalidPlaybackLink),
            (307, ["Location":"https://video.example:65536/file"], "", .invalidPlaybackLink),
            (307, ["Location":"https://127.0.0.1/file"], "", .invalidPlaybackLink),
            (307, ["Location":"https://user:\(key)@video.example/file"], "", .privatePlaybackLink),
            (307, ["Location":"https://api.torbox.app/v1/api/torrents/requestdl?token=\(key)"], "", .privatePlaybackLink),
            (307, ["Location":"https://video.example/file?token=\(key)"], "", .privatePlaybackLink)
        ] {
            let transport = TorBoxLinkTransport(status:status,headers:headers,body:body)
            do { _ = try await TorBoxClient(key:key,transport:transport).download(torrent:torrent(),fileID:9); XCTFail("Expected link failure") }
            catch {
                XCTAssertEqual(error as? TorBoxError,expected)
                XCTAssertFalse(error.localizedDescription.contains(key)); XCTAssertFalse(error.localizedDescription.contains("private "))
                XCTAssertFalse(error.localizedDescription.contains("https://"))
            }
            let requests = await transport.requests; XCTAssertEqual(requests.count,1)
        }
    }
    func testPlaybackLinkRequestsKeepTorBoxAuthenticationAndServiceErrors() async throws {
        for (status,body,expected) in [
            (403,#"{"success":false,"error":"BAD_TOKEN","data":null}"#,TorBoxError.unauthorized),
            (429,"private \(key)",.rateLimited),
            (500,#"{"success":false,"error":"UNKNOWN_ERROR","data":null}"#,.rejected(status:500,code:"UNKNOWN_ERROR"))
        ] {
            let transport = TorBoxLinkTransport(status:status,headers:["Location":"https://video.example/file"],body:body)
            do { _ = try await TorBoxClient(key:key,transport:transport).download(torrent:torrent(),fileID:9); XCTFail("Expected API failure") }
            catch { XCTAssertEqual(error as? TorBoxError,expected) }
            let requests = await transport.requests; XCTAssertEqual(requests.count,1)
        }
    }
    func testNotReadyOrNonVideoCannotGenerateDownloadRequest() async throws {
        let transport = SeanimeTestTransport([]), client = try TorBoxClient(key:key,transport:transport)
        do { _ = try await client.download(torrent:torrent(),fileID:11); XCTFail("Expected invalid file") } catch { XCTAssertEqual(error as? TorBoxError,.invalidFile) }
        let waiting = try torrent(ready.replacingOccurrences(of:"\"download_finished\":true",with:"\"download_finished\":false"))
        do { _ = try await client.download(torrent:waiting,fileID:9); XCTFail("Expected wait") } catch { XCTAssertEqual(error as? TorBoxError,.notReady) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCDNResolutionRejectsUnsafeFilesAndAccountPermalinks() async throws {
        let value = try torrent(#"{"id":7,"files":[{"id":1,"name":"infected.mkv","infected":true},{"id":2,"name":"archive.mkv","zipped":true},{"id":3,"name":"sample.zip"},{"id":4,"name":"valid.mkv"}]}"#)
        XCTAssertEqual(value.videoFiles.map(\.id),[4])
        for (url,expected) in [("http://cdn.torbox.app/file",TorBoxError.invalidPlaybackLink), ("https://api.torbox.app/v1/api/torrents/requestdl?token=\(key)",.privatePlaybackLink), ("https://cdn.torbox.app/file?token=\(key)",.privatePlaybackLink), ("file:///private/video.mkv",.invalidPlaybackLink)] {
            do { _ = try await TorBoxClient(key:key,transport:SeanimeTestTransport([(200,result("\"\(url)\""))])).download(torrent:torrent(),fileID:9); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? TorBoxError,expected) }
        }
    }
    func testTorBoxErrorsAreSanitizedAndDoNotLeakPrivateBodiesOrToken() async throws {
        for (status,json,expected) in [
            (401,"private \(key)",TorBoxError.unauthorized), (429,"private \(key)",.rateLimited),
            (200,#"{"success":false,"error":"DOWNLOAD_NOT_CACHED","data":null}"#,.notCached),
            (200,#"{"success":false,"error":"MONTHLY_LIMIT","data":{"monthly_limit":1}}"#,.quota),
            (200,#"{"success":true,"error":null,"data":"wrong"}"#,.invalidResponse), (302,"private redirect",.rejected(status: 302, code: nil))] {
            do { try await TorBoxClient(key:key,transport:SeanimeTestTransport([(status,json)])).verify(); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? TorBoxError,expected); XCTAssertFalse(error.localizedDescription.contains(key)); XCTAssertFalse(error.localizedDescription.contains("private redirect")) }
        }
    }
    func testHTTP400CacheMissAndAccountLimitsAreNotNetworkFailures() async throws {
        for (code, detail, expected) in [
            ("DOWNLOAD_NOT_CACHED", "Not cached", TorBoxError.notCached),
            ("DIFF_ISSUE", "This torrent is not cached on TorBox", .notCached),
            ("DIFF_ISSUE", "You have reached the maximum queued downloads limit", .quota),
            ("MONTHLY_LIMIT", "Monthly limit", .quota), ("ACTIVE_LIMIT", "Active limit", .quota),
            ("COOLDOWN_LIMIT", "Cooldown", .quota), ("DOWNLOAD_TOO_LARGE", "Too large", .quota),
            ("PLAN_RESTRICTED_FEATURE", "Upgrade required", .planRestricted),
            ("BOZO_TORRENT", "Invalid torrent", .invalidTorrent), ("ITEM_NOT_FOUND", "Missing", .missingTorrent)
        ] {
            let json = "{\"success\":false,\"error\":\"\(code)\",\"detail\":\"\(detail) private \(key)\",\"data\":null}"
            let transport = SeanimeTestTransport([(400, json)])
            do { _ = try await TorBoxClient(key:key, transport:transport).add(magnet:magnet, cachedOnly:true); XCTFail("Expected TorBox rejection") }
            catch { XCTAssertEqual(error as? TorBoxError, expected); XCTAssertFalse(error.localizedDescription.contains(key)) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, "A rejected add must never be resubmitted automatically")
        }
    }
    func testUnknownHTTPRejectionsAndServerErrorsRetainOnlySafeDiagnostics() async throws {
        for (status, code) in [(400, "FUTURE_OPTION"), (500, "DOWNLOAD_SERVER_ERROR"), (403, "PLAN_RESTRICTED_FEATURE")] {
            let json = "{\"success\":false,\"error\":\"\(code)\",\"detail\":\"https://private.example/?token=\(key)\",\"data\":{\"token\":\"\(key)\"}}"
            let expected: TorBoxError = code == "PLAN_RESTRICTED_FEATURE" ? .planRestricted : .rejected(status:status, code:code)
            do { try await TorBoxClient(key:key, transport:SeanimeTestTransport([(status, json)])).verify(); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? TorBoxError, expected); XCTAssertFalse(error.localizedDescription.contains(key)); XCTAssertFalse(error.localizedDescription.contains("private.example")) }
        }
        for code in [key, "BAD_" + key, "PRIVATE TOKEN", String(repeating:"X", count:65)] {
            let json = "{\"success\":false,\"error\":\"\(code)\",\"detail\":\"\(key)\",\"data\":null}"
            do { try await TorBoxClient(key:key, transport:SeanimeTestTransport([(400, json)])).verify(); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? TorBoxError, .rejected(status:400, code:nil)); XCTAssertFalse(error.localizedDescription.contains(key)) }
        }
    }
    func testNonJSONHTTPFailureDoesNotClaimAnOfflineDeviceOrAnInvalidKey() async throws {
        for status in [400, 403, 422, 500, 503] {
            do { try await TorBoxClient(key:key, transport:SeanimeTestTransport([(status, "private \(key)")])).verify(); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? TorBoxError, .rejected(status:status, code:nil)); XCTAssertFalse(error.localizedDescription.contains(key)) }
        }
    }
    func testCacheOnlyCanBeChangedOnlyByAnExplicitSecondAdd() async throws {
        let transport = SeanimeTestTransport([(400, #"{"success":false,"error":"DOWNLOAD_NOT_CACHED","data":null}"#), (200, result(#"{"torrent_id":7}"#))])
        let client = try TorBoxClient(key:key, transport:transport)
        do { _ = try await client.add(magnet:magnet, cachedOnly:true); XCTFail("Expected cache miss") }
        catch { XCTAssertEqual(error as? TorBoxError, .notCached) }
        let beforeRetry = await transport.requests
        XCTAssertEqual(beforeRetry.count, 1)
        let id = try await client.add(magnet:magnet, cachedOnly:false)
        XCTAssertEqual(id.torrentID, 7)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(String(data:requests[1].httpBody!, encoding:.utf8)!.contains("name=\"add_only_if_cached\"\r\n\r\nfalse"))
    }
    func testNetworkTimeoutOfflineAndCancellationHaveDifferentSafeOutcomes() async throws {
        for (code, expected) in [(URLError.Code.notConnectedToInternet, TorBoxError.offline), (.timedOut, .timedOut), (.cannotConnectToHost, .unavailable)] {
            do { try await TorBoxClient(key:key, transport:TorBoxFailingTransport(code:code)).verify(); XCTFail("Expected network failure") }
            catch { XCTAssertEqual(error as? TorBoxError, expected); XCTAssertFalse(error.localizedDescription.contains(key)) }
        }
        do { try await TorBoxClient(key:key, transport:TorBoxFailingTransport(code:.cancelled)).verify(); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testQueuedSubmissionRecoversByHashAndResolvesTheSelectedFileWithOnlyOnePOST() async throws {
        let batch = ready.replacingOccurrences(of: "\"name\":\"Batch\"", with: "\"hash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"name\":\"Batch\"")
        let transport = SeanimeTestTransport([
            (200, result(#"{"queued_id":31,"torrent_id":null,"active_limit":3}"#)),
            (200, result("[\(batch)]")), (200, result(#""https://cdn.example/episode10.mkv""#))])
        let client = try TorBoxClient(key:key, transport:transport)
        let job = try await client.add(magnet:magnet, cachedOnly:false)
        XCTAssertNil(job.torrentID); XCTAssertEqual(job.queuedID,31)
        let resolved = try await client.resolve(job)
        let cloud = try XCTUnwrap(resolved)
        XCTAssertEqual(cloud.id,7)
        let url = try await client.download(torrent:cloud, fileID:10)
        XCTAssertEqual(url.absoluteString,"https://cdn.example/episode10.mkv")
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count,1)
        XCTAssertFalse(requests[1].url!.absoluteString.contains("id=31"), "A queue ID is never a torrent ID")
        XCTAssertTrue(requests[2].url!.absoluteString.contains("file_id=10"))
    }
    func testSuccessfulReceiptWithoutIDsIsRecoverableAndNeverAutomaticallyResubmitted() async throws {
        for payload in ["null", "{}", #"{"torrent_id":"7"}"#, #"{"torrent_id":false,"queued_id":null}"#] {
            let batch = ready.replacingOccurrences(of:"\"id\":7", with:"\"id\":\"7\",\"hash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"")
            let transport = SeanimeTestTransport([(200,result(payload)),(200,result("[\(batch)]"))])
            let client = try TorBoxClient(key:key,transport:transport)
            let job = try await client.add(magnet:magnet,cachedOnly:true)
            XCTAssertEqual(job.infoHash,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
            let cloud = try await client.resolve(job)
            XCTAssertEqual(cloud?.id,7)
            let requests = await transport.requests
            XCTAssertEqual(requests.map(\.httpMethod),["POST","GET"])
        }
    }
    func testSDKArbitraryErrorValueDoesNotInvalidateASuccessfulReceipt() async throws {
        for value in ["false", "{}", "[]", "null", "\"\""] {
            let json = "{\"success\":true,\"error\":\(value),\"detail\":null,\"data\":{\"torrent_id\":7}}"
            let job = try await TorBoxClient(key:key,transport:SeanimeTestTransport([(200,json)])).add(magnet:magnet,cachedOnly:true)
            XCTAssertEqual(job.torrentID,7)
        }
    }
    func testOptionalDisplayMetadataDoesNotBreakFilesAndUnknownSafetyFlagsCannotPlay() async throws {
        let json = #"{"id":"7","download_present":true,"download_finished":true,"progress":"1","files":[{"id":"9","name":"episode.mkv","short_name":null,"mimetype":false,"size":"123"},{"id":10,"name":"unsafe.mkv","infected":"unknown"},{"id":11,"name":"zipped.mkv","zipped":{}}]}"#
        let client = try TorBoxClient(key:key,transport:SeanimeTestTransport([(200,result(json))]))
        let cloud = try await client.torrent(id:7)
        XCTAssertTrue(cloud.ready); XCTAssertEqual(cloud.videoFiles.map(\.id),[9])
        XCTAssertNil(cloud.progress); XCTAssertNil(cloud.videoFiles[0].mimetype)
    }
    func testHashRecoveryDoesNotChooseSimilarNamesAndNormalizesBase32() async throws {
        let unrelated = #"{"id":8,"name":"Batch","hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","files":[]}"#
        let transport = SeanimeTestTransport([(200,result("[\(unrelated)]"))])
        let value = try await TorBoxClient(key:key,transport:transport).resolve(TorBoxJob(magnet:magnet))
        XCTAssertNil(value)
        let job = try TorBoxJob(magnet:"magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(job.infoHash,String(repeating:"0",count:40))
        XCTAssertEqual(try JSONDecoder().decode(TorBoxJob.self,from:JSONEncoder().encode(job)),job)
    }
    func testHashRecoveryPagesPastAnAccountPageAndKeepsTheExactFileID() async throws {
        let first = (0..<100).map { "{\"id\":\($0 + 100),\"hash\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}" }.joined(separator:",")
        let batch = ready.replacingOccurrences(of:"\"id\":7", with:"\"id\":7,\"hash\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"")
        let transport = SeanimeTestTransport([(200,result("[\(first)]")),(200,result("[\(batch)]"))])
        let cloud = try await TorBoxClient(key:key,transport:transport).resolve(TorBoxJob(magnet:magnet))
        XCTAssertEqual(cloud?.videoFiles.map(\.id),[9,10])
        let requests = await transport.requests
        XCTAssertTrue(requests[1].url!.absoluteString.contains("offset=100"))
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testAcceptedJobCanWaitForMetadataWithoutLosingItsID() async throws {
        let transport = SeanimeTestTransport([(200,result("null")),(200,result(ready))])
        let client = try TorBoxClient(key:key,transport:transport)
        let job = TorBoxJob(torrentID:7)
        let waiting = try await client.resolve(job)
        XCTAssertNil(waiting)
        let ready = try await client.resolve(job)
        XCTAssertEqual(ready?.id,7)
        let requests = await transport.requests
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }
}

private struct TorBoxFailingTransport: HTTPTransport {
    let code: URLError.Code
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(code) }
}

private actor TorBoxLinkTransport: HTTPTransport {
    let status: Int
    let headers: [String:String]
    let body: String
    private(set) var requests: [URLRequest] = []
    init(status: Int, headers: [String:String], body: String) { self.status = status; self.headers = headers; self.body = body }
    func data(for request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        requests.append(request)
        return (Data(body.utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:headers)!)
    }
}

private actor SeanimeTestTransport: HTTPTransport {
    var responses: [(Int,String)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Int,String)]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation(); requests.append(request)
        guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
        let value = responses.removeFirst()
        return (Data(value.1.utf8),HTTPURLResponse(url:request.url!,statusCode:value.0,httpVersion:nil,headerFields:nil)!)
    }
}
