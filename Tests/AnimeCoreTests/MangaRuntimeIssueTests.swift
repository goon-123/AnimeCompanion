import XCTest
@testable import AnimeCore

final class MangaRuntimeIssueTests: XCTestCase {
    func testRuntimeAPIErrorIncludesOnlySafeHostIdentifiers() throws {
        let issue = try JSONDecoder().decode(MangaRuntimeIssue.self, from: Data(#"{"kind":"unsupportedAPI","api":"android.webkit.WebView"}"#.utf8))
        XCTAssertTrue(issue.localizedDescription.contains("android.webkit.WebView"))
        XCTAssertTrue(issue.localizedDescription.contains("Update AnimeCompanion"))
        for api in ["https://private.example?token=secret", "java.secret?token=secret", "guest.private.Token", "java..Secret", String(repeating: "java.", count: 100)] {
            XCTAssertFalse(MangaRuntimeIssue(kind: "unsupportedAPI", api: api).localizedDescription.contains(api))
        }
    }
    func testExecutionLimitAndUnknownKindsHaveBoundedMessages() {
        XCTAssertTrue(MangaRuntimeIssue(kind: "executionLimit").localizedDescription.contains("execution limit"))
        XCTAssertTrue(MangaRuntimeIssue(kind: "sourceResponse").localizedDescription.contains("Open the source website"))
        XCTAssertEqual(MangaRuntimeIssue(kind: "private unknown message").errorDescription, MangaExtensionError.runtimeFailure.errorDescription)
    }
}
