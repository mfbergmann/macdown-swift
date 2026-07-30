import Foundation

/// Where a pasted or dropped image goes, and what gets written into the document.
///
/// Images are saved into a sidecar folder next to the document and linked
/// relatively, so moving the document and its folder together keeps the links
/// working — and so the markdown stays portable to any other renderer.
public enum ImageInsertion {

    /// Sidecar folder name for a document, e.g. `notes.md` -> `notes.assets`.
    ///
    /// Named after the document rather than a shared `images/` so two documents
    /// in one folder can't fight over the same filenames.
    public static func assetsFolderName(for documentURL: URL) -> String {
        let base = documentURL.deletingPathExtension().lastPathComponent
        return "\(base).assets"
    }

    public static func assetsFolder(for documentURL: URL) -> URL {
        documentURL
            .deletingLastPathComponent()
            .appendingPathComponent(assetsFolderName(for: documentURL), isDirectory: true)
    }

    /// A filename in `folder` that isn't taken, suffixing `-1`, `-2`, … if needed.
    public static func uniqueFilename(
        base: String,
        extension ext: String,
        in folder: URL,
        fileManager: FileManager = .default
    ) -> String {
        let safeBase = sanitize(base)
        var candidate = "\(safeBase).\(ext)"
        var counter = 1
        while fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(safeBase)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    /// The markdown to insert for an image saved as `fileName` in `folderName`.
    public static func markdownLink(
        fileName: String,
        folderName: String,
        altText: String = ""
    ) -> String {
        "![\(altText)](\(percentEncode("\(folderName)/\(fileName)")))"
    }

    /// Strip path separators and other characters that make poor filenames.
    ///
    /// Empty components are dropped rather than joined, so a name that is all
    /// separators ("///") collapses to nothing and takes the fallback instead
    /// of becoming "---". Leading dots go too, so an image can't end up hidden.
    static func sanitize(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .drop { $0 == "." }
        return cleaned.isEmpty ? "image" : String(cleaned)
    }

    /// Percent-encode the parts of a path that would otherwise break a
    /// markdown link — spaces most of all.
    static func percentEncode(_ path: String) -> String {
        path.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlPathAllowed
        ) ?? path
    }

    /// A default base name for an image that arrives without one.
    ///
    /// Takes the timestamp from the caller so the result is predictable in tests
    /// and so callers can group a batch of drops under one name.
    public static func defaultBaseName(date: Date, formatter: DateFormatter = timestampFormatter) -> String {
        "image-\(formatter.string(from: date))"
    }

    public static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
