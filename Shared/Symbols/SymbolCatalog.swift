import Foundation

/// SF Symbols names with Apple's search keywords, extracted from macOS by `Scripts/gen_symbols.py`,
/// plus font icons merged in by `Scripts/add_phosphor.py` and `Scripts/build_extra_icons.py`.
struct SymbolCatalog {
    struct Symbol: Decodable, Identifiable, Hashable {
        let n: String
        let k: String
        let c: [String]
        /// Codepoints in a bundled icon font. Nil for SF Symbols.
        let p: [Int]?
        var id: String { n }
        var name: String { n }
        var displayName: String { FontIcons.displayName(n) }
    }

    struct Category: Decodable, Identifiable, Hashable {
        let key: String
        let icon: String
        var id: String { key }

        var title: String {
            Self.titles[key] ?? key.capitalized
        }

        private static let titles = [
            "objectsandtools": "Objects & Tools",
            "cameraandphotos": "Camera & Photos",
            "privacyandsecurity": "Privacy & Security",
            "textformatting": "Text Formatting",
            "clothing": "Clothing",
        ]
    }

    private struct File: Decodable {
        let categories: [Category]
        let symbols: [Symbol]
    }

    let categories: [Category]
    let symbols: [Symbol]
    let fontIconCodes: [String: [Int]]

    init(categories: [Category], symbols: [Symbol]) {
        self.categories = categories
        self.symbols = symbols
        fontIconCodes = Dictionary(uniqueKeysWithValues: symbols.compactMap { s in s.p.map { (s.n, $0) } })
    }

    static let shared: SymbolCatalog = {
        guard let url = Bundle.main.url(forResource: "symbols", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return SymbolCatalog(categories: [], symbols: []) }
        return SymbolCatalog(categories: file.categories, symbols: file.symbols)
    }()

    /// Every word of `query` must match the name or a keyword. Name prefix matches rank first.
    func search(_ query: String, category: String?) -> [Symbol] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        let pool = category.map { key in symbols.filter { $0.c.contains(key) } } ?? symbols
        guard !words.isEmpty else { return pool }
        let matches = pool.filter { symbol in
            words.allSatisfy { symbol.n.contains($0) || symbol.k.contains($0) }
        }
        let first = words[0]
        return matches.filter { $0.displayName.hasPrefix(first) } + matches.filter { !$0.displayName.hasPrefix(first) }
    }
}
