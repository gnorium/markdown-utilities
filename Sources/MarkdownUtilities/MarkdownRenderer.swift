#if SERVER
  import Foundation
  import Markdown
#endif

public struct MarkdownRenderer {
  /// Renders markdown content to HTMLContent string
  public static func render(_ markdown: String) -> String {
    #if CLIENT
      return markdown
    #endif
    #if SERVER
      // Pre-process video syntax: @[Description | Attribution](/videos/file.mp4)
      let processedMarkdown = preprocessVideos(markdown)
      let document = Document(parsing: processedMarkdown)
      var visitor = HTMLVisitor()
      visitor.visit(document)
      return visitor.html.trimmingCharacters(in: .whitespacesAndNewlines)
    #endif
  }

  #if SERVER
    /// Converts @[caption](/path/to/video.mp4) to HTMLContent figure with video
    private static func preprocessVideos(_ markdown: String) -> String {
      // Pattern: @[Description | Attribution](/path/to/video.mp4)
      let pattern = #"@\[([^\]]+)\]\(([^)]+)\)"#
      guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return markdown
      }

      var result = markdown
      let matches = regex.matches(
        in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

      // Process in reverse to maintain string indices
      for match in matches.reversed() {
        guard let captionRange = Range(match.range(at: 1), in: markdown),
          let urlRange = Range(match.range(at: 2), in: markdown),
          let fullRange = Range(match.range, in: markdown)
        else {
          continue
        }

        let caption = String(markdown[captionRange])
        let url = String(markdown[urlRange])

        // Parse "Description | Attribution"
        let parts = caption.split(separator: "|", maxSplits: 1).map {
          $0.trimmingCharacters(in: .whitespaces)
        }

        var figcaptionHTML: String
        if parts.count == 2 {
          figcaptionHTML = "\(parts[0])<br><i>\(parts[1])</i>"
        } else {
          figcaptionHTML = caption
        }

        let videoHTML = """
          <figure class="media-center">
            <video controls>
              <source src="\(url)" type="video/mp4">
            </video>
            <figcaption>\(figcaptionHTML)</figcaption>
          </figure>
          """

        result.replaceSubrange(fullRange, with: videoHTML)
      }

      return result
    }
  #endif
}

