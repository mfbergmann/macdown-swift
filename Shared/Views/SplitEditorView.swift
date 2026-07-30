import Combine
import SwiftUI

/// The main document view: a markdown editor and an HTML preview, shown
/// side by side or one at a time depending on the current `ViewMode`.
public struct SplitEditorView: View {
    @Bindable var document: MarkdownDocument

    /// Where this document lives on disk, or `nil` for a new unsaved document.
    /// Supplied by the `DocumentGroup`; the source of truth for per-file state.
    private let fileURL: URL?

    @State private var renderer = MarkdownRenderer()
    @State private var composer = HTMLComposer()
    @State private var scrollSync = ScrollSync()
    @State private var renderedHTML: String = ""
    @State private var renderTask: Task<Void, Never>?
    @State private var viewMode: ViewMode
    @State private var editorOnRight = false
    @State private var showsSidebar = Preferences.shared.showsSidebar
    @State private var outline = DocumentOutline()
    @State private var listing = FolderListing()
    @State private var jump: HeadingJump?
    @State private var jumpToken = 0
    @State private var writingModes = WritingModes(preferences: .shared)
    #if os(macOS)
    @State private var exportCoordinator = ExportCoordinator()
    #endif

    let preferences = Preferences.shared

    public init(document: MarkdownDocument, fileURL: URL? = nil) {
        self.document = document
        self.fileURL = fileURL
        _viewMode = State(
            initialValue: ViewMode.resolvedForOpening(
                fileURL: fileURL,
                preferences: .shared,
                store: .shared
            )
        )
    }

    /// The system's current light/dark setting for this window.
    @Environment(\.colorScheme) private var colorScheme

    /// Whether the preview and editor should use their dark themes.
    private var isDark: Bool {
        preferences.previewAppearance.isDark(systemIsDark: colorScheme == .dark)
    }

    // Menu commands are broadcast to every open window, so each window only
    // acts on them while it's the key window.
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    private var isKeyWindow: Bool { controlActiveState == .key }
    #else
    private var isKeyWindow: Bool { true }
    #endif

    public var body: some View {
        sidebarSplit
            .toolbar { toolbarContent }
            .modifier(DocumentLifecycle(view: self))
            .modifier(MenuCommands(view: self))
    }

