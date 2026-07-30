import SwiftUI
import MacDownCore

@main
struct MacDownApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            SplitEditorView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            macOSCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }

    @CommandsBuilder
    func macOSCommands() -> some Commands {
        CommandGroup(after: .saveItem) {
            Section {
                Button(ExportCommand.html.menuTitle) { post(.html) }
                Button(ExportCommand.pdf.menuTitle) { post(.pdf) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(ExportCommand.docx.menuTitle) { post(.docx) }
            }

            Section {
                Button(ExportCommand.print.menuTitle) { post(.print) }
                    .keyboardShortcut("p", modifiers: .command)
            }
        }

        CommandGroup(after: .pasteboard) {
            Section {
                Button(ExportCommand.copyHTML.menuTitle) { post(.copyHTML) }
                Button(ExportCommand.copyRichText.menuTitle) { post(.copyRichText) }
            }
        }

        // The editor's NSTextView already has a find bar (`usesFindBar`); these
        // items are what actually reach it, since SwiftUI's stock Edit menu has
        // no Find entries.
        CommandGroup(after: .textEditing) {
            Section {
                Button("Find…") { textFinder(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find and Replace…") { textFinder(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { textFinder(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { textFinder(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { textFinder(.setSearchString) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }

        CommandGroup(after: .textFormatting) {
            Section {
                formatButton(.bold, "b", .command)
                formatButton(.italic, "i", .command)
                formatButton(.strikethrough, "u", [.command, .shift])
                formatButton(.inlineCode, "k", [.command, .shift])
            }

            Section {
                // ⌘1–3 belong to the view modes in a reading-first app, so
                // headings take the control-modified variants.
                formatButton(.heading1, "1", [.control, .command])
                formatButton(.heading2, "2", [.control, .command])
                formatButton(.heading3, "3", [.control, .command])
            }

            Section {
                formatButton(.bulletList, "l", [.command, .shift])
                formatButton(.numberedList, "o", [.command, .shift])
                formatButton(.taskItem, "t", [.command, .shift])
                formatButton(.blockquote, "'", [.command, .shift])
            }

            Section {
                formatButton(.link, "l", .command)
                formatButton(.image, "i", [.command, .shift])
                formatButton(.codeBlock, "c", [.control, .command])
                formatButton(.table, "t", [.control, .command])
                formatButton(.horizontalRule, "-", [.command, .shift])
            }
        }

        CommandGroup(after: .sidebar) {
            Section {
                Button("Editor Only") {
                    NotificationCenter.default.post(
                        name: .setViewMode, object: ViewMode.editorOnly.rawValue
                    )
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Split") {
                    NotificationCenter.default.post(
                        name: .setViewMode, object: ViewMode.split.rawValue
                    )
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Preview Only") {
                    NotificationCenter.default.post(
                        name: .setViewMode, object: ViewMode.previewOnly.rawValue
                    )
                }
                .keyboardShortcut("3", modifiers: .command)
            }

            Section {
                Button("Toggle Preview") {
                    NotificationCenter.default.post(name: .togglePreview, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Toggle Editor") {
                    NotificationCenter.default.post(name: .toggleEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    /// Menu commands are broadcast; the frontmost document window acts on them.
    private func post(_ command: ExportCommand) {
        NotificationCenter.default.post(name: .exportDocument, object: command.rawValue)
    }

    /// Send a find-bar action to whichever text view is first responder.
    ///
    /// `performTextFinderAction:` reads the action out of the sender's tag, so
    /// we hand it a throwaway menu item carrying the one we want.
    private func textFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(
            #selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item
        )
    }

    private func formatButton(
        _ action: MarkdownAction,
        _ key: KeyEquivalent,
        _ modifiers: EventModifiers
    ) -> some View {
        Button(action.menuTitle) {
            NotificationCenter.default.post(
                name: .insertMarkdownFormatting, object: action.rawValue
            )
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}
