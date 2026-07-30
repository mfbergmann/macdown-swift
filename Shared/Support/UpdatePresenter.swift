#if os(macOS)
import AppKit

/// Runs an update check and shows the result.
///
/// A user-initiated check always says something, even "you're up to date" —
/// silence would read as a broken menu item.
@MainActor
public final class UpdatePresenter {
    public static let shared = UpdatePresenter()

    private let checker = UpdateChecker()
    private var isChecking = false

    public init() {}

    /// The app's marketing version, as stamped into the bundle at build time.
    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    public func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            do {
                let result = try await checker.check(currentVersion: Self.currentVersion)
                present(result)
            } catch {
                presentFailure(error)
            }
        }
    }

    private func present(_ result: UpdateChecker.Result) {
        switch result {
        case .upToDate(let current):
            let alert = NSAlert()
            alert.messageText = "You're up to date"
            alert.informativeText = "MacDown \(current) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .updateAvailable(let release):
            let alert = NSAlert()
            alert.messageText = "MacDown \(release.version?.description ?? release.tagName) is available"
            alert.informativeText = releaseSummary(for: release)
            alert.addButton(withTitle: "Download…")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Release notes are markdown; an alert renders plain text, so flatten the
    /// syntax rather than showing raw `##` and `*` to the user.
    private func releaseSummary(for release: Release) -> String {
        let current = "You have \(Self.currentVersion)."
        guard let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty
        else { return current }

        let flattened = body
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: [.regularExpression])
            .replacingOccurrences(
                of: #"(?m)^#{1,6}\s*"#, with: "", options: [.regularExpression]
            )
            .replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: [.regularExpression])
            .replacingOccurrences(
                of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: [.regularExpression]
            )

        // Keep the alert a sensible size; the release page has the full notes.
        let trimmed = flattened.count > 600
            ? String(flattened.prefix(600)) + "…"
            : flattened
        return "\(current)\n\n\(trimmed)"
    }
}
#endif
