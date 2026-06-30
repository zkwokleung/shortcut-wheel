import AppKit
import SwiftUI

/// Inline control that replaces the free-text SF Symbol field: shows the current
/// icon and opens a searchable grid palette on click.
struct SymbolPickerButton: View {
    @Binding var symbol: String?
    let tint: Color

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol ?? "circle")
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(symbol ?? "No icon")
                    .foregroundStyle(symbol == nil ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 140, alignment: .leading)
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SymbolPickerContent(symbol: $symbol, tint: tint, isPresented: $isPresented)
        }
    }
}

private struct SymbolPickerContent: View {
    @Binding var symbol: String?
    let tint: Color
    @Binding var isPresented: Bool

    @State private var query = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8)

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search symbols…", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4, pinnedViews: .sectionHeaders) {
                    clearCell
                    if query.isEmpty {
                        ForEach(SymbolCatalog.groups, id: \.name) { group in
                            Section {
                                ForEach(group.symbols, id: \.self) { cell($0) }
                            } header: {
                                sectionHeader(group.name)
                            }
                        }
                    } else {
                        ForEach(matches, id: \.self) { cell($0) }
                    }
                }
            }

            if !query.isEmpty && matches.isEmpty {
                Text("No matching symbols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(width: 320, height: 360)
    }

    private var clearCell: some View {
        Button {
            symbol = nil
            isPresented = false
        } label: {
            Image(systemName: "slash.circle")
                .frame(width: 30, height: 30)
                .background(symbol == nil ? Color.accentColor.opacity(0.2) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("No icon")
    }

    private func cell(_ name: String) -> some View {
        Button {
            symbol = name
            isPresented = false
        } label: {
            Image(systemName: name)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(symbol == name ? Color.accentColor.opacity(0.2) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .gridCellColumns(8)
    }

    /// Catalog symbols containing the query, plus the raw query itself when it
    /// resolves to a real SF Symbol — the escape hatch to the full library.
    private var matches: [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var result = SymbolCatalog.all.filter { $0.contains(q) }
        if NSImage(systemSymbolName: q, accessibilityDescription: nil) != nil, !result.contains(q) {
            result.insert(q, at: 0)
        }
        return result
    }
}

enum SymbolCatalog {
    struct Group {
        let name: String
        let symbols: [String]
    }

    static let groups: [Group] = [
        Group(name: "Common", symbols: [
            "star", "star.fill", "heart", "heart.fill", "bolt", "bolt.fill",
            "flag", "flag.fill", "bell", "bell.fill", "tag", "tag.fill",
            "bookmark", "bookmark.fill", "pin", "pin.fill", "circle", "circle.fill",
            "checkmark", "checkmark.circle", "xmark", "xmark.circle", "plus", "minus",
        ]),
        Group(name: "Text & Editing", symbols: [
            "doc", "doc.fill", "doc.on.doc", "doc.text", "square.and.pencil", "pencil",
            "scissors", "highlighter", "text.alignleft", "text.aligncenter", "list.bullet",
            "list.number", "textformat", "bold", "italic", "underline", "trash", "trash.fill",
        ]),
        Group(name: "Navigation", symbols: [
            "magnifyingglass", "arrow.left", "arrow.right", "arrow.up", "arrow.down",
            "arrow.uturn.left", "arrow.uturn.right", "chevron.left", "chevron.right",
            "house", "house.fill", "location", "location.fill", "map", "map.fill",
            "arrow.clockwise", "arrow.counterclockwise", "arrow.up.arrow.down",
        ]),
        Group(name: "Communication", symbols: [
            "envelope", "envelope.fill", "paperplane", "paperplane.fill", "message",
            "message.fill", "bubble.left", "phone", "phone.fill", "video", "video.fill",
            "person", "person.fill", "person.2", "at", "link",
        ]),
        Group(name: "Media", symbols: [
            "play", "play.fill", "pause", "pause.fill", "stop", "stop.fill",
            "forward", "backward", "speaker.wave.2", "speaker.slash", "music.note",
            "camera", "camera.fill", "photo", "photo.fill", "mic", "mic.fill",
        ]),
        Group(name: "Files & Folders", symbols: [
            "folder", "folder.fill", "tray", "tray.full", "archivebox", "externaldrive",
            "internaldrive", "square.and.arrow.up", "square.and.arrow.down", "paperclip",
            "doc.zipper", "books.vertical",
        ]),
        Group(name: "Devices & System", symbols: [
            "desktopcomputer", "laptopcomputer", "keyboard", "printer", "display",
            "iphone", "ipad", "applewatch", "headphones", "wifi", "antenna.radiowaves.left.and.right",
            "gearshape", "gearshape.fill", "switch.2", "slider.horizontal.3",
            "lock", "lock.fill", "lock.open", "power", "terminal", "terminal.fill",
        ]),
        Group(name: "Web & Apps", symbols: [
            "safari", "safari.fill", "globe", "network", "cloud", "cloud.fill",
            "calendar", "clock", "clock.fill", "alarm", "timer", "stopwatch",
            "cart", "cart.fill", "creditcard", "wallet.pass", "command", "option",
        ]),
    ]

    static let all: [String] = groups.flatMap(\.symbols)
}
