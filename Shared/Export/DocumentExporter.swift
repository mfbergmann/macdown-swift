#if os(macOS)
import AppKit
import WebKit

/// Turns a rendered document into PDF, HTML, Word, RTF, or a print job.
///
/// Rendering happens in an **offscreen** `WKWebView` rather than the visible
/// preview. That keeps export independent of what's on screen — you can export
/// from editor-only mode, where no preview exists — and lets PDF and print use
/// a page-width layout and a print stylesheet instead of inheriting whatever
/// width the window happens to be.
@MainActor
public final class DocumentExporter {

    /// How long to wait for the page to load before giving up.
    private let loadTimeout: Duration = .seconds(30)

    /// Grace period after `didFinish` for script-driven content — Mermaid
    /// diagrams and MathJax typesetting both run after the load completes and
    /// would otherwise be missing from the output.
    private let scriptSettleDelay: Duration = .milliseconds(700)

    public init() {}

    // MARK: - HTML

    /// A self-contained HTML document.
    public func html(
        for content: ExportContent,
        options: HTMLComposer.ExportOptions = HTMLComposer.ExportOptions()
    ) -> String {
        content.composer.compose(
            title: content.title,
            body: content.body,
            preferences: content.preferences,
            purpose: .export,
            options: options
        )
    }

    // MARK: - PDF

    /// Render to a paginated PDF using a print stylesheet.
    public func pdfData(
        for content: ExportContent,
        pageSetup: HTMLComposer.PageSetup = .default
    ) async throws -> Data {
        let html = content.composer.compose(
            title: content.title,
            body: content.body,
            preferences: content.preferences,
            purpose: .print,
            options: HTMLComposer.ExportOptions(),
            pageSetup: pageSetup
        )

        let webView = try await loadOffscreen(html: html, baseURL: content.baseURL)

        let config = WKPDFConfiguration()  // full page, no rect restriction
        return try await webView.pdf(configuration: config)
    }

    // MARK: - Print

    /// An `NSPrintOperation` for the document, ready to run.
    ///
    /// The returned operation holds a strong reference to the offscreen web
    /// view that backs it, so the caller only needs to keep the operation alive.
    public func printOperation(
        for content: ExportContent,
        printInfo: NSPrintInfo = .shared
    ) async throws -> NSPrintOperation {
        let html = content.composer.compose(
            title: content.title,
            body: content.body,
            preferences: content.preferences,
            purpose: .print,
            options: HTMLComposer.ExportOptions(),
            pageSetup: pageSetup(from: printInfo)
        )

        let webView = try await loadOffscreen(html: html, baseURL: content.baseURL)

        let info = printInfo.copy() as! NSPrintInfo
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let name = content.suggestedFilename {
            operation.jobTitle = name
        }
        return operation
    }

    /// Translate the user's page setup into the CSS `@page` rule so the web
    /// view lays out to the same paper the print job will use.
    private func pageSetup(from printInfo: NSPrintInfo) -> HTMLComposer.PageSetup {
        let size = printInfo.paperSize  // points
        let widthIn = size.width / 72.0
        let heightIn = size.height / 72.0
        let marginIn = printInfo.topMargin / 72.0
        return HTMLComposer.PageSetup(
            size: String(format: "%.2fin %.2fin", widthIn, heightIn),
            margin: String(format: "%.2fin", marginIn)
        )
    }

    // MARK: - Word / Rich Text

    /// Word (.docx) data, via the rendered HTML.
    public func docxData(for content: ExportContent) throws -> Data {
        try attributedData(for: content, documentType: .officeOpenXML, label: "Word")
    }

    /// Rich Text (RTF) data, via the rendered HTML.
    public func rtfData(for content: ExportContent) throws -> Data {
        try attributedData(for: content, documentType: .rtf, label: "Rich Text")
    }

