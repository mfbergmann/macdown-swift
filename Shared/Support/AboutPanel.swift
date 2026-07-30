#if os(macOS)
import AppKit

/// The About box, with credit where it's due.
///
/// Uses AppKit's standard panel rather than a bespoke window so it looks and
/// behaves exactly like every other Mac app's About box.
@MainActor
public enum AboutPanel {

    public static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: version,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// Third-party components actually bundled in this build.
    ///
    /// Kept next to the code rather than in a stale text file so it can't drift
    /// away from what `Package.swift` and `Resources/` really contain.
    private static let components: [(name: String, detail: String)] = [
        ("swift-cmark", "GFM parsing and rendering — Apple"),
        ("Highlightr", "editor syntax highlighting — Illanes J.P."),
        ("Yams", "YAML front matter — JP Simard"),
        ("swift-collections", "ordered collections — Apple"),
        ("Prism", "preview code highlighting — Lea Verou"),
        ("MathJax", "math typesetting — the MathJax Consortium"),
        ("Mermaid", "diagrams — Knut Sveidqvist"),
    ]

    private static var credits: NSAttributedString {
        let body = NSFont.systemFont(ofSize: 11)
        let bold = NSFont.boldSystemFont(ofSize: 11)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2

        let result = NSMutableAttributedString()

        func append(_ text: String, font: NSFont = body) {
            result.append(NSAttributedString(string: text, attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.labelColor,
            ]))
        }

        append("Build \(build)\n\n")

        append("A Swift and SwiftUI rewrite of MacDown.\n\n")

        append("MacDown", font: bold)
        append(" was created by Tzu-ping Chung and contributors,\n")
        append("who took their inspiration from Chen Luo's ")
        append("Mou", font: bold)
        append(".\n")
        append("This rewrite stands on their work; the original\n")
        append("copyright and MIT licence are preserved.\n\n")

        append("Editor themes and preview CSS from Mou, courtesy of Chen Luo.\n\n")

        append("Third-party components\n", font: bold)
        for component in components {
            append("\(component.name) — \(component.detail)\n")
        }
        append("\nFull licence texts are in the LICENSE directory\n")
        append("of the source repository.")

        return result
    }
}
#endif
