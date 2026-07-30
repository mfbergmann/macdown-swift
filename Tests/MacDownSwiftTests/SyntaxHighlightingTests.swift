import Foundation
import Testing
@testable import MacDownCore

private func makePreferences() -> Preferences {
    Preferences(defaults: UserDefaults(suiteName: "MacDownTests.\(UUID().uuidString)")!)
}

/// Prism is bundled rather than fetched at runtime, so exported files keep
/// highlighting offline. These guard the wiring: it was silently missing from
/// the bundle for the whole life of the project before this.
@Suite("Preview syntax highlighting")
struct SyntaxHighlightingTests {

    let composer = HTMLComposer()

    @Test("Prism's script is inlined into the preview")
    func prismScriptPresent() {
        let html = composer.compose(
            title: nil, body: "<pre><code>x</code></pre>", preferences: makePreferences()
        )
        #expect(html.contains("Prism"), "Prism core must be bundled and inlined")
    }

    @Test("A Prism theme is inlined")
    func prismThemePresent() {
        let html = composer.compose(
            title: nil, body: "", preferences: makePreferences()
        )
        #expect(html.contains("token"), "a Prism theme styles .token classes")
    }

    @Test("The bundled Prism knows the languages people actually use")
    func languagesBundled() {
        let html = composer.compose(title: nil, body: "", preferences: makePreferences())
        for language in ["swift", "python", "rust", "json", "yaml", "bash", "typescript"] {
            #expect(
                html.contains("languages.\(language)") || html.contains("\"\(language)\""),
                "\(language) should be in the bundled Prism build"
            )
        }
    }

    @Test("Highlighting can be switched off")
    func canBeDisabled() {
        let prefs = makePreferences()
        prefs.htmlSyntaxHighlighting = false
        let html = composer.compose(title: nil, body: "", preferences: prefs)
        #expect(!html.contains("Prism"))
    }

    @Test("The Prism theme follows the resolved appearance")
    func themeFollowsAppearance() {
        let prefs = makePreferences()
        #expect(prefs.htmlHighlightingThemeName(dark: false) == "prism")
        #expect(prefs.htmlHighlightingThemeName(dark: true) == "prism-tomorrow")

        let dark = composer.compose(title: nil, body: "", preferences: prefs, isDark: true)
        let light = composer.compose(title: nil, body: "", preferences: prefs, isDark: false)
        #expect(dark != light, "dark mode should pull a different Prism theme")
    }

    @Test("Print output uses the light theme whatever the screen is doing")
    func printUsesLightTheme() {
        let prefs = makePreferences()
        let printed = composer.compose(
            title: nil, body: "", preferences: prefs, purpose: .print, isDark: true
        )
        let lightPreview = composer.compose(
            title: nil, body: "", preferences: prefs, isDark: false
        )
        // The print stylesheet is extra, but the Prism theme should be the light one.
        #expect(printed.contains("@page"))
        for marker in ["#2d2d2d", "#ccc"] where lightPreview.contains(marker) == false {
            #expect(!printed.contains(marker), "dark Prism colours must not reach paper")
        }
    }

    @Test("The line-numbers plugin is bundled when switched on")
    func lineNumbersPlugin() {
        let prefs = makePreferences()
        prefs.htmlLineNumbers = true
        let html = composer.compose(title: nil, body: "", preferences: prefs)
        #expect(html.contains("line-numbers"))
    }

    @Test("Exported HTML carries highlighting so it works offline")
    func exportKeepsHighlighting() {
        let html = composer.compose(
            title: nil, body: "<pre><code class=\"language-swift\">let x = 1</code></pre>",
            preferences: makePreferences(), purpose: .export
        )
        #expect(html.contains("Prism"))
        #expect(!html.contains("<script src="), "nothing should be fetched at open time")
    }
}
