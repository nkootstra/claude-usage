// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.5.0"),
    ],
    targets: [
        .target(
            name: "ClaudeUsageCore",
            dependencies: [
                "KeychainAccess",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/ClaudeUsageCore"
        ),
        .executableTarget(
            name: "ClaudeUsageApp",
            dependencies: [
                "ClaudeUsageCore",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "Sources/ClaudeUsageApp"
        ),
        .testTarget(
            name: "ClaudeUsageTests",
            dependencies: ["ClaudeUsageCore"],
            path: "Tests/ClaudeUsageTests"
        ),
    ]
)
