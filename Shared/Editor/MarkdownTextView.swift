import SwiftUI
import Highlightr

/// Shared helper: pick a readable caret/insertion-point color for a background.
@MainActor
private func caretColor(for background: PlatformColor) -> PlatformColor {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    #if os(macOS)
    (background.usingColorSpace(.deviceRGB) ?? background).getRed(&r, green: &g, blue: &b, alpha: &a)
    #else
    background.getRed(&r, green: &g, blue: &b, alpha: &a)
    #endif
    let luminance = 0.299 * r + 0.587 * g + 0.114 * b
    return luminance < 0.5 ? .white : .black
}

#if os(macOS)
import AppKit

/// NSTextView-backed markdown editor for macOS with live syntax highlighting.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var highlightThemeName: String
    var lineSpacing: CGFloat
    var horizontalInset: CGFloat
    var verticalInset: CGFloat
    var isEditable: Bool
    var scrollsPastEnd: Bool
    var behaviorOptions: EditorBehavior.Options
    var writingModes: WritingModes
    var documentURL: URL?
    var jump: HeadingJump?
    var onScroll: ((CGFloat) -> Void)?
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Highlightr's CodeAttributedString is an NSTextStorage that
        // re-highlights its contents as Markdown whenever they change.
        let textStorage = CodeAttributedString()
        textStorage.language = "markdown"
        textStorage.highlightr.setTheme(to: highlightThemeName)
        textStorage.highlightr.theme.codeFont = font

        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: .zero, textContainer: textContainer)
        textView.scrollsPastEnd = scrollsPastEnd
        textView.documentURL = documentURL
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true   // required for attributed (highlighted) text to render
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = font

        let background = textStorage.highlightr.theme.themeBackgroundColor ?? .textBackgroundColor
        textView.backgroundColor = background
        textView.insertionPointColor = caretColor(for: background)

        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        textView.defaultParagraphStyle = paragraphStyle

        textView.string = text
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.behavior.options = behaviorOptions
        context.coordinator.writingModes = writingModes

        scrollView.documentView = textView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.applyFormatting(_:)),
            name: .insertMarkdownFormatting,
            object: nil
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView,
              let textStorage = textView.textStorage as? CodeAttributedString else { return }

        if textStorage.highlightr.theme.codeFont != font {
            textStorage.highlightr.theme.codeFont = font
        }
        if context.coordinator.themeName != highlightThemeName {
            textStorage.highlightr.setTheme(to: highlightThemeName)
            textStorage.highlightr.theme.codeFont = font
            context.coordinator.themeName = highlightThemeName
            let background = textStorage.highlightr.theme.themeBackgroundColor ?? .textBackgroundColor
            textView.backgroundColor = background
            textView.insertionPointColor = caretColor(for: background)
        }

        // Update text only if it changed externally (not from user typing).
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        context.coordinator.behavior.options = behaviorOptions
        context.coordinator.writingModes = writingModes
        textView.documentURL = documentURL
        context.coordinator.performJumpIfNeeded(jump, in: textView)
        context.coordinator.applyWritingModes(to: textView)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        textView.defaultParagraphStyle = paragraphStyle
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: MarkdownNSTextView?
        var themeName: String
        private let formatter = MarkdownFormatter()
        var behavior = EditorBehavior()

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            self.themeName = parent.highlightThemeName
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?()
            applyWritingModes(to: textView)
            centreCaretIfNeeded(in: textView)
        }

        // MARK: - Typing Behaviors

        /// Intercept Return and Tab so lists continue themselves and Tab indents.
        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            let edit: EditorBehavior.Edit?
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                edit = behavior.newlineEdit(in: textView.string, selection: textView.selectedRange())
            case #selector(NSResponder.insertTab(_:)):
                edit = behavior.tabEdit(
                    in: textView.string, selection: textView.selectedRange(), outdent: false
                )
            case #selector(NSResponder.insertBacktab(_:)):
                edit = behavior.tabEdit(
                    in: textView.string, selection: textView.selectedRange(), outdent: true
                )
            default:
                return false
            }

            guard let edit else { return false }  // let the text view handle it normally
            apply(edit, to: textView)
            return true
        }

        /// Intercept single-character insertions for auto-pairing.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString,
                  let edit = behavior.insertionEdit(
                      for: replacementString,
                      in: textView.string,
                      selection: affectedCharRange
                  )
            else { return true }

            apply(edit, to: textView)
            return false
        }

        var writingModes = WritingModes()

        /// Focus mode dims via layout-manager temporary attributes, which are
        /// presentation-only — they never touch the text storage, so they can't
        /// end up in the saved file or in undo.
        func applyWritingModes(to textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)

            guard writingModes.focus else {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
                return
            }

            let lit = FocusRange.paragraph(in: textView.string, selection: textView.selectedRange())
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

            let dimmed = NSColor.secondaryLabelColor.withAlphaComponent(0.35)
            for range in [
                NSRange(location: 0, length: lit.location),
                NSRange(
                    location: lit.upperBound,
                    length: max(0, full.length - lit.upperBound)
                ),
            ] where range.length > 0 {
                layoutManager.addTemporaryAttribute(
                    .foregroundColor, value: dimmed, forCharacterRange: range
                )
            }
        }

        /// Keep the caret vertically centred in the visible area.
        func centreCaretIfNeeded(in textView: NSTextView) {
            guard writingModes.typewriter,
                  let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer
            else { return }

            let caret = layoutManager.boundingRect(
                forGlyphRange: textView.selectedRange(), in: container
            )
            let visibleHeight = scrollView.contentView.bounds.height
            let target = caret.midY + textView.textContainerInset.height - visibleHeight / 2
            let maxOffset = max(0, textView.frame.height - visibleHeight)
            let clamped = min(max(0, target), maxOffset)

            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            applyWritingModes(to: textView)
            centreCaretIfNeeded(in: textView)
        }

        /// Scroll to a heading the sidebar selected, once per request token.
        private var lastJumpToken: Int?

        func performJumpIfNeeded(_ jump: HeadingJump?, in textView: NSTextView) {
            guard let jump, jump.token != lastJumpToken else { return }
            lastJumpToken = jump.token

            let length = (textView.string as NSString).length
            guard jump.range.location <= length else { return }
            let range = NSRange(
                location: jump.range.location,
                length: min(jump.range.length, length - jump.range.location)
            )
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            // Put the heading near the top rather than just barely on screen.
            if let layoutManager = textView.layoutManager,
               let container = textView.textContainer {
                let rect = layoutManager.boundingRect(forGlyphRange: range, in: container)
                let target = max(0, rect.minY - textView.textContainerInset.height)
                textView.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: target))
                textView.enclosingScrollView?.reflectScrolledClipView(
                    textView.enclosingScrollView!.contentView
                )
            }
        }

        /// Apply an edit through the undo-registering path so ⌘Z works normally.
        private func apply(_ edit: EditorBehavior.Edit, to textView: NSTextView) {
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement)
            else { return }
            textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(edit.selectedRange)
        }

        /// Formatting commands are broadcast to every window; only the frontmost
        /// window's editor should act on one.
        @MainActor @objc func applyFormatting(_ notification: Notification) {
            guard let textView,
                  textView.window?.isKeyWindow == true,
                  textView.isEditable,
                  let raw = notification.object as? String,
                  let action = MarkdownAction(rawValue: raw)
            else { return }

            let edit = formatter.apply(
                action, to: textView.string, selection: textView.selectedRange()
            )

            // Break coalescing so the formatting lands as its own undo step
            // rather than merging into whatever the user was typing.
            textView.breakUndoCoalescing()
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement)
            else { return }
            textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(edit.selectedRange)
            textView.breakUndoCoalescing()
        }

        @MainActor @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = textView?.enclosingScrollView else { return }
            let contentView = scrollView.contentView
            let documentView = scrollView.documentView!
            let visibleHeight = contentView.bounds.height
            let totalHeight = documentView.frame.height
            guard totalHeight > visibleHeight else { return }
            let scrollFraction = contentView.bounds.origin.y / (totalHeight - visibleHeight)
            parent.onScroll?(scrollFraction)
        }
    }
}

