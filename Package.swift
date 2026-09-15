// swift-tools-version:6.0
import PackageDescription

// Pomoblock: ポモドーロタイマー + サイトブロッカー（macOS メニューバー常駐）
let package = Package(
    name: "Pomoblock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pomoblock",
            path: "Sources/Pomoblock"
        )
    ]
)
