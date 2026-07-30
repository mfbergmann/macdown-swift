import Foundation

/// A semantic version, compared numerically rather than as text.
///
/// `"0.10.0"` must sort above `"0.9.0"`, which string comparison gets wrong —
/// the reason to parse rather than compare raw tag names.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public var components: [Int]

    /// Parse a version, tolerating a leading `v` and trailing pre-release text.
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text = String(text.dropFirst()) }
        // Drop any pre-release or build suffix: "1.2.0-beta.1" -> "1.2.0".
        let core = text.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            // Treat a missing component as zero, so 1.2 == 1.2.0.
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// What a release looks like in the slice of the GitHub API we care about.
public struct Release: Sendable, Equatable {
    public var tagName: String
    public var name: String?
    public var htmlURL: URL
    public var body: String?
    public var isPrerelease: Bool
    public var isDraft: Bool

    public var version: SemanticVersion? { SemanticVersion(tagName) }

    public init(
        tagName: String,
        name: String? = nil,
        htmlURL: URL,
        body: String? = nil,
        isPrerelease: Bool = false,
        isDraft: Bool = false
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.body = body
        self.isPrerelease = isPrerelease
        self.isDraft = isDraft
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case isPrerelease = "prerelease"
        case isDraft = "draft"
    }
}

extension Release: Decodable {}

/// Checks GitHub Releases for a newer build.
///
/// Deliberately not Sparkle: this app already ships as a signed, notarized
/// download from GitHub, so a version comparison and a link to the release page
/// covers it without adding an update framework and its own signing story.
public struct UpdateChecker: Sendable {
    public enum Result: Equatable, Sendable {
        case upToDate(current: String)
        case updateAvailable(Release)
    }

    public enum Failure: LocalizedError {
        case badResponse(status: Int)
        case malformedVersion(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let status):
                "The update server responded with status \(status)."
            case .malformedVersion(let tag):
                "Could not read the version number from release “\(tag)”."
            }
        }
    }

    /// `owner/repo` on GitHub.
    public var repository: String
    /// Injected so tests don't hit the network.
    public var fetch: @Sendable (URL) async throws -> (Data, URLResponse)

    public init(
        repository: String = "mfbergmann/macdown-swift",
        fetch: (@Sendable (URL) async throws -> (Data, URLResponse))? = nil
    ) {
        self.repository = repository
        self.fetch = fetch ?? { url in try await URLSession.shared.data(from: url) }
    }

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// Compare the newest published release against `currentVersion`.
    public func check(currentVersion: String) async throws -> Result {
        let (data, response) = try await fetch(latestReleaseURL)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badResponse(status: http.statusCode)
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        return Self.compare(release: release, against: currentVersion)
    }

    /// The decision, split out so it can be tested without any I/O.
    public static func compare(release: Release, against currentVersion: String) -> Result {
        // Drafts and pre-releases are never offered to people on a stable build.
        guard !release.isDraft, !release.isPrerelease,
              let latest = release.version,
              let current = SemanticVersion(currentVersion),
              latest > current
        else {
            return .upToDate(current: currentVersion)
        }
        return .updateAvailable(release)
    }
}
