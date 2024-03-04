import AppKit

import Output

/// Handler for application lifecycle events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Screen-reader instance.
    private var agent: VoshAgent?

    func applicationDidFinishLaunching(_ _notification: Notification) {
        Output.shared.announce("Starting Vosh")
        Task() {[self] in
            let agent = await VoshAgent()
            await MainActor.run() {[self] in
                self.agent = agent
            }
            if agent == nil {
                await Output.shared.announce("Vosh failed to start!")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if agent != nil {
            agent = nil
            Output.shared.announce("Terminating Vosh")
            Task() {
                // Allow some time to announce termination before actually terminating.
                try! await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run(body: {NSApplication.shared.terminate(nil)})
            }
            return .terminateCancel
        }
        return .terminateNow
    }
}
