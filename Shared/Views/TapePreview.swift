import SwiftUI

/// The label as it will come out of the printer, on a picture of the loaded tape.
struct TapePreview: View {
    let design: LabelDesign
    var status: PrinterStatus?
    var maxScale: CGFloat = 3
    var showsCaption = true
    var alignment: HorizontalAlignment = .center

    var body: some View {
        let bitmap = LabelRasterizer.bitmap(for: design)
        let tapeDots = (design.tape.millimeters * LabelDesign.dotsPerMM).rounded()
        let loaded = status?.hasTape == true && status?.tape == design.tape
        let background = (loaded ? status?.backgroundRGB : nil) ?? PrinterStatus.RGB(r: 250, g: 250, b: 248)
        let ink = (loaded ? status?.inkRGB : nil) ?? PrinterStatus.RGB(r: 20, g: 20, b: 22)
        let width = CGFloat(max(bitmap.width, design.isEmpty ? 280 : 1))

        VStack(alignment: alignment, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(rgb: background))
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                    }
                if design.isEmpty {
                    Text("Your label")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.black.opacity(0.25))
                } else if let image = bitmap.image(ink: (ink.r, ink.g, ink.b)) {
                    GeometryReader { geometry in
                        let scale = geometry.size.height / tapeDots
                        Image(decorative: image, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: geometry.size.width, height: CGFloat(bitmap.height) * scale)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
            .aspectRatio(width / tapeDots, contentMode: .fit)
            .frame(maxWidth: width * maxScale, maxHeight: tapeDots * maxScale, alignment: Alignment(horizontal: alignment, vertical: .center))
            .accessibilityElement()
            .accessibilityLabel("Label preview: \(design.title)")

            if showsCaption && !design.isEmpty {
                let length = Int(bitmap.lengthMM.rounded())
                let used = Int((bitmap.lengthMM + PrinterSession.leaderMM).rounded())
                Text("\(length) mm long, uses about \(used) mm of tape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

extension Color {
    init(rgb: PrinterStatus.RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
