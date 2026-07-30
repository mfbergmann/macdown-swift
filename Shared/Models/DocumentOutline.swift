import Foundation

/// A heading found in a markdown document.
public struct Heading: Identifiable, Equatable, Sendable {
    /// Position in document order, starting at zero.
    ///
    /// This is what the sidebar uses to jump the preview: the rendered HTML
    /// carries the same index on each heading, so navigation never depends on
    /// slug text matching between the source and the rendered output.
    public let index: Int
    /// 1 through 6.
    public var level: Int
    /// The heading text, with markdown syntax stripped.
    public var title: String
    /// Range of the heading in the source text, for scrolling the editor.
    public var range: NSRange
    /// GitHub-style anchor slug, unique within the document.
    public var slug: String

    public var id: Int { index }
}

/// The headings of a markdown document, in order.
///
/// Parsed from the source rather than the rendered HTML so each heading keeps a
/// source range the editor can scroll to. Fenced code blocks and YAML front
/// matter are skipped, so a `#` in a shell snippet is not mistaken for a heading.
public struct DocumentOutline: Equatable, Sendable {
    public var headings: [Heading]

    public init(headings: [Heading] = []) {
        self.headings = headings
    }

    public var isEmpty: Bool { headings.isEmpty }

    /// The heading containing or immediately preceding `location`, so the
    /// sidebar can show where the caret currently is.
    public func heading(enclosing location: Int) -> Heading? {
        headings.last { $0.range.location <= location }
    }

    // MARK: - Parsing

    public static func parse(_ markdown: String) -> DocumentOutline {
        let ns = markdown as NSString
        var headings: [Heading] = []
        var slugger = Slugger()

        var lineStart = 0
        var lines: [(text: String, range: NSRange)] = []
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            var contentRange = lineRange
            while contentRange.length > 0 {
                let last = ns.character(at: contentRange.upperBound - 1)
                guard last == 0x0A || last == 0x0D else { break }
                contentRange.length -= 1
            }
            lines.append((ns.substring(with: contentRange), contentRange))
            lineStart = lineRange.upperBound
            if lineRange.length == 0 { break }  // guard against a zero-length line range
        }

        var insideFence: String?
        var index = 0
        var lineNumber = 0

        // Skip YAML front matter.
        if lines.first?.text.trimmingCharacters(in: .whitespaces) == "---" {
            var scan = 1
            while scan < lines.count {
                if lines[scan].text.trimmingCharacters(in: .whitespaces) == "---" {
                    lineNumber = scan + 1
                    break
                }
                scan += 1
            }
        }

        while lineNumber < lines.count {
            let line = lines[lineNumber]
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks: everything inside is literal.
            if let fence = insideFence {
                if trimmed.hasPrefix(fence) { insideFence = nil }
                lineNumber += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence = String(trimmed.prefix(3))
                lineNumber += 1
                continue
            }

            // ATX heading: up to three spaces of indent, then 1-6 hashes.
            if let atx = parseATX(line.text) {
                headings.append(
                    Heading(
                        index: index,
                        level: atx.level,
                        title: atx.title,
                        range: line.range,
                        slug: slugger.slug(for: atx.title)
                    )
                )
                index += 1
                lineNumber += 1
                continue
            }

            // Setext heading: text underlined by === (h1) or --- (h2).
            if !trimmed.isEmpty, lineNumber + 1 < lines.count,
               let level = setextLevel(lines[lineNumber + 1].text),
               parseATX(line.text) == nil {
                let title = trimmed
                headings.append(
                    Heading(
                        index: index,
                        level: level,
                        title: title,
                        range: line.range,
                        slug: slugger.slug(for: title)
                    )
                )
                index += 1
                lineNumber += 2
                continue
            }

            lineNumber += 1
        }

        return DocumentOutline(headings: headings)
    }

    private static func parseATX(_ line: String) -> (level: Int, title: String)? {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return nil }  // 4+ spaces is a code block
        let rest = line.dropFirst(indent.count)
        let hashes = rest.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }

        let afterHashes = rest.dropFirst(hashes.count)
        // "#Heading" is not a heading; "#" alone is an empty one.
        guard afterHashes.isEmpty || afterHashes.first == " " || afterHashes.first == "\t" else {
            return nil
        }

        // A closing run of hashes is decoration, not part of the title.
        var title = afterHashes.trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") { title = String(title.dropLast()) }
        title = title.trimmingCharacters(in: .whitespaces)

        return (hashes.count, stripInlineMarkdown(title))
    }

    private static func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    /// Remove the inline markup that would otherwise show up in the outline.
    static func stripInlineMarkdown(_ text: String) -> String {
        var result = text
        // Links and images: keep the label, drop the target.
        result = result.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression
        )
        // Emphasis, strong, strikethrough, inline code.
        for marker in ["***", "___", "**", "__", "~~", "*", "_", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Slugs

    /// Generates GitHub-style anchor slugs, keeping them unique per document.
    struct Slugger {
        private var seen: [String: Int] = [:]

        mutating func slug(for title: String) -> String {
            let base = Self.baseSlug(for: title)
            let key = base.isEmpty ? "section" : base
            let count = seen[key, default: 0]
            seen[key] = count + 1
            return count == 0 ? key : "\(key)-\(count)"
        }

        static func baseSlug(for title: String) -> String {
            var slug = title.lowercased()
            // Keep letters, digits, spaces, hyphens and underscores; drop the rest.
            slug = String(slug.unicodeScalars.filter { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == " " || scalar == "-" || scalar == "_"
            })
            slug = slug.trimmingCharacters(in: .whitespaces)
            slug = slug.replacingOccurrences(of: " ", with: "-")
            // Collapse runs of hyphens.
            while slug.contains("--") {
                slug = slug.replacingOccurrences(of: "--", with: "-")
            }
            return slug
        }
    }
}
