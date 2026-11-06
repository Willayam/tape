import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformFontDescriptor = NSFontDescriptor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformFontDescriptor = UIFontDescriptor
#endif

/// Lets the editor's surroundings (the symbol button, the picker) act on the text view.
@MainActor
final class EditorController {
    var insertSymbol: (String) -> Void = { _ in }
    var focus: () -> Void = {}
    /// Set by the editor screen. The keyboard bar on iPhone calls it.
    var showSymbolPicker: () -> Void = {}
    var editingChanged: (Bool) -> Void = { _ in }
}

/// An inline SF Symbol or font icon in the editor. It behaves like one character:
/// the cursor steps over it and backspace deletes it.
final class SymbolAttachment: NSTextAttachment {
    let symbolName: String

    init(symbolName: String, font: PlatformFont, weight: LabelWeight) {
        self.symbolName = symbolName
        super.init(data: nil, ofType: nil)
        if let glyph = FontIcons.glyph(symbolName, weight: weight) {
            useFontIcon(glyph, font: font)
            return
        }
        #if os(macOS)
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: weight.platformWeight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName)?
            .withSymbolConfiguration(configuration)
        #else
        image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(font: font))?
            .withTintColor(.label, renderingMode: .alwaysOriginal)
        #endif
        if let size = image?.size {
            bounds = CGRect(x: 0, y: ((font.capHeight - size.height) / 2).rounded(), width: size.width, height: size.height)
        }
    }

    /// Draws the glyph as an image, placed where the label renderer puts it.
    private func useFontIcon(_ glyph: FontIcons.Glyph, font: PlatformFont) {
        let size = font.pointSize * FontIcons.scale
        guard let iconFont = PlatformFont(name: glyph.fontName, size: size) else { return }
        let box = CGSize(width: size, height: size)
        #if os(macOS)
        // The font's line box is exactly one em, so drawing from the top-left corner fills the image.
        image = NSImage(size: box, flipped: true) { _ in
            NSAttributedString(string: glyph.character, attributes: [.font: iconFont, .foregroundColor: NSColor.labelColor])
                .draw(at: .zero)
            return true
        }
        #else
        image = UIGraphicsImageRenderer(size: box).image { _ in
            NSAttributedString(string: glyph.character, attributes: [.font: iconFont, .foregroundColor: UIColor.black])
                .draw(at: .zero)
        }
        .withTintColor(.label, renderingMode: .alwaysOriginal)
        #endif
        bounds = CGRect(x: 0, y: iconFont.descender + FontIcons.baselineOffset(fontSize: font.pointSize),
                        width: size, height: size)
    }

    required init?(coder: NSCoder) { fatalError("SymbolAttachment is never archived") }
}

extension LabelWeight {
    var platformWeight: PlatformFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

/// Converts between the label model and the editor's attributed text.
enum LabelText {
    static func font(_ font: LabelFont, weight: LabelWeight, size: CGFloat) -> PlatformFont {
        let width: PlatformFont.Width = font == .condensed ? .condensed : .standard
        let base = PlatformFont.systemFont(ofSize: size, weight: weight.platformWeight, width: width)
        let design: PlatformFontDescriptor.SystemDesign = switch font {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        case .standard, .condensed: .default
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        #if os(macOS)
        return NSFont(descriptor: descriptor, size: size) ?? base
        #else
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }

    static func attributes(_ font: PlatformFont) -> [NSAttributedString.Key: Any] {
        #if os(macOS)
        [.font: font, .foregroundColor: NSColor.labelColor]
        #else
        [.font: font, .foregroundColor: UIColor.label]
        #endif
    }

    static func symbol(_ name: String, font: PlatformFont, weight: LabelWeight) -> NSAttributedString {
        let string = NSMutableAttributedString(attachment: SymbolAttachment(symbolName: name, font: font, weight: weight))
        string.addAttributes(attributes(font), range: NSRange(location: 0, length: string.length))
        return string
    }

    static func attributed(_ lines: [LabelLine], font: PlatformFont, weight: LabelWeight) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let attrs = attributes(font)
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: attrs)) }
            for segment in line {
                switch segment {
                case .text(let string): result.append(NSAttributedString(string: string, attributes: attrs))
                case .symbol(let name): result.append(symbol(name, font: font, weight: weight))
                }
            }
        }
        return result
    }

    static func lines(from text: NSAttributedString) -> [LabelLine] {
        var lines: [LabelLine] = [[]]
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if let attachment = attributes[.attachment] as? SymbolAttachment {
                lines[lines.count - 1].append(.symbol(attachment.symbolName))
                return
            }
            let chunk = string.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            for (index, part) in chunk.components(separatedBy: .newlines).enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty { lines[lines.count - 1].append(.text(part)) }
            }
        }
        return normalized(lines)
    }

    /// Joins neighbouring text and drops empty text, so equal labels compare equal.
    static func normalized(_ lines: [LabelLine]) -> [LabelLine] {
        lines.map { line in
            var out: LabelLine = []
            for segment in line {
                switch (segment, out.last) {
                case (.text(let s), _) where s.isEmpty:
                    continue
                case (.text(let s), .text(let previous)?):
                    out[out.count - 1] = .text(previous + s)
                default:
                    out.append(segment)
                }
            }
            return out
        }
    }

    static func lineCount(of string: String) -> Int {
        string.components(separatedBy: .newlines).count
    }
}

