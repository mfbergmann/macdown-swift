import Foundation

/// Applies markdown formatting to text.
///
/// A pure transform from `(text, selection)` to a single replacement edit, with
/// no dependency on a text view — so the awkward cases (toggling off, multi-line
/// selections, renumbering) are testable directly.
///
/// Ranges are in UTF-16 units, matching what `NSTextView` and `UITextView` speak.
public struct MarkdownFormatter: Sendable {

    /// One replacement, expressed tightly enough to give a clean single undo step.
    public struct Edit: Equatable, Sendable {
        /// Range in the *original* text to replace.
        public var range: NSRange
        /// Text to put there.
        public var replacement: String
        /// Where the selection should land afterwards, in the *new* text.
        public var selectedRange: NSRange

        public init(range: NSRange, replacement: String, selectedRange: NSRange) {
            self.range = range
            self.replacement = replacement
            self.selectedRange = selectedRange
        }

        /// The full document text after applying this edit. Mainly for tests.
        public func applied(to text: String) -> String {
            (text as NSString).replacingCharacters(in: range, with: replacement)
        }
    }

    public init() {}

    public func apply(_ action: MarkdownAction, to text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        // Defend against a stale selection from a previous document revision.
        let selection = clamp(selection, to: ns.length)

        switch action {
        case .bold:
            return wrapInline(ns, selection, delimiter: "**", placeholder: "bold")
        case .italic:
            return wrapInline(ns, selection, delimiter: "*", placeholder: "italic")
        case .strikethrough:
            return wrapInline(ns, selection, delimiter: "~~", placeholder: "strikethrough")
        case .inlineCode:
            return wrapInline(ns, selection, delimiter: "`", placeholder: "code")

        case .heading1:
            return toggleHeading(ns, selection, level: 1)
        case .heading2:
            return toggleHeading(ns, selection, level: 2)
        case .heading3:
            return toggleHeading(ns, selection, level: 3)

        case .bulletList:
            return togglePrefix(ns, selection, prefix: "- ", family: .list)
        case .taskItem:
            return togglePrefix(ns, selection, prefix: "- [ ] ", family: .list)
        case .blockquote:
            return togglePrefix(ns, selection, prefix: "> ", family: .blockquote)
        case .numberedList:
            return toggleNumberedList(ns, selection)

        case .codeBlock:
            return wrapBlock(ns, selection, opening: "```", closing: "```", placeholder: "code")
        case .horizontalRule:
            return insertBlock(ns, selection, block: "---", selectionOffsetInBlock: nil)
        case .table:
            return insertTable(ns, selection)

        case .link:
            return insertLink(ns, selection, isImage: false)
        case .image:
            return insertLink(ns, selection, isImage: true)
        }
    }

    // MARK: - Inline Wrapping

    /// Wrap the selection in `delimiter`, or unwrap it if it's already wrapped.
    ///
    /// Recognises both shapes the user might have selected: the delimiters
    /// themselves (`**bold**`) and just the text between them (`bold`).
    private func wrapInline(
        _ ns: NSString, _ selection: NSRange, delimiter: String, placeholder: String
    ) -> Edit {
        let delimiterLength = (delimiter as NSString).length

        // Nothing selected — drop in a placeholder and select it, so typing replaces it.
        guard selection.length > 0 else {
            return Edit(
                range: selection,
                replacement: delimiter + placeholder + delimiter,
                selectedRange: NSRange(
                    location: selection.location + delimiterLength,
                    length: (placeholder as NSString).length
                )
            )
        }

        let selected = ns.substring(with: selection)

        // Selection includes the delimiters: **bold** -> bold
        if selected.count >= delimiterLength * 2,
           selected.hasPrefix(delimiter), selected.hasSuffix(delimiter) {
            let inner = ns.substring(
                with: NSRange(
                    location: selection.location + delimiterLength,
                    length: selection.length - delimiterLength * 2
                )
            )
            return Edit(
                range: selection,
                replacement: inner,
                selectedRange: NSRange(location: selection.location, length: (inner as NSString).length)
            )
        }

        // Selection sits between the delimiters: **[bold]** -> bold
        let before = NSRange(location: selection.location - delimiterLength, length: delimiterLength)
        let after = NSRange(location: selection.upperBound, length: delimiterLength)
        if before.location >= 0, after.upperBound <= ns.length,
           ns.substring(with: before) == delimiter,
           ns.substring(with: after) == delimiter {
            let outer = NSRange(
                location: before.location,
                length: selection.length + delimiterLength * 2
            )
            return Edit(
                range: outer,
                replacement: selected,
                selectedRange: NSRange(location: outer.location, length: selection.length)
            )
        }

        // Otherwise wrap it.
        return Edit(
            range: selection,
            replacement: delimiter + selected + delimiter,
            selectedRange: NSRange(
                location: selection.location + delimiterLength,
                length: selection.length
            )
        )
    }

    // MARK: - Line Prefixes

