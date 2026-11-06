#if os(iOS)
import ExternalAccessory

/// Talks to the printer through iOS's accessory framework. The PT-P300BT is an MFi Bluetooth accessory,
/// so iOS only hands out a session for the protocol string listed in Info.plist.
final class AccessoryLink: ByteLink, StreamDelegate {
    static let protocolString = "com.brother.ptcbp"

    private var session: EASession?
    private var pendingOut = Data()
    private var writeContinuation: CheckedContinuation<Void, Error>?

    override var isOpen: Bool { session != nil }

    /// Shows the system sheet that pairs Bluetooth accessories.
    static func pair() async {
        await withCheckedContinuation { continuation in
            EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { _ in
                continuation.resume()
            }
        }
    }

    override func open() async throws {
        if session != nil { return }
        let accessories = EAAccessoryManager.shared().connectedAccessories
        guard let accessory = accessories.first(where: { $0.protocolStrings.contains(Self.protocolString) }) else {
            if let other = accessories.first(where: { $0.name.hasPrefix("PT-") || $0.manufacturer.contains("Brother") }) {
                throw PrinterError.connectFailed(
                    "\(other.name) is connected but offers \(other.protocolStrings.joined(separator: ", ")) instead of \(Self.protocolString)."
                )
            }
            throw PrinterError.notPaired("Turn the printer on. If it has never connected to this phone, tap Pair printer.")
        }
        guard let session = EASession(accessory: accessory, forProtocol: Self.protocolString) else {
            throw PrinterError.connectFailed("iOS wouldn't open a session with \(accessory.name). Turn the printer off and on.")
        }
        for stream in [session.inputStream as Stream?, session.outputStream] {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .default)
            stream?.open()
        }
        self.session = session
    }

    override func write(_ data: Data) async throws {
        guard session != nil else { throw PrinterError.disconnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingOut += data
            writeContinuation = continuation
            pump()
        }
    }

    override func close() {
        for stream in [session?.inputStream as Stream?, session?.outputStream] {
            stream?.delegate = nil
            stream?.close()
            stream?.remove(from: .main, forMode: .default)
        }
        session = nil
        pendingOut.removeAll()
        writeContinuation?.resume(throwing: PrinterError.disconnected)
        writeContinuation = nil
        didDisconnect()
    }

    private func pump() {
        guard let output = session?.outputStream else { return }
        while !pendingOut.isEmpty && output.hasSpaceAvailable {
            let written = pendingOut.withUnsafeBytes { buffer in
                output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
            }
            if written < 0 {
                close()
                return
            }
            if written == 0 { break }
            pendingOut.removeFirst(written)
        }
        if pendingOut.isEmpty, let pending = writeContinuation {
            writeContinuation = nil
            pending.resume()
        }
    }

    private func drainInput() {
        guard let input = session?.inputStream else { return }
        var buffer = [UInt8](repeating: 0, count: 256)
        while input.hasBytesAvailable {
            let count = input.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            receive(Data(buffer[0..<count]))
        }
    }

    // The streams run on the main run loop, so these arrive on the main thread.
    nonisolated func stream(_ stream: Stream, handle event: Stream.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .hasBytesAvailable: drainInput()
            case .hasSpaceAvailable: pump()
            case .errorOccurred, .endEncountered: close()
            default: break
            }
        }
    }
}
#endif
