// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Park",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Park",
            path: "Sources/Park",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                // Private SkyLight calls tell which Space each window is on (see Engine/Windows.swift).
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
            ]
        ),
    ]
)
