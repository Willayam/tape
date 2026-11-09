import SwiftUI

/// The label drawn at print resolution, one point per printer dot.
/// The preview and the printer both rasterize this view, so they cannot disagree.
struct LabelCanvas: View {
    let design: LabelDesign
    /// Font size and per-line nudges that fit the ink to the printable band. See `LabelRasterizer.layout`.
    let layout: Layout

    struct Layout {
        var fontSize: CGFloat
        /// Moves each non-blank line so its ink, not its font's line box, is centered in its slot.
        var offsets: [CGFloat]
    }

    /// How the printable band divides into one slot per line.
    struct Slots {
        let height: CGFloat
        let lines: [LabelLine]
        let framed: Bool
        let inset: CGFloat
        let gap: CGFloat
        let lineHeight: CGFloat

        init(_ design: LabelDesign) {
            height = CGFloat(design.tape.printableDots)
            lines = design.lines.filter { !LabelCanvas.isBlank($0) }
            let count = max(lines.count, 1)
            framed = design.style != .plain
            inset = framed ? max(3, (height * 0.1).rounded()) : 0
            gap = count > 1 ? max(1, (height * 0.04).rounded()) : 0
            lineHeight = (height - inset * 2 - gap * CGFloat(count - 1)) / CGFloat(count)
        }
    }

    var body: some View {
        let slots = Slots(design)
        let height = slots.height
        let endPadding = (design.endPaddingMM * LabelDesign.dotsPerMM).rounded()
        let padding = endPadding + (slots.framed ? slots.inset + slots.lineHeight * 0.3 : 0)
        let qr = design.qrCode.flatMap(QRCode.make)
        let hasText = !slots.lines.isEmpty
        let side = Int(height)
        // Four squares of white between the code and the text, the quiet zone QR readers expect.
        let quietZone = qr.map { (CGFloat(side) * 4 / CGFloat($0.modules)).rounded(.up) } ?? 0
        // Plain text needs no padding of its own after the code. A frame keeps its padding inside.
        let qrTrailing = hasText ? (slots.framed ? quietZone : 0) : endPadding
        let qrWidth = qr == nil ? 0 : endPadding + CGFloat(side) + qrTrailing
        let fixedWidth = design.fixedLengthMM.map { CGFloat(($0 * LabelDesign.dotsPerMM).rounded()) }

        HStack(spacing: 0) {
            if let qr, let image = qr.image(side: side) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .frame(width: CGFloat(side), height: CGFloat(side))
                    .padding(.leading, endPadding)
                    .padding(.trailing, qrTrailing)
            }
            if hasText || qr == nil {
                VStack(alignment: design.alignment.horizontal, spacing: slots.gap) {
                    ForEach(Array(slots.lines.enumerated()), id: \.offset) { index, line in
                        Self.line(line, design: design, fontSize: layout.fontSize)
                            .offset(y: index < layout.offsets.count ? layout.offsets[index] : 0)
                            .frame(height: slots.lineHeight)
                    }
                }
                .padding(.leading, qr != nil && !slots.framed ? quietZone : padding)
                .padding(.trailing, padding)
                .frame(
                    minWidth: fixedWidth.map { max(0, $0 - qrWidth) },
                    alignment: Alignment(horizontal: design.alignment.horizontal, vertical: .center)
                )
                .frame(height: height)
                .foregroundStyle(design.style == .inverted ? Color.white : Color.black)
                .background { background(height: height) }
            }
        }
        .frame(minWidth: fixedWidth, alignment: .leading)
        .frame(height: height)
        .background(Color.white)
        .fixedSize(horizontal: true, vertical: false)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func background(height: CGFloat) -> some View {
        let radius = (height * 0.2).rounded()
        ZStack {
            Color.white
            switch design.style {
            case .plain:
                EmptyView()
            case .outlined:
                RoundedRectangle(cornerRadius: radius)
                    .inset(by: 1.5)
                    .stroke(Color.black, lineWidth: 3)
            case .inverted:
                RoundedRectangle(cornerRadius: radius).fill(Color.black)
            }
        }
    }

    /// One line of the label at `fontSize`, sized to its own content.
    static func line(_ line: LabelLine, design: LabelDesign, fontSize: CGFloat) -> some View {
        text(for: line, fontSize: fontSize, weight: design.weight)
            .font(.system(size: fontSize, weight: design.weight.weight, design: design.font.design))
            .fontWidth(design.font.width)
            .lineLimit(1)
            .fixedSize()
    }

    static func text(for line: LabelLine, fontSize: CGFloat, weight: LabelWeight) -> Text {
        line.reduce(Text(verbatim: "")) { result, segment in
            switch segment {
            case .text(let string):
                return Text("\(result)\(Text(verbatim: string))")
            case .symbol(let name):
                guard let glyph = FontIcons.glyph(name, weight: weight) else {
                    return Text("\(result)\(Image(systemName: name))")
                }
                let icon = Text(verbatim: glyph.character)
                    .font(.custom(glyph.fontName, fixedSize: fontSize * FontIcons.scale))
                    .baselineOffset(FontIcons.baselineOffset(fontSize: fontSize))
                return Text("\(result)\(icon)")
            }
        }
    }

    static func isBlank(_ line: LabelLine) -> Bool {
        line.allSatisfy {
            if case .text(let s) = $0 { s.trimmingCharacters(in: .whitespaces).isEmpty } else { false }
        }
    }
}
