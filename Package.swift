// swift-tools-version: 6.0

import Foundation
import PackageDescription

let isAppStoreDistribution =
    ProcessInfo.processInfo.environment["WOICE_DISTRIBUTION"] == "app-store"
let appStoreSwiftSettings: [SwiftSetting] = isAppStoreDistribution
    ? [.define("WOICE_APP_STORE")]
    : []

let package = Package(
    name: "Woice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Woice", targets: ["WoiceApp"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            exact: "1.0.0"
        ),
        .package(
            url: "https://github.com/vfasky/qwen3-asr-swift.git",
            revision: "4824c95e1e4624200405d639fb4ebe10f93f1075"
        )
    ],
    targets: [
        .target(
            name: "WoiceCore",
            path: "Sources/WoiceCore"
        ),
        .executableTarget(
            name: "WoiceApp",
            dependencies: [
                "WoiceCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Qwen3ASR", package: "qwen3-asr-swift"),
                .product(name: "Qwen3Common", package: "qwen3-asr-swift")
            ],
            path: "Sources/WoiceApp",
            resources: [.process("Resources")],
            swiftSettings: appStoreSwiftSettings
        ),
        .testTarget(
            name: "WoiceAppTests",
            dependencies: ["WoiceCore", "WoiceApp"],
            path: "Tests/WoiceAppTests",
            swiftSettings: appStoreSwiftSettings
        )
    ]
)
