#if SERVER
  import Foundation
  import Markdown
#endif
#if CLIENT
  import EmbeddedSwiftUtilities
#endif

public struct MarkdownRenderer {
  /// Renders markdown to an HTML fragment string.
  ///
  /// - SERVER: swift-markdown + media extensions
  /// - CLIENT (WASM): lightweight CommonMark subset—streaming-safe for live SSE
  /// `codeBlock` writes a fence (its language and its escaped code) as the
  /// page frames one; a bare `<pre><code class="language-…">` without it.
  /// The client renders bare fences, framed on the page.
  public static func render(_ markdown: String, codeBlock: ((String, String) -> String)? = nil) -> String {
    #if CLIENT
      return renderClient(markdown)
    #elseif SERVER
      let processedMarkdown = preserveHardLineBreaks(preprocessVideos(markdown))
      let document = Document(parsing: processedMarkdown)
      var visitor = HTMLVisitor()
      visitor.codeBlock = codeBlock
      visitor.visit(document)
      return visitor.html.trimmingCharacters(in: .whitespacesAndNewlines)
    #else
      return markdown
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

    /// Proof/Sight transcripts are plain line-oriented text. CommonMark soft breaks
    /// can collapse to spaces in some paths—force hard breaks outside fences.
    private static func preserveHardLineBreaks(_ markdown: String) -> String {
      var out = ""
      var inFence = false
      for line in markdown.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
          inFence.toggle()
          out += line + "\n"
          continue
        }
        if inFence || trimmed.isEmpty {
          out += line + "\n"
        } else if isMarkdownListItem(trimmed) {
          // Hard-breaks glue the next line into the same paragraph and
          // prevent `1.` / `-` lists from interrupting.
          out += line + "\n"
        } else {
          out += line + "  \n"
        }
      }
      return out
    }

    /// `1. item` / `- item` / `* item` / `+ item`
    private static func isMarkdownListItem(_ trimmed: String) -> Bool {
      if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
        return true
      }
      var digits = 0
      var i = trimmed.startIndex
      while i < trimmed.endIndex, trimmed[i].isNumber {
        digits += 1
        if digits > 9 { return false }
        i = trimmed.index(after: i)
      }
      guard digits > 0, i < trimmed.endIndex, trimmed[i] == "." else { return false }
      let afterDot = trimmed.index(after: i)
      return afterDot < trimmed.endIndex && trimmed[afterDot] == " "
    }
  #endif
}

