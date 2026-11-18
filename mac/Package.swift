// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceStudio",
    platforms: [.macOS(.v14)],
    targets: [
        // 可測試的邏輯與畫面都在這裡；執行檔只負責啟動。
        .target(name: "VoiceStudioCore", path: "Sources/VoiceStudioCore"),
        .executableTarget(name: "VoiceStudio", dependencies: ["VoiceStudioCore"], path: "Sources/VoiceStudio"),
        .testTarget(name: "VoiceStudioCoreTests", dependencies: ["VoiceStudioCore"],
                    path: "Tests/VoiceStudioCoreTests", resources: [.copy("Fixtures")]),
    ]
)
