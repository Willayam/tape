import Foundation

enum PrinterError: LocalizedError {
    case notPaired(String)
    case connectFailed(String)
    case noReply
    case notReady([String])
    case tapeMismatch(loaded: TapeWidth, label: TapeWidth)
    case noTape
    case disconnected
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notPaired(let detail): detail
        case .connectFailed(let detail): detail
        case .noReply: "The printer didn't answer. Check that it's on, then try again."
        case .notReady(let problems): problems.first ?? "The printer isn't ready."
        case .tapeMismatch(let loaded, let label): "\(loaded.title) tape is loaded, but this label is set up for \(label.title)."
        case .noTape: "No tape loaded."
        case .disconnected: "The printer disconnected."
        case .timedOut: "The printer stopped responding during the print."
        }
    }
}

/// A byte pipe to the printer. Subclasses open the platform transport and call `receive(_:)`
/// when bytes arrive; this class turns those callbacks into awaitable reads.
@MainActor
class ByteLink: NSObject {
    private var received = Data()
    private var waiter: (count: Int, token: UUID, continuation: CheckedContinuation<Data, Never>)?

    var isOpen: Bool { false }
    func open() async throws { fatalError("subclass") }
    func write(_ data: Data) async throws { fatalError("subclass") }
    func close() {}

    func receive(_ data: Data) {
        received += data
        if let waiter, received.count >= waiter.count {
            self.waiter = nil
            waiter.continuation.resume(returning: take(waiter.count))
        }
    }

    func discardReceived() { received.removeAll() }

    /// Waits for `count` bytes. Returns fewer if `timeout` passes first.
    func read(_ count: Int, timeout: Duration) async -> Data {
        if received.count >= count { return take(count) }
        let token = UUID()
        return await withCheckedContinuation { continuation in
            waiter = (count, token, continuation)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard let waiter = self.waiter, waiter.token == token else { return }
                self.waiter = nil
                waiter.continuation.resume(returning: self.take(self.received.count))
            }
        }
    }

    /// Wakes a pending read when the transport goes away.
    func didDisconnect() {
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: take(received.count))
        }
    }

    private func take(_ count: Int) -> Data {
        let n = min(count, received.count)
        let out = received.prefix(n)
        received.removeFirst(n)
        return Data(out)
    }
}
