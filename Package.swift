// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MaKeep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MaKeep",
            path: "Sources/MaKeep",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MaKeepTests",
            dependencies: ["MaKeep"],
            path: "Tests/MaKeepTests",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