#if CLIENT
  extension MarkdownRenderer {
    /// Lightweight CommonMark subset for Embedded / WASM (no swift-markdown).
    /// Streaming-safe: an unclosed `` ``` `` fence is rendered as an open code block.
    private static func renderClient(_ markdown: String) -> String {
      let normalized = stringReplace(markdown, "\r\n", "\n")
      let lines = stringSplit(normalized, separator: "\n")
      var html = ""
      var i = 0
      var inFence = false
      var fenceLang = ""
      var fenceBody: [String] = []

      func flushParagraph(_ buf: inout [String]) {
        guard !buf.isEmpty else { return }
        html = stringJoin([html, "<p>"], separator: "")
        for (idx, line) in buf.enumerated() {
          if idx > 0 {
            html = stringJoin([html, "<br>\n"], separator: "")
          }
          html = stringJoin([html, renderInlines(line)], separator: "")
        }
        html = stringJoin([html, "</p>\n"], separator: "")
        buf = []
      }

      func flushFence() {
        let code = stringJoin(fenceBody, separator: "\n")
        let lang = stringIsEmpty(fenceLang) ? "plaintext" : fenceLang
        html = stringJoin(
          [
            html,
            "<pre><code class=\"language-",
            escapeClientAttr(lang),
            "\">",
            escapeClientHTML(code),
            "</code></pre>\n",
          ],
          separator: ""
        )
        inFence = false
        fenceLang = ""
        fenceBody = []
      }

      var paragraph: [String] = []

      while i < lines.count {
        let line = lines[i]
        let trimmed = stringTrim(line)

        if inFence {
          if isFenceMarker(trimmed) {
            flushFence()
          } else {
            fenceBody.append(line)
          }
          i += 1
          continue
        }

        if isFenceMarker(trimmed) {
          flushParagraph(&paragraph)
          inFence = true
          fenceLang = fenceLanguage(trimmed)
          fenceBody = []
          i += 1
          continue
        }

        if stringIsEmpty(trimmed) {
          flushParagraph(&paragraph)
          i += 1
          continue
        }

        if let heading = parseHeading(trimmed) {
          flushParagraph(&paragraph)
          html = stringJoin(
            [
              html,
              "<h",
              intToString(heading.level),
              ">",
              renderInlines(heading.text),
              "</h",
              intToString(heading.level),
              ">\n",
            ],
            separator: ""
          )
          i += 1
          continue
        }

        if stringStartsWith(trimmed, "- ") || stringStartsWith(trimmed, "* ") {
          flushParagraph(&paragraph)
          html = stringJoin([html, "<ul>\n"], separator: "")
          while i < lines.count {
            let itemLine = stringTrim(lines[i])
            if stringStartsWith(itemLine, "- ") || stringStartsWith(itemLine, "* ") {
              let text = stringSubstring(itemLine, from: 2)
              html = stringJoin(
                [html, "<li>", renderInlines(text), "</li>\n"],
                separator: ""
              )
              i += 1
            } else {
              break
            }
          }
          html = stringJoin([html, "</ul>\n"], separator: "")
          continue
        }

        if let itemText = orderedListItemText(trimmed) {
          flushParagraph(&paragraph)
          html = stringJoin([html, "<ol>\n"], separator: "")
          var text = itemText
          while true {
            html = stringJoin(
              [html, "<li>", renderInlines(text), "</li>\n"],
              separator: ""
            )
            i += 1
            guard i < lines.count else { break }
            let next = stringTrim(lines[i])
            guard let more = orderedListItemText(next) else { break }
            text = more
          }
          html = stringJoin([html, "</ol>\n"], separator: "")
          continue
        }

        paragraph.append(line)
        i += 1
      }

      if inFence {
        // Streaming: still emit the open fence body as a code block.
        flushFence()
      }
      flushParagraph(&paragraph)
      return stringTrim(html)
    }

    private static func isFenceMarker(_ line: String) -> Bool {
      stringStartsWith(line, "```")
    }

    private static func fenceLanguage(_ line: String) -> String {
      stringTrim(stringSubstring(line, from: 3))
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
      var level = 0
      let utf8 = Array(line.utf8)
      while level < utf8.count, utf8[level] == 35 /* # */, level < 6 {
        level += 1
      }
      guard level > 0, level < utf8.count, utf8[level] == 32 else { return nil }
      let text = stringTrim(stringSubstring(line, from: level + 1))
      return (level, text)
    }

    /// `1. item` → `item`. Marker is 1–9 digits, then `. `.
    private static func orderedListItemText(_ line: String) -> String? {
      let utf8 = Array(line.utf8)
      var i = 0
      while i < utf8.count, utf8[i] >= 48, utf8[i] <= 57 {
        i += 1
        if i > 9 { return nil }
      }
      guard i > 0, i + 1 < utf8.count, utf8[i] == 46, utf8[i + 1] == 32 else { return nil }
      return stringSubstring(line, from: i + 2)
    }

    private static func renderInlines(_ text: String) -> String {
      let bytes = Array(text.utf8)
      func slice(_ start: Int, _ end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
      }
      func whitespace(_ byte: UInt8?) -> Bool {
        guard let byte else { return true }
        return byte == 32 || (byte >= 9 && byte <= 13)
      }
      func punctuation(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return (byte >= 33 && byte <= 47) || (byte >= 58 && byte <= 64)
          || (byte >= 91 && byte <= 96) || (byte >= 123 && byte <= 126)
      }
      func flanking(_ start: Int, _ length: Int) -> (opens: Bool, closes: Bool) {
        let before: UInt8? = start > 0 ? bytes[start - 1] : nil
        let after: UInt8? = start + length < bytes.count ? bytes[start + length] : nil
        let left = !whitespace(after) && (!punctuation(after) || whitespace(before) || punctuation(before))
        let right = !whitespace(before) && (!punctuation(before) || whitespace(after) || punctuation(after))
        if bytes[start] == 95 {
          // CommonMark underscores cannot open or close inside identifiers.
          return (left && (!right || punctuation(before)), right && (!left || punctuation(after)))
        }
        return (left, right)
      }
      var output = ""
      var i = 0
      while i < bytes.count {
        let byte = bytes[i]
        if byte == 92, i + 1 < bytes.count, punctuation(bytes[i + 1]) {
          output += escapeClientHTML(slice(i + 1, i + 2)); i += 2; continue
        }
        if byte == 96 {
          var length = 1
          while i + length < bytes.count, bytes[i + length] == 96 { length += 1 }
          var j = i + length
          var closing: Int? = nil
          while j < bytes.count {
            if bytes[j] == 96 {
              var run = 1
              while j + run < bytes.count, bytes[j + run] == 96 { run += 1 }
              if run == length { closing = j; break }
              j += run
            } else { j += 1 }
          }
          if let closing {
            output += "<code>" + escapeClientHTML(slice(i + length, closing)) + "</code>"
            i = closing + length; continue
          }
        }
        if byte == 91 { // [label](destination), with balanced destination parentheses.
          var endLabel = i + 1
          while endLabel < bytes.count {
            if bytes[endLabel] == 92 { endLabel += 2; continue }
            if bytes[endLabel] == 93 { break }
            endLabel += 1
          }
          if endLabel + 1 < bytes.count, bytes[endLabel + 1] == 40 {
            var endURL = endLabel + 2
            var depth = 1
            while endURL < bytes.count {
              if bytes[endURL] == 92 { endURL += 2; continue }
              if bytes[endURL] == 40 { depth += 1 }
              if bytes[endURL] == 41 { depth -= 1; if depth == 0 { break } }
              endURL += 1
            }
            if depth == 0 {
              let destination = slice(endLabel + 2, endURL)
              let lower = stringLowercased(destination)
              // No script/data URLs or control characters in generated links.
              let safe = !Array(destination.utf8).contains { $0 <= 32 || $0 == 127 }
                && (stringStartsWith(lower, "https://") || stringStartsWith(lower, "http://")
                  || stringStartsWith(lower, "mailto:") || stringStartsWith(lower, "#")
                  || (stringStartsWith(lower, "/") && !stringStartsWith(lower, "//")))
              if safe {
                output += "<a href=\"" + escapeClientAttr(destination) + "\">"
                  + renderInlines(slice(i + 1, endLabel)) + "</a>"
                i = endURL + 1; continue
              }
            }
          }
        }
        if byte == 42 || byte == 95 {
          let length = i + 1 < bytes.count && bytes[i + 1] == byte ? 2 : 1
          if flanking(i, length).opens {
            var j = i + length
            var closing: Int? = nil
            while j + length <= bytes.count {
              // Inline code and escapes protect their literal delimiters.
              if bytes[j] == 92 { j += 2; continue }
              if bytes[j] == 96 {
                var k = j + 1
                while k < bytes.count, bytes[k] != 96 { k += 1 }
                j = min(k + 1, bytes.count); continue
              }
              if bytes[j] == byte && (length == 1 || bytes[j + 1] == byte), flanking(j, length).closes {
                closing = j; break
              }
              j += 1
            }
            if let closing {
              let tag = length == 2 ? "strong" : "em"
              output += "<" + tag + ">" + renderInlines(slice(i + length, closing)) + "</" + tag + ">"
              i = closing + length; continue
            }
          }
          output += escapeClientHTML(slice(i, i + length)); i += length; continue
        }
        // Copy complete UTF-8 sequences so multibyte text stays verbatim.
        var length = 1
        if byte >= 240 { length = 4 } else if byte >= 224 { length = 3 } else if byte >= 192 { length = 2 }
        length = min(length, bytes.count - i)
        output += escapeClientHTML(slice(i, i + length)); i += length
      }
      return output
    }

    private static func escapeClientHTML(_ string: String) -> String {
      var s = stringReplace(string, "&", "&amp;")
      s = stringReplace(s, "<", "&lt;")
      s = stringReplace(s, ">", "&gt;")
      s = stringReplace(s, "\"", "&quot;")
      s = stringReplace(s, "'", "&#39;")
      return s
    }

    private static func escapeClientAttr(_ string: String) -> String {
      var s = stringReplace(string, "&", "&amp;")
      s = stringReplace(s, "\"", "&quot;")
      s = stringReplace(s, "'", "&#39;")
      return s
    }
  }
#endif

#if SERVER
  /// Visitor that converts Markdown AST to HTMLContent
  private struct HTMLVisitor: MarkupWalker {
    var html = ""
    var codeBlock: ((String, String) -> String)?
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
      let destination = link.destination ?? ""
      let lower = destination.lowercased()
      let safe = !destination.utf8.contains { $0 <= 32 || $0 == 127 }
        && (lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:")
          || lower.hasPrefix("#") || (!destination.contains(":") && !lower.hasPrefix("//")))
      if safe { html += "<a href=\"\(escapeAttribute(destination))\">" }
      descendInto(link)
      if safe { html += "</a>" }
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
      } else if let codeBlock = self.codeBlock {
        html += codeBlock(language, escapeHTML(code))
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
      // Same policy as typical chat UIs (ChatGPT / react-markdown default):
      // assistant markdown may *contain* angle-brackets, but they are never
      // injected as live DOM. Fenced code blocks already escape via visitCodeBlock.
      html += "<p>"
      html += escapeHTML(htmlBlock.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))
      html += "</p>\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
      html += escapeHTML(inlineHTML.rawHTML)
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
