import Foundation

/// Files the user can add to, living in Application Support.
///
/// Custom preview stylesheets go here: drop a `.css` file in and it shows up in
/// the style picker next to the bundled ones. Keeping them outside the app
/// bundle means they survive updates and don't need the bundle to be writable.
public enum UserResources {

    /// `~/Library/Application Support/MacDown`.
    public static var supportDirectory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return base.appendingPathComponent("MacDown", isDirectory: true)
    }

    /// `~/Library/Application Support/MacDown/Styles`.
    public static var stylesDirectory: URL? {
        supportDirectory?.appendingPathComponent("Styles", isDirectory: true)
    }

    /// Create the styles folder if it isn't there yet, and return it.
    @discardableResult
    public static func ensureStylesDirectory() -> URL? {
        guard let directory = stylesDirectory else { return nil }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    /// Names of the user's own stylesheets, without the `.css` extension.
    public static func customStyleNames() -> [String] {
        guard let directory = stylesDirectory,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              )
        else { return [] }

        return contents
            .filter { $0.pathExtension.lowercased() == "css" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// The CSS for a user stylesheet, or `nil` if there isn't one by that name.
    public static func customStyleCSS(named name: String) -> String? {
        guard let directory = stylesDirectory else { return nil }
        let url = directory.appendingPathComponent(name).appendingPathExtension("css")
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
