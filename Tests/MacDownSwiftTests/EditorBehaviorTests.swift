import Foundation
import Testing
@testable import MacDownCore

private let behavior = EditorBehavior()

/// Apply the Return-key rule and return the resulting text, or nil if the
/// behavior declined to act (meaning: insert a plain newline).
private func onReturn(_ text: String, at location: Int) -> String? {
    behavior.newlineEdit(in: text, selection: NSRange(location: location, length: 0))?
        .applied(to: text)
}

/// Press Return at the very end of `text`.
private func onReturnAtEnd(_ text: String) -> String? {
    onReturn(text, at: (text as NSString).length)
}

private func onTab(_ text: String, _ selection: NSRange, outdent: Bool = false) -> String? {
    behavior.tabEdit(in: text, selection: selection, outdent: outdent)?.applied(to: text)
}

private func onType(_ input: String, _ text: String, _ selection: NSRange) -> String? {
    behavior.insertionEdit(for: input, in: text, selection: selection)?.applied(to: text)
}

@Suite("List continuation")
struct ListContinuationTests {

    @Test("Continues a bullet list")
    func bullet() {
        #expect(onReturnAtEnd("- first") == "- first\n- ")
    }

    @Test("Continues with the same bullet character")
    func bulletCharacterPreserved() {
        #expect(onReturnAtEnd("* first") == "* first\n* ")
        #expect(onReturnAtEnd("+ first") == "+ first\n+ ")
    }

    @Test("Increments a numbered list")
    func numbered() {
        #expect(onReturnAtEnd("1. first") == "1. first\n2. ")
        #expect(onReturnAtEnd("9. ninth") == "9. ninth\n10. ")
    }

    @Test("Continues a task item unchecked, even from a checked one")
    func taskItem() {
        #expect(onReturnAtEnd("- [ ] todo") == "- [ ] todo\n- [ ] ")
        #expect(onReturnAtEnd("- [x] done") == "- [x] done\n- [ ] ")
    }

    @Test("Continues a blockquote")
    func blockquote() {
        #expect(onReturnAtEnd("> quoted") == "> quoted\n> ")
    }

    @Test("Preserves indentation of a nested item")
    func nestedIndent() {
        #expect(onReturnAtEnd("    - nested") == "    - nested\n    - ")
        #expect(onReturnAtEnd("  1. nested") == "  1. nested\n  2. ")
    }

    @Test("Return on an empty item ends the list")
    func emptyItemEndsList() {
        #expect(onReturnAtEnd("- first\n- ") == "- first\n")
        #expect(onReturnAtEnd("1. first\n2. ") == "1. first\n")
        #expect(onReturnAtEnd("> ") == "")
    }

    @Test("Declines on a plain paragraph")
    func plainText() {
        #expect(onReturnAtEnd("just a sentence") == nil)
    }

    @Test("Declines when the caret sits inside the marker")
    func caretInsideMarker() {
        // Caret between "1" and ". " — the user is editing the number.
        #expect(onReturn("1. first", at: 1) == nil)
    }

    @Test("Declines when text is selected")
    func withSelection() {
        let edit = behavior.newlineEdit(
            in: "- first", selection: NSRange(location: 2, length: 5)
        )
        #expect(edit == nil, "Return should replace the selection, not continue the list")
    }

    @Test("Declines when the preference is off")
    func disabled() {
        var options = EditorBehavior.Options()
        options.continuesLists = false
        let off = EditorBehavior(options: options)
        #expect(off.newlineEdit(in: "- first", selection: NSRange(location: 7, length: 0)) == nil)
    }

    @Test("Continues mid-document, not just at the end")
    func midDocument() {
        let text = "- first\nafter"
        // Caret at the end of the "- first" line.
        #expect(onReturn(text, at: 7) == "- first\n- \nafter")
    }
}

@Suite("Tab handling")
struct TabHandlingTests {

    @Test("Tab inserts spaces when converting tabs")
    func insertsSpaces() {
        #expect(onTab("abc", NSRange(location: 0, length: 0)) == "    abc")
    }

    @Test("Tab inserts a real tab when not converting")
    func insertsTab() {
        var options = EditorBehavior.Options()
        options.convertsTabsToSpaces = false
        let tabby = EditorBehavior(options: options)
        let edit = tabby.tabEdit(in: "abc", selection: NSRange(location: 0, length: 0), outdent: false)
        #expect(edit?.applied(to: "abc") == "\tabc")
    }