    @ViewBuilder
    private var sidebarSplit: some View {
        #if os(macOS)
        HSplitView {
            if showsSidebar {
                SidebarView(
                    outline: outline,
                    listing: listing,
                    currentFile: fileURL,
                    activeHeading: nil,
                    onSelectHeading: jump(to:),
                    onSelectFile: open(_:)
                )
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 400)
            }
            content
                .frame(minWidth: 320)
        }
        #else
        content
        #endif
    }

    // MARK: - Navigation

    /// Scroll both panes to `heading`.
    private func jump(to heading: Heading) {
        jumpToken += 1
        jump = HeadingJump(
            token: jumpToken, headingIndex: heading.index, range: heading.range
        )
    }

    /// Open another markdown file from the folder listing in its own window.
    private func open(_ url: URL) {
        #if os(macOS)
        NSDocumentController.shared.openDocument(
            withContentsOf: url, display: true
        ) { _, _, _ in }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .split:
            splitView
        case .editorOnly:
            editorView
        case .previewOnly:
            previewView
        }
    }

    // MARK: - Lifecycle

    /// Setup, re-rendering, and remembering how this file was viewed.
    ///
    /// Kept in a `ViewModifier` rather than chained onto `body` so the type
    /// checker has a much smaller expression to solve.
    private struct DocumentLifecycle: ViewModifier {
        let view: SplitEditorView

        func body(content: Content) -> some View {
            content
                .onAppear {
                    view.editorOnRight = view.preferences.editorOnRight
                    view.document.fileURL = view.fileURL
                    view.listing = FolderListing.forDocument(at: view.fileURL)
                    view.renderMarkdown()
                }
                .onChange(of: view.document.text) { _, _ in
                    view.scheduleRender()
                }
                .onChange(of: view.isDark) { _, _ in
                    // Appearance flipped: re-render so the preview swaps stylesheets.
                    view.renderMarkdown()
                }
                .onChange(of: view.viewMode) { _, newMode in
                    view.rememberViewMode(newMode)
                }
                .onChange(of: view.fileURL) { _, newURL in
                    // A new document just got saved for the first time — start
                    // remembering it under its new home.
                    view.document.fileURL = newURL
                    view.listing = FolderListing.forDocument(at: newURL)
                    view.rememberViewMode(view.viewMode)
                }
        }
    }

    // MARK: - Menu Commands

    /// Menu and keyboard commands arrive as broadcast notifications; each
    /// window ignores them unless it's the key window.
    private struct MenuCommands: ViewModifier {
        let view: SplitEditorView

        func body(content: Content) -> some View {
            content
                .onReceive(NotificationCenter.default.publisher(for: .setViewMode)) { note in
                    guard view.isKeyWindow,
                          let raw = note.object as? String,
                          let mode = ViewMode(rawValue: raw) else { return }
                    view.viewMode = mode
                }
                .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
                    guard view.isKeyWindow else { return }
                    view.viewMode = view.viewMode.togglingPreview()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleEditor)) { _ in
                    guard view.isKeyWindow else { return }
                    view.viewMode = view.viewMode.togglingEditor()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                    guard view.isKeyWindow else { return }
                    view.showsSidebar.toggle()
                    view.preferences.showsSidebar = view.showsSidebar
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleFocusMode)) { _ in
                    guard view.isKeyWindow else { return }
                    view.writingModes.focus.toggle()
                    view.preferences.focusMode = view.writingModes.focus
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleTypewriterMode)) { _ in
                    guard view.isKeyWindow else { return }
                    view.writingModes.typewriter.toggle()
                    view.preferences.typewriterMode = view.writingModes.typewriter
                }
                .modifier(PlatformMenuCommands(view: view))
        }
    }

    #if os(macOS)
    private struct PlatformMenuCommands: ViewModifier {
        let view: SplitEditorView

        func body(content: Content) -> some View {
            content
                .onReceive(NotificationCenter.default.publisher(for: .exportDocument)) { note in
                    guard view.isKeyWindow,
                          let raw = note.object as? String,
                          let command = ExportCommand(rawValue: raw) else { return }
                    Task { await view.exportCoordinator.run(command, content: view.exportContent()) }
                }
        }
    }
    #else
    private struct PlatformMenuCommands: ViewModifier {
        let view: SplitEditorView
        func body(content: Content) -> some View { content }
    }
    #endif

    // MARK: - Export

    #if os(macOS)
    /// Re-render the document for export rather than reusing `renderedHTML`,
    /// which carries preview-only scripts and reflects the on-screen theme.
    private func exportContent() -> ExportContent {
        let options = MarkdownRenderer.Options.from(preferences: preferences)
        let result = renderer.render(document.text, options: options)
        return ExportContent(
            title: result.title ?? document.title,
            body: result.html,
            baseURL: fileURL,
            suggestedFilename: fileURL?.deletingPathExtension().lastPathComponent
                ?? result.title
                ?? document.title,
            preferences: preferences,
            composer: composer
        )
    }
    #endif

    // MARK: - Split View

    @ViewBuilder
    private var splitView: some View {
        #if os(macOS)
        HSplitView {
            if editorOnRight {
                previewView
                editorView
            } else {
                editorView
                previewView
            }
        }
        #else
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if editorOnRight {
                    previewView
                        .frame(width: geometry.size.width / 2)
                    Divider()
                    editorView
                        .frame(width: geometry.size.width / 2)
                } else {
                    editorView
                        .frame(width: geometry.size.width / 2)
                    Divider()
                    previewView
                        .frame(width: geometry.size.width / 2)
                }
            }
        }
        #endif
    }

    // MARK: - Editor

    private var editorView: some View {
        MarkdownTextView(
            text: $document.text,
            font: editorFont,
            highlightThemeName: preferences.editorStyleName(dark: isDark),
            lineSpacing: preferences.editorLineSpacing,
            horizontalInset: preferences.editorHorizontalInset,
            verticalInset: preferences.editorVerticalInset,
            isEditable: true,
            scrollsPastEnd: preferences.editorScrollsPastEnd,
            behaviorOptions: EditorBehavior.Options(preferences: preferences),
            writingModes: writingModes,
            jump: jump,
            onScroll: { fraction in
                if preferences.editorSyncScrolling {
                    scrollSync.editorDidScroll(to: fraction)
                }
            },
            onTextChange: {
                scheduleRender()
            }
        )
        #if os(macOS)
        .frame(minWidth: 200)
        #endif
    }

    // MARK: - Preview

    private var previewView: some View {
        PreviewWebView(
            html: renderedHTML,
            baseURL: fileURL,
            scrollFraction: scrollSync.previewScrollFraction,
            jump: jump,
            onScrollChange: { fraction in
                if preferences.editorSyncScrolling {
                    scrollSync.previewDidScroll(to: fraction)
                }
            }
        )
        #if os(macOS)
        .frame(minWidth: 200)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            Button {
                showsSidebar.toggle()
                preferences.showsSidebar = showsSidebar
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help("Show or hide the sidebar")
        }
        #endif

        if viewMode.showsEditor {
            ToolbarItemGroup {
                ForEach(Self.quickFormatActions, id: \.self) { action in
                    Button {
                        post(action)
                    } label: {
                        Label(action.menuTitle, systemImage: action.systemImage)
                    }
                    .help(action.menuTitle)
                }

                Menu {
                    formatMenuSections
                } label: {
                    Label("Format", systemImage: "textformat")
                }
                .help("Insert markdown formatting")
            }
        }

        ToolbarItemGroup {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button {
                editorOnRight.toggle()
                preferences.editorOnRight = editorOnRight
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap editor and preview positions")
            .disabled(viewMode != .split)

            if preferences.editorShowWordCount {
                Text(wordCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The handful of actions worth a permanent toolbar button; everything
    /// else lives one click deeper in the Format menu.
    private static let quickFormatActions: [MarkdownAction] = [
        .bold, .italic, .inlineCode, .link,
    ]

    @ViewBuilder
    private var formatMenuSections: some View {
        Section {
            menuButton(.bold)
            menuButton(.italic)
            menuButton(.strikethrough)
            menuButton(.inlineCode)
        }
        Section {
            menuButton(.heading1)
            menuButton(.heading2)
            menuButton(.heading3)
        }
        Section {
            menuButton(.bulletList)
            menuButton(.numberedList)
            menuButton(.taskItem)
            menuButton(.blockquote)
        }
        Section {
            menuButton(.link)
            menuButton(.image)
            menuButton(.codeBlock)
            menuButton(.table)
            menuButton(.horizontalRule)
        }
    }

    private func menuButton(_ action: MarkdownAction) -> some View {
        Button {
            post(action)
        } label: {
            Label(action.menuTitle, systemImage: action.systemImage)
        }
    }

    private func post(_ action: MarkdownAction) {
        NotificationCenter.default.post(
            name: .insertMarkdownFormatting, object: action.rawValue
        )
    }

    // MARK: - View Mode Memory

    private func rememberViewMode(_ mode: ViewMode) {
        guard preferences.remembersViewModePerFile, let fileURL else { return }
        ViewModeStore.shared.setMode(mode, for: fileURL)
    }

    // MARK: - Rendering

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            if !preferences.markdownManualRender {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            renderMarkdown()
        }
    }

    private func renderMarkdown() {
        let options = MarkdownRenderer.Options.from(preferences: preferences)
        let result = renderer.render(document.text, options: options)
        outline = DocumentOutline.parse(document.text)
        renderedHTML = composer.compose(
            title: result.title,
            body: result.html,
            preferences: preferences,
            isDark: isDark
        )
    }

    // MARK: - Computed Properties

    private var wordCountText: String {
        let words = document.text.split { $0.isWhitespace || $0.isNewline }.count
        return "\(words) words"
    }

    private var editorFont: PlatformFont {
        PlatformFont(name: preferences.editorFontName, size: preferences.editorFontSize)
            ?? PlatformFont.monospacedSystemFont(ofSize: preferences.editorFontSize, weight: .regular)
    }
}
