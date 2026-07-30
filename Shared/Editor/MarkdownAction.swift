import Foundation

/// A formatting action the user can invoke from the toolbar or a menu.
///
/// Carried as a raw value on the `.insertMarkdownFormatting` notification.
public enum MarkdownAction: String, CaseIterable, Sendable {
    // Inline
    case bold
    case italic
    case strikethrough
    case inlineCode

    // Headings
    case heading1
    case heading2
    case heading3

    // Blocks
    case codeBlock
    case bulletList
    case numberedList
    case taskItem
    case blockquote

    // Insertions
    case link
    case image
    case horizontalRule
    case table

    public var menuTitle: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .inlineCode: "Code"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .codeBlock: "Code Block"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .taskItem: "Task Item"
        case .blockquote: "Blockquote"
        case .link: "Link"
        case .image: "Image"
        case .horizontalRule: "Horizontal Rule"
        case .table: "Table"
        }
    }

    /// SF Symbol for toolbar buttons.
    public var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .heading1: "1.square"
        case .heading2: "2.square"
        case .heading3: "3.square"
        case .codeBlock: "curlybraces.square"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .taskItem: "checklist"
        case .blockquote: "text.quote"
        case .link: "link"
        case .image: "photo"
        case .horizontalRule: "minus"
        case .table: "tablecells"
        }
    }

    /// Actions offered in the document toolbar, in order.
    public static let toolbarActions: [MarkdownAction] = [
        .bold, .italic, .strikethrough, .inlineCode,
        .heading1, .heading2, .heading3,
        .bulletList, .numberedList, .taskItem, .blockquote,
        .link, .image, .codeBlock, .table,
    ]
}
