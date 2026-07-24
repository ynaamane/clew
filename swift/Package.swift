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
            exclude: ["OwnscribeCapture"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .testTarget(
            name: "OwnscribeCaptureTests",
            dependencies: ["OwnscribeCapture"]
        ),
    ]
)
