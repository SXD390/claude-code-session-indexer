// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessions",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeSessions",
            path: "Sources/ClaudeSessions",
            // Links the SYSTEM SQLite (libsqlite3, ships with macOS, includes FTS5) for the
            // optional search index. NOT a SwiftPM package dependency — just the system library.
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClaudeSessionsTests",
            dependencies: ["ClaudeSessions"],
            path: "Tests/ClaudeSessionsTests"
        )
    ]
)
