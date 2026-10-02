// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ColonEmoji",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ColonEmoji",
            path: "Sources/ColonEmoji"
        )
    ]
)
