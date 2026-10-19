// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Arc",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "arc", targets: ["arc"]),
        .executable(name: "ArcApp", targets: ["ArcApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", exact: "0.12.1"),
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0"),
        .package(url: "https://github.com/appstefan/HighlightSwift", exact: "1.1.0"),
    ],
    targets: [
        .target(
            name: "ArcCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "ArcAgentKit",
            dependencies: [
                "ArcCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .target(
            name: "ArcMarkdown",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "HighlightSwift", package: "HighlightSwift"),
            ]
        ),
        .executableTarget(
            name: "arc",
            dependencies: [
                "ArcAgentKit",
                "ArcCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "ArcApp",
            dependencies: ["ArcCore", "ArcMarkdown", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "ArcCoreTests", dependencies: ["ArcCore"]),
        .testTarget(name: "ArcAgentKitTests", dependencies: ["ArcAgentKit", "ArcCore"]),
        .testTarget(name: "ArcMarkdownTests", dependencies: ["ArcMarkdown"]),
    ],
    swiftLanguageModes: [.v6]
)
