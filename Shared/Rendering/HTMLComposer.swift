import Foundation

/// Composes a full HTML document by wrapping rendered markdown HTML
/// with CSS styles, JavaScript extensions, and a document template.
public struct HTMLComposer: Sendable {

    /// What the composed HTML is for. Determines whether interactive scripts
    /// are included and whether a print stylesheet is added.
    public enum Purpose: Sendable {
        /// The live on-screen preview: everything, including interactivity.
        case preview
        /// A standalone `.html` file the user will keep or share.
        case export
        /// Paper or PDF: adds a print stylesheet, drops interactivity.
        case print
    }

    /// Which parts of the document to carry into an export.
    ///
    /// Everything is inlined rather than linked, so an exported file is
    /// self-contained and keeps working after it's moved or emailed. The one
    /// exception is MathJax, which loads from a CDN and therefore needs a
    /// network connection to typeset.
    public struct ExportOptions: Sendable {
        public var includeStyles: Bool
        public var includeHighlighting: Bool
        public var includeMath: Bool
        public var includeDiagrams: Bool

        public init(
            includeStyles: Bool = true,
            includeHighlighting: Bool = true,
            includeMath: Bool = true,
            includeDiagrams: Bool = true
        ) {
            self.includeStyles = includeStyles
            self.includeHighlighting = includeHighlighting
            self.includeMath = includeMath
            self.includeDiagrams = includeDiagrams
        }

        /// Body text only — no theme, no highlighting. Useful when pasting into
        /// another document that brings its own styling.
        public static let plain = ExportOptions(
            includeStyles: false,
            includeHighlighting: false,
            includeMath: false,
            includeDiagrams: false
        )
    }

    /// Page geometry for PDF and print output.
    public struct PageSetup: Sendable {
        /// Page size in CSS units, e.g. `"letter"`, `"A4"`, `"letter landscape"`.
        public var size: String
        /// Page margin in CSS units, e.g. `"0.75in"`.
        public var margin: String

        public init(size: String = "letter", margin: String = "0.75in") {
            self.size = size
            self.margin = margin
        }

        public static let `default` = PageSetup()
    }

    public init() {}

    /// Compose the live preview document.
    ///
    /// - Parameter isDark: whether the resolved appearance is dark, which
    ///   selects between the light and dark preview stylesheets.
    public func compose(
        title: String?,
        body: String,
        preferences: Preferences,
        isDark: Bool = false
    ) -> String {
        compose(
            title: title,
            body: body,
            preferences: preferences,
            purpose: .preview,
            options: ExportOptions(),
            pageSetup: .default,
            isDark: isDark
        )
    }

