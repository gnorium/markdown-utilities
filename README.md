# MarkdownUtilities, as used in [gnorium.com](https://gnorium.com)

A Swift package for rendering Markdown to HTML with extended syntax support for media.

## Overview

MarkdownUtilities provides a robust `MarkdownRenderer` built on top of `swift-markdown`. It adds custom processing for media attributions to support rich storytelling with proper credits.

### Features
- **Standard Markdown**: Full CommonMark support via swift-markdown.
- **Image captions with attribution**: `![Description | Attribution](/path/to/image.jpg)`
- **Video embeds with attribution**: `@[Description | Attribution](/path/to/video.mp4)`

### Extended Syntax

**Images**
```markdown
![Description | Attribution](/path/to/image.jpg)
```
Renders as a `<figure>` containing description and italicized attribution.

**Videos**
```markdown
@[Description | Attribution](/path/to/video.mp4)
```
Renders as a `<figure>` with a `<video>` element and a caption.

## Installation

### Swift Package Manager

Add MarkdownUtilities to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gnorium/markdown-utilities.git", branch: "main")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MarkdownUtilities", package: "markdown-utilities")
    ]
)
```

## Requirements

- Swift 6.2+

## Usage

```swift
import MarkdownUtilities

let html = MarkdownRenderer.render("""
# Hello World

![A beautiful sunset | John Doe](/images/sunset.jpg)

@[Time-lapse of flowers blooming | Jane Smith](/videos/flowers.mp4)
""")
```

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Related Packages

- [design-tokens](https://github.com/gnorium/design-tokens) - Universal design tokens based on Apple HIG
- [embedded-swift-utilities](https://github.com/gnorium/embedded-swift-utilities) - Utility functions for Embedded Swift environments
- [web-administrator](https://github.com/gnorium/web-administrator) - Web administration panel for applications
- [web-apis](https://github.com/gnorium/web-apis) - Web API implementations for Swift WebAssembly
- [web-builders](https://github.com/gnorium/web-builders) - HTML, CSS, JS, and SVG DSL builders
- [web-components](https://github.com/gnorium/web-components) - Reusable UI components for web applications
- [web-formats](https://github.com/gnorium/web-formats) - Structured data format builders
- [web-security](https://github.com/gnorium/web-security) - Portable security utilities for web applications
- [web-types](https://github.com/gnorium/web-types) - Shared web types and design tokens
