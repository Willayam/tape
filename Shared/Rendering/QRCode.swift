import CoreImage
import CoreGraphics

/// A QR code sized for the tape. Fewer squares means bigger squares, and bigger squares scan
/// more reliably, so the encoder picks the smallest code that holds the text.
struct QRCode: Equatable {
    enum Correction: String, CaseIterable {
        case high = "H", quartile = "Q", medium = "M", low = "L"
    }

    /// Squares per side, without the blank border.
    let modules: Int
    let correction: Correction
    /// Top row first. `true` is a dark square.
    let squares: [[Bool]]

    /// 29 squares across is the largest code a phone read on a test print of 12 mm tape.
    /// The next size up, 33, would leave some squares one dot wide.
    static let maxModules = 29

    /// The printer needs at least two dots per square for a phone to tell them apart.
    static let minDotsPerModule = 2.0

    /// The smallest code for `text`, with the most error correction that keeps it that small.
    /// Nil when the text is empty or too long to print reliably.
    static func make(_ text: String) -> QRCode? {
        if let hit = cache[text] { return hit }
        guard !text.isEmpty else { return nil }
        let candidates = Correction.allCases.compactMap { level in
            squares(for: text, correction: level).map { QRCode(modules: $0.count, correction: level, squares: $0) }
        }
        // allCases runs from most to least correction, so the first of the smallest wins.
        let smallest = candidates.map(\.modules).min()
        let code = candidates.first { $0.modules == smallest && $0.modules <= maxModules }
        if cache.count > 100 { cache.removeAll() }
        cache[text] = code
        return code
    }

    nonisolated(unsafe) private static var cache: [String: QRCode?] = [:]

    /// Whether the code's squares come out big enough to scan on this tape.
    func fits(_ tape: TapeWidth) -> Bool {
        Double(tape.printableDots) / Double(modules) >= Self.minDotsPerModule
    }

    /// The code stretched to `side` dots, black on white. The printer only has whole dots,
    /// so a square comes out one dot wider or narrower depending on where it falls.
    func image(side: Int) -> CGImage? {
        var gray = [UInt8](repeating: 255, count: side * side)
        for y in 0..<side {
            let row = squares[y * modules / side]
            for x in 0..<side where row[x * modules / side] {
                gray[y * side + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// Asks Core Image for the code and crops the blank border it adds.
    private static func squares(for text: String, correction: Correction) -> [[Bool]]? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let image = context.createCGImage(output, from: output.extent)
        else { return nil }
        let width = image.width, height = image.height
        var gray = [UInt8](repeating: 255, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let rows = (0..<height).map { y in (0..<width).map { gray[y * width + $0] < 128 } }
        let usedRows = rows.indices.filter { rows[$0].contains(true) }
        let usedColumns = (0..<width).filter { x in rows.contains { $0[x] } }
        guard let top = usedRows.first, let bottom = usedRows.last,
              let left = usedColumns.first, let right = usedColumns.last,
              bottom - top == right - left
        else { return nil }
        return rows[top...bottom].map { Array($0[left...right]) }
    }

    nonisolated(unsafe) private static let context = CIContext()
}
