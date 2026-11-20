import XCTest
import Flutter
import FlutterPluginRegistrant

final class ExtensionStartupTests: XCTestCase {
    @MainActor
    func testRealEngineCanOpenStorageAndLoadAllSourceSystems() async throws {
        let snapshotPath = Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework/flutter_assets/kernel_blob.bin").path
        guard FileManager.default.fileExists(atPath: snapshotPath) else {
            XCTFail("The simulator Dart snapshot is missing from the startup test host.")
            return
        }
        let engine = FlutterEngine(name: "extension-startup-test", project: nil, allowHeadlessExecution: true)
        XCTAssertTrue(engine.run())
        GeneratedPluginRegistrant.register(with: engine)
        defer { engine.destroyContext() }
        let channel = FlutterMethodChannel(name: "com.animecompanion.extensions", binaryMessenger: engine.binaryMessenger)
        let started = expectation(description: "Extension initialization returned a system list")
        var response: [String: Any]?
        var errorCode: String?
        channel.invokeMethod("initialize", arguments: [:]) { value in
            response = value as? [String: Any]
            errorCode = (value as? FlutterError)?.code
            started.fulfill()
        }
        await fulfillment(of: [started], timeout: 180)
        XCTAssertNil(errorCode, "Startup failed with code: \(errorCode ?? "unknown")")
        let snapshot = try XCTUnwrap(response)
        let managers = try XCTUnwrap(snapshot["managers"] as? [[String: Any]])
        XCTAssertEqual(managers.count, 11)
        XCTAssertEqual(Set(managers.compactMap { $0["id"] as? String }).count, 11)
        XCTAssertTrue(managers.contains { ($0["name"] as? String)?.localizedCaseInsensitiveContains("CloudStream") == true })
        XCTAssertNotNil(snapshot["installed"] as? [[String: Any]])
        XCTAssertNotNil(snapshot["available"] as? [[String: Any]])
        // A second initialization reads the same stored runtime, rather than
        // masking a first-launch-only success with an empty fallback list.
        let repeated = expectation(description: "Repeated initialization")
        channel.invokeMethod("initialize", arguments: [:]) { value in
            XCTAssertEqual(((value as? [String: Any])?["managers"] as? [[String: Any]])?.count, 11)
            repeated.fulfill()
        }
        await fulfillment(of: [repeated], timeout: 30)
    }
}
