import SwiftUI

struct LabelEditorView: View {
    @Binding var design: LabelDesign

    @Environment(PrinterSession.self) private var printer
    @State private var controller = EditorController()
    @State private var showingSymbols = false
    @State private var printRequested = false
    @State private var printError: String?
    @State private var editing = false
    @State private var showingQRCode = false

    private var maxLines: Int {
        switch design.tape {
        case .mm12: 3
        case .mm9: 2
        case .mm6, .mm3_5: 1
        }
    }

    private var usedLines: Int {
        design.lines.filter { !LabelCanvas.isBlank($0) }.count
    }

    var body: some View {
        Form {
            Section {
                TapePreview(design: design, status: printer.status)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .animation(.snappy(duration: 0.2), value: design.renderKey)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    LabelTextView(lines: $design.lines, font: design.font, weight: design.weight,
                                  maxLines: maxLines, controller: controller)
                        .frame(height: CGFloat(min(maxLines, usedLines + 1)) * LabelTextView.fontSize * 1.3 + 22)
                    if design.textIsEmpty {
                        Text("Type your label")
                            .font(.system(size: LabelTextView.fontSize, design: design.font.design))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 10)
                            .padding(.leading, 7)
                            .allowsHitTesting(false)
                    }
                }
                #if os(macOS)
                HStack(spacing: 8) {
                    symbolButton
                    qrButton
                }
                #else
                symbolButton
                qrButton
                #endif
            } header: {
                Text("Text")
            } footer: {
                if let code = design.qrCode.flatMap(QRCode.make), !code.fits(design.tape) {
                    Text("The QR code's squares come out too small to scan on \(design.tape.title) tape. Use 12 mm tape.")
                        .foregroundStyle(.red)
                } else {
                    Text(maxLines == 1 ? "This tape fits one line." : "Press Return for a new line. This tape fits \(maxLines).")
                }
            }

            Section("Style") {
                Picker("Font", selection: $design.font) {
                    ForEach(LabelFont.allCases) { Text($0.title).tag($0) }
                }
                Picker("Weight", selection: $design.weight) {
                    ForEach(LabelWeight.allCases) { Text($0.title).tag($0) }
                }
                Picker("Look", selection: $design.style) {
                    ForEach(LabelStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if usedLines > 1 || design.fixedLengthMM != nil {
                    Picker("Alignment", selection: $design.alignment) {
                        ForEach(LabelAlignment.allCases) {
                            Label($0.rawValue.capitalized, systemImage: $0.symbol).labelStyle(.iconOnly).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                LabeledContent("Size") {
                    Slider(value: $design.textScale, in: 0.5...1.0) {
                        Text("Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .labelsHidden()
                }
            }

            Section("Tape") {
                Picker("Width", selection: $design.tape) {
                    ForEach(TapeWidth.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper(value: $design.endPaddingMM, in: 0...20, step: 1) {
                    LabeledContent("Space at each end", value: "\(Int(design.endPaddingMM)) mm")
                }
                Toggle("Fixed length", isOn: fixedLengthEnabled)
                if let length = design.fixedLengthMM {
                    Stepper(value: fixedLength, in: 10...400, step: 5) {
                        LabeledContent("Length", value: "\(Int(length)) mm")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(design.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !editing {
                printButton
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                PrinterStatusMenu()
            }
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                printButton
                    .labelStyle(.titleOnly)
            }
            #endif
        }
        .onChange(of: printer.phase) { _, phase in
            guard printRequested else { return }
            switch phase {
            case .failed(let message):
                printRequested = false
                printError = message
            case .printed, .ready, .idle:
                printRequested = false
            default:
                break
            }
        }
        .alert("Couldn't print", isPresented: Binding(get: { printError != nil }, set: { if !$0 { printError = nil } })) {
            if case .tapeMismatch(let loaded, _)? = printer.lastError {
                Button("Print on \(loaded.title)") {
                    design.tape = loaded
                    startPrint()
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(printError ?? "")
        }
        .task {
            controller.showSymbolPicker = { showingSymbols = true }
            controller.editingChanged = { editing = $0 }
            if design.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                controller.focus()
            }
        }
    }

    @ViewBuilder
    private var symbolButton: some View {
        let button = Button {
            showingSymbols = true
        } label: {
            Label("Insert symbol", systemImage: "star.square.on.square")
        }
        .keyboardShortcut("k")
        #if os(macOS)
        button.popover(isPresented: $showingSymbols, arrowEdge: .bottom) {
            SymbolPicker { name in
                DispatchQueue.main.async { controller.insertSymbol(name) }
            }
            .frame(width: 460, height: 500)
        }
        #else
        button.sheet(isPresented: $showingSymbols) {
            SymbolPicker { name in
                DispatchQueue.main.async { controller.insertSymbol(name) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        #endif
    }

    @ViewBuilder
    private var qrButton: some View {
        let button = Button {
            showingQRCode = true
        } label: {
            Label(design.qrCode == nil ? "Add QR code" : "Edit QR code", systemImage: "qrcode")
        }
        let editor = QRCodeEditor(qrCode: $design.qrCode, tape: design.tape) { showingQRCode = false }
        #if os(macOS)
        button.popover(isPresented: $showingQRCode, arrowEdge: .bottom) {
            editor.frame(width: 400)
        }
        #else
        button.sheet(isPresented: $showingQRCode) {
            editor
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    /// Blue while there is something to print. An empty label gets the plain grey
    /// button, which is how macOS shows a default button that can't be pressed.
    @ViewBuilder
    private var printButton: some View {
        let button = Button(action: startPrint) {
            Group {
                if printer.isPrinting {
                    HStack(spacing: 8) {
                        ProgressView(value: printProgress)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        Text("Printing")
                    }
                } else if printer.phase == .printed {
                    Label("Printed", systemImage: "checkmark")
                } else {
                    Label("Print", systemImage: "printer")
                }
            }
            .frame(maxWidth: maxButtonWidth)
            #if os(macOS)
            .padding(.horizontal, 6)
            #endif
        }
        .keyboardShortcut("p")
        .disabled(design.isEmpty)
        if design.isEmpty {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var printProgress: Double {
        if case .printing(let progress) = printer.phase { progress } else { 0 }
    }

    private var maxButtonWidth: CGFloat? {
        #if os(iOS)
        .infinity
        #else
        nil
        #endif
    }

    private func startPrint() {
        printRequested = true
        Task { await printer.print(design) }
    }

    private var fixedLengthEnabled: Binding<Bool> {
        Binding(
            get: { design.fixedLengthMM != nil },
            set: { on in
                let current = LabelRasterizer.bitmap(for: design).lengthMM
                design.fixedLengthMM = on ? max(10, (current / 5).rounded(.up) * 5) : nil
            }
        )
    }

    private var fixedLength: Binding<Double> {
        Binding(get: { design.fixedLengthMM ?? 40 }, set: { design.fixedLengthMM = $0 })
    }
}
