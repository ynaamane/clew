// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ownscribe-audio",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "OwnscribeCapture",
            path: "Sources/OwnscribeCapture",
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
            path: "Sources/OwnscribeMenuBar"
        ),
        .testTarget(
            name: "OwnscribeCaptureTests",
            dependencies: ["OwnscribeCapture"]
        ),
        .testTarget(
            name: "OwnscribeMenuBarTests",
            dependencies: ["OwnscribeMenuBar"]
        ),
    ]
)
