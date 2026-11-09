import SwiftUI

/// TZe tape widths the PT-P300BT accepts.
enum TapeWidth: Int, Codable, CaseIterable, Identifiable {
    case mm3_5 = 4
    case mm6 = 6
    case mm9 = 9
    case mm12 = 12

    var id: Int { rawValue }

    var title: String { self == .mm3_5 ? "3.5 mm" : "\(rawValue) mm" }

    var millimeters: Double { self == .mm3_5 ? 3.5 : Double(rawValue) }

    /// Dots the head can print across this tape. 64 for 12 mm is measured on the PT-P300BT.
    /// The narrower widths follow Brother's P-touch raster spec and may need tuning on real tape.
    var printableDots: Int {
        switch self {
        case .mm3_5: 24
        case .mm6: 32
        case .mm9: 50
        case .mm12: 64
        }
    }

    /// The status reply reports 3.5 mm tape as 4.
    init?(statusWidth: UInt8) {
        self.init(rawValue: Int(statusWidth))
    }
}

enum Segment: Codable, Hashable {
    case text(String)
    case symbol(String)
}

typealias LabelLine = [Segment]

enum LabelFont: String, Codable, CaseIterable, Identifiable {
    case rounded, standard, condensed, serif, mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .standard: "Sans"
        case .condensed: "Condensed"
        case .serif: "Serif"
        case .mono: "Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .standard, .condensed: .default
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    var width: Font.Width { self == .condensed ? .condensed : .standard }
}

enum LabelWeight: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold, heavy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var weight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

enum LabelStyle: String, Codable, CaseIterable, Identifiable {
    case plain, outlined, inverted

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum LabelAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var symbol: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

struct LabelDesign: Codable, Hashable, Identifiable {
    var id = UUID()
    var modified = Date()
    var lines: [LabelLine] = [[.text("")]]
    var font: LabelFont = .rounded
    var weight: LabelWeight = .semibold
    var style: LabelStyle = .plain
    var alignment: LabelAlignment = .center
    var tape: TapeWidth = .mm12
    /// Fraction of the largest size that fits. 1 makes the tallest line's ink fill the printable band.
    /// Older labels may hold values above 1; the renderer caps them at 1 so nothing is cut off.
    var textScale: Double = 1.0
    var endPaddingMM: Double = 2
    var fixedLengthMM: Double?
    /// Text for a QR code printed at the start of the label, filling the printable band.
    var qrCode: String?

    static let dotsPerMM = 180.0 / 25.4

    var title: String {
        let text = lines.map { line in
            line.compactMap { if case .text(let s) = $0 { s } else { nil } }.joined()
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, let qrCode { return qrCode }
        return text.isEmpty ? "Untitled label" : text
    }

    var isEmpty: Bool {
        textIsEmpty && qrCode == nil
    }

    var textIsEmpty: Bool {
        lines.allSatisfy { line in
            line.allSatisfy {
                if case .text(let s) = $0 { s.trimmingCharacters(in: .whitespaces).isEmpty } else { false }
            }
        }
    }

    /// The design with identity stripped, so two labels that print the same share a cache entry.
    var renderKey: LabelDesign {
        var copy = self
        copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        copy.modified = .distantPast
        return copy
    }
}
