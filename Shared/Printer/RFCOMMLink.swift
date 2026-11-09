#if os(macOS)
import IOBluetooth

/// Talks to the paired printer over a Bluetooth serial (RFCOMM) channel.
/// Owning the channel directly avoids the /dev/cu.* bridge, which leaves the link half-open on recent macOS.
final class RFCOMMLink: ByteLink, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?

    override var isOpen: Bool { channel?.isOpen() ?? false }

    override func open() async throws {
        if isOpen { return }
        guard let address = await Self.pairedPrinterAddress(),
              let device = IOBluetoothDevice(addressString: address)
        else {
            throw PrinterError.notPaired(
                "Pair the printer first. Turn it on, open System Settings › Bluetooth and connect to PT-P300BT."
            )
        }

        let channelID = await serialChannel(on: device)
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let newChannel else {
            throw PrinterError.connectFailed("Couldn't reach \(device.name ?? "the printer"). Is it turned on?")
        }
        channel = newChannel

        let token = UUID()
        openToken = token
        try await withCheckedThrowingContinuation { continuation in
            openContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                guard self.openToken == token, let pending = self.openContinuation else { return }
                self.openContinuation = nil
                self.close()
                pending.resume(throwing: PrinterError.connectFailed("The printer didn't accept the connection. Is it turned on?"))
            }
        }
    }

    private var openToken: UUID?

    /// The first IOBluetooth call waits for the user to answer macOS's Bluetooth permission prompt,
    /// so the lookup runs off the main thread. It returns an address rather than the device, because
    /// the channel has to be opened from a device made on the main thread to get its callbacks there.
    private nonisolated static func pairedPrinterAddress() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
                let printer = paired.first { ($0.name ?? "").hasPrefix("PT-P300") }
                    ?? paired.first { ($0.name ?? "").hasPrefix("PT-") }
                continuation.resume(returning: printer?.addressString)
            }
        }
    }

    /// The Serial Port Profile channel from the device's service record, or 1 when the record isn't cached.
    private func serialChannel(on device: IOBluetoothDevice) async -> BluetoothRFCOMMChannelID {
        let spp = IOBluetoothSDPUUID(uuid16: 0x1101)
        var record = device.getServiceRecord(for: spp)
        if record == nil {
            device.performSDPQuery(nil)
            for _ in 0..<30 where record == nil {
                try? await Task.sleep(for: .milliseconds(100))
                record = device.getServiceRecord(for: spp)
            }
        }
        var id: BluetoothRFCOMMChannelID = 0
        if let record, record.getRFCOMMChannelID(&id) == kIOReturnSuccess, id != 0 {
            return id
        }
        return 1
    }

    override func write(_ data: Data) async throws {
        var offset = data.startIndex
        while offset < data.endIndex {
            guard let channel, channel.isOpen() else { throw PrinterError.disconnected }
            let mtu = max(Int(channel.getMTU()), 64)
            let chunk = data[offset..<min(offset + mtu, data.endIndex)]
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk.count, alignment: 1)
            defer { buffer.deallocate() }
            chunk.copyBytes(to: UnsafeMutableRawBufferPointer(start: buffer, count: chunk.count))
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeContinuation = continuation
                if channel.writeAsync(buffer, length: UInt16(chunk.count), refcon: nil) != kIOReturnSuccess {
                    writeContinuation = nil
                    continuation.resume(throwing: PrinterError.disconnected)
                }
            }
            offset += chunk.count
        }
    }

    override func close() {
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        failPending()
    }

    private func failPending() {
        openContinuation?.resume(throwing: PrinterError.disconnected)
        openContinuation = nil
        writeContinuation?.resume(throwing: PrinterError.disconnected)
        writeContinuation = nil
        didDisconnect()
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate. IOBluetooth calls these on the main run loop.

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard let pending = openContinuation else { return }
            openContinuation = nil
            if error == kIOReturnSuccess {
                pending.resume()
            } else {
                channel = nil
                pending.resume(throwing: PrinterError.connectFailed("The Bluetooth connection failed (code \(error)). Turn the printer off and on, then try again."))
            }
        }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        MainActor.assumeIsolated { receive(data) }
    }

    nonisolated func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard let pending = writeContinuation else { return }
            writeContinuation = nil
            if error == kIOReturnSuccess { pending.resume() } else { pending.resume(throwing: PrinterError.disconnected) }
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            channel = nil
            failPending()
        }
    }
}
#endif
