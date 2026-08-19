// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchApp",
    platforms: [
        .macOS("15.0")
    ],
    targets: [
        .executableTarget(
            name: "NotchApp",
            path: "Sources/NotchApp",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