#if os(iOS)
struct LabelTextView: UIViewRepresentable {
    @Binding var lines: [LabelLine]
    var font: LabelFont
    var weight: LabelWeight
    var maxLines: Int
    var controller: EditorController

    static let fontSize: CGFloat = 26

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 2, bottom: 10, right: 2)
        textView.delegate = context.coordinator
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.inputAccessoryView = context.coordinator.makeKeyboardBar()
        context.coordinator.textView = textView
        context.coordinator.sync(force: true)
        let coordinator = context.coordinator
        controller.insertSymbol = { [weak coordinator] in coordinator?.insert($0) }
        controller.focus = { [weak textView] in textView?.becomeFirstResponder() }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(force: false)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LabelTextView
        weak var textView: UITextView?
        private var styleKey = ""

        init(parent: LabelTextView) { self.parent = parent }

        private var platformFont: PlatformFont {
            LabelText.font(parent.font, weight: parent.weight, size: LabelTextView.fontSize)
        }

        func sync(force: Bool) {
            guard let textView, textView.markedTextRange == nil else { return }
            let key = "\(parent.font.rawValue)-\(parent.weight.rawValue)"
            let wanted = LabelText.normalized(parent.lines)
            guard force || key != styleKey || LabelText.lines(from: textView.attributedText) != wanted else { return }
            styleKey = key
            let selection = textView.selectedRange
            textView.attributedText = LabelText.attributed(wanted, font: platformFont, weight: parent.weight)
            textView.typingAttributes = LabelText.attributes(platformFont)
            let length = textView.attributedText.length
            textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }

        func insert(_ name: String) {
            guard let textView else { return }
            let symbol = LabelText.symbol(name, font: platformFont, weight: parent.weight)
            let range = textView.selectedRange
            textView.textStorage.replaceCharacters(in: range, with: symbol)
            textView.selectedRange = NSRange(location: range.location + symbol.length, length: 0)
            textView.typingAttributes = LabelText.attributes(platformFont)
            publish()
            textView.becomeFirstResponder()
        }

        private func publish() {
            guard let textView else { return }
            let lines = LabelText.lines(from: textView.attributedText)
            if lines != LabelText.normalized(parent.lines) { parent.lines = lines }
        }

        func textViewDidChange(_ textView: UITextView) { publish() }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.controller.editingChanged(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.controller.editingChanged(false) }

        func makeKeyboardBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            let symbol = UIBarButtonItem(
                title: "Symbol", image: UIImage(systemName: "star.square.on.square"),
                primaryAction: UIAction { [weak self] _ in self?.parent.controller.showSymbolPicker() }
            )
            let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
                self?.textView?.resignFirstResponder()
            })
            bar.items = [symbol, .flexibleSpace(), done]
            bar.sizeToFit()
            return bar
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text.rangeOfCharacter(from: .newlines) != nil else { return true }
            let result = (textView.text as NSString).replacingCharacters(in: range, with: text)
            return LabelText.lineCount(of: result) <= parent.maxLines
        }
    }
}
#else
struct LabelTextView: NSViewRepresentable {
    @Binding var lines: [LabelLine]
    var font: LabelFont
    var weight: LabelWeight
    var maxLines: Int
    var controller: EditorController

    static let fontSize: CGFloat = 24

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        let textView = scrollView.documentView as! NSTextView
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 10)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.sync(force: true)
        let coordinator = context.coordinator
        controller.insertSymbol = { [weak coordinator] in coordinator?.insert($0) }
        controller.focus = { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(force: false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LabelTextView
        weak var textView: NSTextView?
        private var styleKey = ""

        init(parent: LabelTextView) { self.parent = parent }

        private var platformFont: PlatformFont {
            LabelText.font(parent.font, weight: parent.weight, size: LabelTextView.fontSize)
        }

        func sync(force: Bool) {
            guard let textView, let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let key = "\(parent.font.rawValue)-\(parent.weight.rawValue)"
            let wanted = LabelText.normalized(parent.lines)
            guard force || key != styleKey || LabelText.lines(from: storage) != wanted else { return }
            styleKey = key
            let selection = textView.selectedRange()
            storage.setAttributedString(LabelText.attributed(wanted, font: platformFont, weight: parent.weight))
            textView.typingAttributes = LabelText.attributes(platformFont)
            textView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        }

        func insert(_ name: String) {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            let symbol = LabelText.symbol(name, font: platformFont, weight: parent.weight)
            textView.insertText(symbol, replacementRange: textView.selectedRange())
            textView.typingAttributes = LabelText.attributes(platformFont)
        }

        private func publish() {
            guard let storage = textView?.textStorage else { return }
            let lines = LabelText.lines(from: storage)
            if lines != LabelText.normalized(parent.lines) { parent.lines = lines }
        }

        func textDidChange(_ notification: Notification) { publish() }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard let text, text.rangeOfCharacter(from: .newlines) != nil else { return true }
            let result = (textView.string as NSString).replacingCharacters(in: range, with: text)
            return LabelText.lineCount(of: result) <= parent.maxLines
        }
    }
}
#endif
