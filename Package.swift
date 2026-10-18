// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnimeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "AnimeCore", targets: ["AnimeCore"])],
    targets: [
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "AnimeCore", dependencies: ["CZlib"]),
        .testTarget(name: "AnimeCoreTests", dependencies: ["AnimeCore"], resources: [.process("Fixtures")])
    ]
)
