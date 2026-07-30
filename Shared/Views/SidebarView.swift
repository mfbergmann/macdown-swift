import SwiftUI

/// A request to scroll both panes to a particular heading.
///
/// Carries a token rather than being consumed on read: the text view and web
/// view each remember the last token they handled, so a repeat tap on the same
/// heading still scrolls, and neither pane has to mutate view state to clear it.
public struct HeadingJump: Equatable, Sendable {
    public var token: Int
    public var headingIndex: Int
    public var range: NSRange

    public init(token: Int, headingIndex: Int, range: NSRange) {
        self.token = token
        self.headingIndex = headingIndex
        self.range = range
    }
}

/// The document sidebar: an outline of the current file's headings, and the
/// other markdown files sitting next to it.
struct SidebarView: View {
    let outline: DocumentOutline
    let listing: FolderListing
    let currentFile: URL?
    let activeHeading: Heading?
    var onSelectHeading: (Heading) -> Void
    var onSelectFile: (URL) -> Void

    var body: some View {
        List {
            Section("Outline") {
                if outline.isEmpty {
                    Text("No headings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(outline.headings) { heading in
                        Button {
                            onSelectHeading(heading)
                        } label: {
                            Text(heading.title.isEmpty ? "Untitled" : heading.title)
                                .font(font(for: heading.level))
                                .foregroundStyle(
                                    heading.id == activeHeading?.id ? .primary : .secondary
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                                // Indent by level so the hierarchy reads at a glance.
                                .padding(.leading, CGFloat(heading.level - 1) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !listing.isEmpty {
                Section("Folder") {
                    ForEach(listing.entries) { entry in
                        if entry.isDirectory {
                            Label(entry.name, systemImage: "folder")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Button {
                                onSelectFile(entry.url)
                            } label: {
                                Label(entry.name, systemImage: "doc.text")
                                    .font(.callout)
                                    .fontWeight(isCurrent(entry.url) ? .semibold : .regular)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
    }

    private func isCurrent(_ url: URL) -> Bool {
        guard let currentFile else { return false }
        return url.standardizedFileURL == currentFile.standardizedFileURL
    }

    /// Bigger, heavier type for higher-level headings.
    private func font(for level: Int) -> Font {
        switch level {
        case 1: .callout.weight(.semibold)
        case 2: .callout
        default: .caption
        }
    }
}
