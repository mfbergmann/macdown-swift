import Foundation
import Testing
@testable import MacDownCore

/// Convenience: apply an action and return the resulting document text.
private func format(
    _ action: MarkdownAction,
    _ text: String,
    _ selection: NSRange
) -> String {
    MarkdownFormatter().apply(action, to: text, selection: selection).applied(to: text)
}

/// Apply an action and return both the text and what ends up selected.
private func formatWithSelection(
    _ action: MarkdownAction,
    _ text: String,
    _ selection: NSRange
) -> (text: String, selected: String) {
    let edit = MarkdownFormatter().apply(action, to: text, selection: selection)
    let newText = edit.applied(to: text)
    let selected = (newText as NSString).substring(with: edit.selectedRange)
    return (newText, selected)
}

/// Range of the first occurrence of `substring`.
private func range(of substring: String, in text: String) -> NSRange {
    (text as NSString).range(of: substring)
}

@Suite("Inline formatting")
struct InlineFormattingTests {

    @Test("Wraps a selection in bold")
    func bold() {
        let text = "make this bold"
        #expect(format(.bold, text, range(of: "this", in: text)) == "make **this** bold")
    }

    @Test("Wraps a selection in italic, strikethrough, and code")
    func otherInlineDelimiters() {
        let text = "word"
        let all = NSRange(location: 0, length: 4)
        #expect(format(.italic, text, all) == "*word*")
        #expect(format(.strikethrough, text, all) == "~~word~~")
        #expect(format(.inlineCode, text, all) == "`word`")
    }

    @Test("Selection stays on the wrapped text, not the delimiters")
    func selectionSurvivesWrapping() {
        let text = "make this bold"
        let result = formatWithSelection(.bold, text, range(of: "this", in: text))
        #expect(result.selected == "this")
    }

    @Test("An empty selection inserts a placeholder and selects it")
    func emptySelectionUsesPlaceholder() {
        let result = formatWithSelection(.bold, "", NSRange(location: 0, length: 0))
        #expect(result.text == "**bold**")
        #expect(result.selected == "bold", "typing should replace the placeholder")
    }

    @Test("Toggles off when the delimiters are inside the selection")
    func unwrapWithDelimitersSelected() {
        let text = "make **this** bold"
        #expect(format(.bold, text, range(of: "**this**", in: text)) == "make this bold")
    }

    @Test("Toggles off when only the inner text is selected")
    func unwrapWithInnerTextSelected() {
        let text = "make **this** bold"
        let result = formatWithSelection(.bold, text, range(of: "this", in: text))
        #expect(result.text == "make this bold")
        #expect(result.selected == "this")
    }

    @Test("Bold applied twice returns to the original")
    func boldIsInvolutive() {
        let text = "make this bold"
        let selection = range(of: "this", in: text)
        let once = MarkdownFormatter().apply(.bold, to: text, selection: selection)
        let onceText = once.applied(to: text)
        let twice = MarkdownFormatter().apply(.bold, to: onceText, selection: once.selectedRange)
        #expect(twice.applied(to: onceText) == text)
    }

    @Test("Handles a selection at the very start of the document")
    func selectionAtStart() {
        let text = "abc"
        #expect(format(.bold, text, NSRange(location: 0, length: 3)) == "**abc**")
    }

    @Test("Handles multi-byte characters without corrupting the text")
    func multiByteSafe() {
        let text = "emoji 🎉 party"
        let result = format(.bold, text, range(of: "🎉", in: text))
        #expect(result == "emoji **🎉** party")
    }
}

@Suite("Headings")
struct HeadingFormattingTests {

    @Test("Adds a heading prefix")
    func addHeading() {
        #expect(format(.heading1, "Title", NSRange(location: 0, length: 0)) == "# Title")
        #expect(format(.heading2, "Title", NSRange(location: 0, length: 0)) == "## Title")
        #expect(format(.heading3, "Title", NSRange(location: 0, length: 0)) == "### Title")
    }

    @Test("Changing level replaces the prefix instead of stacking")
    func replacesLevel() {
        #expect(format(.heading3, "# Title", NSRange(location: 0, length: 0)) == "### Title")
        #expect(format(.heading1, "### Title", NSRange(location: 0, length: 0)) == "# Title")
    }