/// Custom NSTextView with scroll-past-end and editor features.
class MarkdownNSTextView: NSTextView {
    var scrollsPastEnd = true

    /// Where the document lives, so pasted images can be saved beside it.
    /// Nil for an unsaved document, which has nowhere to put them yet.
    var documentURL: URL?

    // MARK: - Image Paste and Drop

    /// Intercept image pastes and write them to the document's sidecar folder.
    ///
    /// This view is `isRichText` (the syntax highlighter needs attributed text),
    /// so without this an image would paste as a text attachment — invisible in
    /// the plain string we save, and silently lost. Turning it into a markdown
    /// link is both the useful behaviour and the safe one.
    override func paste(_ sender: Any?) {
        if handleImages(from: NSPasteboard.general) { return }
        super.pasteAsPlainText(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if handleImages(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    /// Save any images on `pasteboard` next to the document and insert links.
    /// Returns false if there were none, so normal handling can continue.
    private func handleImages(from pasteboard: NSPasteboard) -> Bool {
        let images = imagePayloads(from: pasteboard)
        guard !images.isEmpty else { return false }

        guard let documentURL else {
            presentUnsavedDocumentAlert()
            return true  // handled: pasting an attachment would be worse
        }

        let folder = ImageInsertion.assetsFolder(for: documentURL)
        let folderName = ImageInsertion.assetsFolderName(for: documentURL)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var links: [String] = []
        for payload in images {
            let name = ImageInsertion.uniqueFilename(
                base: payload.baseName, extension: payload.fileExtension, in: folder
            )
            let destination = folder.appendingPathComponent(name)
            guard (try? payload.data.write(to: destination, options: .atomic)) != nil else { continue }
            links.append(
                ImageInsertion.markdownLink(
                    fileName: name, folderName: folderName, altText: payload.altText
                )
            )
        }
        guard !links.isEmpty else { return false }

        let markdown = links.joined(separator: "\n")
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: markdown) else { return true }
        textStorage?.replaceCharacters(in: range, with: markdown)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (markdown as NSString).length, length: 0))
        return true
    }