    /// Compose a complete, self-contained HTML document.
    public func compose(
        title: String?,
        body: String,
        preferences: Preferences,
        purpose: Purpose,
        options: ExportOptions = ExportOptions(),
        pageSetup: PageSetup = .default,
        isDark: Bool = false
    ) -> String {
        var styleTags: [String] = []
        var scriptTags: [String] = []

        // Base stylesheet. Paper is always white, so print ignores dark mode.
        let styleName = preferences.htmlStyleName(dark: isDark && purpose != .print)
        if options.includeStyles, let css = loadStyleCSS(named: styleName) {
            styleTags.append(inlineStyle(css))
        }

        // Syntax highlighting via Prism
        if options.includeHighlighting && preferences.htmlSyntaxHighlighting {
            if let prismCSS = loadPrismThemeCSS(named: preferences.htmlHighlightingThemeName) {
                styleTags.append(inlineStyle(prismCSS))
            }
            if let prismJS = loadPrismCoreJS() {
                scriptTags.append(inlineScript(prismJS))
            }
            // Line numbers plugin
            if preferences.htmlLineNumbers {
                if let lineNumCSS = loadPrismPluginCSS(named: "line-numbers") {
                    styleTags.append(inlineStyle(lineNumCSS))
                }
                if let lineNumJS = loadPrismPluginJS(named: "line-numbers") {
                    scriptTags.append(inlineScript(lineNumJS))
                }
            }
        }

        // MathJax
        if options.includeMath && preferences.htmlMathJax {
            let mathjaxCDN = "https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/MathJax.js?config=TeX-AMS-MML_HTMLorMML"
            scriptTags.append(externalScript(mathjaxCDN))
            if preferences.htmlMathJaxInlineDollar {
                let config = """
                <script type="text/x-mathjax-config">
                MathJax.Hub.Config({
                    tex2jax: { inlineMath: [['$','$'], ['\\\\(','\\\\)']] }
                });
                </script>
                """
                scriptTags.append(config)
            }
        }

        // Mermaid
        if options.includeDiagrams && preferences.htmlMermaid {
            if let mermaidJS = loadExtensionFile(named: "mermaid.min", ext: "js") {
                scriptTags.append(inlineScript(mermaidJS))
            }
            if let initJS = loadExtensionFile(named: "mermaid.init", ext: "js") {
                scriptTags.append(inlineScript(initJS))
            }
        }

        // Task list interactivity — only meaningful in the live preview, where
        // toggling a checkbox writes back to the document.
        if purpose == .preview && preferences.htmlTaskList {
            if let taskJS = loadExtensionFile(named: "tasklist", ext: "js") {
                scriptTags.append(inlineScript(taskJS))
            }
        }

        if purpose == .print {
            styleTags.append(inlineStyle(Self.printCSS(pageSetup: pageSetup)))
        }

        let titleTag = title.map { "<title>\(escapeHTML($0))</title>" } ?? ""
        let styleBlock = styleTags.joined(separator: "\n")
        let scriptBlock = scriptTags.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
        \(titleTag)
        \(styleBlock)
        </head>
        <body>
        \(body)
        \(scriptBlock)
        </body>
        </html>
        """
    }

    /// Compose HTML suitable for export.
    ///
    /// - Note: Retained for source compatibility; prefer
    ///   ``compose(title:body:preferences:purpose:options:pageSetup:)``.
    public func composeForExport(
        title: String?,
        body: String,
        preferences: Preferences,
        includeStyles: Bool,
        includeHighlighting: Bool
    ) -> String {
        compose(
            title: title,
            body: body,
            preferences: preferences,
            purpose: .export,
            options: ExportOptions(
                includeStyles: includeStyles,
                includeHighlighting: includeHighlighting
            )
        )
    }

    // MARK: - Print Stylesheet

    /// Styles that only apply on paper: page geometry, a white canvas
    /// regardless of the screen theme, and break rules that stop code blocks
    /// and tables being sliced across pages.
    static func printCSS(pageSetup: PageSetup) -> String {
        """
        @page {
            size: \(pageSetup.size);
            margin: \(pageSetup.margin);
        }
        @media print {
            html, body {
                background: #fff !important;
                width: auto !important;
                max-width: none !important;
                margin: 0 !important;
                padding: 0 !important;
            }
            pre, blockquote, table, figure, img, .mermaid {
                break-inside: avoid;
                page-break-inside: avoid;
            }
            h1, h2, h3, h4, h5, h6 {
                break-after: avoid;
                page-break-after: avoid;
            }
            pre {
                white-space: pre-wrap;
                word-wrap: break-word;
            }
            img, table, pre {
                max-width: 100% !important;
            }
        }
        """
    }

    // MARK: - Resource Loading

    /// Bundled stylesheets win over user ones of the same name.
    ///
    /// The obvious precedence would be the other way round, but the original
    /// Objective-C MacDown used this same Application Support folder, so many
    /// installs already contain its copies of `GitHub2.css` and friends.
    /// Preferring the bundle means we render with our own themes rather than
    /// silently picking up a decade-old file the user has forgotten about.
    /// A custom stylesheet just needs a name we don't already ship.
    private func loadStyleCSS(named name: String) -> String? {
        loadResourceFile(name: name, ext: "css", subdirectory: "Styles")
            ?? UserResources.customStyleCSS(named: name)
    }

    private func loadPrismThemeCSS(named name: String) -> String? {
        loadResourceFile(name: name, ext: "css", subdirectory: "Prism/themes")
    }

    private func loadPrismCoreJS() -> String? {
        loadResourceFile(name: "prism", ext: "js", subdirectory: "Prism")
    }

    private func loadPrismPluginCSS(named name: String) -> String? {
        loadResourceFile(name: "prism-\(name)", ext: "css", subdirectory: "Prism/plugins/\(name)")
    }

    private func loadPrismPluginJS(named name: String) -> String? {
        let minified = loadResourceFile(name: "prism-\(name).min", ext: "js", subdirectory: "Prism/plugins/\(name)")
        return minified ?? loadResourceFile(name: "prism-\(name)", ext: "js", subdirectory: "Prism/plugins/\(name)")
    }

    private func loadExtensionFile(named name: String, ext: String) -> String? {
        loadResourceFile(name: name, ext: ext, subdirectory: "Extensions")
    }

    private func loadResourceFile(name: String, ext: String, subdirectory: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - HTML Helpers

    private func inlineStyle(_ css: String) -> String {
        "<style>\n\(css)\n</style>"
    }

    private func inlineScript(_ js: String) -> String {
        "<script>\n\(js)\n</script>"
    }

    private func externalScript(_ url: String) -> String {
        "<script src=\"\(url)\"></script>"
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Available Styles

    /// Bundled styles plus any the user has dropped into their Styles folder.
    public static func availablePreviewStyles() -> [String] {
        let bundled: [String] = {
            guard let url = Bundle.module.url(forResource: "Styles", withExtension: nil),
                  let contents = try? FileManager.default.contentsOfDirectory(
                      at: url, includingPropertiesForKeys: nil
                  )
            else { return [] }
            return contents
                .filter { $0.pathExtension == "css" }
                .map { $0.deletingPathExtension().lastPathComponent }
        }()

        return Set(bundled + UserResources.customStyleNames()).sorted()
    }
}
