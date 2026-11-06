import Foundation
import Observation

@MainActor @Observable
final class LabelStore {
    var labels: [LabelDesign] = [] {
        didSet { scheduleSave() }
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL

    init() {
        let folder = URL.applicationSupportDirectory.appending(path: "Tape", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "labels.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([LabelDesign].self, from: data) {
            labels = saved
        }
        if labels.isEmpty {
            labels = Self.examples
        }
    }

    @discardableResult
    func newLabel(tape: TapeWidth?) -> LabelDesign {
        var label = LabelDesign()
        if let tape { label.tape = tape }
        labels.insert(label, at: 0)
        return label
    }

    func duplicate(_ id: LabelDesign.ID) -> LabelDesign? {
        guard let index = labels.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = labels[index]
        copy.id = UUID()
        copy.modified = Date()
        labels.insert(copy, at: index + 1)
        return copy
    }

    func delete(_ ids: Set<LabelDesign.ID>) {
        labels.removeAll { ids.contains($0.id) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = labels
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static let examples: [LabelDesign] = [
        LabelDesign(lines: [[.symbol("cable.connector"), .text(" USB-C")]]),
        LabelDesign(lines: [[.symbol("leaf.fill"), .text(" Basil")]], font: .serif, weight: .medium),
        LabelDesign(lines: [[.text("Spare keys "), .symbol("key.fill")]], style: .inverted),
        LabelDesign(lines: [[.symbol("shippingbox.fill"), .text(" Winter clothes")], [.text("Attic, shelf 2")]],
                    weight: .bold, alignment: .leading),
    ]
}
