import Foundation

/// Which panes a document window is showing.
///
/// Cases are ordered the way they appear in the toolbar picker and the
/// View menu, so `allCases` doubles as the ⌘1 / ⌘2 / ⌘3 ordering.
public enum ViewMode: String, CaseIterable, Codable, Sendable {
    case editorOnly
    case split
    case previewOnly

    public var displayName: String {
        switch self {
        case .editorOnly: "Editor"
        case .split: "Split"
        case .previewOnly: "Preview"
        }
    }

    public var showsEditor: Bool { self != .previewOnly }
    public var showsPreview: Bool { self != .editorOnly }

    /// Show the preview if it's hidden, hide it if it's showing.
    public func togglingPreview() -> ViewMode {
        showsPreview ? .editorOnly : .split
    }

    /// Show the editor if it's hidden, hide it if it's showing.
    public func togglingEditor() -> ViewMode {
        showsEditor ? .previewOnly : .split
    }
}

// MARK: - Opening a document

public extension ViewMode {
    /// The mode a freshly-opened document should start in.
    ///
    /// Reading comes first. A file that already exists on disk opens in the mode
    /// you last read *that file* in, falling back to the preferred mode for opened
    /// files. A brand-new, unsaved document has nothing to read yet, so it opens
    /// in the editor.
    static func resolvedForOpening(
        fileURL: URL?,
        preferences: Preferences,
        store: ViewModeStore
    ) -> ViewMode {
        guard let fileURL else {
            return preferences.newDocumentViewMode
        }
        if preferences.remembersViewModePerFile, let remembered = store.mode(for: fileURL) {
            return remembered
        }
        return preferences.openedFileViewMode
    }
}

// MARK: - Per-file memory

/// Remembers the view mode each file was last read in, so reopening a file
/// restores how you were using it.
///
/// Bounded to the `maxEntries` most recently used files, most-recent first, so
/// the defaults database can't grow without limit on a machine that opens a lot
/// of Markdown.
public final class ViewModeStore {
    nonisolated(unsafe) public static let shared = ViewModeStore()

    private struct Entry: Codable {
        var path: String
        var mode: ViewMode
    }

    private let key: String
    private let maxEntries: Int
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard,
        key: String = "perFileViewModes",
        maxEntries: Int = 200
    ) {
        self.defaults = defaults
        self.key = key
        self.maxEntries = maxEntries
    }

    /// The remembered mode for `url`, or `nil` if this file hasn't been seen.
    public func mode(for url: URL) -> ViewMode? {
        let path = Self.identity(for: url)
        return entries().first { $0.path == path }?.mode
    }

    /// Record `mode` for `url`, promoting it to most-recently-used.
    public func setMode(_ mode: ViewMode, for url: URL) {
        let path = Self.identity(for: url)
        var list = entries().filter { $0.path != path }
        list.insert(Entry(path: path, mode: mode), at: 0)
        write(Array(list.prefix(maxEntries)))
    }

    public func forget(_ url: URL) {
        let path = Self.identity(for: url)
        write(entries().filter { $0.path != path })
    }

    public func removeAll() {
        defaults.removeObject(forKey: key)
    }

    /// Number of remembered files. Exposed for Settings ("Forget… (N files)").
    public var count: Int { entries().count }

    private static func identity(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func entries() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }

    private func write(_ list: [Entry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}
