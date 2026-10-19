import XCTest
@testable import AnimeCore

final class MangaSourceSettingsTests: XCTestCase {
    func testTypedSettingsRoundTripWithoutLosingIntegerPrecisionOrStringSetContents() throws {
        let values: [String: MangaSourceSettingValue] = [
            "address": .string("https://mirror.example/日本語"), "split": .boolean(true), "small": .integer(.min),
            "large": .long(.max), "speed": .decimal(1.25), "genres": .stringSet(["", "Action\nAdventure"])
        ]
        let settings = MangaSourceSettings(values: values)
        XCTAssertEqual(try MangaSourceSettings.decode(settings.encoded()), settings)
        XCTAssertEqual(try settings.encoded(), settings.encoded())
    }
    func testUnknownSchemasMalformedValuesAndOversizedCredentialsAreRejected() throws {
        for json in [#"{"schema":2,"values":{}}"#, #"{"schema":1,"values":{"split":{"type":"boolean","value":"true"}}}"#] {
            XCTAssertThrowsError(try MangaSourceSettings.decode(Data(json.utf8)))
        }
        XCTAssertThrowsError(try MangaSourceSettings(values: ["password": .string(String(repeating: "a", count: 16_385))]).encoded())
        XCTAssertThrowsError(try MangaSourceSettings(values: ["": .boolean(true)]).encoded())
        XCTAssertThrowsError(try MangaSourceSettings(values: ["speed": .decimal(.infinity)]).encoded())
        XCTAssertThrowsError(try MangaSourceSettings(values: Dictionary(uniqueKeysWithValues: (0..<129).map { ("key\($0)", .boolean(true)) })).encoded())
        XCTAssertThrowsError(try MangaSourceSettings(values: ["genres": .stringSet([String(repeating: "a", count: 4097)])]).encoded())
        XCTAssertThrowsError(try MangaSourceSettings(values: Dictionary(uniqueKeysWithValues: (0..<5).map { ("key\($0)", .string(String(repeating: "a", count: 16_384))) })).encoded())
    }
    func testDeclaredControlsRejectWrongTypesAndUnknownChoices() {
        let choice = MangaSourceSetting(id: "one", key: "quality", title: "Quality", control: .choice,
            choices: [.init(label: "High", value: "high")])
        XCTAssertTrue(choice.accepts(.string("high")))
        XCTAssertFalse(choice.accepts(.string("removed")))
        XCTAssertFalse(choice.accepts(.boolean(true)))
        let multi = MangaSourceSetting(id: "two", key: "genres", title: "Genres", control: .multiChoice, choices: choice.choices)
        XCTAssertTrue(multi.accepts(.stringSet([])))
        XCTAssertFalse(multi.accepts(.stringSet(["high", "unknown"])))
        XCTAssertTrue(MangaSourceSetting(id: "three", key: "api_key", title: "Access", control: .text).isSecret)
        XCTAssertFalse(choice.isSecret)
    }
}
