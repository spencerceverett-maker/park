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
            ]
        ),
        .testTarget(
            name: "ParkTests",
            dependencies: ["Park"],
            path: "Tests/ParkTests"
        ),
    ]
)
