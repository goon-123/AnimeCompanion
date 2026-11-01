import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CommunityTests: XCTestCase {
    private func thread(_ title: String, ids: [Int] = [42], source: CommunitySource = .aniList) -> CommunityThread {
        CommunityThread(source: source, threadID: 100, title: title, author: "viewer", activityAt: nil, commentCount: 2,
            media: ids.map { CommunityMedia(id: $0, type: "ANIME", title: AnimeTitle(english: "Show Season 2"), isAdult: false) },
            url: URL(string: "https://anilist.co/forum/thread/100")!)
    }
    func testEpisodeMatchingRequiresOneExactSeasonIDAndNumber() {
        let anime = Anime(id: 42, title: "Show Season 2")
        XCTAssertTrue(CommunityEpisodeTitle.matches(thread("Show Season 2 - Episode 1 Discussion"), anime: anime, episode: 1))
        XCTAssertFalse(CommunityEpisodeTitle.matches(thread("Show Season 2 - Episode 2 Discussion"), anime: anime, episode: 1))
        XCTAssertFalse(CommunityEpisodeTitle.matches(thread("Show Season 2 - Episode 1 Discussion", ids: [43]), anime: anime, episode: 1))
        XCTAssertFalse(CommunityEpisodeTitle.matches(thread("Show Season 2 - Episode 1 Discussion", ids: [42, 43]), anime: anime, episode: 1))
        XCTAssertFalse(CommunityEpisodeTitle.matches(thread("Show Season 2 - Episode 1 Discussion", ids: []), anime: anime, episode: 1))
    }
    func testEpisodeGrammarRejectsRangesSpecialsAndMultipleNumbers() {
        for title in ["Show Episode 1-2", "Show Episodes 1 & 2", "Show Episode 1.5", "Episode 1 and Episode 2", "Show Episode 0"] {
            XCTAssertNil(CommunityEpisodeTitle.parse(title), title)
        }
        XCTAssertEqual(CommunityEpisodeTitle.parse("Show - Ep. 01 Discussion")?.episode, 1)
        XCTAssertNil(CommunityEpisodeTitle.parse("Show general discussion"))
    }
    func testNumberingOffsetsAreExplicitAndPreserveSeasonTitles() {
        let anime = Anime(id: 42, title: "Show Season 2")
        let match = thread("Show Season 2 Episode 13 Discussion", source: .myAnimeList)
        XCTAssertFalse(CommunityEpisodeTitle.matches(match, anime: anime, episode: 1))
        XCTAssertTrue(CommunityEpisodeTitle.matches(match, anime: anime, episode: 1, offset: 12))
        XCTAssertFalse(CommunityEpisodeTitle.matches(thread("Show Season 1 Episode 13", source: .myAnimeList), anime: anime, episode: 1, offset: 12))
        XCTAssertFalse(CommunityEpisodeTitle.matches(thread("Show Episode 13", source: .myAnimeList), anime: anime, episode: 1, offset: 12))
    }
    func testUnwatchedEpisodeTitlesDoNotLeakAsPreviews() {
        let item = thread("Show Episode 5 - A huge plot spoiler")
        XCTAssertFalse(item.previewTitle(progress: [42: 4]).contains("huge plot spoiler"))
        XCTAssertFalse(item.previewTitle(progress: [:]).contains("huge plot spoiler"))
        XCTAssertTrue(item.previewTitle(progress: [42: 5]).contains("huge plot spoiler"))
        XCTAssertFalse(thread("Show Episodes 5-6 - Spoiler").previewTitle(progress: [42: 100]).contains("Spoiler"))
    }
    func testSpoilerMarkupRemainsHiddenInNativeText() {
        for raw in ["Before ~!secret!~ after", "Before [spoiler=Ending]secret[/spoiler] after", "Before >!secret!< after", "<p>Before</p><div class='spoiler'><div class='spoiler_content'>secret</div></div><p>after</p>"] {
            let pieces = CommunityText.segments(raw)
            let visible = pieces.compactMap { if case .text(let text) = $0 { return text }; return nil }.joined()
            let hidden = pieces.compactMap { if case .spoiler(let text) = $0 { return text }; return nil }.joined()
            XCTAssertFalse(visible.contains("secret"), raw)
            XCTAssertTrue(hidden.contains("secret"), raw)
        }
        XCTAssertTrue(CommunityText.segments("Before ~!unclosed secret").allSatisfy { if case .spoiler = $0 { return true }; return false })
    }
    func testAniListCommentsDecodeRawJSONRepliesAndUsePublicRead() async throws {
        let payload = #"{"data":{"Thread":{"id":100,"title":"Show Episode 1","body":"opening","mediaCategories":[]},"Page":{"pageInfo":{"hasNextPage":true},"threadComments":[{"id":1,"comment":"root","user":{"name":"Root"},"createdAt":1700000000,"likeCount":2,"childComments":[{"id":2,"comment":"<span class='spoiler'>secret</span>","user":{"name":"Reply"},"childComments":[{"id":3,"comment":"nested","user":null,"childComments":null}]}]}]}}}"#
        let transport = CommunityTransport(payload)
        let client = AniListClient(transport: transport, minimumRequestInterval: 0)
        let result = try await client.communityComments(threadID: 100, page: 2, sort: .newest)
        XCTAssertTrue(result.hasNextPage)
        XCTAssertEqual(result.comments.first?.replies.first?.author, "Reply")
        XCTAssertEqual(result.comments.first?.replies.first?.replies.first?.author, "Deleted user")
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertTrue((body["query"] as? String ?? "").contains("childComments"))
        XCTAssertFalse((body["query"] as? String ?? "").contains("childComments {"))
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(variables["sort"] as? String, "ID_DESC")
        XCTAssertEqual(variables["page"] as? Int, 2)
    }
    func testRemovedAniListThreadIsNotAnEmptySuccess() async throws {
        let client = AniListClient(transport: CommunityTransport(#"{"data":{"Thread":null,"Page":{"pageInfo":null,"threadComments":[]}}}"#), minimumRequestInterval: 0)
        do { _ = try await client.communityComments(threadID: 100); XCTFail("Removed thread must report unavailable") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unavailable")) }
    }
    func testMALReadsActualPostBodiesAndReconstructsPaginationOnOfficialHost() async throws {
        let transport = CommunityTransport(#"{"data":{"title":"Show Episode 1","posts":[{"id":10,"body":"<p>Real post</p>","created_at":"2026-10-29T12:00:00+00:00","created_by":{"name":"Reader"}}]},"paging":{"next":"https://untrusted.example/ignored"}}"#)
        let client = MALCommunityClient(transport: transport, minimumRequestInterval: 0)
        let result = try await client.comments(threadID: 100, clientID: "registered-id", page: 2)
        XCTAssertEqual(result.comments.first?.body, "<p>Real post</p>")
        XCTAssertEqual(result.comments.first?.author, "Reader")
        XCTAssertNil(result.comments.first?.score)
        XCTAssertTrue(result.hasNextPage)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.host, "api.myanimelist.net")
        XCTAssertTrue(request.url?.query?.contains("offset=25") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MAL-CLIENT-ID"), "registered-id")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testRedditFallbackUsesOfficialPageWithSeasonNameIntact() {
        let anime = Anime(id: 42, title: "Show Season 2")
        let url = CommunityBrowserLinks.reddit(filter: .episodes, anime: anime, episode: 1)
        XCTAssertEqual(url.host, "www.reddit.com")
        // Foundation's URL.path drops a trailing slash on Linux but preserves it on Darwin.
        XCTAssertTrue(["/r/anime/search", "/r/anime/search/"].contains(url.path))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
        XCTAssertTrue(query.contains("Show Season 2")); XCTAssertTrue(query.contains("Episode 1"))
        XCTAssertFalse(url.path.contains(".json"))
    }
}

private actor CommunityTransport: HTTPTransport {
    let payload: Data
    private var requests: [URLRequest] = []
    init(_ raw: String) { payload = Data(raw.utf8) }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (payload, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
    func lastRequest() -> URLRequest? { requests.last }
}
