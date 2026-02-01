// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CmdSpeak",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cmdspeak", targets: ["CmdSpeakCLI"]),
        .executable(name: "CmdSpeakApp", targets: ["CmdSpeakApp"]),
        .library(name: "CmdSpeakCore", targets: ["CmdSpeakCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "CmdSpeakApp",
            dependencies: ["CmdSpeakCore"],
            path: "Sources/CmdSpeak/App"
        ),
        .executableTarget(
            name: "CmdSpeakCLI",
            dependencies: [
                "CmdSpeakCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CmdSpeak/CLI"
        ),
        .target(
            name: "CmdSpeakCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/CmdSpeak/Core"
        ),
        .testTarget(
            name: "CmdSpeakTests",
            dependencies: ["CmdSpeakCore"],
            path: "Tests/CmdSpeakTests"
        )
    ]
)
