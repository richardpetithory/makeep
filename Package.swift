// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "makeep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "makeep",
            path: "Sources/makeep",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "makeepTests",
            dependencies: ["makeep"],
            path: "Tests/makeepTests",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
