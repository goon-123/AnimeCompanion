import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Neutral, owned metadata. No real tokens, libraries, book text or cover bytes.
final class MangaBakaTests: XCTestCase {
    private let record = #"{"id":81,"type":"manhwa","status":"releasing","content_rating":"safe","rating":82.5,"titles":[{"language":"ja","title":"Native","is_primary":true},{"language":"en","title":"Alternate","is_primary":false},{"language":"en","title":"Paper Moon","is_primary":true}],"description":"A <b>gentle</b> adventure.","published":{"start_date":"2024-07-01"},"cover":{"x350":"https://cdn.mangabaka.dev/owned-cover.jpg"},"authors":["Owned Author"],"total_chapters":20}"#
    private func series(_ json: String) throws -> MangaBakaSeries { try JSONDecoder().decode(MangaBakaSeries.self, from: Data(json.utf8)) }
    private func page(_ record: String, next: String = "null", count: Int = 1, page: Int = 1) -> String {
        "{\"status\":200,\"data\":[\(record)],\"pagination\":{\"count\":\(count),\"page\":\(page),\"next\":\(next)}}"
    }
    private func client(_ transport: MBTestTransport, directory: URL? = nil) -> MangaBakaClient {
        MangaBakaClient(transport: transport, directory: directory, minimumRequestInterval: 0)
    }
    private func key(_ kind: MangaBakaCredential.Kind = .apiKey) throws -> MangaBakaCredential {
        try MangaBakaCredential(kind: kind, secret: "owned-test-credential")
    }
    func testFormatsAndVerifiedSortKeys() {
        XCTAssertEqual(MangaBakaFormat.allCases.map(\.rawValue), ["manga", "novel", "manhwa", "manhua", "oel", "other"])
        XCTAssertEqual(MangaBakaShelf.recentlyAdded.sort, "latest")
        XCTAssertEqual(MangaBakaShelf.popular.sort, "popularity_asc")
        XCTAssertEqual(MangaBakaShelf.topRated.sort, "score_desc")
    }
    func testAniListAdaptationLookupHydratesTheMangaBakaIdentityAndCachesPublicRequests() async throws {
        let transport = MBTestTransport([.json(#"{"data":{"id":"30002","series":[{"id":81,"state":"active"},{"id":81,"state":"active"},{"id":82,"state":"merged"},{"id":83,"state":"deleted"}]}}"#),
            .json("{\"data\":\(record)}")])
        let api = client(transport)
        for _ in 0..<2 {
            let matches = try await api.series(anilistID: 30002)
            XCTAssertEqual(matches.map(\.id), [81]); XCTAssertEqual(matches.first?.displayTitle, "Paper Moon")
        }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/source/anilist/30002", "/v1/series/81"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "X-API-Key") == nil })
    }
    func testAniListLookupPreservesMultipleMatchesAndTheirContentRatings() async throws {
        let transport = MBTestTransport([.json(#"{"data":{"id":30002,"series":[{"id":"81"},{"id":82,"state":"active"}]}}"#),
            .json("{\"data\":\(record)}"), .json(#"{"data":{"id":82,"type":"novel","content_rating":"erotica"}}"#)])
        let matches = try await client(transport).series(anilistID: 30002)
        XCTAssertEqual(matches.map(\.id), [81, 82])
        XCTAssertEqual(matches.filter { $0.isVisible(includeAdult: false) }.map(\.id), [81])
        XCTAssertEqual(matches.last?.type, "novel")
    }
    func testMissingAniListMappingReturnsNoMatchWithoutSearchingForAnotherTitle() async throws {
        for reply in [MBTestTransport.Response.json(#"{"data":{"id":30002,"series":[]}}"#),
            .json(#"{"data":{"id":30002,"series":[{"id":81,"state":"merged"}]}}"#), .json("{}", status: 404)] {
            let transport = MBTestTransport([reply])
            let matches = try await client(transport).series(anilistID: 30002)
            XCTAssertTrue(matches.isEmpty)
            let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
        }
    }
    func testAniListMappingRejectsWrongIdentitiesAndMalformedSourcePayloads() async throws {
        for body in [#"{"data":{"id":999,"series":[{"id":81}]}}"#,
            #"{"data":{"id":30002}}"#, #"{"data":{"id":30002,"series":[{"id":0}]}}"#] {
            let transport = MBTestTransport([.json(body)])
            do { _ = try await client(transport).series(anilistID: 30002); XCTFail("An invalid mapping must not open another series") }
            catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
            let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
        }
        let wrongDetails = MBTestTransport([.json(#"{"data":{"id":30002,"series":[{"id":82}]}}"#), .json("{\"data\":\(record)}")])
        do { _ = try await client(wrongDetails).series(anilistID: 30002); XCTFail("Detail identity must match the mapping") }
        catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
    }
    func testAniListMappingFailureCanBeRetriedWithoutBecomingAMissingListing() async throws {
        let transport = MBTestTransport([.json("{}", status: 503), .json(#"{"data":{"id":30002,"series":[{"id":81}]}}"#),
            .json("{\"data\":\(record)}")]), api = client(transport)
        do { _ = try await api.series(anilistID: 30002); XCTFail("Service failure must offer retry") }
        catch { XCTAssertEqual(error as? MangaBakaError, .http(503)) }
        let matches = try await api.series(anilistID: 30002, refresh: true)
        XCTAssertEqual(matches.map(\.id), [81])
    }
    func testInvalidAniListIdentityNeverRequestsTheCatalog() async throws {
        let transport = MBTestTransport([]), api = client(transport)
        for id in [0, -1] {
            do { _ = try await api.series(anilistID: id); XCTFail("Invalid AniList identity") }
            catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
        }
        let requests = await transport.recorded(); XCTAssertTrue(requests.isEmpty)
    }
    func testGenreTagAndContentRatingFiltersComposeWithSearchAndPaging() throws {
        let query = MangaBakaQuery(format: .manga, text: "Moon & stars", genres: [.init(value: "science_fiction", label: "Sci-Fi")],
            tags: [.init(id: 42, name: "space_travel")], excludedTags: [.init(id: 91, name: "time_loop")], contentRatings: [.suggestive])
        let url = MangaBakaClient.browseURL(query, page: 3, limit: 30, includeAdult: true)
        XCTAssertEqual(url.path, "/v1/series/search")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        for item in [URLQueryItem(name: "genre", value: "science_fiction"), .init(name: "tag", value: "42"),
                     .init(name: "tag_not", value: "91"), .init(name: "page", value: "3"), .init(name: "content_rating", value: "suggestive")] {
            XCTAssertTrue(items.contains(item))
        }
        XCTAssertEqual(items.filter { $0.name == "content_rating" }.count, 1)
        let filteredShelf = MangaBakaClient.browseURL(.init(shelf: .hiddenGems, tags: query.tags), page: 1, limit: 24, includeAdult: false)
        XCTAssertTrue(filteredShelf.path.hasSuffix("/search"))
        let ratingOnly = MangaBakaClient.browseURL(.init(contentRatings: [.suggestive]), page: 1, limit: 24, includeAdult: false)
        XCTAssertEqual(ratingOnly.path, "/v2/series/search")
    }
    func testMatureOnlyFilterDoesNotFallBackToUnfilteredSearch() async throws {
        let query = MangaBakaQuery(contentRatings: [.erotica])
        XCTAssertTrue(query.allowedRatings(includeAdult: false).isEmpty)
        let transport = MBTestTransport([]), api = client(transport)
        do { _ = try await api.browse(query, includeAdult: false); XCTFail("Must not broaden an unavailable rating") } catch {}
        let requests = await transport.recorded(); XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(query.includes(try series(record), includeAdult: true))
    }
    func testPublisherIdentityAndLegacyNameFiltersComposeWithoutBecomingTitleSearch() throws {
        let publisher = try JSONDecoder().decode(MangaBakaPublisher.self, from: Data(#"{"id":"19","name":"Owned & Other Press"}"#.utf8))
        XCTAssertEqual(publisher.id, 19)
        let byID = MangaBakaQuery(shelf: .hiddenGems, format: .manga, text: "Moon", status: "completed",
            genres: [.init(value: "fantasy", label: "Fantasy")], contentRatings: [.safe], publisher: publisher)
        XCTAssertTrue(byID.hasFacets); XCTAssertEqual(byID.filterCount, 5)
        let url = MangaBakaClient.browseURL(byID, page: 2, limit: 30, includeAdult: false)
        XCTAssertEqual(url.path, "/v1/series/search")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        for item in [URLQueryItem(name: "publisher_id", value: "19"), .init(name: "genre", value: "fantasy"),
            .init(name: "q", value: "Moon"), .init(name: "type", value: "manga"), .init(name: "status", value: "completed"),
            .init(name: "page", value: "2"), .init(name: "content_rating", value: "safe")] {
            XCTAssertTrue(items.contains(item))
        }
        XCTAssertFalse(items.contains { $0.name == "publisher" })
        let legacy = MangaBakaQuery(publisher: .init(name: "Owned & Other Press"))
        let named = MangaBakaClient.browseURL(legacy, page: 3, limit: 24, includeAdult: false)
        XCTAssertEqual(named.path, "/v1/series/search")
        let namedItems = try XCTUnwrap(URLComponents(url: named, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(namedItems.contains(.init(name: "publisher", value: "Owned & Other Press")))
        XCTAssertFalse(namedItems.contains { $0.name == "q" || $0.name == "publisher_id" })
        let modern = MangaBakaClient.browseURL(.init(publisher: publisher), page: 1, limit: 24, includeAdult: false)
        XCTAssertEqual(modern.path, "/v2/series/search")
        XCTAssertNotEqual(legacy, MangaBakaQuery(publisher: publisher))
    }
    func testTaxonomyAndDetailedTagsRetainHierarchyAndLabels() async throws {
        let transport = MBTestTransport([.json(#"{"data":[{"value":"science_fiction","label":"Sci-Fi"}]}"#),
            .json(#"{"data":[{"id":42,"name":"space_travel","name_path":"Themes > Science > Space Travel","description":"A <b>journey</b>.","is_spoiler":true,"is_implied":true,"weight":3}]}"#)])
        let api = client(transport)
        let genres = try await api.genres(), tags = try await api.tags()
        XCTAssertEqual(genres.first?.value, "science_fiction"); XCTAssertEqual(genres.first?.label, "Sci-Fi")
        XCTAssertEqual(tags.first?.id, 42); XCTAssertEqual(tags.first?.category, "Themes")
        XCTAssertEqual(tags.first?.path, "Themes > Science > Space Travel")
        XCTAssertEqual(tags.first?.description, "A journey."); XCTAssertEqual(tags.first?.weight, 3)
        XCTAssertEqual(tags.first?.isSpoiler, true); XCTAssertEqual(tags.first?.isImplied, true)
        let detail = try series(#"{"id":81,"tags":["space_travel"],"published":{"start_date":"2020-01-01","end_date":"2022-03-01"},"publishers":[{"name":"Owned Press"}],"is_licensed":true}"#)
        XCTAssertEqual(detail.tags.first?.name, "space_travel"); XCTAssertEqual(detail.publishedEnd, "2022-03-01")
        XCTAssertTrue(detail.isLicensed); XCTAssertEqual(detail.publishers.first?.name, "Owned Press")
        let weighted = try series(#"{"id":81,"tags_v2":[{"id":42,"name":"space_travel","name_path":"Themes > Space","weight":"core","implied_by_tag_ids":[1]}],"popularity":{"global":{"current":10}},"source":{"anilist":{"id":1,"rating_normalized":85}}}"#)
        XCTAssertEqual(weighted.tags.first?.weightLabel, "core"); XCTAssertEqual(weighted.tags.first?.isImplied, true)
        XCTAssertEqual(weighted.popularityRank, 10); XCTAssertEqual(weighted.sourceRatings.first?.score, 85)
    }
    func testCoversUseFullImagesAndValidateSeriesBeforeShowing() async throws {
        let image = #"{"id":5,"series_id":81,"type":"volume","index":"2","language":"en","content_rating":"safe","image":{"raw":{"url":"https://cdn.mangabaka.dev/full.jpg"},"x350":{"x1":"https://cdn.mangabaka.dev/thumb.jpg"}}}"#
        let transport = MBTestTransport([.json(page(image)), .json(page(image))]), api = client(transport)
        let covers = try await api.covers(id: 81)
        XCTAssertEqual(covers.items.first?.thumbnailURL?.lastPathComponent, "thumb.jpg")
        XCTAssertEqual(covers.items.first?.fullURL?.lastPathComponent, "full.jpg")
        XCTAssertEqual(covers.items.first?.caption, "Volume 2 · EN")
        XCTAssertEqual(covers.items.first?.isVisible(includeAdult: false), true)
        do { _ = try await api.covers(id: 82); XCTFail("Wrong title's artwork") } catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
    }
    func testRecommendationKindsUseRealEndpointsAndDropDuplicatesAndHiddenTitles() async throws {
        let other = #"{"id":82,"title":"Another story","content_rating":"safe"}"#
        let hidden = #"{"id":83,"title":"Hidden story","content_rating":"erotica"}"#
        let payload = "{\"data\":[{\"series\":\(other),\"relationship\":\"sequel\",\"shared_tags_total\":12,\"shared_users\":70},{\"series\":\(other)},{\"series\":\(hidden)},{\"series\":\(record)}]}"
        let transport = MBTestTransport(Array(repeating: .json(payload), count: 3)), api = client(transport)
        for kind in MangaBakaRelatedKind.allCases {
            let result = try await api.related(id: 81, kind: kind, includeAdult: false)
            XCTAssertEqual(result.map(\.id), [82]); XCTAssertEqual(result.first?.relationship, "sequel")
            XCTAssertEqual(result.first?.sharedTags, 12); XCTAssertEqual(result.first?.sharedReaders, 70)
        }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/series/81/relationships", "/v2/series/81/similar", "/v2/series/81/readers-also-like"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }
    func testV2TitlesCoverMetadataAndPlainSynopsis() throws {
        let item = try series(record)
        XCTAssertEqual(item.id, 81); XCTAssertEqual(item.displayTitle, "Paper Moon")
        XCTAssertEqual(item.year, 2024); XCTAssertEqual(item.totalChapters, 20)
        XCTAssertEqual(item.coverURL?.host, "cdn.mangabaka.dev")
        XCTAssertFalse(item.synopsis.contains("<b>")); XCTAssertEqual(item.searchTitles.first, "Paper Moon")
        XCTAssertEqual(item.websiteURL.absoluteString, "https://mangabaka.org/81")
    }
    func testLegacyDetailsNestedCoverAndNumericStrings() throws {
        let item = try series(#"{"id":"81","title":"Owned title","content_rating":"safe","cover":{"x250":{"x1":"https://cdn.mangabaka.dev/legacy.jpg"}},"year":"2020","total_chapters":"31.5","final_volume":"8","genres":["fantasy",{"id":2,"name":"adventure"}],"source":{"anilist":{"id":10},"my_anime_list":{"id":null}}}"#)
        XCTAssertEqual(item.displayTitle, "Owned title"); XCTAssertEqual(item.coverURL?.lastPathComponent, "legacy.jpg")
        XCTAssertEqual(item.year, 2020); XCTAssertEqual(item.totalChapters, 31.5); XCTAssertEqual(item.finalVolume, 8)
        XCTAssertEqual(item.genres.map(\.name), ["fantasy", "adventure"]); XCTAssertEqual(item.providers, ["AniList"])
    }
    func testRecommendationAliasesAndWrappedSeries() throws {
        let item = try series(#"{"series_id":81,"title":"Owned recommendation","media_type":"novel","cover_image":"https://cdn.mangabaka.dev/recommendation.jpg","published_year":2023,"content_rating":"safe"}"#)
        XCTAssertEqual(item.type, "novel"); XCTAssertEqual(item.year, 2023); XCTAssertNotNil(item.coverURL)
        XCTAssertEqual(try series("{\"series\":\(record)}").id, 81)
    }
    func testContentFilteringFailsClosedForUnknownRatings() throws {
        for rating in ["safe", "suggestive", "erotica", "pornographic", "unknown"] {
            let item = try series("{\"id\":1,\"content_rating\":\"\(rating)\"}")
            XCTAssertEqual(item.isVisible(includeAdult: false), ["safe", "suggestive"].contains(rating))
            XCTAssertTrue(item.isVisible(includeAdult: true))
        }
        XCTAssertFalse(try series(#"{"id":1}"#).isVisible(includeAdult: false))
    }
    func testMalformedIdentityAndUnsafeArtwork() throws {
        for json in [#"{"id":0}"#, #"{"id":-1}"#, #"{"title":"No identity"}"#] { XCTAssertThrowsError(try series(json)) }
        for url in ["http://cdn.mangabaka.dev/a.jpg", "https://localhost/a.jpg", "https://127.0.0.1/a.jpg", "https://reader:secret@example.com/a.jpg", "https://example.com:444/a.jpg"] {
            XCTAssertNil(MangaBakaSeries.publicURL(url))
        }
        XCTAssertNotNil(MangaBakaSeries.publicURL("https://cdn.mangabaka.dev/a.jpg"))
    }
    func testBrowseEncodingRatingsFormatsAndPagination() throws {
        let url = MangaBakaClient.browseURL(.init(shelf: .topRated, format: .novel, status: "completed"), page: 2, limit: 30, includeAdult: false)
        let q = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(q.filter { $0.name == "content_rating" }.compactMap(\.value), ["safe", "suggestive"])
        XCTAssertTrue(q.contains(.init(name: "type", value: "novel"))); XCTAssertTrue(q.contains(.init(name: "page", value: "2")))
        XCTAssertTrue(q.contains(.init(name: "status", value: "completed"))); XCTAssertTrue(q.contains(.init(name: "sort_by", value: "score_desc")))
        XCTAssertTrue(q.contains(.init(name: "rating_lower", value: "1")))
    }
    func testSearchUsesRelevanceAndEncodesReservedText() throws {
        let url = MangaBakaClient.browseURL(.init(text: "  Moon & stars + 1  "), page: 1, limit: 24, includeAdult: false)
        let q = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(q.first { $0.name == "q" }?.value, "Moon & stars + 1")
        XCTAssertNil(q.first { $0.name == "sort_by" })
    }
    func testCuratedQueriesAndNewReleaseDate() throws {
        let gems = MangaBakaClient.browseURL(.init(shelf: .hiddenGems), page: 1, limit: 100, includeAdult: false)
        let q = try XCTUnwrap(URLComponents(url: gems, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(gems.path.hasSuffix("/hidden-gems"))
        XCTAssertEqual(q.filter { $0.name == "not_content_rating" }.compactMap(\.value), ["erotica", "pornographic"])
        let release = MangaBakaClient.browseURL(.init(shelf: .newReleases), page: 1, limit: 24, includeAdult: false, now: Date(timeIntervalSince1970: 1_735_689_600))
        XCTAssertTrue(release.absoluteString.contains("published_start_date_lower=2024-01-02"))
    }
    func testPaginationDoesNotTrustRemoteNextURL() throws {
        let decoded = try JSONDecoder().decode(MangaBakaPage<MangaBakaSeries>.self, from: Data(page(record, next: "\"https://attacker.example/steal\"", count: 200, page: 3).utf8))
        XCTAssertTrue(decoded.hasNext); XCTAssertEqual(decoded.total, 200); XCTAssertEqual(decoded.page, 3)
        let next = MangaBakaClient.browseURL(.init(), page: decoded.page + 1, limit: 24, includeAdult: false)
        XCTAssertEqual(next.host, "api.mangabaka.org"); XCTAssertTrue(next.absoluteString.contains("page=4"))
    }
    func testPublicRequestsCoalesceAndHaveNoCredentials() async throws {
        let transport = MBTestTransport([.json(page(record))]), api = client(transport)
        async let a = api.browse(.init(), includeAdult: false)
        async let b = api.browse(.init(), includeAdult: false)
        let results = try await (a, b)
        XCTAssertEqual(results.0.items.first?.id, results.1.items.first?.id)
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(requests.first?.value(forHTTPHeaderField: "X-API-Key"))
        let session = MangaBakaClient.publicSession()
        XCTAssertNil(session.configuration.httpCookieStorage); XCTAssertNil(session.configuration.urlCredentialStorage)
        session.invalidateAndCancel()
    }
    func testPublicCacheSurvivesRestartAndExcludesAccountData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = MBTestTransport([.json(page(record)), .json(#"{"data":{"id":"owned-user-id","nickname":"Private Name"}}"#)])
        let first = client(transport, directory: directory)
        _ = try await first.browse(.init(), includeAdult: false); _ = try await first.profile(key())
        let bytes = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
        let stored = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(stored.contains("Private Name")); XCTAssertFalse(stored.contains("owned-test-credential")); XCTAssertFalse(stored.contains("/my/"))
        let unused = MBTestTransport([]), restarted = client(unused, directory: directory)
        let cached = try await restarted.browse(.init(), includeAdult: false)
        XCTAssertEqual(cached.items.first?.id, 81)
        let requests = await unused.recorded(); XCTAssertTrue(requests.isEmpty)
    }
    func testFailedRefreshPreservesLastGoodPublicCache() async throws {
        let transport = MBTestTransport([.json(page(record)), .json("{}", status: 503)]), api = client(transport)
        _ = try await api.browse(.init(), includeAdult: false)
        do { _ = try await api.browse(.init(), includeAdult: false, refresh: true); XCTFail("Expected server failure") } catch { XCTAssertEqual(error as? MangaBakaError, .http(503)) }
        let retained = try await api.browse(.init(), includeAdult: false); XCTAssertEqual(retained.items.first?.id, 81)
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
    }
    func testMalformedPublicPayloadIsNotReused() async throws {
        let transport = MBTestTransport([.json(#"{"data":"unexpected"}"#), .json(page(record))]), api = client(transport)
        do { _ = try await api.browse(.init(), includeAdult: false); XCTFail("Expected schema error") } catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
        let recovered = try await api.browse(.init(), includeAdult: false); XCTAssertEqual(recovered.items.count, 1)
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
    }
    func testRateLimitDoesNotRetryOrSpendMoreRequests() async throws {
        let transport = MBTestTransport([.json("{}", status: 429, headers: ["Retry-After": "120"])]), api = client(transport)
        for _ in 0..<2 {
            do { _ = try await api.browse(.init(), includeAdult: false); XCTFail("Expected cooldown") }
            catch { guard let service = error as? MangaBakaError, case .rateLimited(let seconds) = service else { return XCTFail("Wrong error") }; XCTAssertGreaterThan(seconds, 0) }
        }
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
    }
    func testPrivateHeadersAndLibraryPayload() async throws {
        let entry = "{\"series_id\":81,\"Series\":\(record),\"state\":\"reading\",\"progress_chapter\":\"3.5\",\"progress_volume\":2,\"rating\":\"80\",\"is_private\":false,\"note\":\"Owned note\"}"
        let transport = MBTestTransport([.json(#"{"data":{"id":"owned-user","preferred_username":"reader","rating_steps":5}}"#), .json(page(entry))]), api = client(transport)
        let profile = try await api.profile(key(.oauth)), library = try await api.library(key(), page: 2, state: "reading")
        XCTAssertEqual(profile.name, "reader"); XCTAssertEqual(profile.ratingSteps, 5)
        XCTAssertEqual(library.items.first?.chapter, 3.5); XCTAssertEqual(library.items.first?.isPrivate, false)
        let requests = await transport.recorded()
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer owned-test-credential")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "X-API-Key"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "X-API-Key"), "owned-test-credential")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization")); XCTAssertTrue(requests[1].url!.absoluteString.contains("state=reading"))
    }
    func testLibraryIdentitiesAreValidatedBeforeEditing() throws {
        let bad = "{\"series_id\":82,\"series\":\(record),\"state\":\"reading\"}"
        XCTAssertThrowsError(try JSONDecoder().decode(MangaBakaLibraryEntry.self, from: Data(bad.utf8)))
        let entry = try JSONDecoder().decode(MangaBakaLibraryEntry.self, from: Data(#"{"state":"reading","progress_chapter":0}"#.utf8))
        XCTAssertEqual(try entry.attaching(series(record)).id, 81)
    }
    func testMissingEntryIsNotConfusedWithAuthenticationFailure() async throws {
        let transport = MBTestTransport([.json("{}", status: 404), .json("{}", status: 401)]), api = client(transport)
        let missing = try await api.entry(id: 81, credential: key()); XCTAssertNil(missing)
        do { _ = try await api.entry(id: 81, credential: key()); XCTFail("Expected authentication error") } catch { XCTAssertEqual(error as? MangaBakaError, .unauthorized) }
    }
    func testLegacyLibraryPagesWithoutPaginationStillLoadTheRest() async throws {
        let records = (1...40).map { "{\"series\":{\"id\":\($0),\"title\":\"Owned \($0)\",\"content_rating\":\"safe\"},\"state\":\"reading\"}" }.joined(separator: ",")
        let transport = MBTestTransport([.json("{\"data\":[\(records)]}"), .json(#"{"data":[]}"#)]), api = client(transport)
        let first = try await api.library(key(), page: 1, state: nil)
        XCTAssertTrue(first.hasNext); XCTAssertNil(first.total)
        let second = try await api.library(key(), page: 2, state: nil)
        XCTAssertFalse(second.hasNext); XCTAssertEqual(second.page, 2)
    }
    func testWritesUseCorrectMethodsAndExplicitNullsWithoutOtherFields() async throws {
        let transport = MBTestTransport([.json(#"{"status":201,"data":true}"#, status: 201), .json(#"{"data":true}"#), .json("", status: 204)]), api = client(transport)
        let update = try MangaBakaLibraryUpdate(state: "reading", chapter: 0, volume: 1.5, rating: nil, note: nil, isPrivate: false)
        try await api.save(id: 81, update: update, existing: false, credential: key())
        try await api.save(id: 81, update: update, existing: true, credential: key())
        try await api.remove(id: 81, credential: key())
        let requests = await transport.recorded(); XCTAssertEqual(requests.map(\.httpMethod), ["POST", "PUT", "DELETE"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        XCTAssertEqual(body["progress_chapter"] as? Int, 0); XCTAssertEqual(body["progress_volume"] as? Double, 1.5)
        XCTAssertTrue(body["rating"] is NSNull); XCTAssertTrue(body["note"] is NSNull)
        XCTAssertNil(body["start_date"]); XCTAssertNil(body["finish_date"]); XCTAssertNil(body["lists"])
        XCTAssertEqual(body["is_private"] as? Bool, false)
    }
    func testRejectedWritesNeverAutomaticallyRetry() async throws {
        let transport = MBTestTransport([.json("{}", status: 403)]), api = client(transport)
        let update = try MangaBakaLibraryUpdate(state: "reading", chapter: 1, volume: nil, rating: nil, note: nil, isPrivate: true)
        do { try await api.save(id: 81, update: update, existing: false, credential: key()); XCTFail("Expected scope error") } catch { XCTAssertEqual(error as? MangaBakaError, .http(403)) }
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 1)
    }
    func testProgressAndCredentialsValidateInput() throws {
        for value in [-1.0, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try MangaBakaLibraryUpdate(state: "reading", chapter: value, volume: nil, rating: nil, note: nil, isPrivate: true))
        }
        XCTAssertThrowsError(try MangaBakaLibraryUpdate(state: "invalid", chapter: nil, volume: nil, rating: nil, note: nil, isPrivate: true))
        XCTAssertThrowsError(try MangaBakaLibraryUpdate(state: "reading", chapter: nil, volume: nil, rating: 101, note: nil, isPrivate: true))
        XCTAssertThrowsError(try MangaBakaCredential(kind: .apiKey, secret: "x\r\nInjected: secret"))
        XCTAssertThrowsError(try JSONDecoder().decode(MangaBakaCredential.self, from: Data(#"{"kind":"apiKey","secret":""}"#.utf8)))
        let original = try key(); XCTAssertEqual(try JSONDecoder().decode(MangaBakaCredential.self, from: JSONEncoder().encode(original)), original)
    }
    func testOAuthURLAndBoundCallback() throws {
        let date = Date(timeIntervalSince1970: 1000)
        let url = try MangaBakaOAuth.authorize(clientID: "owned-app", state: "owned-state", challenge: "owned-challenge")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "mangabaka.org"); XCTAssertTrue(query.contains(.init(name: "code_challenge_method", value: "S256")))
        XCTAssertTrue(query.contains(.init(name: "redirect_uri", value: "animecompanion://oauth/mangabaka")))
        let callback = URL(string: "animecompanion://oauth/mangabaka?code=owned-code&state=owned-state&iss=https%3A%2F%2Fmangabaka.org%2Fauth")!
        XCTAssertEqual(try MangaBakaOAuth.code(from: callback, expectedState: "owned-state", startedAt: date, now: date.addingTimeInterval(30)), "owned-code")
        XCTAssertThrowsError(try MangaBakaOAuth.code(from: callback, expectedState: "wrong", startedAt: date, now: date))
        XCTAssertThrowsError(try MangaBakaOAuth.code(from: callback, expectedState: "owned-state", startedAt: date, now: date.addingTimeInterval(601)))
    }
    func testOAuthRejectsUnrelatedDuplicateAndErrorCallbacks() {
        let date = Date()
        for value in ["animecompanion://oauth/wrong?code=c&state=s", "https://oauth/mangabaka?code=c&state=s", "animecompanion://oauth/mangabaka?code=c&state=s&state=s", "animecompanion://oauth/mangabaka?code=c&state=s&iss=https://attacker.example", "animecompanion://oauth/mangabaka?error=denied&state=s", "animecompanion://oauth/mangabaka?code=c&state=s#fragment"] {
            XCTAssertThrowsError(try MangaBakaOAuth.code(from: URL(string: value)!, expectedState: "s", startedAt: date, now: date))
        }
    }
    func testTokenExchangeAndRefreshRotation() async throws {
        let transport = MBTestTransport([.json(#"{"access_token":"owned-access","refresh_token":"owned-refresh","expires_in":3600}"#), .json(#"{"access_token":"owned-renewed","refresh_token":"owned-rotated","expires_in":7200}"#)]), api = client(transport)
        let credential = try await api.exchange(code: "owned+code&value", verifier: "owned-verifier", clientID: "owned-app")
        XCTAssertFalse(credential.needsRefresh()); XCTAssertEqual(credential.refreshToken, "owned-refresh")
        let renewed = try await api.refresh(credential); XCTAssertEqual(renewed.secret, "owned-renewed"); XCTAssertEqual(renewed.refreshToken, "owned-rotated")
        let requests = await transport.recorded(), body = String(decoding: requests[0].httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("code=owned%2Bcode%26value")); XCTAssertTrue(body.contains("code_verifier=owned-verifier"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "X-API-Key")); XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(String(decoding: requests[1].httpBody!, as: UTF8.self).contains("grant_type=refresh_token"))
    }
    func testPrivateRecommendationsAreNotCachedOrReplacedByPopular() async throws {
        let transport = MBTestTransport([.json("{\"results\":[\(record)]}"), .json(#"{"results":[]}"#)]), api = client(transport)
        let a = try await api.recommendations(key(), includeAdult: false), b = try await api.recommendations(key(), includeAdult: false)
        XCTAssertEqual(a.count, 1); XCTAssertTrue(b.isEmpty)
        do { _ = try await api.browse(.init(shelf: .recommended), includeAdult: false); XCTFail("Cannot fake recommendations") } catch {}
        let requests = await transport.recorded(); XCTAssertEqual(requests.count, 2)
    }
    func testRecommendationsPreferResultsAndDoNotLoseValidRecordsToOneMalformedItem() async throws {
        let payload = "{\"data\":[],\"results\":[null,{\"unexpected\":true},{\"series\":\(record)},\(record)]}"
        let transport = MBTestTransport([.json(payload)]), api = client(transport)
        let result = try await api.recommendations(key(.oauth), includeAdult: false)
        XCTAssertEqual(result.map(\.id), [81])
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer owned-test-credential")
    }
    func testLeanRecommendationsResolveContentRatingBeforeLocalFilteringWithoutForwardingCredentials() async throws {
        let lean = #"{"results":[{"series_id":81,"title":"First story"},{"series_id":82,"title":"Second story"}]}"#
        let details = #"{"data":[{"id":82,"title":"Second story","content_rating":"erotica"},{"id":81,"title":"First story","content_rating":" Safe "}]}"#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = MBTestTransport([.json(lean), .json(details)]), api = client(transport, directory: directory)
        let result = try await api.recommendations(key(.oauth), includeAdult: false)
        XCTAssertEqual(result.map(\.id), [81, 82]); XCTAssertEqual(result.first?.contentRating, "safe")
        var state = MangaBakaRecommendationsState()
        let attempt = try XCTUnwrap(state.begin(account: UUID(), includeAdult: false))
        state.complete(result, for: attempt); state.finish(attempt)
        XCTAssertEqual(state.items.map(\.id), [81])
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/my/series/recommendations", "/v1/series/batch"])
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.map(\.value), ["81", "82"])
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization")); XCTAssertNil(requests[1].value(forHTTPHeaderField: "X-API-Key"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("catalog.json").path), "Private recommendations and their grouped lookup must stay memory-only")
    }
    func testUnresolvedRecommendationsRemainDiagnosableInsteadOfClaimingAColdProfile() async throws {
        let transport = MBTestTransport([.json(#"{"results":[{"series_id":81,"title":"Owned story"}]}"#), .json(#"{"data":[]}"#)])
        let result = try await client(transport).recommendations(key(), includeAdult: false)
        var state = MangaBakaRecommendationsState()
        let attempt = try XCTUnwrap(state.begin(account: UUID(), includeAdult: false))
        state.complete(result, for: attempt); state.finish(attempt)
        XCTAssertTrue(state.items.isEmpty); XCTAssertEqual(state.unverifiedCount, 1)
        XCTAssertTrue(state.emptyMessage.contains("missing content details"))
    }
    func testMalformedRecommendationsAndWrongBatchIdentitiesAreNotSuccessfulEmptyResults() async throws {
        let bad = MBTestTransport([.json(#"{"results":[null,{"missing_id":81}]}"#)])
        do { _ = try await client(bad).recommendations(key(), includeAdult: false); XCTFail("Not an empty profile") }
        catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
        let mismatch = MBTestTransport([.json(#"{"data":[{"id":999,"title":"Wrong series","content_rating":"safe"}]}"#)])
        do { _ = try await client(mismatch).details(ids: [81]); XCTFail("Wrong series must not hydrate a recommendation") }
        catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
    }
    func testRecommendationReadinessAcceptsBothEnvelopesAndAlwaysUsesPrivateAuthentication() async throws {
        let transport = MBTestTransport([.json(#"{"data":{"cold_start":true,"profile_stale":false,"library_count":0}}"#),
            .json(#"{"cold_start":false,"profile_stale":true,"library_count":42}"#)])
        let api = client(transport)
        let first = try await api.recommendationStatus(key(.oauth)), second = try await api.recommendationStatus(key())
        XCTAssertEqual(first.coldStart, true); XCTAssertEqual(first.libraryCount, 0)
        XCTAssertEqual(second.profileStale, true); XCTAssertEqual(second.libraryCount, 42)
        let requests = await transport.recorded()
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/v1/my/series/recommendations/status" })
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer owned-test-credential")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "X-API-Key"), "owned-test-credential")
    }
    func testWrongDetailIdentityAndRedirectedResponsesAreRejected() async throws {
        let transport = MBTestTransport([.json("{\"data\":\(record)}"), .json(page(record), responseURL: URL(string: "https://attacker.example/redirect")!)]), api = client(transport)
        do { _ = try await api.details(id: 82); XCTFail("Wrong series") } catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
        do { _ = try await api.browse(.init(), includeAdult: false); XCTFail("Unexpected redirect") } catch { XCTAssertEqual(error as? MangaBakaError, .invalidResponse) }
    }
}

private actor MBTestTransport: HTTPTransport {
    struct Response: Sendable {
        let body: String
        let status: Int
        let headers: [String: String]
        let url: URL?
        static func json(_ body: String, status: Int = 200, headers: [String: String] = [:], responseURL: URL? = nil) -> Self {
            Self(body: body, status: status, headers: headers, url: responseURL)
        }
    }
    private var queue: [Response]
    private var requests: [URLRequest] = []
    init(_ responses: [Response]) { queue = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !queue.isEmpty else { throw MangaBakaError.message("Unexpected owned test request") }
        let next = queue.removeFirst()
        return (Data(next.body.utf8), HTTPURLResponse(url: next.url ?? request.url!, statusCode: next.status, httpVersion: nil, headerFields: next.headers)!)
    }
    func recorded() -> [URLRequest] { requests }
}

