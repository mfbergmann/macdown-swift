import Foundation
import Testing
@testable import MacDownCore

private func makePreferences() -> Preferences {
    Preferences(defaults: UserDefaults(suiteName: "MacDownTests.\(UUID().uuidString)")!)
}

@Suite("HTMLComposer purposes")
struct HTMLComposerPurposeTests {

    let composer = HTMLComposer()

    @Test("Print output carries a page rule and print stylesheet")
    func printAddsPrintCSS() {
        let html = composer.compose(
            title: "Doc", body: "<p>hi</p>",
            preferences: makePreferences(),
            purpose: .print,
            pageSetup: HTMLComposer.PageSetup(size: "A4", margin: "1in")
        )
        #expect(html.contains("@page"))
        #expect(html.contains("size: A4"))
        #expect(html.contains("margin: 1in"))
        #expect(html.contains("@media print"))
    }

    @Test("Preview and export output carry no page rule")
    func nonPrintOmitsPageRule() {
        // Several bundled themes ship their own `@media print` block, so the
        // `@page` rule — which only our print stylesheet emits — is what
        // actually distinguishes print output.
        for purpose in [HTMLComposer.Purpose.preview, .export] {
            let html = composer.compose(
                title: nil, body: "<p>hi</p>",
                preferences: makePreferences(),
                purpose: purpose
            )
            #expect(!html.contains("@page"), "purpose \(purpose) should not add page geometry")
        }
    }

    @Test("Task list interactivity is preview-only")
    func taskListScriptIsPreviewOnly() {
        let prefs = makePreferences()
        prefs.htmlTaskList = true

        let preview = composer.compose(title: nil, body: "", preferences: prefs, purpose: .preview)
        let exported = composer.compose(title: nil, body: "", preferences: prefs, purpose: .export)

        // The bundled tasklist script writes checkbox state back to the editor,
        // which is meaningless in a file someone else opens.
        #expect(preview.count > exported.count)
    }

    @Test("Plain export options drop styling")
    func plainOptionsDropStyling() {
        let prefs = makePreferences()
        let styled = composer.compose(
            title: nil, body: "<p>hi</p>", preferences: prefs,
            purpose: .export, options: HTMLComposer.ExportOptions()
        )
        let plain = composer.compose(
            title: nil, body: "<p>hi</p>", preferences: prefs,
            purpose: .export, options: .plain
        )
        #expect(!plain.contains("<style>"))
        #expect(styled.contains("<style>"))
        #expect(plain.contains("<p>hi</p>"))
    }

    @Test("Titles are HTML-escaped")
    func titleIsEscaped() {
        let html = composer.compose(
            title: "a < b & c", body: "", preferences: makePreferences(), purpose: .export
        )
        #expect(html.contains("<title>a &lt; b &amp; c</title>"))
    }

    @Test("Composed output is a complete document")
    func wellFormed() {
        let html = composer.compose(
            title: "T", body: "<p>body</p>", preferences: makePreferences(), purpose: .export
        )
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(html.hasSuffix("</html>"))
    }
}

#if os(macOS)

@MainActor
@Suite("DocumentExporter")
struct DocumentExporterTests {

    private func content(markdown: String = "# Title\n\nSome **bold** text.\n") -> ExportContent {
        let prefs = makePreferences()
        let renderer = MarkdownRenderer()
        let result = renderer.render(markdown, options: .from(preferences: prefs))
        return ExportContent(
            title: result.title,
            body: result.html,
            baseURL: nil,
            suggestedFilename: "Test",
            preferences: prefs
        )
    }

    @Test("Exports a self-contained HTML document")
    func htmlExport() {
        let html = DocumentExporter().html(for: content())
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(!html.contains("<link rel=\"stylesheet\""), "assets must be inlined, not linked")
    }

    @Test("Produces a valid PDF")
    func pdfExport() async throws {
        let data = try await DocumentExporter().pdfData(for: content())
        #expect(data.count > 0)
        // Every PDF starts with the %PDF- magic number.
        #expect(data.prefix(5) == Data("%PDF-".utf8))
    }

    @Test("Produces a valid DOCX")
    func docxExport() throws {
        let data = try DocumentExporter().docxData(for: content())
        #expect(data.count > 0)
        // .docx is a zip archive; zips start with "PK\u{03}\u{04}".
        #expect(data.prefix(2) == Data("PK".utf8))
    }

    @Test("Produces valid RTF")
    func rtfExport() throws {
        let data = try DocumentExporter().rtfData(for: content())
        #expect(data.prefix(5) == Data("{\\rtf".utf8))
    }

    @Test("DOCX round-trips the document's text")
    func docxKeepsText() throws {
        let data = try DocumentExporter().docxData(
            for: content(markdown: "# Heading\n\nA distinctive sentence.\n")
        )
        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        )
        #expect(restored.string.contains("A distinctive sentence."))
        #expect(restored.string.contains("Heading"))
    }
}

#endif
