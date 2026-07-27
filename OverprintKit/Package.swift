// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OverprintKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OverprintKit", targets: ["OverprintKit"]),
        .executable(name: "overprint", targets: ["overprint"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.6.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/stencilproject/Stencil", from: "0.15.1"),
        .package(url: "https://github.com/httpswift/swifter", from: "1.5.0"),
    ],
    targets: [
        // The engine: parse, render, build, plus site/store logic and the default theme.
        .target(
            name: "OverprintKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Stencil", package: "Stencil"),
                .product(name: "Swifter", package: "swifter"),
            ],
            resources: [
                .copy("Resources/Theme"),
                .copy("Resources/Scaffold"),
                .copy("Resources/Examples")
            ]
        ),
        // The CLI, a thin front-end over OverprintKit.
        .executableTarget(
            name: "overprint",
            dependencies: [
                "OverprintKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "OverprintKitTests",
            dependencies: ["OverprintKit"]
        ),
    ]
)
