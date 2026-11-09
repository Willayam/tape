import SwiftUI

struct ContentView: View {
    @Environment(LabelStore.self) private var store
    @Environment(PrinterSession.self) private var printer
    @State private var selection: LabelDesign.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.labels) { label in
                    LabelRow(design: label)
                        .tag(label.id)
                        .contextMenu {
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                selection = store.duplicate(label.id)?.id
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete([label.id])
                            }
                        }
                }
                .onDelete { offsets in
                    delete(Set(offsets.map { store.labels[$0].id }))
                }
            }
            .navigationTitle("Labels")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .onDeleteCommand { if let selection { delete([selection]) } }
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New label", systemImage: "plus", action: newLabel)
                        .keyboardShortcut("n")
                }
            }
        } detail: {
            if let selection, let binding = binding(for: selection) {
                LabelEditorView(design: binding)
                    .id(selection)
            } else {
                ContentUnavailableView {
                    Label("No label selected", systemImage: "tag")
                } actions: {
                    Button("New label", action: newLabel)
                }
            }
        }
        .task {
            #if os(macOS)
            if selection == nil { selection = store.labels.first?.id }
            #endif
            // The first Bluetooth call blocks the main thread until macOS's permission prompt
            // is answered, so let the window draw first.
            try? await Task.sleep(for: .milliseconds(400))
            await printer.refresh()
        }
    }

    private func newLabel() {
        selection = store.newLabel(tape: printer.status?.tape).id
    }

    private func delete(_ ids: Set<LabelDesign.ID>) {
        if let selection, ids.contains(selection) { self.selection = nil }
        store.delete(ids)
    }

    private func binding(for id: LabelDesign.ID) -> Binding<LabelDesign>? {
        guard store.labels.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.labels.first { $0.id == id } ?? LabelDesign() },
            set: { updated in
                guard let index = store.labels.firstIndex(where: { $0.id == id }) else { return }
                var copy = updated
                copy.modified = Date()
                store.labels[index] = copy
            }
        )
    }
}

private struct LabelRow: View {
    let design: LabelDesign

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TapePreview(design: design, maxScale: 0.6, showsCaption: false, alignment: .leading)
                .frame(height: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(design.tape.title) tape · \(Int(LabelRasterizer.bitmap(for: design).lengthMM.rounded())) mm long")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(design.title)
    }
}
