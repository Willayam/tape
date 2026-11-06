import Foundation

/// The printer's 32-byte status reply.
struct PrinterStatus: Equatable {
    struct RGB: Equatable {
        let r, g, b: UInt8
    }

    enum Kind: UInt8 {
        case reply = 0x00, printingCompleted = 0x01, error = 0x02, turnedOff = 0x04, notification = 0x05, phaseChange = 0x06
    }

    let model: UInt8
    let power: UInt8
    let errors: UInt16
    let tapeWidthMM: UInt8
    let mediaType: UInt8
    let tapeLengthMM: UInt8
    let kind: Kind?
    let phaseType: UInt8
    let phase: UInt16
    let tapeBackground: UInt8
    let tapeInk: UInt8

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count == 32, b[0] == 0x80, b[1] == 0x20, b[2] == 0x42 else { return nil }
        model = b[4]
        power = b[7]
        errors = UInt16(b[8]) << 8 | UInt16(b[9])
        tapeWidthMM = b[10]
        mediaType = b[11]
        tapeLengthMM = b[17]
        kind = Kind(rawValue: b[18])
        phaseType = b[19]
        phase = UInt16(b[20]) << 8 | UInt16(b[21])
        tapeBackground = b[24]
        tapeInk = b[25]
    }

    var isReady: Bool { errors == 0 && phaseType == 0 && phase == 0 }
    var tape: TapeWidth? { TapeWidth(statusWidth: tapeWidthMM) }
    var hasTape: Bool { mediaType != 0x00 && tapeWidthMM != 0 }

    var modelName: String { model == 0x72 ? "PT-P300BT" : String(format: "Printer 0x%02X", model) }

    /// Plain-language problems, worst first.
    var problems: [String] {
        let messages: [(bit: Int, text: String)] = [
            (8, "No tape loaded"),
            (0, "Replace the tape cassette"),
            (9, "The tape ran out or the label is too long"),
            (4, "The cover is open"),
            (5, "The printer is too hot. Let it cool down"),
            (11, "The batteries are low"),
            (12, "The printer is busy"),
            (10, "The tape is jammed"),
            (6, "The tape didn't feed"),
            (2, "Bluetooth transfer failed"),
            (3, "The printer's buffer is full"),
            (1, "The printer's buffer is full"),
            (7, "The printer reported a system error. Turn it off and on"),
            (13, "The printer isn't powered"),
        ]
        var seen = Set<String>()
        return messages.filter { errors & (1 << $0.bit) != 0 && seen.insert($0.text).inserted }.map(\.text)
    }

    var powerDescription: String? {
        switch power {
        case 0: "Battery full"
        case 1: "Battery half"
        case 2: "Battery low"
        case 3: "Battery critical"
        case 4: "AC adapter"
        default: nil
        }
    }

    var tapeDescription: String? {
        guard hasTape, let tape else { return nil }
        let colors = [Self.colorName(tapeInk), Self.colorName(tapeBackground)].compactMap { $0 }
        return colors.count == 2 ? "\(tape.title), \(colors[0]) on \(colors[1])" : tape.title
    }

    var backgroundRGB: RGB? { Self.backgrounds[tapeBackground]?.rgb }
    var inkRGB: RGB? { Self.inks[tapeInk]?.rgb }

    private static func colorName(_ code: UInt8) -> String? {
        (backgrounds[code] ?? inks[code])?.name.lowercased()
    }

    private static let backgrounds: [UInt8: (name: String, rgb: RGB)] = [
        0x01: ("White", RGB(r: 250, g: 250, b: 248)),
        0x03: ("Clear", RGB(r: 236, g: 240, b: 242)),
        0x04: ("Red", RGB(r: 214, g: 48, b: 49)),
        0x05: ("Blue", RGB(r: 40, g: 98, b: 196)),
        0x06: ("Yellow", RGB(r: 252, g: 220, b: 60)),
        0x07: ("Green", RGB(r: 60, g: 160, b: 90)),
        0x08: ("Black", RGB(r: 28, g: 28, b: 30)),
        0x09: ("Clear", RGB(r: 236, g: 240, b: 242)),
        0x20: ("Matte white", RGB(r: 244, g: 244, b: 240)),
        0x21: ("Matte clear", RGB(r: 232, g: 236, b: 238)),
        0x22: ("Matte silver", RGB(r: 196, g: 198, b: 200)),
        0x23: ("Satin gold", RGB(r: 212, g: 180, b: 110)),
        0x24: ("Satin silver", RGB(r: 200, g: 202, b: 206)),
        0x30: ("Blue", RGB(r: 40, g: 98, b: 196)),
        0x31: ("Red", RGB(r: 214, g: 48, b: 49)),
        0x40: ("Orange", RGB(r: 255, g: 140, b: 40)),
        0x41: ("Yellow", RGB(r: 240, g: 250, b: 60)),
        0x50: ("Pink", RGB(r: 232, g: 120, b: 160)),
        0x51: ("Gray", RGB(r: 200, g: 200, b: 204)),
        0x52: ("Lime", RGB(r: 170, g: 220, b: 90)),
        0x60: ("Yellow", RGB(r: 252, g: 220, b: 60)),
        0x61: ("Pink", RGB(r: 240, g: 150, b: 180)),
        0x62: ("Blue", RGB(r: 120, g: 180, b: 230)),
    ]

    private static let inks: [UInt8: (name: String, rgb: RGB)] = [
        0x01: ("White", RGB(r: 255, g: 255, b: 255)),
        0x04: ("Red", RGB(r: 200, g: 30, b: 40)),
        0x05: ("Blue", RGB(r: 30, g: 70, b: 170)),
        0x08: ("Black", RGB(r: 20, g: 20, b: 22)),
        0x0A: ("Gold", RGB(r: 190, g: 150, b: 70)),
    ]
}
