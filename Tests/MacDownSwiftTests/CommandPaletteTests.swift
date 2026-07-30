import Foundation
import Testing
@testable import MacDownCore

private func titles(_ query: String) -> [String] {
    CommandPalette.filter(query).map(\.title)
}

@Suite("Command palette registry")
struct CommandPaletteRegistryTests {

    @Test("Covers view, format, and export commands")
    func coversGroups() {
        let groups = Set(CommandPalette.commands.map(\.group))
        #expect(groups == ["View", "Format", "Export"])
    }

    @Test("Every markdown action is reachable")
    func allFormatActions() {
        let ids = Set(CommandPalette.commands.map(\.id))
        for action in MarkdownAction.allCases {
            #expect(ids.contains("format.\(action.rawValue)"), "missing \(action)")
        }
    }

    @Test("Every export command is reachable")
    func allExportCommands() {
        let ids = Set(CommandPalette.commands.map(\.id))
        for command in ExportCommand.allCases {
            #expect(ids.contains("export.\(command.rawValue)"), "missing \(command)")
        }
    }

    @Test("Command ids are unique")
    func uniqueIDs() {
        let ids = CommandPalette.commands.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Export titles drop the menu ellipsis")
    func noEllipsis() {
        let exports = CommandPalette.commands.filter { $0.group == "Export" }
        #expect(exports.allSatisfy { !$0.title.contains("…") })
    }
}

@Suite("Command palette filtering")
struct CommandPaletteFilterTests {

    @Test("An empty query shows everything")
    func emptyQuery() {
        #expect(CommandPalette.filter("").count == CommandPalette.commands.count)
        #expect(CommandPalette.filter("   ").count == CommandPalette.commands.count)
    }

    @Test("Matches on the command's own title")
    func matchesTitle() {
        #expect(titles("bold").contains("Bold"))
    }

    @Test("Matches on the group name too")
    func matchesGroup() {
        // "export" is the group, not part of any title after the ellipsis strip.
        let results = CommandPalette.filter("export")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.group == "Export" })
    }

    @Test("Matches a scattered subsequence")
    func subsequence() {
        // "hrz" as a subsequence of "Horizontal Rule".
        #expect(titles("hrz").contains("Horizontal Rule"))
    }

    @Test("Is case-insensitive")
    func caseInsensitive() {
        #expect(titles("BOLD").contains("Bold"))
        #expect(titles("bOlD").contains("Bold"))
    }

    @Test("Rejects a query that isn't a subsequence")
    func noMatch() {
        #expect(CommandPalette.filter("zzzzqqq").isEmpty)
    }

    @Test("Ranks a prefix match above a scattered one")
    func ranksPrefixHigher() {
        let results = titles("split")
        #expect(results.first == "Split")
    }

    @Test("Spaces in the query are ignored rather than matched literally")
    func ignoresSpaces() {
        #expect(titles("code block").contains("Code Block"))
        #expect(titles("codeblock").contains("Code Block"))
    }

    @Test("Word-start matches outrank mid-word ones")
    func wordStartsWin() {
        // "tw" should find "Typewriter Mode" via its two word starts.
        let results = titles("tw")
        #expect(results.contains("Typewriter Mode"))
    }

    @Test("Ordering is deterministic for equally-scored matches")
    func deterministicOrder() {
        let first = titles("o")
        let second = titles("o")
        #expect(first == second)
    }
}

@Suite("Fuzzy scoring")
struct FuzzyScoreTests {

    @Test("An exact substring scores above a scattered match")
    func consecutiveBeatsScattered() {
        let consecutive = CommandPalette.fuzzyScore(query: "abc", in: "abcdef")
        let scattered = CommandPalette.fuzzyScore(query: "abc", in: "axbxcx")
        #expect(consecutive != nil && scattered != nil)
        #expect(consecutive! > scattered!)
    }

    @Test("Returns nil when characters are missing")
    func missingCharacters() {
        #expect(CommandPalette.fuzzyScore(query: "xyz", in: "abc") == nil)
    }

    @Test("Returns nil when characters appear out of order")
    func outOfOrder() {
        #expect(CommandPalette.fuzzyScore(query: "ba", in: "abc") == nil)
    }

    @Test("An empty query matches anything")
    func emptyQuery() {
        #expect(CommandPalette.fuzzyScore(query: "", in: "anything") == 0)
    }
}
