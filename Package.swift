// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stixx",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Stixx",
            path: "Sources/Stixx",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StixxTests",
            dependencies: ["Stixx"],
            path: "Tests/StixxTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