    @Test("Applying the same level again removes the heading")
    func togglesOff() {
        #expect(format(.heading2, "## Title", NSRange(location: 0, length: 0)) == "Title")
    }

    @Test("Applies to every line of a multi-line selection")
    func multiLine() {
        let text = "One\nTwo"
        let result = format(.heading1, text, NSRange(location: 0, length: 7))
        #expect(result == "# One\n# Two")
    }

    @Test("Works from a cursor in the middle of a line")
    func cursorMidLine() {
        let text = "Some title"
        #expect(format(.heading1, text, NSRange(location: 5, length: 0)) == "# Some title")
    }
}

@Suite("Lists and blockquotes")
struct ListFormattingTests {

    @Test("Adds bullet markers")
    func bullets() {
        let text = "a\nb"
        #expect(format(.bulletList, text, NSRange(location: 0, length: 3)) == "- a\n- b")
    }

    @Test("Removes bullet markers when every line already has one")
    func bulletsToggleOff() {
        let text = "- a\n- b"
        #expect(format(.bulletList, text, NSRange(location: 0, length: 7)) == "a\nb")
    }

    @Test("Numbers a list sequentially")
    func numberedList() {
        let text = "a\nb\nc"
        let result = format(.numberedList, text, NSRange(location: 0, length: 5))
        #expect(result == "1. a\n2. b\n3. c")
    }

    @Test("Removes numbering when every line is already numbered")
    func numberedToggleOff() {
        let text = "1. a\n2. b"
        #expect(format(.numberedList, text, NSRange(location: 0, length: 9)) == "a\nb")
    }

    @Test("Switching list kinds replaces the marker")
    func switchListKind() {
        let text = "- a\n- b"
        let result = format(.numberedList, text, NSRange(location: 0, length: 7))
        #expect(result == "1. a\n2. b", "should not produce '1. - a'")
    }

    @Test("Bullets become task items without doubling the marker")
    func bulletToTask() {
        let text = "- a"
        #expect(format(.taskItem, text, NSRange(location: 0, length: 3)) == "- [ ] a")
    }

    @Test("Task items toggle back off")
    func taskToggleOff() {
        let text = "- [ ] a"
        #expect(format(.taskItem, text, NSRange(location: 0, length: 7)) == "a")
    }

    @Test("A checked task item is still recognised as a task marker")
    func checkedTaskRecognised() {
        let text = "- [x] a"
        #expect(format(.bulletList, text, NSRange(location: 0, length: 7)) == "- a")
    }

    @Test("Adds and removes blockquote markers")
    func blockquote() {
        let text = "quoted"
        let quoted = format(.blockquote, text, NSRange(location: 0, length: 6))
        #expect(quoted == "> quoted")
        #expect(format(.blockquote, quoted, NSRange(location: 0, length: 8)) == "quoted")
    }

    @Test("Keeps indentation, putting the marker after it")
    func preservesIndent() {
        let text = "    nested"
        #expect(format(.bulletList, text, NSRange(location: 0, length: 10)) == "    - nested")
    }

    @Test("Keeps indentation when toggling a marker off")
    func preservesIndentOnRemoval() {
        let text = "    - nested"
        #expect(format(.bulletList, text, NSRange(location: 0, length: 12)) == "    nested")
    }

    @Test("An indented heading keeps its indentation")
    func indentedHeading() {
        let text = "  Title"
        #expect(format(.heading1, text, NSRange(location: 0, length: 7)) == "  # Title")
    }

    @Test("A mixed selection gets the marker applied to every line")
    func mixedSelectionApplies() {
        // Not all lines have the marker, so this adds rather than removes.
        let text = "- a\nb"
        #expect(format(.bulletList, text, NSRange(location: 0, length: 5)) == "- a\n- b")
    }
}

@Suite("Blocks and insertions")
struct BlockFormattingTests {

    @Test("Fences a selection as a code block")
    func codeBlock() {
        let text = "let x = 1"
        let result = format(.codeBlock, text, NSRange(location: 0, length: 9))
        #expect(result == "```\nlet x = 1\n```")
    }

