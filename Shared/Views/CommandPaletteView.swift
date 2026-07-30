import SwiftUI

/// Fuzzy-searchable list of every command, opened with ⌘K.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFieldFocused: Bool

    private var matches: [PaletteCommand] {
        CommandPalette.filter(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Run a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($isFieldFocused)
                .onSubmit(runSelected)
                .onChange(of: query) { _, _ in selection = 0 }

            Divider()

            if matches.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                                row(command, isSelected: index == selection)
                                    .id(index)
                                    .onTapGesture { run(command) }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection) { _, new in
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 24)
        .onAppear { isFieldFocused = true }
        // Arrow keys move the selection while the text field keeps focus, so
        // you can keep typing without reaching for the mouse.
        .onKeyPress(.downArrow) {
            move(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func row(_ command: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(command.group)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(command.title)
                .lineLimit(1)
            Spacer()
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    private func move(by delta: Int) {
        guard !matches.isEmpty else { return }
        selection = (selection + delta + matches.count) % matches.count
    }

    private func runSelected() {
        guard matches.indices.contains(selection) else { return }
        run(matches[selection])
    }

    private func run(_ command: PaletteCommand) {
        // Dismiss first: the command may open a save panel or a sheet of its
        // own, which shouldn't have to fight the palette for focus.
        isPresented = false
        DispatchQueue.main.async { command.post() }
    }
}
