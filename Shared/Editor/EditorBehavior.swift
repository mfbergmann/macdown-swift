import Foundation

/// The typing conveniences that make a markdown editor feel native: lists that
/// continue themselves, brackets that close themselves, and a Tab key that
/// indents instead of inserting a stray tab character.
///
/// Like ``MarkdownFormatter``, every rule here is a pure transform from
/// `(text, selection)` to an optional edit. Returning `nil` means "no opinion —
/// let the text view do its normal thing", which keeps the delegate glue thin
/// and makes each rule testable on its own.
///
/// Ranges are in UTF-16 units, matching what `NSTextView` and `UITextView` speak.
public struct EditorBehavior: Sendable {

    public typealias Edit = MarkdownFormatter.Edit

    /// The knobs these behaviors read. Mirrors the matching `Preferences`
    /// properties, but as a plain value so tests don't need a defaults suite.
    public struct Options: Sendable {
        public var continuesLists: Bool
        public var completesMatchingCharacters: Bool
        public var convertsTabsToSpaces: Bool
        public var indentWidth: Int

        public init(
            continuesLists: Bool = true,
            completesMatchingCharacters: Bool = true,
            convertsTabsToSpaces: Bool = true,
            indentWidth: Int = 4
        ) {
            self.continuesLists = continuesLists
            self.completesMatchingCharacters = completesMatchingCharacters
            self.convertsTabsToSpaces = convertsTabsToSpaces
            self.indentWidth = indentWidth
        }
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    // MARK: - Return: continue the current list

    /// What pressing Return should do, or `nil` to insert a plain newline.
    ///
    /// Continues bullets, numbered items (incrementing), task items (always
    /// unchecked), and blockquotes. Pressing Return on an item that has no
    /// content ends the list instead of adding another empty bullet — the same
    /// escape hatch every list editor uses.
    public func newlineEdit(in text: String, selection: NSRange) -> Edit? {
        guard options.continuesLists else { return nil }
        // With text selected, Return replaces it; continuation would be surprising.
        guard selection.length == 0 else { return nil }

        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = ns.substring(with: lineRange)
        guard let marker = ListMarker(line: line) else { return nil }

        let caretColumn = selection.location - lineRange.location

        // Only continue when the caret is past the marker; hitting Return with
        // the caret inside "1. " is just splitting the line.
        guard caretColumn >= marker.prefixLength else { return nil }

        // An empty item means "I'm done with this list".
        if marker.contentIsEmpty {
            let clearRange = NSRange(
                location: lineRange.location,
                length: marker.prefixLength
            )
            return Edit(
                range: clearRange,
                replacement: "",
                selectedRange: NSRange(location: lineRange.location, length: 0)
            )
        }

        let continuation = "\n" + marker.nextPrefix
        return Edit(
            range: selection,
            replacement: continuation,
            selectedRange: NSRange(
                location: selection.location + (continuation as NSString).length,
                length: 0
            )
        )
    }

    // MARK: - Tab: indent

    /// What Tab (or Shift-Tab) should do.
    ///
    /// With a selection spanning lines, indents or outdents the whole block.
    /// With a plain caret, inserts one indent step — spaces or a tab depending
    /// on the preference. Shift-Tab always outdents.
    public func tabEdit(in text: String, selection: NSRange, outdent: Bool) -> Edit? {
        let ns = text as NSString
        let indent = options.convertsTabsToSpaces
            ? String(repeating: " ", count: options.indentWidth)
            : "\t"

        let selectionSpansLines = selection.length > 0
            && ns.substring(with: selection).contains("\n")

        if !selectionSpansLines && !outdent {
            return Edit(
                range: selection,
                replacement: indent,
                selectedRange: NSRange(
                    location: selection.location + (indent as NSString).length,
                    length: 0
                )
            )
        }

        // Block indent / outdent across every line the selection touches.
        var lineRange = ns.lineRange(for: selection)
        while lineRange.length > 0 {
            let last = ns.character(at: lineRange.upperBound - 1)
            guard last == 0x0A || last == 0x0D else { break }
            lineRange.length -= 1
        }
        let lines = ns.substring(with: lineRange).components(separatedBy: "\n")

        let newLines: [String] = lines.map { line in
            if outdent {
                return Self.removingOneIndent(from: line, width: options.indentWidth)
            }
            return indent + line
        }

        let replacement = newLines.joined(separator: "\n")
        guard replacement != ns.substring(with: lineRange) else { return nil }

        return Edit(
            range: lineRange,
            replacement: replacement,
            selectedRange: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }

    /// Strip one level of leading indentation: a tab, or up to `width` spaces.
    static func removingOneIndent(from line: String, width: Int) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        var removed = 0
        var remaining = Substring(line)
        while removed < width, remaining.first == " " {
            remaining = remaining.dropFirst()
            removed += 1
        }
        return String(remaining)
    }

    // MARK: - Auto-pairing