    private struct ImagePayload {
        var data: Data
        var fileExtension: String
        var baseName: String
        var altText: String
    }

    private func imagePayloads(from pasteboard: NSPasteboard) -> [ImagePayload] {
        // Dragged files first: they carry a real name and their original bytes,
        // so we copy rather than re-encode and lose quality.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            let imageURLs = urls.filter {
                ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]
                    .contains($0.pathExtension.lowercased())
            }
            if !imageURLs.isEmpty {
                return imageURLs.compactMap { url -> ImagePayload? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    let base = url.deletingPathExtension().lastPathComponent
                    return ImagePayload(
                        data: data,
                        fileExtension: url.pathExtension.lowercased(),
                        baseName: base,
                        altText: base
                    )
                }
            }
        }

        // Otherwise an image on the clipboard: normalise to PNG.
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return [] }

        return [
            ImagePayload(
                data: png,
                fileExtension: "png",
                baseName: ImageInsertion.defaultBaseName(date: Date()),
                altText: ""
            )
        ]
    }

    private func presentUnsavedDocumentAlert() {
        let alert = NSAlert()
        alert.messageText = "Save the document first"
        alert.informativeText =
            "Images are saved in a folder next to the document, so this one needs a home on disk before you can add them."
        alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        var adjustedSize = newSize
        if scrollsPastEnd, let scrollView = enclosingScrollView {
            let visibleHeight = scrollView.contentSize.height
            let usedRect = layoutManager?.usedRect(for: textContainer!) ?? .zero
            let contentHeight = usedRect.height + 2 * textContainerInset.height
            let extraSpace = max(0, visibleHeight - 50) // Leave 50pt at bottom
            if contentHeight > visibleHeight {
                adjustedSize.height = max(adjustedSize.height, contentHeight + extraSpace)
            }
        }
        super.setFrameSize(adjustedSize)
    }
}

#else
import UIKit