    /// Prefix shapes we recognise when toggling, so switching between list kinds
    /// replaces the marker instead of stacking markers up.
    private enum PrefixFamily {
        /// Bullets and task items share a family: applying "task item" to a
        /// bullet should convert it, not nest a second marker inside it.
        case list
        case blockquote
        case heading

        /// Length in characters of the existing marker at the start of
        /// `content`, or `0` if there isn't one.
        ///
        /// Returns a length rather than a slice: a `Substring` literal would
        /// carry indices belonging to a different string, which is a crash
        /// waiting to happen when the caller slices with them.
        func markerLength(in content: Substring) -> Int {
            switch self {
            case .list:
                // "- ", "* ", "+ ", "1. ", and the task variants "- [ ] " / "- [x] ".
                if let bullet = content.first, "-*+".contains(bullet) {
                    let afterBullet = content.dropFirst()
                    guard afterBullet.first == " " else { return 0 }
                    let rest = afterBullet.dropFirst()
                    let checkbox = ["[ ] ", "[x] ", "[X] "].first { rest.hasPrefix($0) }
                    return 2 + (checkbox?.count ?? 0)
                }
                let digits = content.prefix { $0.isNumber }
                if !digits.isEmpty, content.dropFirst(digits.count).hasPrefix(". ") {
                    return digits.count + 2
                }
                return 0

            case .blockquote:
                if content.hasPrefix("> ") { return 2 }
                return content.hasPrefix(">") ? 1 : 0

            case .heading:
                let hashes = content.prefix { $0 == "#" }
                guard !hashes.isEmpty, hashes.count <= 6,
                      content.dropFirst(hashes.count).hasPrefix(" ")
                else { return 0 }
                return hashes.count + 1
            }
        }
    }

    /// A line split so a marker can be swapped without disturbing indentation.
    private struct ParsedLine {
        var indent: Substring
        var marker: Substring
        var content: Substring

        /// Rebuild the line with `marker` in place of whatever was there.
        func rebuilt(marker newMarker: String) -> String {
            String(indent) + newMarker + String(content)
        }

        /// Rebuild the line with no marker at all.
        var unmarked: String { String(indent) + String(content) }
    }

    private func parse(_ line: String, family: PrefixFamily) -> ParsedLine {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let afterIndent = line[indent.endIndex...]
        let markerLength = family.markerLength(in: afterIndent)
        return ParsedLine(
            indent: indent,
            marker: afterIndent.prefix(markerLength),
            content: afterIndent.dropFirst(markerLength)
        )
    }

    /// Add `prefix` to every line the selection touches, or strip the marker
    /// from all of them if they all already carry this exact prefix.
    private func togglePrefix(
        _ ns: NSString, _ selection: NSRange, prefix: String, family: PrefixFamily
    ) -> Edit {
        let block = lineBlock(ns, selection)
        let parsed = block.lines.map { parse($0, family: family) }
        // Only a marker that matches *exactly* counts as "already applied" —
        // otherwise applying "bullet" to "- [x] done" would strip the "- " and
        // leave the orphaned checkbox behind.
        let allHavePrefix = parsed.allSatisfy { $0.marker == prefix }

        let newLines = parsed.map { line in
            allHavePrefix ? line.unmarked : line.rebuilt(marker: prefix)
        }
        return replaceLines(block, with: newLines)
    }

    /// Numbered lists need renumbering rather than a constant prefix.
    private func toggleNumberedList(_ ns: NSString, _ selection: NSRange) -> Edit {
        let block = lineBlock(ns, selection)
        let parsed = block.lines.map { parse($0, family: .list) }
        let isNumbered: (ParsedLine) -> Bool = { line in
            line.marker.first?.isNumber == true
        }
        let allNumbered = parsed.allSatisfy(isNumbered)

        let newLines = parsed.enumerated().map { index, line in
            allNumbered ? line.unmarked : line.rebuilt(marker: "\(index + 1). ")
        }
        return replaceLines(block, with: newLines)
    }

    private func toggleHeading(_ ns: NSString, _ selection: NSRange, level: Int) -> Edit {
        let block = lineBlock(ns, selection)
        let prefix = String(repeating: "#", count: level) + " "
        let parsed = block.lines.map { parse($0, family: .heading) }
        // Already at this exact level? Toggle the heading off.
        let allAtLevel = parsed.allSatisfy { $0.marker == prefix }

        let newLines = parsed.map { line in
            allAtLevel ? line.unmarked : line.rebuilt(marker: prefix)
        }
        return replaceLines(block, with: newLines)
    }

    // MARK: - Blocks

