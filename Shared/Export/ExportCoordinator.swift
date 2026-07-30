#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Drives an ``ExportCommand`` from menu item to finished file: picks a
/// destination, produces the bytes, writes them, and reports failures.
///
/// Split out from the document view so the view only has to say *what* the
/// user asked for, not how each format gets made or saved.
@MainActor
public final class ExportCoordinator {
    private let exporter = DocumentExporter()

    /// Held for the lifetime of the print job — `NSPrintOperation` needs to
    /// outlive the call that starts it.
    private var activePrintOperation: NSPrintOperation?

    public init() {}

    public func run(_ command: ExportCommand, content: ExportContent) async {
        do {
            switch command {
            case .html:
                let html = exporter.html(for: content)
                guard let data = html.data(using: .utf8) else {
                    throw ExportError.conversionFailed(format: "HTML")
                }
                try await save(data, as: command, content: content)

            case .pdf:
                let data = try await exporter.pdfData(for: content)
                try await save(data, as: command, content: content)

            case .docx:
                let data = try exporter.docxData(for: content)
                try await save(data, as: command, content: content)

            case .print:
                let operation = try await exporter.printOperation(for: content)
                activePrintOperation = operation
                operation.run()
                activePrintOperation = nil

            case .copyHTML:
                exporter.copyAsHTML(content)

            case .copyRichText:
                try exporter.copyAsRichText(content)
            }
        } catch {
            presentError(error, command: command)
        }
    }

    // MARK: - Saving

    private func save(_ data: Data, as command: ExportCommand, content: ExportContent) async throws {
        guard let url = await destinationURL(for: command, content: content) else {
            return  // user cancelled
        }
        try data.write(to: url, options: .atomic)
    }

    private func destinationURL(for command: ExportCommand, content: ExportContent) async -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFilename(for: command, content: content)
        if let type = contentType(for: command) {
            panel.allowedContentTypes = [type]
        }

        // Default to sitting next to the document being exported.
        if let baseURL = content.baseURL {
            panel.directoryURL = baseURL.deletingLastPathComponent()
        }

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK else { return nil }
        return panel.url
    }

    private func suggestedFilename(for command: ExportCommand, content: ExportContent) -> String {
        let base = content.suggestedFilename
            ?? content.title
            ?? "Untitled"
        guard let ext = command.fileExtension else { return base }
        return "\(base).\(ext)"
    }

    private func contentType(for command: ExportCommand) -> UTType? {
        switch command {
        case .pdf: .pdf
        case .html: .html
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .print, .copyHTML, .copyRichText: nil
        }
    }

    // MARK: - Errors

    private func presentError(_ error: Error, command: ExportCommand) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t complete \(command.menuTitle.replacingOccurrences(of: "…", with: ""))"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

#endif
