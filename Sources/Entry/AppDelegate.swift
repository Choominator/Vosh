import AppKit

/// Handler for application lifecycle events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Screen-reader instance.
    private var agent: Agent?

    func applicationDidFinishLaunching(_ _notification: Notification) {
        Task() {[self] in
            let agent = await Agent()
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