#if SERVER
  /// Visitor that converts Markdown AST to HTMLContent
  private struct HTMLVisitor: MarkupWalker {
    var html = ""
    private var skipPrefix: String?

    mutating func visitHeading(_ heading: Heading) {
      let level = heading.level
      let text = heading.plainText

      // Check for explicit {#custom-id} anchor
      let id: String
      let displayText: String
      let anchorPattern = #"\s*\{#([^}]+)\}\s*$"#
      if let regex = try? NSRegularExpression(pattern: anchorPattern),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let idRange = Range(match.range(at: 1), in: text),
        let fullRange = Range(match.range, in: text)
      {
        id = String(text[idRange])
        displayText = String(text[text.startIndex..<fullRange.lowerBound])
      } else {
        id = slugify(text)
        displayText = text
      }

      html += "<h\(level) id=\"\(escapeAttribute(id))\">"
      // If we extracted a custom id, render children normally but the text won't include the {#id}
      if displayText != text {
        html += escapeHTML(displayText)
      } else {
        descendInto(heading)
      }
      html += "</h\(level)>\n"
    }

    private func slugify(_ text: String) -> String {
      let slug = text.lowercased()
        .replacingOccurrences(of: " ", with: "-")
        .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        .reduce(into: "") { $0.append(String($1)) }

      // Clean up consecutive hyphens and trim
      return slug.split(separator: "-")
        .compactMap { $0.isEmpty ? nil : String($0) }
        .joined(separator: "-")
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
      html += "<p>"
      descendInto(paragraph)
      html += "</p>\n"
    }

    mutating func visitText(_ text: Text) {
      var s = text.string
      if let prefix = skipPrefix, s.hasPrefix(prefix) {
        s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        skipPrefix = nil
      }
      html += escapeHTML(s)
    }

    mutating func visitStrong(_ strong: Strong) {
      html += "<strong>"
      descendInto(strong)
      html += "</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
      html += "<em>"
      descendInto(emphasis)
      html += "</em>"
    }

    mutating func visitLink(_ link: Link) {
      html += "<a href=\"\(escapeAttribute(link.destination ?? ""))\">"
      descendInto(link)
      html += "</a>"
    }

    mutating func visitImage(_ image: Image) {
      html += "<figure class=\"article-image\">"
      html += "<img src=\"\(escapeAttribute(image.source ?? ""))\" "

      // Parse alt text as "Description | Attribution"
      let altText = image.plainText
      let parts = altText.split(separator: "|", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      let description = parts.first ?? altText
      let attribution = parts.count == 2 ? parts[1] : nil

      if !description.isEmpty {
        html += "alt=\"\(escapeAttribute(description))\" "
      }
      html += "/>"

      // Build figcaption
      if !description.isEmpty || attribution != nil {
        html += "<figcaption>"
        if !description.isEmpty {
          html += escapeHTML(description)
        }
        if let attr = attribution {
          html += "<br><i>\(escapeHTML(attr))</i>"
        }
        html += "</figcaption>"
      }
      html += "</figure>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
      let language = codeBlock.language ?? "plaintext"
      let code = codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines)
      if language == "mermaid" {
        html += "<pre class=\"mermaid\">"
        html += code
        html += "</pre>"
      } else {
        html += "<pre><code class=\"language-\(language)\">"
        html += escapeHTML(code)
        html += "</code></pre>"
      }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
      html += "<code>"
      html += escapeHTML(inlineCode.code)
      html += "</code>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
      html += "<ul>\n"
      descendInto(unorderedList)
      html += "</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
      html += "<ol>\n"
      descendInto(orderedList)
      html += "</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
      html += "<li>"
      descendInto(listItem)
      html += "</li>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
      var alertClass: String?
      var icon: String?
      var markerToRemove: String?

      // Peek into first paragraph and text node to detect GFM markers
      if let firstParagraph = blockQuote.child(at: 0) as? Paragraph,
        let firstText = firstParagraph.child(at: 0) as? Text
      {
        let text = firstText.string
        let types: [(marker: String, className: String, icon: String)] = [
          ("[!TIP]", "markdown-alert-tip", "💡"),
          ("[!NOTE]", "markdown-alert-note", "ℹ️"),
          ("[!IMPORTANT]", "markdown-alert-important", "📢"),
          ("[!WARNING]", "markdown-alert-warning", "⚠️"),
          ("[!CAUTION]", "markdown-alert-caution", "🛑"),
        ]
        for t in types {
          if text.hasPrefix(t.marker) {
            alertClass = t.className
            icon = t.icon
            markerToRemove = t.marker
            break
          }
        }
      }

      if let alertClass = alertClass, let icon = icon, let marker = markerToRemove {
        html += "<blockquote class=\"markdown-alert \(alertClass)\">\n"
        html += "<span class=\"markdown-alert-icon\">\(icon)</span>\n"
        skipPrefix = marker
      } else {
        html += "<blockquote>\n"
      }

      descendInto(blockQuote)
      html += "</blockquote>\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
      html += "<br>"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
      html += "<br>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
      html += "<hr>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
      html += "<del>"
      descendInto(strikethrough)
      html += "</del>"
    }

    mutating func visitTable(_ table: Table) {
      html += "<!-- TABLE FOUND -->"
      html += "<table>"
      descendInto(table)
      html += "</table>"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
      html += "<thead>"
      descendInto(tableHead)
      html += "</thead>"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
      html += "<tbody>"
      descendInto(tableBody)
      html += "</tbody>"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
      html += "<tr>"
      descendInto(tableRow)
      html += "</tr>"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
      let tagName = tableCell.parent is Table.Head ? "th" : "td"
      var style = ""

      var current: Markup? = tableCell.parent
      while current != nil && !(current is Table) {
        current = current?.parent
      }

      if let table = current as? Table {
        let columnIndex = tableCell.indexInParent
        if columnIndex < table.columnAlignments.count,
          let alignment = table.columnAlignments[columnIndex]
        {
          switch alignment {
          case .left: style = " style=\"text-align: left;\""
          case .center: style = " style=\"text-align: center;\""
          case .right: style = " style=\"text-align: right;\""
          }
        }
      }

      html += "<\(tagName)\(style)>"
      descendInto(tableCell)
      html += "</\(tagName)>"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
      html += htmlBlock.rawHTML
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
      html += inlineHTML.rawHTML
    }

    // MARK: - HTMLContent Escaping

    private func escapeHTML(_ string: String) -> String {
      string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeAttribute(_ string: String) -> String {
      string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
    }
  }
#endif
