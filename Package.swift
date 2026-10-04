// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnimeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "AnimeCore", targets: ["AnimeCore"])],
    targets: [
        .target(name: "AnimeCore"),
        .testTarget(name: "AnimeCoreTests", dependencies: ["AnimeCore"], resources: [.process("Fixtures")])
    ]
)
