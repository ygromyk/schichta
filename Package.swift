// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Schichta",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Schichta", path: "Sources/Schichta"),
        .testTarget(name: "SchichtaTests", dependencies: ["Schichta"], path: "Tests/SchichtaTests"),
    ],
    swiftLanguageModes: [.v6]
)
