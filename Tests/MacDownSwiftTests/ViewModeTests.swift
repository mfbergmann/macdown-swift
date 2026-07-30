import Foundation
import Testing
@testable import MacDownCore

/// A throwaway defaults suite, so tests never touch the real preferences database.
private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "MacDownTests.\(UUID().uuidString)")!
}

private func makeStore(maxEntries: Int = 200) -> ViewModeStore {
    ViewModeStore(defaults: makeDefaults(), key: "perFileViewModes", maxEntries: maxEntries)
}

private func url(_ path: String) -> URL {
    URL(fileURLWithPath: path)
}

@Suite("ViewMode")
struct ViewModeTests {

    @Test("Pane visibility matches the mode")
    func paneVisibility() {
        #expect(ViewMode.editorOnly.showsEditor)
        #expect(!ViewMode.editorOnly.showsPreview)

        #expect(ViewMode.split.showsEditor)
        #expect(ViewMode.split.showsPreview)

        #expect(!ViewMode.previewOnly.showsEditor)
        #expect(ViewMode.previewOnly.showsPreview)
    }

    @Test("Toggling the preview shows it when hidden and hides it when shown")
    func togglePreview() {
        #expect(ViewMode.editorOnly.togglingPreview() == .split)
        #expect(ViewMode.split.togglingPreview() == .editorOnly)
        #expect(ViewMode.previewOnly.togglingPreview() == .editorOnly)
    }

    @Test("Toggling the editor shows it when hidden and hides it when shown")
    func toggleEditor() {
        #expect(ViewMode.previewOnly.togglingEditor() == .split)
        #expect(ViewMode.split.togglingEditor() == .previewOnly)
        #expect(ViewMode.editorOnly.togglingEditor() == .previewOnly)
    }

    @Test("Toggling a pane twice returns to a mode showing the same panes")
    func toggleIsStable() {
        for mode in ViewMode.allCases {
            let round = mode.togglingPreview().togglingPreview()
            #expect(round.showsPreview == mode.showsPreview)
        }
    }
}

@Suite("ViewModeStore")
struct ViewModeStoreTests {

    @Test("Returns nil for a file it has never seen")
    func unknownFile() {
        let store = makeStore()
        #expect(store.mode(for: url("/tmp/never-seen.md")) == nil)
    }

    @Test("Round-trips a remembered mode")
    func roundTrip() {
        let store = makeStore()
        let file = url("/tmp/notes.md")
        store.setMode(.previewOnly, for: file)
        #expect(store.mode(for: file) == .previewOnly)
    }

    @Test("Recording the same file again replaces rather than duplicates")
    func overwrite() {
        let store = makeStore()
        let file = url("/tmp/notes.md")
        store.setMode(.previewOnly, for: file)
        store.setMode(.split, for: file)
        #expect(store.mode(for: file) == .split)
        #expect(store.count == 1)
    }

    @Test("Distinct files are remembered independently")
    func independentFiles() {
        let store = makeStore()
        store.setMode(.editorOnly, for: url("/tmp/a.md"))
        store.setMode(.previewOnly, for: url("/tmp/b.md"))
        #expect(store.mode(for: url("/tmp/a.md")) == .editorOnly)
        #expect(store.mode(for: url("/tmp/b.md")) == .previewOnly)
    }

    @Test("Paths are normalized, so equivalent URLs hit the same entry")
    func pathNormalization() {
        let store = makeStore()
        store.setMode(.split, for: url("/tmp/dir/../notes.md"))
        #expect(store.mode(for: url("/tmp/notes.md")) == .split)
    }

    @Test("Evicts least-recently-used entries past the cap")
    func lruEviction() {
        let store = makeStore(maxEntries: 3)
        store.setMode(.split, for: url("/tmp/1.md"))
        store.setMode(.split, for: url("/tmp/2.md"))
        store.setMode(.split, for: url("/tmp/3.md"))
        store.setMode(.split, for: url("/tmp/4.md"))

        #expect(store.count == 3)
        #expect(store.mode(for: url("/tmp/1.md")) == nil, "oldest entry should be evicted")
        #expect(store.mode(for: url("/tmp/4.md")) == .split)
    }

    @Test("Re-recording a file promotes it and saves it from eviction")
    func recordingPromotes() {
        let store = makeStore(maxEntries: 3)
        store.setMode(.split, for: url("/tmp/1.md"))
        store.setMode(.split, for: url("/tmp/2.md"))
        store.setMode(.split, for: url("/tmp/3.md"))
        store.setMode(.previewOnly, for: url("/tmp/1.md"))  // promote the oldest
        store.setMode(.split, for: url("/tmp/4.md"))

        #expect(store.mode(for: url("/tmp/1.md")) == .previewOnly, "promoted entry survives")
        #expect(store.mode(for: url("/tmp/2.md")) == nil, "new oldest is evicted instead")
    }

    @Test("Forgetting a file drops just that entry")
    func forget() {
        let store = makeStore()
        store.setMode(.split, for: url("/tmp/a.md"))
        store.setMode(.split, for: url("/tmp/b.md"))
        store.forget(url("/tmp/a.md"))
        #expect(store.mode(for: url("/tmp/a.md")) == nil)
        #expect(store.mode(for: url("/tmp/b.md")) == .split)
    }
}

@Suite("Opening a document")
struct ViewModeOpeningTests {

    /// Preferences at their shipped defaults, on a throwaway suite.
    private func defaultPreferences() -> Preferences {
        Preferences(defaults: makeDefaults())
    }

    @Test("A new unsaved document opens in the editor")
    func newDocumentOpensInEditor() {
        let resolved = ViewMode.resolvedForOpening(
            fileURL: nil,
            preferences: defaultPreferences(),
            store: makeStore()
        )
        #expect(resolved == .editorOnly, "there is nothing to read yet — start writing")
    }

    @Test("An existing file with no history opens in preview")
    func existingFileOpensInPreview() {
        let resolved = ViewMode.resolvedForOpening(
            fileURL: url("/tmp/readme.md"),
            preferences: defaultPreferences(),
            store: makeStore()
        )
        #expect(resolved == .previewOnly, "reading comes first")
    }

    @Test("An existing file reopens in the mode it was last read in")
    func existingFileRestoresRememberedMode() {
        let store = makeStore()
        let file = url("/tmp/readme.md")
        store.setMode(.split, for: file)

        let resolved = ViewMode.resolvedForOpening(
            fileURL: file,
            preferences: defaultPreferences(),
            store: store
        )
        #expect(resolved == .split)
    }

    @Test("Per-file memory is skipped when the preference is off")
    func rememberingCanBeDisabled() {
        let preferences = defaultPreferences()
        let store = makeStore()
        let file = url("/tmp/readme.md")
        store.setMode(.editorOnly, for: file)

        preferences.remembersViewModePerFile = false

        let resolved = ViewMode.resolvedForOpening(
            fileURL: file,
            preferences: preferences,
            store: store
        )
        #expect(resolved == .previewOnly, "falls back to the opened-file default")
    }
}
