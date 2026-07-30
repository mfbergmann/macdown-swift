#if os(macOS)
import AppKit

/// The welcome document shown the first time MacDown runs.
///
/// Written to Application Support and opened as a normal file rather than
/// synthesised in memory, so it doubles as a demonstration of the reading-first
/// behaviour: because it already exists on disk, it opens in preview.
@MainActor
public enum FirstRun {
    private static let hasRunKey = "hasCompletedFirstRun"

    public static func presentWelcomeIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: hasRunKey) else { return }
        defaults.set(true, forKey: hasRunKey)

        guard let url = writeWelcomeDocument() else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// Write the welcome file, returning where it landed.
    static func writeWelcomeDocument() -> URL? {
        guard let directory = UserResources.supportDirectory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("Welcome to MacDown.md")
        // Don't clobber it if the user kept and edited their copy.
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }

        try? Data(welcomeMarkdown.utf8).write(to: url, options: .atomic)
        return url
    }

    static let welcomeMarkdown = """
    # Welcome to MacDown

    A fast, native Markdown editor for macOS — a Swift rewrite of the original
    [MacDown](https://github.com/MacDownApp/macdown) by Tzu-ping Chung.

    You're reading this in **preview mode**, because MacDown opens files you
    already have so you can read them. Press <kbd>⌘1</kbd> to switch to the
    editor, or <kbd>⌘2</kbd> for both side by side. Whichever you choose,
    MacDown remembers it for this file next time.

    ## Getting around

    | Shortcut | Does |
    | --- | --- |
    | <kbd>⌘K</kbd> | Command palette — search every command |
    | <kbd>⌥⌘S</kbd> | Sidebar with the document outline and nearby files |
    | <kbd>⌘1</kbd> / <kbd>⌘2</kbd> / <kbd>⌘3</kbd> | Editor, split, preview |
    | <kbd>⌘F</kbd> | Find, with replace on <kbd>⌥⌘F</kbd> |

    ## Writing

    Lists continue themselves — press Return at the end of this line:

    - a bullet that will keep going
    - press Return twice to stop

    Numbered lists renumber as you go, and task items carry on unchecked:

    - [x] something finished
    - [ ] something still to do

    Brackets and quotes close themselves, and selecting text before typing one
    wraps the selection instead.

    ### Focus and typewriter modes

    <kbd>⌃⌘F</kbd> dims everything except the paragraph you're in.
    <kbd>⌥⇧⌘T</kbd> keeps the cursor centred as you type.

    ## Sharing

    Export to PDF, HTML, or Word from the File menu, or copy the document as
    rich text straight into Mail or Pages.

    ```swift
    // Code blocks are highlighted, in the editor and the preview.
    func greet(_ name: String) -> String {
        "Hello, \\(name)"
    }
    ```

    Math and diagrams work too, once you switch them on in Settings → Rendering.

    ---

    This file lives in your Application Support folder. Edit it, move it, or
    throw it away — MacDown won't recreate it.
    """
}
#endif
