// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Schichta",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Schichta", path: "Sources/Schichta"),
    ],
    swiftLanguageModes: [.v5]
)
