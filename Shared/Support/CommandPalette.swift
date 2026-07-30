import Foundation

/// One entry in the command palette.
///
/// Commands are plain data rather than closures: every action in the app
/// already travels as a notification, so a command is just the notification to
/// post. That keeps the whole registry testable without a running UI.
public struct PaletteCommand: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var group: String
    public var shortcut: String?
    /// Raw value of the `Notification.Name` to post.
    public var notification: String
    /// Optional object to post with it (an action or mode raw value).
    public var object: String?

    public init(
        id: String,
        title: String,
        group: String,
        shortcut: String? = nil,
        notification: Notification.Name,
        object: String? = nil
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.shortcut = shortcut
        self.notification = notification.rawValue
        self.object = object
    }

    /// Text the fuzzy matcher searches: the title plus its group, so typing
    /// "export" finds "PDF" and typing "format" finds "Bold".
    var searchableText: String { "\(group) \(title)" }

    public func post() {
        NotificationCenter.default.post(
            name: Notification.Name(notification), object: object
        )
    }
}

/// The palette's command registry and its fuzzy filter.
public enum CommandPalette {

    /// Every command the palette offers, in display order.
    public static var commands: [PaletteCommand] {
        viewCommands + formatCommands + exportCommands
    }

    private static var viewCommands: [PaletteCommand] {
        [
            PaletteCommand(
                id: "view.editor", title: "Editor Only", group: "View",
                shortcut: "⌘1", notification: .setViewMode, object: ViewMode.editorOnly.rawValue
            ),
            PaletteCommand(
                id: "view.split", title: "Split", group: "View",
                shortcut: "⌘2", notification: .setViewMode, object: ViewMode.split.rawValue
            ),
            PaletteCommand(
                id: "view.preview", title: "Preview Only", group: "View",
                shortcut: "⌘3", notification: .setViewMode, object: ViewMode.previewOnly.rawValue
            ),
            PaletteCommand(
                id: "view.sidebar", title: "Show or Hide Sidebar", group: "View",
                shortcut: "⌥⌘S", notification: .toggleSidebar
            ),
            PaletteCommand(
                id: "view.focus", title: "Focus Mode", group: "View",
                shortcut: "⌃⌘F", notification: .toggleFocusMode
            ),
            PaletteCommand(
                id: "view.typewriter", title: "Typewriter Mode", group: "View",
                shortcut: "⌥⇧⌘T", notification: .toggleTypewriterMode
            ),
        ]
    }

    private static var formatCommands: [PaletteCommand] {
        MarkdownAction.allCases.map { action in
            PaletteCommand(
                id: "format.\(action.rawValue)",
                title: action.menuTitle,
                group: "Format",
                notification: .insertMarkdownFormatting,
                object: action.rawValue
            )
        }
    }

    private static var exportCommands: [PaletteCommand] {
        ExportCommand.allCases.map { command in
            PaletteCommand(
                id: "export.\(command.rawValue)",
                // The menu titles end in an ellipsis, which reads oddly in a list.
                title: command.menuTitle.replacingOccurrences(of: "…", with: ""),
                group: "Export",
                notification: .exportDocument,
                object: command.rawValue
            )
        }
    }

    // MARK: - Filtering

    /// Commands matching `query`, best match first.
    ///
    /// An empty query returns everything, so opening the palette shows what's
    /// available rather than a blank list.
    public static func filter(
        _ query: String,
        in commands: [PaletteCommand] = CommandPalette.commands
    ) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commands }

        return commands
            .compactMap { command -> (command: PaletteCommand, score: Int)? in
                guard let score = fuzzyScore(query: trimmed, in: command.searchableText)
                else { return nil }
                return (command, score)
            }
            // Stable within equal scores: `sorted` isn't guaranteed stable, so
            // fall back to the registry's own order for a predictable list.
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score {
                    return lhs.element.score > rhs.element.score
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element.command)
    }

    /// Score `query` as a subsequence of `text`, or `nil` if it doesn't match.
    ///
    /// Rewards matches that are consecutive or land at the start of a word, so
    /// "eh" ranks "Export HTML" above a scattered coincidental match.
    static func fuzzyScore(query: String, in text: String) -> Int? {
        let haystack = Array(text.lowercased())
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var haystackIndex = 0
        var previousMatchIndex: Int?

        for character in needle {
            // Spaces in the query shouldn't have to match literally.
            if character == " " { continue }

            var found = false
            while haystackIndex < haystack.count {
                defer { haystackIndex += 1 }
                guard haystack[haystackIndex] == character else { continue }

                score += 1
                if let previous = previousMatchIndex, haystackIndex == previous + 1 {
                    score += 4  // consecutive
                }
                let isWordStart = haystackIndex == 0
                    || haystack[haystackIndex - 1] == " "
                    || haystack[haystackIndex - 1] == "-"
                if isWordStart { score += 3 }

                previousMatchIndex = haystackIndex
                found = true
                break
            }
            guard found else { return nil }
        }
        return score
    }
}