    @Test("Indents every line of a multi-line selection")
    func blockIndent() {
        let text = "one\ntwo"
        #expect(onTab(text, NSRange(location: 0, length: 7)) == "    one\n    two")
    }

    @Test("Outdents every line of a multi-line selection")
    func blockOutdent() {
        let text = "    one\n    two"
        #expect(onTab(text, NSRange(location: 0, length: 15), outdent: true) == "one\ntwo")
    }

    @Test("Outdent removes a tab as one level")
    func outdentTab() {
        #expect(onTab("\tone", NSRange(location: 0, length: 4), outdent: true) == "one")
    }

    @Test("Outdent removes only partial indentation when that's all there is")
    func outdentPartial() {
        #expect(onTab("  one", NSRange(location: 0, length: 5), outdent: true) == "one")
    }

    @Test("Outdenting an unindented line changes nothing")
    func outdentNoop() {
        #expect(onTab("one", NSRange(location: 0, length: 3), outdent: true) == nil)
    }

    @Test("Caret-only Shift-Tab outdents the current line")
    func caretOutdent() {
        #expect(onTab("    one", NSRange(location: 7, length: 0), outdent: true) == "one")
    }
}

@Suite("Auto-pairing")
struct AutoPairingTests {

    @Test("Typing an opener at end of line inserts the pair")
    func insertsPair() {
        #expect(onType("(", "call", NSRange(location: 4, length: 0)) == "call()")
        #expect(onType("[", "", NSRange(location: 0, length: 0)) == "[]")
        #expect(onType("{", "", NSRange(location: 0, length: 0)) == "{}")
    }

    @Test("The caret lands between the pair")
    func caretBetweenPair() {
        let edit = behavior.insertionEdit(
            for: "(", in: "call", selection: NSRange(location: 4, length: 0)
        )
        #expect(edit?.selectedRange == NSRange(location: 5, length: 0))
    }

    @Test("Typing an opener with a selection wraps it")
    func wrapsSelection() {
        let text = "wrap me"
        let edit = behavior.insertionEdit(
            for: "(", in: text, selection: NSRange(location: 5, length: 2)
        )
        #expect(edit?.applied(to: text) == "wrap (me)")
        #expect(edit?.selectedRange == NSRange(location: 6, length: 2), "selection stays on the text")
    }

    @Test("Typing a closer before that same closer steps over it")
    func typesOverCloser() {
        let text = "call()"
        let edit = behavior.insertionEdit(
            for: ")", in: text, selection: NSRange(location: 5, length: 0)
        )
        #expect(edit?.applied(to: text) == "call()", "no duplicate paren")
        #expect(edit?.selectedRange == NSRange(location: 6, length: 0), "caret moves past it")
    }

    @Test("Does not auto-close before a word")
    func noPairBeforeWord() {
        // Typing "(" before "word" is usually wrapping an existing edit.
        #expect(onType("(", "word", NSRange(location: 0, length: 0)) == nil)
    }

    @Test("Auto-closes before whitespace and closing brackets")
    func pairsBeforeBoundaries() {
        #expect(onType("(", " tail", NSRange(location: 0, length: 0)) == "() tail")
        // Typing inside an existing pair, e.g. "[|]" -> "[(|)]".
        #expect(onType("(", "[]", NSRange(location: 1, length: 0)) == "[()]")
    }

    @Test("Does not double a backtick that is closing a code span")
    func noPairClosingCodeSpan() {
        // Second backtick of `` — the user is closing, not opening.
        #expect(onType("`", "`", NSRange(location: 1, length: 0)) == nil)
    }

    @Test("Declines when the preference is off")
    func disabled() {
        var options = EditorBehavior.Options()
        options.completesMatchingCharacters = false
        let off = EditorBehavior(options: options)
        #expect(off.insertionEdit(for: "(", in: "", selection: NSRange(location: 0, length: 0)) == nil)
    }

    @Test("Ignores multi-character input such as a paste")
    func ignoresPaste() {
        #expect(onType("(pasted)", "", NSRange(location: 0, length: 0)) == nil)
    }

    @Test("Ignores characters that are not part of a pair")
    func ignoresPlainCharacters() {
        #expect(onType("a", "", NSRange(location: 0, length: 0)) == nil)
    }
}
