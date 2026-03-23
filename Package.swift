// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceType",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "VoiceType",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox")
            ]
        )
    ]
)