/// UITextView-backed markdown editor for iOS with live syntax highlighting.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var highlightThemeName: String
    var lineSpacing: CGFloat
    var horizontalInset: CGFloat
    var verticalInset: CGFloat
    var isEditable: Bool
    var scrollsPastEnd: Bool
    var behaviorOptions: EditorBehavior.Options
    var writingModes: WritingModes
    var documentURL: URL?
    var jump: HeadingJump?
    var onScroll: ((CGFloat) -> Void)?
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textStorage = CodeAttributedString()
        textStorage.language = "markdown"
        textStorage.highlightr.setTheme(to: highlightThemeName)
        textStorage.highlightr.theme.codeFont = font

        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)

        let textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = font
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no

        let background = textStorage.highlightr.theme.themeBackgroundColor ?? .systemBackground
        textView.backgroundColor = background
        textView.tintColor = caretColor(for: background)

        textView.textContainerInset = UIEdgeInsets(
            top: verticalInset, left: horizontalInset,
            bottom: verticalInset, right: horizontalInset
        )

        textView.text = text
        textView.delegate = context.coordinator

        if scrollsPastEnd {
            textView.contentInset.bottom = 300
        }
        textView.keyboardDismissMode = .interactive

        context.coordinator.textView = textView
        context.coordinator.behavior.options = behaviorOptions
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.applyFormatting(_:)),
            name: .insertMarkdownFormatting,
            object: nil
        )

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard let textStorage = textView.textStorage as? CodeAttributedString else { return }

        if context.coordinator.themeName != highlightThemeName {
            textStorage.highlightr.setTheme(to: highlightThemeName)
            textStorage.highlightr.theme.codeFont = font
            context.coordinator.themeName = highlightThemeName
            let background = textStorage.highlightr.theme.themeBackgroundColor ?? .systemBackground
            textView.backgroundColor = background
            textView.tintColor = caretColor(for: background)
        }

        if textView.text != text {
            let selectedRange = textView.selectedRange
            textView.text = text
            textView.selectedRange = selectedRange
        }

        textView.font = font
        textView.textContainerInset = UIEdgeInsets(
            top: verticalInset, left: horizontalInset,
            bottom: verticalInset, right: horizontalInset
        )
        context.coordinator.behavior.options = behaviorOptions
        context.coordinator.writingModes = writingModes
        textView.documentURL = documentURL
        context.coordinator.performJumpIfNeeded(jump, in: textView)
        context.coordinator.applyWritingModes(to: textView)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: UITextView?
        var themeName: String
        private let formatter = MarkdownFormatter()
        var behavior = EditorBehavior()
        var writingModes = WritingModes()

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            self.themeName = parent.highlightThemeName
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChange?()
        }

        /// On iOS every insertion — Return, Tab, and ordinary characters —
        /// arrives here, so all three typing behaviors hang off this one hook.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let edit: EditorBehavior.Edit?
            switch text {
            case "\n":
                edit = behavior.newlineEdit(in: textView.text, selection: range)
            case "\t":
                edit = behavior.tabEdit(in: textView.text, selection: range, outdent: false)
            default:
                edit = behavior.insertionEdit(for: text, in: textView.text, selection: range)
            }

            guard let edit else { return true }
            apply(edit, to: textView)
            return false
        }

        private var lastJumpToken: Int?

        func performJumpIfNeeded(_ jump: HeadingJump?, in textView: UITextView) {
            guard let jump, jump.token != lastJumpToken else { return }
            lastJumpToken = jump.token

            let length = (textView.text as NSString).length
            guard jump.range.location <= length else { return }
            let range = NSRange(
                location: jump.range.location,
                length: min(jump.range.length, length - jump.range.location)
            )
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }

        /// Apply an edit through `replace(_:withText:)` so UIKit's undo stack stays intact.
        func apply(_ edit: EditorBehavior.Edit, to textView: UITextView) {
            guard let start = textView.position(
                    from: textView.beginningOfDocument, offset: edit.range.location
                  ),
                  let end = textView.position(from: start, offset: edit.range.length),
                  let textRange = textView.textRange(from: start, to: end)
            else { return }

            textView.replace(textRange, withText: edit.replacement)
            textView.selectedRange = edit.selectedRange
            textViewDidChange(textView)
        }

        @MainActor @objc func applyFormatting(_ notification: Notification) {
            guard let textView,
                  textView.window?.isKeyWindow == true,
                  textView.isEditable,
                  let raw = notification.object as? String,
                  let action = MarkdownAction(rawValue: raw)
            else { return }

            let edit = formatter.apply(
                action, to: textView.text, selection: textView.selectedRange
            )

            apply(edit, to: textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let contentHeight = scrollView.contentSize.height
            let visibleHeight = scrollView.bounds.height
            guard contentHeight > visibleHeight else { return }
            let offset = scrollView.contentOffset.y
            let scrollFraction = offset / (contentHeight - visibleHeight)
            parent.onScroll?(max(0, min(1, scrollFraction)))
        }
    }
}
#endif
