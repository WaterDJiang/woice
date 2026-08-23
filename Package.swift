// swift-tools-version: 6.0

import PackageDescription

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
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/WoiceApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WoiceAppTests",
            dependencies: ["WoiceCore", "WoiceApp"],
            path: "Tests/WoiceAppTests"
        )
    ]
)
