import Foundation
import Testing
@testable import MacDownCore

/// A temporary directory populated with `names`, cleaned up by the caller.
private func makeFolder(_ names: [String]) throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MacDownTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in names {
        if name.hasSuffix("/") {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(String(name.dropLast())),
                withIntermediateDirectories: true
            )
        } else {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
    }
    return folder
}

@Suite("Folder listing")
struct FolderListingTests {

    @Test("Lists markdown files and skips other types")
    func filtersToMarkdown() throws {
        let folder = try makeFolder(["a.md", "b.markdown", "c.png", "d.swift", "e.mkd"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let names = FolderListing.listing(of: folder).entries.map(\.name)
        #expect(names.contains("a.md"))
        #expect(names.contains("b.markdown"))
        #expect(names.contains("e.mkd"))
        #expect(!names.contains("c.png"))
        #expect(!names.contains("d.swift"))
    }

    @Test("Folders sort before files, each alphabetically")
    func ordering() throws {
        let folder = try makeFolder(["zebra.md", "apple.md", "sub/", "another/"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let entries = FolderListing.listing(of: folder).entries
        #expect(entries.map(\.name) == ["another", "sub", "apple.md", "zebra.md"])
        let leadingAreFolders = entries.prefix(2).allSatisfy { $0.isDirectory }
        #expect(leadingAreFolders)
    }

    @Test("Sorting is case-insensitive")
    func caseInsensitiveOrder() throws {
        let folder = try makeFolder(["Beta.md", "alpha.md"])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FolderListing.listing(of: folder).entries.map(\.name) == ["alpha.md", "Beta.md"])
    }

    @Test("Skips hidden files")
    func skipsHidden() throws {
        let folder = try makeFolder([".hidden.md", "visible.md"])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FolderListing.listing(of: folder).entries.map(\.name) == ["visible.md"])
    }

    @Test("Lists the folder containing the document")
    func forDocument() throws {
        let folder = try makeFolder(["one.md", "two.md"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let listing = FolderListing.forDocument(at: folder.appendingPathComponent("one.md"))
        #expect(listing.entries.count == 2)
        // Compare paths: a directory URL carries a trailing slash, the original doesn't.
        #expect(listing.folder?.standardizedFileURL.path == folder.standardizedFileURL.path)
    }

    @Test("An unsaved document has no folder to list")
    func unsavedDocument() {
        let listing = FolderListing.forDocument(at: nil)
        #expect(listing.isEmpty)
        #expect(listing.folder == nil)
    }

    @Test("A missing folder yields an empty listing rather than failing")
    func missingFolder() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(FolderListing.listing(of: missing).isEmpty)
    }
}
