import Foundation
import Testing
@testable import MacDownCore

/// The text focus mode would keep lit for a caret at `location`.
private func lit(_ text: String, at location: Int) -> String {
    let range = FocusRange.paragraph(in: text, selection: NSRange(location: location, length: 0))
    return (text as NSString).substring(with: range)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

@Suite("Focus range")
struct FocusRangeTests {

    @Test("Lights the paragraph containing the caret")
    func singleParagraph() {
        let text = "First para.\n\nSecond para.\n\nThird para."
        let location = (text as NSString).range(of: "Second").location
        #expect(lit(text, at: location) == "Second para.")
    }

    @Test("A wrapped multi-line paragraph stays lit as one unit")
    func multiLineParagraph() {
        let text = "Alpha\nBravo\nCharlie\n\nNext one."
        #expect(lit(text, at: 0) == "Alpha\nBravo\nCharlie")
        let middle = (text as NSString).range(of: "Bravo").location
        #expect(lit(text, at: middle) == "Alpha\nBravo\nCharlie")
    }

    @Test("Works at the very start and end of the document")
    func boundaries() {
        let text = "Only paragraph."
        #expect(lit(text, at: 0) == "Only paragraph.")
        #expect(lit(text, at: (text as NSString).length) == "Only paragraph.")
    }

    @Test("An empty document produces an empty range")
    func emptyDocument() {
        let range = FocusRange.paragraph(in: "", selection: NSRange(location: 0, length: 0))
        #expect(range.length == 0)
    }

    @Test("Clamps a caret past the end of the text")
    func outOfBounds() {
        let text = "Short."
        let range = FocusRange.paragraph(
            in: text, selection: NSRange(location: 999, length: 0)
        )
        #expect(range.upperBound <= (text as NSString).length)
    }

    @Test("A selection spanning paragraphs lights all of them")
    func spanningSelection() {
        let text = "One.\n\nTwo.\n\nThree."
        let start = (text as NSString).range(of: "One").location
        let end = (text as NSString).range(of: "Two").upperBound
        let range = FocusRange.paragraph(
            in: text, selection: NSRange(location: start, length: end - start)
        )
        let selected = (text as NSString).substring(with: range)
        #expect(selected.contains("One."))
        #expect(selected.contains("Two."))
    }

    @Test("A blank line between paragraphs is a boundary")
    func blankLineBoundary() {
        let text = "Above.\n\nBelow."
        let location = (text as NSString).range(of: "Below").location
        #expect(lit(text, at: location) == "Below.")
        #expect(!lit(text, at: location).contains("Above"))
    }

    @Test("Whitespace-only lines count as blank")
    func whitespaceIsBlank() {
        let text = "Above.\n   \nBelow."
        let location = (text as NSString).range(of: "Below").location
        #expect(lit(text, at: location) == "Below.")
    }
}

@Suite("Writing modes")
struct WritingModesTests {

    @Test("Both modes are off by default")
    func defaultsOff() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "T.\(UUID().uuidString)")!)
        let modes = WritingModes(preferences: prefs)
        #expect(!modes.focus)
        #expect(!modes.typewriter)
        #expect(!modes.isAnyEnabled)
    }

    @Test("Modes are independent")
    func independent() {
        var modes = WritingModes()
        modes.focus = true
        #expect(modes.isAnyEnabled)
        #expect(!modes.typewriter)
    }

    @Test("Reads both modes from preferences")
    func readsPreferences() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "T.\(UUID().uuidString)")!)
        prefs.focusMode = true
        prefs.typewriterMode = true
        let modes = WritingModes(preferences: prefs)
        #expect(modes.focus)
        #expect(modes.typewriter)
    }
}
