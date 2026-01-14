// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkdownUtilities",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MarkdownUtilities",
            targets: ["MarkdownUtilities"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "MarkdownUtilities",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        )
    ]
)
