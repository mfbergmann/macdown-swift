import SwiftUI
import MacDownCore

@main
struct MacDownApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            SplitEditorView(document: file.document, fileURL: file.fileURL)
                .toolbarRole(.editor)
        }
    }
}
