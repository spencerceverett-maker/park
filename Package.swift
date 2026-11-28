// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Park",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates: checks the appcast on each GitHub release and installs new versions.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Park",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Park",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                // Sparkle.framework is copied into Park.app/Contents/Frameworks by the build scripts.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ParkTests",
            dependencies: ["Park"],
            path: "Tests/ParkTests"
        ),
    ]
)
