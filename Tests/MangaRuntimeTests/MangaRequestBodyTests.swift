import XCTest
@testable import AnimeCompanion

final class MangaRequestBodyTests: XCTestCase {
    func testRawBytesTakePrecedenceWithoutUTF8Conversion() throws {
        let bytes = Data([0, 255, 128, 195, 40, 13, 10])
        XCTAssertEqual(try MangaRuntimeRequestBody.decode(text: "wrong", base64: bytes.base64EncodedString()), bytes)
        XCTAssertEqual(try MangaRuntimeRequestBody.decode(text: "Owned café\0", base64: nil), Data("Owned café\0".utf8))
    }

    func testEmptyBodyIsDistinctFromNoBody() throws {
        XCTAssertNil(try MangaRuntimeRequestBody.decode(text: nil, base64: nil))
        XCTAssertEqual(try MangaRuntimeRequestBody.decode(text: nil, base64: ""), Data())
        XCTAssertEqual(try MangaRuntimeRequestBody.decode(text: "", base64: nil), Data())
    }

    func testMalformedOrOversizedRawBodyNeverFallsBackToText() throws {
        for encoded in ["!", "YQ", "YQ==\n", "!!!!"] {
            XCTAssertThrowsError(try MangaRuntimeRequestBody.decode(text: "valid fallback", base64: encoded))
        }
        let maximum = Data(repeating: 255, count: MangaRuntimeRequestBody.limit)
        XCTAssertEqual(try MangaRuntimeRequestBody.decode(text: nil, base64: maximum.base64EncodedString()), maximum)
        let oversized = Data(repeating: 255, count: MangaRuntimeRequestBody.limit + 1)
        XCTAssertThrowsError(try MangaRuntimeRequestBody.decode(text: "fallback", base64: oversized.base64EncodedString()))
        XCTAssertThrowsError(try MangaRuntimeRequestBody.decode(text: String(repeating: "a", count: MangaRuntimeRequestBody.limit + 1), base64: nil))
    }
}
