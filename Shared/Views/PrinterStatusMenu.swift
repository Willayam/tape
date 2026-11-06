import SwiftUI

struct PrinterStatusMenu: View {
    @Environment(PrinterSession.self) private var printer

    var body: some View {
        Menu {
            if let status = printer.status {
                Text(status.modelName)
                if let tape = status.tapeDescription { Text(tape) } else { Text("No tape loaded") }
                if let power = status.powerDescription { Text(power) }
                ForEach(status.problems, id: \.self) { Text($0) }
            }
            if case .failed(let message) = printer.phase {
                Text(message)
            }
            Divider()
            Button("Reconnect", systemImage: "arrow.clockwise") {
                Task { await printer.refresh() }
            }
            .disabled(printer.isBusy)
            #if os(iOS)
            Button("Pair printer…", systemImage: "link") {
                Task {
                    await AccessoryLink.pair()
                    await printer.refresh()
                }
            }
            #endif
        } label: {
            Label {
                Text(summary)
            } icon: {
                Image(systemName: "printer")
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: 2)
                    }
            }
            #if os(macOS)
            .labelStyle(.titleAndIcon)
            #endif
        }
        .fixedSize()
        .help("Printer status")
    }

    private var connected: Bool {
        guard printer.status != nil else { return false }
        switch printer.lastError {
        case .notPaired, .connectFailed, .noReply, .disconnected: return false
        default: return true
        }
    }

    private var summary: String {
        switch printer.phase {
        case .connecting: return "Connecting…"
        case .printing: return "Printing…"
        default: break
        }
        guard connected, let status = printer.status else {
            return printer.status == nil && printer.phase == .idle ? "Connect printer" : "Not connected"
        }
        if !status.hasTape { return "No tape" }
        return "\(status.tape?.title ?? "\(status.tapeWidthMM) mm") tape"
    }

    private var dotColor: Color {
        if printer.isBusy { return .blue }
        guard connected, let status = printer.status else { return .gray }
        return status.isReady && status.hasTape ? .green : .orange
    }
}
