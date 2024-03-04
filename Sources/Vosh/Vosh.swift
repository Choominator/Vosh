import SwiftUI

/// Entry point and user interface.
@main struct Vosh: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Vosh", systemImage: "eye") {
            Button(action: {NSApplication.shared.terminate(nil)}, label: {Text("Exit")})
        }
    }
}
