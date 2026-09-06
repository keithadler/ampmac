// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AmpMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AmpMac", path: "Sources/AmpMac"),
        .testTarget(name: "AmpMacTests", dependencies: ["AmpMac"], path: "Tests/AmpMacTests"),
    ]
)
