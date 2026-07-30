import Foundation
import Testing
@testable import MacDownCore

private func makePreferences() -> Preferences {
    Preferences(defaults: UserDefaults(suiteName: "MacDownTests.\(UUID().uuidString)")!)
}

@Suite("Preview appearance")
struct PreviewAppearanceTests {

    @Test("Following the system tracks it in both directions")
    func followsSystem() {
        #expect(PreviewAppearance.system.isDark(systemIsDark: true))
        #expect(!PreviewAppearance.system.isDark(systemIsDark: false))
    }

    @Test("A pinned appearance ignores the system")
    func pinnedIgnoresSystem() {
        #expect(!PreviewAppearance.light.isDark(systemIsDark: true))
        #expect(PreviewAppearance.dark.isDark(systemIsDark: false))
    }

    @Test("Defaults to following the system")
    func defaultsToSystem() {
        #expect(makePreferences().previewAppearance == .system)
    }

    @Test("Light and dark themes are separate settings")
    func separateThemes() {
        let prefs = makePreferences()
        #expect(prefs.htmlStyleName(dark: false) == "GitHub2")
        #expect(prefs.htmlStyleName(dark: true) == "GitHub Dark")
        #expect(prefs.editorStyleName(dark: false) == "xcode")
        #expect(prefs.editorStyleName(dark: true) == "atom-one-dark")
    }

    @Test("Changing one theme leaves the other alone")
    func themesAreIndependent() {
        let prefs = makePreferences()
        prefs.htmlStyleNameDark = "Solarized (Dark)"
        #expect(prefs.htmlStyleName(dark: true) == "Solarized (Dark)")
        #expect(prefs.htmlStyleName(dark: false) == "GitHub2", "light theme untouched")
    }

    @Test("The dark stylesheet ships in the bundle")
    func darkStylesheetExists() {
        #expect(HTMLComposer.availablePreviewStyles().contains("GitHub Dark"))
    }
}

@Suite("Appearance in composed HTML")
struct AppearanceCompositionTests {

    let composer = HTMLComposer()

    @Test("Dark preview uses the dark stylesheet")
    func darkPreviewUsesDarkCSS() {
        let prefs = makePreferences()
        let dark = composer.compose(title: nil, body: "<p>x</p>", preferences: prefs, isDark: true)
        let light = composer.compose(title: nil, body: "<p>x</p>", preferences: prefs, isDark: false)

        #expect(dark.contains("#0d1117"), "GitHub Dark's background colour")
        #expect(!light.contains("#0d1117"))
    }

    @Test("Print output stays on white paper even in dark mode")
    func printIgnoresDarkMode() {
        let prefs = makePreferences()
        let printed = composer.compose(
            title: nil, body: "<p>x</p>", preferences: prefs,
            purpose: .print, isDark: true
        )
        #expect(!printed.contains("#0d1117"), "paper is white regardless of the screen")
        #expect(printed.contains("@page"))
    }

    @Test("Exported HTML honours the appearance it was exported in")
    func exportHonoursAppearance() {
        let prefs = makePreferences()
        let exported = composer.compose(
            title: nil, body: "<p>x</p>", preferences: prefs,
            purpose: .export, isDark: true
        )
        #expect(exported.contains("#0d1117"))
    }
}
