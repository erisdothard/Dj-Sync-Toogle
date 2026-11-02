// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SetlistCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SetlistCore", targets: ["SetlistCore"])
    ],
    targets: [
        .target(name: "SetlistCore"),
        .testTarget(name: "SetlistCoreTests", dependencies: ["SetlistCore"])
    ]
)
