// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Schichta",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Schichta", path: "Sources/Schichta", resources: [.process("Resources")]),
        .testTarget(name: "SchichtaTests", dependencies: ["Schichta"], path: "Tests/SchichtaTests"),
    ],
    swiftLanguageModes: [.v6]
)
