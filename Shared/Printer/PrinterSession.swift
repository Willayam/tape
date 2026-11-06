import SwiftUI

@MainActor @Observable
final class PrinterSession {
    enum Phase: Equatable {
        case idle
        case connecting
        case ready
        case printing(Double)
        case printed
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var status: PrinterStatus?
    private(set) var lastError: PrinterError?

    /// The Cube feeds this much blank tape before the first printed dot. It can't be trimmed.
    static let leaderMM = 25.0
    /// Print speed from Brother's spec sheet.
    static let speedMMPerSecond = 20.0

    @ObservationIgnored private let link: ByteLink = {
        #if os(macOS)
        RFCOMMLink()
        #else
        AccessoryLink()
        #endif
    }()

    var isBusy: Bool {
        switch phase {
        case .connecting, .printing: true
        default: false
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        phase = .connecting
        do {
            status = try await connectAndQuery()
            lastError = nil
            phase = .ready
        } catch {
            fail(error)
        }
    }

    func print(_ design: LabelDesign) async {
        guard !isBusy, !design.isEmpty else { return }
        let bitmap = LabelRasterizer.bitmap(for: design)
        phase = .printing(0)
        do {
            let status = try await connectAndQuery()
            self.status = status
            guard status.hasTape else { throw PrinterError.noTape }
            guard status.isReady else { throw PrinterError.notReady(status.problems) }
            if let loaded = status.tape, loaded != design.tape {
                throw PrinterError.tapeMismatch(loaded: loaded, label: design.tape)
            }

            let lines = PTCBP.rasterLines(width: bitmap.width, height: bitmap.height) { bitmap[$0, $1] }
            let job = PTCBP.job(lines: lines, mediaType: status.mediaType,
                                widthMM: status.tapeWidthMM, lengthMM: status.tapeLengthMM)
            var offset = job.startIndex
            while offset < job.endIndex {
                let end = min(offset + 512, job.endIndex)
                try await link.write(job[offset..<end])
                offset = end
                phase = .printing(0.3 * Double(offset) / Double(job.count))
            }

            link.discardReceived()
            try await link.write(PTCBP.printAndFeed)
            try await waitForCompletion(tapeMM: bitmap.lengthMM + Self.leaderMM)
            try? await link.write(PTCBP.reset)
            phase = .printed
            lastError = nil
            Task {
                try? await Task.sleep(for: .seconds(2))
                if phase == .printed { phase = .ready }
            }
        } catch {
            fail(error)
            link.close()
        }
    }

    private func connectAndQuery() async throws -> PrinterStatus {
        do {
            try await link.open()
            return try await queryStatus()
        } catch PrinterError.noReply, PrinterError.disconnected {
            // A link left over from a printer that slept or switched off. Reconnect once.
            link.close()
            try await link.open()
            return try await queryStatus()
        }
    }

    private func queryStatus() async throws -> PrinterStatus {
        // The first request after connecting is sometimes lost, so ask a few times.
        for _ in 0..<4 {
            link.discardReceived()
            try await link.write(PTCBP.reset + PTCBP.statusRequest)
            if let status = PrinterStatus(await link.read(32, timeout: .seconds(2))) {
                return status
            }
        }
        throw PrinterError.noReply
    }

    /// Reads status notifications until the printer says it finished.
    /// Closing the link before that leaves the PT-P300BT in an error state.
    private func waitForCompletion(tapeMM: Double) async throws {
        let expected = tapeMM / Self.speedMMPerSecond
        let start = ContinuousClock.now
        let deadline = start + .seconds(expected * 3 + 15)
        while ContinuousClock.now < deadline {
            let reply = await link.read(32, timeout: .milliseconds(250))
            let elapsed = (ContinuousClock.now - start) / .seconds(1)
            phase = .printing(0.3 + 0.69 * min(elapsed / expected, 1))
            guard reply.count == 32, let status = PrinterStatus(reply) else {
                if !link.isOpen { throw PrinterError.disconnected }
                continue
            }
            self.status = status
            switch status.kind {
            case .printingCompleted: return
            case .error: throw PrinterError.notReady(status.problems)
            case .turnedOff: throw PrinterError.disconnected
            default: continue
            }
        }
        throw PrinterError.timedOut
    }

    private func fail(_ error: Error) {
        let printerError = error as? PrinterError
        lastError = printerError
        phase = .failed(printerError?.errorDescription ?? error.localizedDescription)
    }
}
