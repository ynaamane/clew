// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ownscribe-audio",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "OwnscribeCapture",
            path: "Sources/OwnscribeCapture",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .executableTarget(
            name: "ownscribe-audio",
            dependencies: ["OwnscribeCapture"],
            path: "Sources",
            exclude: ["OwnscribeCapture", "OwnscribeMenuBar"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "OwnscribeMenuBar",
            dependencies: ["OwnscribeCapture"],
            path: "Sources/OwnscribeMenuBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OwnscribeCaptureTests",
            dependencies: ["OwnscribeCapture"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OwnscribeMenuBarTests",
            dependencies: ["OwnscribeMenuBar"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
