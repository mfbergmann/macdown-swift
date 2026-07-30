import Foundation

/// The export actions available from the File menu.
///
/// Carried as a raw value on the `.exportDocument` notification.
public enum ExportCommand: String, CaseIterable, Sendable {
    case pdf
    case html
    case docx
    case print
    case copyHTML
    case copyRichText

    public var menuTitle: String {
        switch self {
        case .pdf: "Export as PDF…"
        case .html: "Export as HTML…"
        case .docx: "Export as Word (.docx)…"
        case .print: "Print…"
        case .copyHTML: "Copy as HTML"
        case .copyRichText: "Copy as Rich Text"
        }
    }

    /// File extension for the commands that write a file.
    public var fileExtension: String? {
        switch self {
        case .pdf: "pdf"
        case .html: "html"
        case .docx: "docx"
        case .print, .copyHTML, .copyRichText: nil
        }
    }
}

/// Anything that can go wrong on the way to a file.
public enum ExportError: LocalizedError {
    case renderTimedOut
    case conversionFailed(format: String)

    public var errorDescription: String? {
        switch self {
        case .renderTimedOut:
            "The preview took too long to finish rendering."
        case .conversionFailed(let format):
            "The document could not be converted to \(format)."
        }
    }
}
