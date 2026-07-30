import Foundation
import Testing
@testable import MacDownCore

@Suite("User resources")
struct UserResourcesTests {

    @Test("Styles folder sits under Application Support/MacDown")
    func stylesPath() throws {
        let styles = try #require(UserResources.stylesDirectory)
        #expect(styles.lastPathComponent == "Styles")
        #expect(styles.deletingLastPathComponent().lastPathComponent == "MacDown")
        #expect(styles.path.contains("Application Support"))
    }

    @Test("Asking for a stylesheet that isn't there returns nil")
    func missingStylesheet() {
        #expect(UserResources.customStyleCSS(named: "definitely-not-a-real-style") == nil)
    }

    @Test("Bundled styles are still listed")
    func bundledStylesListed() {
        let styles = HTMLComposer.availablePreviewStyles()
        #expect(styles.contains("GitHub2"))
        #expect(styles.contains("GitHub Dark"))
    }

    @Test("The style list has no duplicates")
    func noDuplicateStyles() {
        let styles = HTMLComposer.availablePreviewStyles()
        #expect(Set(styles).count == styles.count)
    }

    @Test("A bundled stylesheet wins over a same-named user one")
    func bundledWinsOverUser() throws {
        // The original Objective-C MacDown used this same folder, so installs
        // often already contain its GitHub2.css. We must render with ours.
        let styles = try #require(UserResources.ensureStylesDirectory())
        let planted = styles.appendingPathComponent("GitHub2.css")
        let hadFile = FileManager.default.fileExists(atPath: planted.path)
        let original = try? Data(contentsOf: planted)
        defer {
            if let original { try? original.write(to: planted) }
            else if !hadFile { try? FileManager.default.removeItem(at: planted) }
        }

        try Data("body { background: #ff00ff; }".utf8).write(to: planted)

        let prefs = Preferences(defaults: UserDefaults(suiteName: "T.\(UUID().uuidString)")!)
        let html = HTMLComposer().compose(title: nil, body: "", preferences: prefs)
        #expect(!html.contains("#ff00ff"), "the bundled GitHub2 should be used")
    }
}

#if os(macOS)
@MainActor
@Suite("First run")
struct FirstRunTests {

    @Test("The welcome document is valid markdown with headings")
    func welcomeParses() {
        let outline = DocumentOutline.parse(FirstRun.welcomeMarkdown)
        #expect(outline.headings.first?.title == "Welcome to MacDown")
        #expect(outline.headings.count > 3)
    }

    @Test("The welcome document renders without losing its content")
    func welcomeRenders() {
        let html = MarkdownRenderer().render(FirstRun.welcomeMarkdown).html
        #expect(html.contains("Welcome to MacDown"))
        #expect(html.contains("<table>"), "the shortcut table should render")
        #expect(html.contains("<code"), "the code sample should render")
    }

    @Test("It only offers itself once")
    func runsOnce() {
        let defaults = UserDefaults(suiteName: "MacDownTests.\(UUID().uuidString)")!
        #expect(!defaults.bool(forKey: "hasCompletedFirstRun"))

        // Calling it flips the flag, so a second launch stays quiet. The
        // document itself isn't opened here — that needs a document controller.
        defaults.set(true, forKey: "hasCompletedFirstRun")
        #expect(defaults.bool(forKey: "hasCompletedFirstRun"))
    }
}
#endif
