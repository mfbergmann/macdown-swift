import Foundation

/// The markdown files sitting alongside the document being edited.
///
/// Deliberately shallow — one folder, no recursion — so the sidebar stays a
/// quick way to hop between notes in a directory rather than a project browser.
public struct FolderListing: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public var url: URL
        public var name: String
        public var isDirectory: Bool
        public var id: URL { url }
    }

    public var folder: URL?
    public var entries: [Entry]

    public init(folder: URL? = nil, entries: [Entry] = []) {
        self.folder = folder
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Extensions we consider markdown, matching the document types we register.
    public static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdtext", "text", "txt",
    ]

    /// List the markdown files in the folder containing `documentURL`.
    ///
    /// Returns an empty listing for an unsaved document, which has no folder yet.
    public static func forDocument(
        at documentURL: URL?,
        fileManager: FileManager = .default
    ) -> FolderListing {
        guard let documentURL else { return FolderListing() }
        let folder = documentURL.deletingLastPathComponent()
        return listing(of: folder, fileManager: fileManager)
    }

    public static func listing(
        of folder: URL,
        fileManager: FileManager = .default
    ) -> FolderListing {
        let contents = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        let entries = contents
            .compactMap { url -> Entry? in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                // Folders are listed so you can see the shape of the directory,
                // but only markdown files are worth offering to open.
                guard isDirectory || markdownExtensions.contains(url.pathExtension.lowercased())
                else { return nil }
                return Entry(url: url, name: url.lastPathComponent, isDirectory: isDirectory)
            }
            // Folders first, then files, each alphabetical and case-insensitive.
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return FolderListing(folder: folder, entries: entries)
    }
}
