import XCTest
@testable import AnimeCore

final class DeviceSyncLocationTests: XCTestCase {
    func testExistingFolderGrantSurvivesUpgrade() {
        XCTAssertEqual(DeviceSyncLocation.restored(saved: nil, hasFolderBookmark: true), .folder)
    }
    func testAutomaticConnectionDoesNotRequireAnExternalBookmark() {
        XCTAssertEqual(DeviceSyncLocation.restored(saved: "automatic", hasFolderBookmark: false), .automatic)
    }
    func testAutomaticConnectionTakesPrecedenceOverAnOldFolderBookmark() {
        XCTAssertEqual(DeviceSyncLocation.restored(saved: "automatic", hasFolderBookmark: true), .automatic)
    }
    func testMissingFolderGrantNeverPretendsToBeConnected() {
        XCTAssertNil(DeviceSyncLocation.restored(saved: "folder", hasFolderBookmark: false))
        XCTAssertNil(DeviceSyncLocation.restored(saved: nil, hasFolderBookmark: false))
        XCTAssertNil(DeviceSyncLocation.restored(saved: "unsupported", hasFolderBookmark: false))
    }
    func testConnectionMetadataNeverEntersPortablePreferences() {
        for key in ["deviceSync.location.v1", "deviceSync.iCloudIdentity.v1", "deviceSync.folderBookmark.v1"] {
            XCTAssertFalse(DeviceSyncPreferences.keys.contains(key))
            XCTAssertThrowsError(try DeviceSyncPayload.validate(key: "preference." + key, value: nil))
        }
    }
}
