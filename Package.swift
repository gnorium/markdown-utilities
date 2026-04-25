// swift-tools-version: 6.2

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
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    .package(url: "https://github.com/gnorium/embedded-swift-utilities", branch: "main"),
  ],
  targets: [
    .target(
      name: "MarkdownUtilities",
      dependencies: [
        .product(
          name: "Markdown", package: "swift-markdown",
          condition: .when(platforms: [.macOS, .linux, .windows, .iOS, .tvOS, .watchOS, .visionOS])),
        .product(name: "EmbeddedSwiftUtilities", package: "embedded-swift-utilities"),
      ],
      swiftSettings: [
        .enableExperimentalFeature("Embedded", .when(platforms: [.wasi])),
        .define("CLIENT", .when(platforms: [.wasi])),
        .define("SERVER", .when(platforms: [.macOS, .linux, .windows])),
      ]
    )
  ]
)