    /// Fence the selection between `opening` and `closing` on their own lines.
    private func wrapBlock(
        _ ns: NSString, _ selection: NSRange, opening: String, closing: String, placeholder: String
    ) -> Edit {
        let block = lineBlock(ns, selection)
        let hasContent = !(block.lines.count == 1 && block.lines[0].isEmpty)
        let bodyLines = hasContent ? block.lines : [placeholder]

        // Already fenced? Unwrap.
        if bodyLines.count >= 2,
           bodyLines.first?.hasPrefix(opening) == true,
           bodyLines.last?.hasPrefix(closing) == true {
            return replaceLines(block, with: Array(bodyLines.dropFirst().dropLast()))
        }

        let newLines = [opening] + bodyLines + [closing]
        let edit = replaceLines(block, with: newLines)
        // Select the body so the user can type over the placeholder.
        let bodyStart = edit.range.location + (opening as NSString).length + 1
        let bodyLength = (bodyLines.joined(separator: "\n") as NSString).length
        return Edit(
            range: edit.range,
            replacement: edit.replacement,
            selectedRange: NSRange(location: bodyStart, length: bodyLength)
        )
    }

    /// Drop a standalone block in at the cursor, on its own lines.
    private func insertBlock(
        _ ns: NSString, _ selection: NSRange, block: String, selectionOffsetInBlock: NSRange?
    ) -> Edit {
        let lineStart = lineBlock(ns, selection).range.location
        let atLineStart = selection.location == lineStart
        let needsLeadingBlank = !atLineStart || (lineStart > 0 && !endsWithBlankLine(ns, before: lineStart))

        var replacement = ""
        if !atLineStart { replacement += "\n" }
        if needsLeadingBlank && lineStart > 0 { replacement += "\n" }
        let blockStart = (replacement as NSString).length
        replacement += block + "\n"

        let range = NSRange(location: selection.location, length: selection.length)
        let caret = selection.location + (replacement as NSString).length
        let selected = selectionOffsetInBlock.map {
            NSRange(location: selection.location + blockStart + $0.location, length: $0.length)
        }

        return Edit(
            range: range,
            replacement: replacement,
            selectedRange: selected ?? NSRange(location: caret, length: 0)
        )
    }

    private func insertTable(_ ns: NSString, _ selection: NSRange) -> Edit {
        let table = """
        | Column 1 | Column 2 |
        | --- | --- |
        |  |  |
        """
        // Select the first header cell so the user can name their columns.
        let firstCell = NSRange(location: 2, length: 8)  // "Column 1"
        return insertBlock(ns, selection, block: table, selectionOffsetInBlock: firstCell)
    }

    private func insertLink(_ ns: NSString, _ selection: NSRange, isImage: Bool) -> Edit {
        let bang = isImage ? "!" : ""
        let selected = selection.length > 0 ? ns.substring(with: selection) : ""

        // A selected URL is the target, not the label.
        if looksLikeURL(selected) {
            let label = isImage ? "alt text" : "link text"
            let replacement = "\(bang)[\(label)](\(selected))"
            return Edit(
                range: selection,
                replacement: replacement,
                selectedRange: NSRange(
                    location: selection.location + (bang as NSString).length + 1,
                    length: (label as NSString).length
                )
            )
        }

        let label = selected.isEmpty ? (isImage ? "alt text" : "link text") : selected
        let placeholderURL = isImage ? "path/to/image.png" : "https://"
        let replacement = "\(bang)[\(label)](\(placeholderURL))"
        // Put the caret on the URL — that's the part the user still has to fill in.
        let urlStart = (bang as NSString).length + 1 + (label as NSString).length + 2
        return Edit(
            range: selection,
            replacement: replacement,
            selectedRange: NSRange(
                location: selection.location + urlStart,
                length: (placeholderURL as NSString).length
            )
        )
    }

    private func looksLikeURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        return trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("mailto:")
            || trimmed.hasPrefix("/")
            || trimmed.hasPrefix("./")
            || trimmed.hasPrefix("www.")
    }

    // MARK: - Line Helpers

    /// The whole lines a selection touches, split for per-line editing.
    private struct LineBlock {
        /// Range covering those lines, excluding any trailing newline.
        var range: NSRange
        var lines: [String]
    }

    private func lineBlock(_ ns: NSString, _ selection: NSRange) -> LineBlock {
        var range = ns.lineRange(for: selection)
        // lineRange includes the trailing newline; editing per-line is easier without it.
        while range.length > 0 {
            let last = ns.character(at: range.upperBound - 1)
            guard last == 0x0A || last == 0x0D else { break }
            range.length -= 1
        }
        let text = ns.substring(with: range)
        return LineBlock(range: range, lines: text.components(separatedBy: "\n"))
    }

    private func replaceLines(_ block: LineBlock, with lines: [String]) -> Edit {
        let replacement = lines.joined(separator: "\n")
        return Edit(
            range: block.range,
            replacement: replacement,
            selectedRange: NSRange(
                location: block.range.location,
                length: (replacement as NSString).length
            )
        )
    }

    private func endsWithBlankLine(_ ns: NSString, before location: Int) -> Bool {
        guard location >= 2 else { return location == 0 }
        let previous = ns.character(at: location - 2)
        return previous == 0x0A || previous == 0x0D
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }
}
