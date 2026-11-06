import Foundation

/// Brother's P-touch raster command set (PTCBP), as the PT-P300BT speaks it over Bluetooth serial.
/// Byte layout follows https://github.com/Ircama/PT-P300BT, which prints on this model.
enum PTCBP {
    static let headDots = 128
    static let bytesPerLine = headDots / 8

    /// Clears a half-received job, wakes the printer and switches it to raster mode.
    static let reset: Data = Data(repeating: 0, count: 64) + [0x1B, 0x40] + [0x1B, 0x69, 0x61, 0x01]
    static let statusRequest = Data([0x1B, 0x69, 0x53])
    static let printAndFeed = Data([0x1A])

    /// Everything up to the print command: setup followed by one command per raster line.
    static func job(lines: [[UInt8]], mediaType: UInt8, widthMM: UInt8, lengthMM: UInt8,
                    endMarginDots: UInt16 = 0, compress: Bool = true) -> Data {
        var out = reset
        out += printInformation(mediaType: mediaType, widthMM: widthMM, lengthMM: lengthMM, lineCount: UInt32(lines.count))
        out += [0x1B, 0x69, 0x4B, 0x08]  // advanced mode: no page chaining
        out += [0x1B, 0x69, 0x4D, 0x00]  // mode: no auto cut, no mirror
        out += [0x1B, 0x69, 0x64, UInt8(endMarginDots & 0xFF), UInt8(endMarginDots >> 8)]
        out += [0x4D, compress ? 0x02 : 0x00]
        for line in lines {
            out += rasterLine(line, compress: compress)
        }
        return out
    }

    static func printInformation(mediaType: UInt8, widthMM: UInt8, lengthMM: UInt8, lineCount: UInt32) -> Data {
        // Valid fields: width, quality, recovery.
        var out = Data([0x1B, 0x69, 0x7A, 0xC4, mediaType, widthMM, lengthMM])
        withUnsafeBytes(of: lineCount.littleEndian) { out += $0 }
        out += [0x00, 0x00]
        return out
    }

    static func rasterLine(_ line: [UInt8], compress: Bool) -> Data {
        if line.allSatisfy({ $0 == 0 }) { return Data([0x5A]) }
        let payload = compress ? packBits(line) : line
        return Data([0x47, UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + payload)
    }

    /// Turns a label image into raster lines. Column `x` of the image becomes line `x`,
    /// and the image's rows sit centered on the 128-dot head, top row on the lowest pin.
    static func rasterLines(width: Int, height: Int, ink: (_ x: Int, _ y: Int) -> Bool) -> [[UInt8]] {
        let offset = (headDots - height) / 2
        return (0..<width).map { x in
            var line = [UInt8](repeating: 0, count: bytesPerLine)
            for y in 0..<height where ink(x, y) {
                let pin = offset + y
                line[pin / 8] |= 0x80 >> UInt8(pin % 8)
            }
            return line
        }
    }

    /// TIFF PackBits, matching the encoder the reference tool uses.
    static func packBits(_ data: [UInt8]) -> [UInt8] {
        guard data.count > 1 else { return data.isEmpty ? [] : [0x00] + data }
        let maxLength = 127
        var result: [UInt8] = []
        var raw: [UInt8] = []
        var repeatCount = 0
        var inRun = false
        var pos = 0

        func finishRaw() {
            guard !raw.isEmpty else { return }
            result.append(UInt8(raw.count - 1))
            result += raw
            raw.removeAll()
        }
        func finishRun() {
            result.append(UInt8(256 - (repeatCount - 1)))
            result.append(data[pos])
        }

        while pos < data.count - 1 {
            if data[pos] == data[pos + 1] {
                if !inRun {
                    finishRaw()
                    inRun = true
                    repeatCount = 1
                } else {
                    if repeatCount == maxLength {
                        finishRun()
                        repeatCount = 0
                    }
                    repeatCount += 1
                }
            } else if inRun {
                repeatCount += 1
                finishRun()
                inRun = false
                repeatCount = 0
            } else {
                if raw.count == maxLength { finishRaw() }
                raw.append(data[pos])
            }
            pos += 1
        }
        if inRun {
            repeatCount += 1
            finishRun()
        } else {
            raw.append(data[pos])
            finishRaw()
        }
        return result
    }
}
