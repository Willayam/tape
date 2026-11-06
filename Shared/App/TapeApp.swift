import SwiftUI

@main
struct TapeApp: App {
    @State private var store = LabelStore()
    @State private var printer = PrinterSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(printer)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        .commands {
            // The editor's Print and New buttons own ⌘P and ⌘N.
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
