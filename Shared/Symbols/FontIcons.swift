import CoreText
import Foundation

/// Icons drawn from bundled fonts, for things SF Symbols lacks, such as most clothing.
/// They live in the label model as `.symbol("<prefix><name>")`.
/// - `ph:` Phosphor (MIT, phosphoricons.com). `.fill` names use the filled style.
/// - `tp:` TapeIcons, extra clothing built by `Scripts/build_extra_icons.py` with Phosphor's
///   metrics and stroke widths, so both fonts follow the layout rule below.
enum FontIcons {
    struct Glyph {
        let character: String
        let fontName: String
    }

    private struct Library {
        let prefix: String
        let source: String
        let regular: String
        let bold: String
        let fill: String?
    }

    private static let libraries = [
        Library(prefix: "ph:", source: "Phosphor", regular: "Phosphor", bold: "Phosphor-Bold", fill: "Phosphor-Fill"),
        Library(prefix: "tp:", source: "Lucide Lab, Hugeicons, Iconoven",
                regular: "TapeIcons-Regular", bold: "TapeIcons-Bold", fill: nil),
    ]

    private static let fontFiles = [
        ("Phosphor", "ttf"), ("Phosphor-Bold", "ttf"), ("Phosphor-Fill", "ttf"),
        ("TapeIcons-Regular", "otf"), ("TapeIcons-Bold", "otf"),
    ]

    /// Size relative to the text. SF Symbols draw about 1.3 times the cap height, and these
    /// fonts leave padding inside the em box, so this is above 1 to match them.
    static let scale: CGFloat = 1.2

    /// Drops the glyph so its center sits on the middle of the capitals, as SF Symbols do.
    /// The glyphs span -1/16 to 15/16 of an em, so their center is 7/16 em above the baseline.
    static func baselineOffset(fontSize: CGFloat) -> CGFloat {
        (0.36 - 7.0 / 16.0 * scale) * fontSize
    }

    static func isFontIcon(_ name: String) -> Bool { library(for: name) != nil }

    static func displayName(_ name: String) -> String {
        library(for: name).map { String(name.dropFirst($0.prefix.count)) } ?? name
    }

    /// Where the icon comes from, for the picker's tooltip. Nil for SF Symbols.
    static func source(_ name: String) -> String? { library(for: name)?.source }

    static func glyph(_ name: String, weight: LabelWeight) -> Glyph? {
        guard let library = library(for: name), fontsRegistered,
              let codes = SymbolCatalog.shared.fontIconCodes[name], let first = codes.first
        else { return nil }
        if name.hasSuffix(".fill"), let fill = library.fill {
            return Glyph(character: character(first), fontName: fill)
        }
        let bold = codes.count > 1 && [.semibold, .bold, .heavy].contains(weight)
        return Glyph(character: character(bold ? codes[1] : first), fontName: bold ? library.bold : library.regular)
    }

    private static func library(for name: String) -> Library? {
        libraries.first { name.hasPrefix($0.prefix) }
    }

    private static func character(_ code: Int) -> String {
        Unicode.Scalar(code).map { String(Character($0)) } ?? ""
    }

    private static let fontsRegistered: Bool = {
        for (name, ext) in fontFiles {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return true
    }()
}