    /// Characters that close themselves when typed.
    private static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`",
    ]

    /// Closing characters that should be "typed over" rather than duplicated.
    private static let closers: Set<Character> = [")", "]", "}", "\"", "`"]

    /// What typing `input` should do, or `nil` to insert it normally.
    ///
    /// Three behaviors, in priority order:
    /// 1. Typing an opener with text selected wraps the selection in the pair.
    /// 2. Typing a closer immediately before that same closer steps over it,
    ///    so you can type through a pair you just created.
    /// 3. Typing an opener inserts the pair and leaves the caret between them.
    public func insertionEdit(for input: String, in text: String, selection: NSRange) -> Edit? {
        guard options.completesMatchingCharacters,
              input.count == 1,
              let character = input.first
        else { return nil }

        let ns = text as NSString

        // 1. Wrap a selection.
        if selection.length > 0, let closer = Self.pairs[character] {
            let selected = ns.substring(with: selection)
            let replacement = String(character) + selected + String(closer)
            return Edit(
                range: selection,
                replacement: replacement,
                // Keep the original text selected, now inside the pair.
                selectedRange: NSRange(location: selection.location + 1, length: selection.length)
            )
        }

        guard selection.length == 0 else { return nil }

        // 2. Step over a closer we most likely inserted ourselves.
        if Self.closers.contains(character),
           selection.location < ns.length,
           ns.substring(with: NSRange(location: selection.location, length: 1)) == String(character) {
            return Edit(
                range: NSRange(location: selection.location, length: 1),
                replacement: String(character),
                selectedRange: NSRange(location: selection.location + 1, length: 0)
            )
        }

        // 3. Auto-close, but only where a pair is plausible: at end of line or
        //    before whitespace//a closing bracket. Typing "(" before a word is
        //    usually the start of an edit, not a new pair.
        guard let closer = Self.pairs[character] else { return nil }
        if selection.location < ns.length {
            let next = ns.substring(with: NSRange(location: selection.location, length: 1))
            let nextIsBoundary = next == "\n" || next == " " || next == "\t"
                || Self.closers.contains(Character(next))
            guard nextIsBoundary else { return nil }
        }

        // Quote-like characters double as markdown syntax; don't auto-close one
        // that is closing an existing run (e.g. the second ` of an inline code span).
        if character == "\"" || character == "`" {
            let before = selection.location > 0
                ? ns.substring(with: NSRange(location: selection.location - 1, length: 1))
                : ""
            if before == String(character) { return nil }
        }

        let replacement = String(character) + String(closer)
        return Edit(
            range: selection,
            replacement: replacement,
            selectedRange: NSRange(location: selection.location + 1, length: 0)
        )
    }

    // MARK: - List Markers

    /// A list or quote marker at the start of a line, and what should follow it
    /// on the next line.
    struct ListMarker {
        /// Length in UTF-16 units of indentation + marker + trailing space.
        var prefixLength: Int
        /// The prefix to use on the continuation line.
        var nextPrefix: String
        /// Whether this line has nothing after its marker.
        var contentIsEmpty: Bool

        init?(line: String) {
            // Strip a trailing newline before measuring content.
            var body = Substring(line)
            while body.last == "\n" || body.last == "\r" { body = body.dropLast() }

            let indent = String(body.prefix { $0 == " " || $0 == "\t" })
            let afterIndent = body.dropFirst(indent.count)

            /// The marker as typed, the marker to repeat on the next line, and
            /// whatever content followed it.
            let parsed: (marker: String, next: String, content: Substring)?

            if let bullet = afterIndent.first, "-*+".contains(bullet),
               afterIndent.dropFirst().first == " " {
                let rest = afterIndent.dropFirst(2)
                if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
                    // A continued task item always starts unchecked.
                    parsed = ("\(bullet) [x] ", "\(bullet) [ ] ", rest.dropFirst(4))
                } else {
                    parsed = ("\(bullet) ", "\(bullet) ", rest)
                }
            } else if case let digits = afterIndent.prefix(while: { $0.isNumber }),
                      !digits.isEmpty,
                      afterIndent.dropFirst(digits.count).hasPrefix(". ") {
                // Numbered: continue with the next number.
                let next = (Int(digits) ?? 0) + 1
                parsed = ("\(digits). ", "\(next). ", afterIndent.dropFirst(digits.count + 2))
            } else if afterIndent.hasPrefix("> ") {
                parsed = ("> ", "> ", afterIndent.dropFirst(2))
            } else {
                parsed = nil
            }

            guard let parsed else { return nil }

            prefixLength = (indent + parsed.marker).utf16.count
            nextPrefix = indent + parsed.next
            contentIsEmpty = parsed.content.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

// MARK: - Preferences Bridge

public extension EditorBehavior.Options {
    init(preferences: Preferences) {
        self.init(
            continuesLists: preferences.editorAutoIncrementNumberedLists,
            completesMatchingCharacters: preferences.editorCompleteMatchingCharacters,
            convertsTabsToSpaces: preferences.editorConvertTabs,
            indentWidth: 4
        )
    }
}
