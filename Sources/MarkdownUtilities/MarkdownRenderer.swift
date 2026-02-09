import Foundation
import Markdown

public struct MarkdownRenderer {
	/// Renders markdown content to HTMLProtocol string
	public static func render(_ markdown: String) -> String {
		// Pre-process video syntax: @[Description | Attribution](/videos/file.mp4)
		let processedMarkdown = preprocessVideos(markdown)
		
		let document = Document(parsing: processedMarkdown)
		var visitor = HTMLVisitor()
		visitor.visit(document)
		return visitor.html
	}
	
	/// Converts @[caption](/path/to/video.mp4) to HTMLProtocol figure with video
	private static func preprocessVideos(_ markdown: String) -> String {
		// Pattern: @[Description | Attribution](/path/to/video.mp4)
		let pattern = #"@\[([^\]]+)\]\(([^)]+)\)"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return markdown
		}
		
		var result = markdown
		let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
		
		// Process in reverse to maintain string indices
		for match in matches.reversed() {
			guard let captionRange = Range(match.range(at: 1), in: markdown),
				  let urlRange = Range(match.range(at: 2), in: markdown),
				  let fullRange = Range(match.range, in: markdown) else {
				continue
			}
			
			let caption = String(markdown[captionRange])
			let url = String(markdown[urlRange])
			
			// Parse "Description | Attribution"
			let parts = caption.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
			
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
}

/// Visitor that converts Markdown AST to HTMLProtocol
private struct HTMLVisitor: MarkupWalker {
	var html = ""

	mutating func visitHeading(_ heading: Heading) {
		let level = heading.level
		html += "<h\(level)>"
		descendInto(heading)
		html += "</h\(level)>"
	}

	mutating func visitParagraph(_ paragraph: Paragraph) {
		html += "<p>"
		descendInto(paragraph)
		html += "</p>"
	}

	mutating func visitText(_ text: Text) {
		html += escapeHTML(text.string)
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
		let parts = altText.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
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
		html += "</figure>"
	}

	mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
		let language = codeBlock.language ?? "plaintext"
		html += "<pre><code class=\"language-\(language)\">"
		html += escapeHTML(codeBlock.code)
		html += "</code></pre>"
	}

	mutating func visitInlineCode(_ inlineCode: InlineCode) {
		html += "<code>"
		html += escapeHTML(inlineCode.code)
		html += "</code>"
	}

	mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
		html += "<ul>"
		descendInto(unorderedList)
		html += "</ul>"
	}

	mutating func visitOrderedList(_ orderedList: OrderedList) {
		html += "<ol>"
		descendInto(orderedList)
		html += "</ol>"
	}

	mutating func visitListItem(_ listItem: ListItem) {
		html += "<li>"
		descendInto(listItem)
		html += "</li>"
	}

	mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
		html += "<blockquote>"
		descendInto(blockQuote)
		html += "</blockquote>"
	}

	mutating func visitLineBreak(_ lineBreak: LineBreak) {
		html += "<br>"
	}

	mutating func visitSoftBreak(_ softBreak: SoftBreak) {
		html += " "
	}

	mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
		html += "<hr>"
	}

	mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
		html += htmlBlock.rawHTML
	}

	mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
		html += inlineHTML.rawHTML
	}

	// MARK: - HTMLProtocol Escaping

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
