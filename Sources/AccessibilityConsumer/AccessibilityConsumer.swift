import SwiftUI

/// Entry point and user interface.
@main struct AccessibilityConsumer: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Vosh", systemImage: "eye") {
            Button(action: {NSApplication.shared.terminate(nil)}, label: {Text("Exit")})
        }
    }
    
    /// Handler for application lifecycle events.
    private final class AppDelegate: NSObject, NSApplicationDelegate {
        /// Screen-reader instance.
        private var agent: AccessibilityAgent?

        func applicationDidFinishLaunching(_ _notification: Notification) {
            Task() {[self] in
                let agent = await AccessibilityAgent()
                await MainActor.run() {[self] in
                    self.agent = agent
                    if agent == nil {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }

        func applicationShouldTerminate(_ _sender: NSApplication) -> NSApplication.TerminateReply {
            if agent != nil {
                agent = nil
                Task() {
                    // Give the output conveyer some time to announce termination before actually terminating.
                    try! await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run(body: {NSApplication.shared.terminate(nil)})
                }
                return .terminateCancel
            }
            return .terminateNow
        }
    }
}
