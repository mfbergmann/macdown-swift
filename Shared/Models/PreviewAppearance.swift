import Foundation

/// Whether the preview follows the system's light/dark setting or is pinned.
///
/// The editor and preview each have a light and a dark theme; this decides
/// which pair is in force, so the two panes always match each other.
public enum PreviewAppearance: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Resolve to a concrete choice.
    ///
    /// - Parameter systemIsDark: whether the surrounding UI is currently dark.
    public func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }
}
