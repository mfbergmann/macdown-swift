import Foundation

/// Distraction-reducing editor modes.
public struct WritingModes: Equatable, Sendable {
    /// Dim everything except the paragraph the caret is in.
    public var focus: Bool
    /// Keep the caret vertically centred as you type.
    public var typewriter: Bool

    public init(focus: Bool = false, typewriter: Bool = false) {
        self.focus = focus
        self.typewriter = typewriter
    }

    public var isAnyEnabled: Bool { focus || typewriter }

    public init(preferences: Preferences) {
        self.init(focus: preferences.focusMode, typewriter: preferences.typewriterMode)
    }
}

/// Works out which range of text focus mode should keep at full strength.
public enum FocusRange {
    /// The paragraph containing `selection`.
    ///
    /// A paragraph is a run of lines bounded by blank lines, which matches how
    /// markdown blocks read — so a multi-line list item or wrapped sentence
    /// stays lit as one unit rather than only the single line the caret is on.
    public static func paragraph(in text: String, selection: NSRange) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }

        let location = min(max(0, selection.location), ns.length)
        let caretLine = ns.lineRange(for: NSRange(location: location, length: 0))

        // Walk backwards over non-blank lines.
        var start = caretLine.location
        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            let text = ns.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { break }
            start = previous.location
        }

        // Walk forwards over non-blank lines.
        var end = caretLine.upperBound
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            let text = ns.substring(with: next).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { break }
            end = next.upperBound
            if next.length == 0 { break }
        }

        // A selection spanning several paragraphs should light all of them.
        if selection.length > 0 {
            let selectionEnd = min(selection.upperBound, ns.length)
            if selectionEnd > end {
                let trailing = ns.lineRange(for: NSRange(location: selectionEnd - 1, length: 0))
                end = max(end, trailing.upperBound)
            }
        }

        return NSRange(location: start, length: max(0, end - start))
    }
}