    private func attributedData(
        for content: ExportContent,
        documentType: NSAttributedString.DocumentType,
        label: String
    ) throws -> Data {
        let attributed = try attributedString(for: content)
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: documentType]
        )
        guard !data.isEmpty else { throw ExportError.conversionFailed(format: label) }
        return data
    }

    /// The document as an `NSAttributedString`, built from its HTML.
    ///
    /// AppKit's HTML importer handles inline CSS but not scripts, so Prism
    /// highlighting and Mermaid diagrams don't survive this path — code blocks
    /// arrive as plain monospaced text. That's the expected trade for a format
    /// that has to be editable in Word.
    private func attributedString(for content: ExportContent) throws -> NSAttributedString {
        let html = content.composer.compose(
            title: content.title,
            body: content.body,
            preferences: content.preferences,
            purpose: .export,
            options: HTMLComposer.ExportOptions(
                includeStyles: true,
                includeHighlighting: false,
                includeMath: false,
                includeDiagrams: false
            )
        )

        guard let data = html.data(using: .utf8) else {
            throw ExportError.conversionFailed(format: "HTML")
        }

        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let baseURL = content.baseURL {
            options[.baseURL] = baseURL
        }

        guard let attributed = try? NSAttributedString(
            data: data, options: options, documentAttributes: nil
        ) else {
            throw ExportError.conversionFailed(format: "Rich Text")
        }
        return attributed
    }

    // MARK: - Clipboard

    /// Put the document on the pasteboard as HTML (with a plain-text fallback
    /// so apps that don't take HTML still get the markup).
    public func copyAsHTML(_ content: ExportContent) {
        let html = html(for: content, options: HTMLComposer.ExportOptions())
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    /// Put the document on the pasteboard as rich text, so pasting into Mail,
    /// Pages, or Notes keeps the formatting.
    public func copyAsRichText(_ content: ExportContent) throws {
        let rtf = try rtfData(for: content)
        let plain = try attributedString(for: content).string
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString(plain, forType: .string)
    }

    // MARK: - Offscreen Rendering

    /// Load `html` into an offscreen web view and return once it has finished
    /// laying out (plus a grace period for script-driven content).
    private func loadOffscreen(html: String, baseURL: URL?) async throws -> WKWebView {
        // US Letter at 96dpi, less 0.75in margins each side. The exact width
        // only sets the layout viewport — `@page` governs the printed result —
        // but it must be page-ish so media queries and tables break sensibly.
        let layoutWidth: CGFloat = 816 - 144
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: layoutWidth, height: 1056),
            configuration: WKWebViewConfiguration()
        )
        let delegate = LoadDelegate()
        webView.navigationDelegate = delegate

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await delegate.waitForLoad {
                    webView.loadHTMLString(html, baseURL: baseURL)
                }
            }
            group.addTask { [loadTimeout] in
                try await Task.sleep(for: loadTimeout)
                throw ExportError.renderTimedOut
            }
            try await group.next()
            group.cancelAll()
        }

        try? await Task.sleep(for: scriptSettleDelay)
        // Keep the delegate alive until we're done with it.
        withExtendedLifetime(delegate) {}
        return webView
    }

    /// Bridges `WKNavigationDelegate` callbacks to async/await.
    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Never>?

        @MainActor
        func waitForLoad(_ start: @MainActor () -> Void) async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                start()
            }
        }

        private func finish() {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish()
        }

        // A failed load still produces a page we can render — an empty one, or
        // one missing a remote asset. Better a thin PDF than a hang.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finish()
        }
    }
}

// MARK: - Export Content

/// Everything the exporter needs to build a document, gathered in one place so
/// the view layer doesn't have to know how each format is produced.
///
/// Main-actor bound because `Preferences` is an `@Observable` reference type
/// read from the UI — export never leaves the main actor anyway.
@MainActor
public struct ExportContent {
    public var title: String?
    public var body: String
    public var baseURL: URL?
    public var suggestedFilename: String?
    public var preferences: Preferences
    public var composer: HTMLComposer

    public init(
        title: String?,
        body: String,
        baseURL: URL?,
        suggestedFilename: String?,
        preferences: Preferences,
        composer: HTMLComposer = HTMLComposer()
    ) {
        self.title = title
        self.body = body
        self.baseURL = baseURL
        self.suggestedFilename = suggestedFilename
        self.preferences = preferences
        self.composer = composer
    }
}

#endif
