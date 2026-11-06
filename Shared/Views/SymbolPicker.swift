import SwiftUI

struct SymbolPicker: View {
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String?
    @AppStorage("recentSymbols") private var recentsRaw = ""
    @FocusState private var searchFocused: Bool

    private let catalog = SymbolCatalog.shared

    private var recents: [String] {
        recentsRaw.split(separator: ",").map(String.init)
    }

    private var results: [SymbolCatalog.Symbol] {
        catalog.search(query, category: category)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = results.first { pick(first.name) } }
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
            .padding([.horizontal, .top], 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, title: "All", icon: "square.grid.2x2")
                    ForEach(catalog.categories) { item in
                        categoryChip(item.key, title: item.title, icon: item.icon)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()

            ScrollView {
                if query.isEmpty, category == nil, !recents.isEmpty {
                    section("Recent", names: recents)
                }
                if results.isEmpty {
                    ContentUnavailableView.search(text: query).padding(.top, 40)
                } else {
                    section(query.isEmpty && category == nil ? "All symbols" : nil, names: results.map(\.name))
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    private func section(_ title: String?, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 4)], spacing: 4) {
                ForEach(names, id: \.self) { name in
                    Button { pick(name) } label: {
                        SymbolGlyph(name: name, size: 22)
                            .frame(width: 46, height: 46)
                            .contentShape(.rect)
                    }
                    .buttonStyle(SymbolCellStyle())
                    .help(FontIcons.source(name).map { "\(FontIcons.displayName(name)) (\($0))" } ?? name)
                    .accessibilityLabel(FontIcons.displayName(name))
                }
            }
        }
        .padding(12)
    }

    private func categoryChip(_ key: String?, title: String, icon: String) -> some View {
        let selected = category == key
        return Button { category = key } label: {
            Label(title, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.6)), in: .capsule)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private func pick(_ name: String) {
        var updated = recents.filter { $0 != name }
        updated.insert(name, at: 0)
        recentsRaw = updated.prefix(24).joined(separator: ",")
        onPick(name)
        dismiss()
    }
}

/// One icon from either library, sized like an SF Symbol at `size` points.
struct SymbolGlyph: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if let glyph = FontIcons.glyph(name, weight: .regular) {
            Text(verbatim: glyph.character)
                .font(.custom(glyph.fontName, fixedSize: size * FontIcons.scale))
                .baselineOffset(FontIcons.baselineOffset(fontSize: size))
        } else {
            Image(systemName: name).font(.system(size: size))
        }
    }
}

private struct SymbolCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SymbolCell(configuration: configuration)
    }

    private struct SymbolCell: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary.opacity(configuration.isPressed ? 0.15 : hovering ? 0.07 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}
