import Foundation
import Testing
@testable import MacDownCore

private func makeFolder() throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MacDownImages-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Suite("Image insertion")
struct ImageInsertionTests {

    @Test("Assets folder is named after the document")
    func assetsFolderName() {
        let doc = URL(fileURLWithPath: "/notes/journal.md")
        #expect(ImageInsertion.assetsFolderName(for: doc) == "journal.assets")
        #expect(ImageInsertion.assetsFolder(for: doc).path == "/notes/journal.assets")
    }

    @Test("Two documents in one folder get separate asset folders")
    func separateFolders() {
        let a = ImageInsertion.assetsFolderName(for: URL(fileURLWithPath: "/n/a.md"))
        let b = ImageInsertion.assetsFolderName(for: URL(fileURLWithPath: "/n/b.md"))
        #expect(a != b)
    }

    @Test("Builds a relative markdown link")
    func markdownLink() {
        let link = ImageInsertion.markdownLink(
            fileName: "shot.png", folderName: "notes.assets", altText: "A screenshot"
        )
        #expect(link == "![A screenshot](notes.assets/shot.png)")
    }

    @Test("Spaces in the path are percent-encoded so the link doesn't break")
    func encodesSpaces() {
        let link = ImageInsertion.markdownLink(
            fileName: "my shot.png", folderName: "my notes.assets"
        )
        #expect(link == "![](my%20notes.assets/my%20shot.png)")
        #expect(!link.contains(" "))
    }

    @Test("An empty alt text produces empty brackets, not a placeholder")
    func emptyAlt() {
        let link = ImageInsertion.markdownLink(fileName: "a.png", folderName: "d.assets")
        #expect(link.hasPrefix("![]("))
    }

    @Test("Unique filenames avoid clobbering an existing file")
    func uniqueFilenames() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(ImageInsertion.uniqueFilename(base: "shot", extension: "png", in: folder) == "shot.png")

        try Data("x".utf8).write(to: folder.appendingPathComponent("shot.png"))
        #expect(ImageInsertion.uniqueFilename(base: "shot", extension: "png", in: folder) == "shot-1.png")

        try Data("x".utf8).write(to: folder.appendingPathComponent("shot-1.png"))
        #expect(ImageInsertion.uniqueFilename(base: "shot", extension: "png", in: folder) == "shot-2.png")
    }

    @Test("Path separators are stripped from filenames")
    func sanitizesNames() {
        #expect(ImageInsertion.sanitize("a/b") == "a-b")
        #expect(!ImageInsertion.sanitize("../../etc/passwd").contains("/"))
    }

    @Test("A name that sanitizes to nothing falls back to a usable one")
    func emptyNameFallback() {
        #expect(ImageInsertion.sanitize("///") == "image")
        #expect(ImageInsertion.sanitize("   ") == "image")
    }

    @Test("Default names are timestamped and stable for a given instant")
    func defaultBaseName() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ImageInsertion.defaultBaseName(date: date)
        let second = ImageInsertion.defaultBaseName(date: date)
        #expect(first == second)
        #expect(first.hasPrefix("image-"))
    }

    @Test("A generated link round-trips through the renderer as an image")
    func linkRenders() {
        let link = ImageInsertion.markdownLink(
            fileName: "my shot.png", folderName: "doc.assets", altText: "alt"
        )
        let html = MarkdownRenderer().render(link).html
        #expect(html.contains("<img"))
        #expect(html.contains("alt=\"alt\""))
        #expect(html.contains("doc.assets/my%20shot.png"))
    }
}
