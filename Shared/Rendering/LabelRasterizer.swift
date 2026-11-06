import SwiftUI

/// A one-bit image of the label. `width` runs along the tape, `height` across it.
struct LabelBitmap: Equatable {
    let width: Int
    let height: Int
    /// Row-major, top row first. `true` means the head burns a dot.
    let ink: [Bool]

    subscript(x: Int, y: Int) -> Bool { ink[y * width + x] }

    var lengthMM: Double { Double(width) / LabelDesign.dotsPerMM }

    /// Ink in `color`, everything else transparent, for drawing on a picture of the tape.
    func image(ink color: (r: UInt8, g: UInt8, b: UInt8)) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<ink.count where ink[i] {
            rgba[i * 4] = color.r
            rgba[i * 4 + 1] = color.g
            rgba[i * 4 + 2] = color.b
            rgba[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

@MainActor
enum LabelRasterizer {
    private static var cache: [LabelDesign: LabelBitmap] = [:]

    static func bitmap(for design: LabelDesign) -> LabelBitmap {
        let key = design.renderKey
        if let hit = cache[key] { return hit }
        let bitmap = render(design)
        if cache.count > 300 { cache.removeAll() }
        cache[key] = bitmap
        return bitmap
    }

    private static func render(_ design: LabelDesign) -> LabelBitmap {
        let height = design.tape.printableDots
        let renderer = ImageRenderer(content: LabelCanvas(design: design, layout: layout(for: design)))
        renderer.scale = 1
        guard let image = renderer.cgImage, image.width > 0 else {
            return LabelBitmap(width: 1, height: height, ink: Array(repeating: false, count: height))
        }
        return LabelBitmap(width: image.width, height: height, ink: threshold(image, height: height))
    }

    /// Sizes the text so the tallest line's ink fills its slot without touching the band's edge,
    /// then centers each line on its ink. A "p" tail or a tall icon shrinks the line instead of being cut off.
    static func layout(for design: LabelDesign) -> LabelCanvas.Layout {
        let slots = LabelCanvas.Slots(design)
        let inks = slots.lines.map { ink(of: $0, design: design) }
        // Two dots of clearance top and bottom absorb rounding when the measurement is scaled down.
        let room = slots.lineHeight - 4
        let fill = inks.map { room / $0.height * referenceSize }.min() ?? slots.lineHeight * 0.8
        let fontSize = fill * min(max(design.textScale, 0.3), 1)
        return LabelCanvas.Layout(
            fontSize: fontSize,
            offsets: inks.map { -$0.centerOffset * fontSize / referenceSize }
        )
    }

    private struct Ink {
        /// Height of the drawn pixels at `referenceSize`.
        let height: CGFloat
        /// How far the ink's middle sits below the middle of the line's layout box.
        let centerOffset: CGFloat
    }

    private static let referenceSize: CGFloat = 200
    private static var inkCache: [String: Ink] = [:]

    /// Renders a line large and finds the rows that hold ink. Text and icons scale linearly,
    /// so the result applies at any size.
    private static func ink(of line: LabelLine, design: LabelDesign) -> Ink {
        let key = "\(line)|\(design.font.rawValue)|\(design.weight.rawValue)"
        if let hit = inkCache[key] { return hit }
        let pad = referenceSize / 2
        let renderer = ImageRenderer(content:
            LabelCanvas.line(line, design: design, fontSize: referenceSize)
                .padding(pad)
                .foregroundStyle(.black)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1
        var result = Ink(height: referenceSize * 1.2, centerOffset: 0)
        if let image = renderer.cgImage {
            let rows = threshold(image, height: image.height)
            let width = image.width
            let inked = (0..<image.height).filter { y in rows[(y * width)..<((y + 1) * width)].contains(true) }
            if let top = inked.first, let bottom = inked.last {
                result = Ink(height: CGFloat(bottom - top + 1),
                             centerOffset: CGFloat(top + bottom + 1) / 2 - CGFloat(image.height) / 2)
            }
        }
        if inkCache.count > 500 { inkCache.removeAll() }
        inkCache[key] = result
        return result
    }

    /// Flattens the image onto white and marks pixels darker than mid-gray as ink.
    private static func threshold(_ image: CGImage, height: Int) -> [Bool] {
        let width = image.width
        var gray = [UInt8](repeating: 255, count: width * height)
        gray.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Pin the image's top edge to the top row in case the renderer rounds the height.
            context.draw(image, in: CGRect(x: 0, y: height - image.height, width: width, height: image.height))
        }
        return gray.map { $0 < 128 }
    }
}
