import SwiftUI

/// Adds, changes or removes the label's QR code.
struct QRCodeEditor: View {
    @Binding var qrCode: String?
    let tape: TapeWidth
    let close: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(qrCode: Binding<String?>, tape: TapeWidth, close: @escaping () -> Void) {
        _qrCode = qrCode
        self.tape = tape
        self.close = close
        _text = State(initialValue: qrCode.wrappedValue ?? "")
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let code = QRCode.make(trimmed)
        VStack(alignment: .leading, spacing: 16) {
            Text("QR code")
                .font(.title2.weight(.semibold))

            TextField("Web address or text", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .focused($focused)
                .onSubmit(save)

            HStack(alignment: .top, spacing: 14) {
                preview(code)
                Text(advice(code))
                    .font(.callout)
                    .foregroundStyle(code?.fits(tape) == true || trimmed.isEmpty ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if qrCode != nil {
                    Button("Remove", role: .destructive) {
                        qrCode = nil
                        close()
                    }
                }
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button(qrCode == nil ? "Add" : "Done", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code == nil)
            }
        }
        .padding(20)
        .onAppear { focused = true }
    }

    /// The code at the dots it will print with, scaled up.
    @ViewBuilder
    private func preview(_ code: QRCode?) -> some View {
        let side: CGFloat = 88
        if let code, let image = code.image(side: tape.printableDots) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: side, height: side)
                .padding(6)
                .background(.white, in: .rect(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.1)))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: side + 12, height: side + 12)
                .overlay(Image(systemName: "qrcode").font(.largeTitle).foregroundStyle(.tertiary))
        }
    }

    private func advice(_ code: QRCode?) -> String {
        guard let code else {
            return trimmed.isEmpty
                ? "Type a web address or any text. Shorter text gives bigger squares, which scan more easily."
                : "That's too long to print as a code a phone can read. Keep it under about 50 characters, for example with a short link."
        }
        guard code.fits(tape) else {
            return "On \(tape.title) tape the squares come out too small to scan. Use 12 mm tape."
        }
        let dots = Double(tape.printableDots) / Double(code.modules)
        var lines = ["\(code.modules) × \(code.modules) squares, about \(dots.formatted(.number.precision(.fractionLength(1)))) dots each."]
        if code.modules > 21 {
            lines.append("Shorter text gives bigger squares.")
        }
        return lines.joined(separator: " ")
    }

    private func save() {
        guard QRCode.make(trimmed) != nil else { return }
        qrCode = trimmed
        close()
    }
}