    @Test("An empty code block gets a selected placeholder")
    func emptyCodeBlock() {
        let result = formatWithSelection(.codeBlock, "", NSRange(location: 0, length: 0))
        #expect(result.text == "```\ncode\n```")
        #expect(result.selected == "code")
    }

    @Test("A fenced block unfences")
    func codeBlockToggleOff() {
        let text = "```\nlet x = 1\n```"
        let result = format(.codeBlock, text, NSRange(location: 0, length: (text as NSString).length))
        #expect(result == "let x = 1")
    }

    @Test("Inserts a horizontal rule on its own line")
    func horizontalRule() {
        let result = format(.horizontalRule, "", NSRange(location: 0, length: 0))
        #expect(result.contains("---"))
    }

    @Test("Inserts a table skeleton with the first header cell selected")
    func table() {
        let result = formatWithSelection(.table, "", NSRange(location: 0, length: 0))
        #expect(result.text.contains("| Column 1 | Column 2 |"))
        #expect(result.text.contains("| --- | --- |"))
        #expect(result.selected == "Column 1")
    }

    @Test("A rule inserted mid-line starts a new line first")
    func ruleBreaksLine() {
        let text = "some text"
        let result = format(.horizontalRule, text, NSRange(location: 9, length: 0))
        #expect(result.hasPrefix("some text\n"))
        #expect(result.contains("---"))
    }
}

@Suite("Links and images")
struct LinkFormattingTests {

    @Test("Turns selected text into a link with the URL selected")
    func linkFromText() {
        let text = "click here"
        let result = formatWithSelection(.link, text, range(of: "here", in: text))
        #expect(result.text == "click [here](https://)")
        #expect(result.selected == "https://", "the URL is what still needs filling in")
    }

    @Test("Treats a selected URL as the target, not the label")
    func linkFromURL() {
        let text = "https://example.com"
        let result = formatWithSelection(.link, text, NSRange(location: 0, length: 19))
        #expect(result.text == "[link text](https://example.com)")
        #expect(result.selected == "link text")
    }

    @Test("An empty selection produces a full link skeleton")
    func emptyLink() {
        let result = format(.link, "", NSRange(location: 0, length: 0))
        #expect(result == "[link text](https://)")
    }

    @Test("Images get the leading bang")
    func image() {
        let text = "photo"
        let result = format(.image, text, NSRange(location: 0, length: 5))
        #expect(result == "![photo](path/to/image.png)")
    }

    @Test("A selected image path becomes the target")
    func imageFromPath() {
        let text = "./diagram.png"
        let result = formatWithSelection(.image, text, NSRange(location: 0, length: 13))
        #expect(result.text == "![alt text](./diagram.png)")
        #expect(result.selected == "alt text")
    }

    @Test("Text with spaces is never mistaken for a URL")
    func spacedTextIsNotURL() {
        let text = "not a url"
        let result = format(.link, text, NSRange(location: 0, length: 9))
        #expect(result == "[not a url](https://)")
    }
}

@Suite("Robustness")
struct FormatterRobustnessTests {

    @Test("Every action handles an empty document without crashing")
    func emptyDocument() {
        for action in MarkdownAction.allCases {
            let edit = MarkdownFormatter().apply(action, to: "", selection: NSRange(location: 0, length: 0))
            #expect(edit.range.location == 0)
            _ = edit.applied(to: "")
        }
    }

    @Test("Every action clamps a selection past the end of the text")
    func outOfBoundsSelection() {
        let text = "short"
        for action in MarkdownAction.allCases {
            let wild = NSRange(location: 999, length: 999)
            let edit = MarkdownFormatter().apply(action, to: text, selection: wild)
            #expect(edit.range.upperBound <= (text as NSString).length)
            _ = edit.applied(to: text)
        }
    }

    @Test("Resulting selection always lands inside the new text")
    func selectionInBounds() {
        let text = "some sample text\nsecond line"
        for action in MarkdownAction.allCases {
            let selection = range(of: "sample", in: text)
            let edit = MarkdownFormatter().apply(action, to: text, selection: selection)
            let newText = edit.applied(to: text) as NSString
            #expect(
                edit.selectedRange.upperBound <= newText.length,
                "\(action) produced an out-of-bounds selection"
            )
        }
    }
}
