import Foundation

/// Names for the app-wide notifications that carry menu and toolbar commands
/// down to whichever document window is frontmost.
///
/// These live in the shared core so the app targets that *post* them and the
/// views that *observe* them agree on one spelling. Every observer is expected
/// to ignore commands unless its window is key — notifications are broadcast,
/// so an unguarded observer would act in every open window at once.
public extension Notification.Name {
    /// Object: a `MarkdownAction` raw value. Applies formatting in the editor.
    static let insertMarkdownFormatting = Notification.Name("insertMarkdownFormatting")

    /// Object: a `ViewMode` raw value. Switches the window's view mode.
    static let setViewMode = Notification.Name("setViewMode")

    /// Object: `nil`. Shows the preview pane if hidden, hides it if shown.
    static let togglePreview = Notification.Name("togglePreview")

    /// Object: `nil`. Shows the editor pane if hidden, hides it if shown.
    static let toggleEditor = Notification.Name("toggleEditor")

    /// Object: `nil`. Shows or hides the outline/folder sidebar.
    static let toggleSidebar = Notification.Name("toggleSidebar")

    /// Object: an `ExportCommand` raw value. Runs an export/print/copy action.
    static let exportDocument = Notification.Name("exportDocument")
}
