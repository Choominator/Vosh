import AppKit
import OSLog

import Element
import Output

/// Accessibility context.
@AccessActor public final class Access {
    /// System-wide element.
    private let system: Element
    /// Active application.
    private var application: Element?
    /// Process identifier of the active application.
    private var processIdentifier: pid_t = 0
    /// Active application observer.
    private var observer: ElementObserver?
    /// Entity with user focus.
    private var focus: AccessFocus?
    /// Trigger to refocus when the frontmost application changes.
    private var refocusTrigger: NSKeyValueObservation?
    /// System logging facility.
    private static let logger = Logger()

    /// Initializes the accessibility framework.
    public init?() async {
        guard await Element.confirmProcessTrustedStatus() else {
            return nil
        }
        system = await Element()
        Task() {[weak self] in
            while let self = self {
                var eventIterator = await self.observer?.eventStream.makeAsyncIterator()
                while let event = await eventIterator?.next() {
                    await handleEvent(event)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await refocus(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        refocusTrigger = NSWorkspace.shared.observe(\.frontmostApplication, options: .new) {[weak self] (_, value) in
            guard let runningApplication = value.newValue else {
                return
            }
            let processIdentifier = runningApplication?.processIdentifier
            Task {[self] in
                await self?.refocus(processIdentifier: processIdentifier)
            }
        }
    }

    /// Sets the response timeout of the accessibility framework.
    /// - Parameter seconds: Time in seconds.
    public func setTimeout(seconds: Float) async {
        do {
            try await system.setTimeout(seconds: seconds)
        } catch {
            await handleError(error)
        }
    }

    /// Reads the accessibility contents of the element with user focus.
    public func readFocus() async {
        do {
            guard let focus = focus else {
                let content = [OutputSemantic.noFocus]
                await Output.shared.convey(content)
                return
            }
            let content = try await focus.reader.read()
            await Output.shared.convey(content)
        } catch {
            await handleError(error)
        }
    }

    /// Moves the user focus to its interesting parent.
    public func focusParent() async {
        do {
            guard let oldFocus = focus else {
                let content = [OutputSemantic.noFocus]
                await Output.shared.convey(content)
                return
            }
            guard let parent = try await oldFocus.entity.getParent() else {
                var content = [OutputSemantic.boundary]
                content.append(contentsOf: try await oldFocus.reader.read())
                await Output.shared.convey(content)
                return
            }
            let newFocus = try await AccessFocus(on: parent)
            self.focus = newFocus
            try await newFocus.entity.setKeyboardFocus()
            var content = [OutputSemantic.exiting]
            content.append(contentsOf: try await newFocus.reader.readSummary())
            await Output.shared.convey(content)
        } catch {
            await handleError(error)
        }
    }

    /// Moves the user focus to its next interesting sibling.
    /// - Parameter backwards: Whether to search backwards.
    public func focusNextSibling(backwards: Bool) async {
        do {
            guard let oldFocus = focus else {
                let content = [OutputSemantic.noFocus]
                await Output.shared.convey(content)
                return
            }
            guard let sibling = try await oldFocus.entity.getNextSibling(backwards: backwards) else {
                var content = [OutputSemantic.boundary]
                content.append(contentsOf: try await oldFocus.reader.read())
                await Output.shared.convey(content)
                return
            }
            let newFocus = try await AccessFocus(on: sibling)
            self.focus = newFocus
            try await newFocus.entity.setKeyboardFocus()
            var content = [!backwards ? OutputSemantic.next : OutputSemantic.previous]
            content.append(contentsOf: try await newFocus.reader.read())
            await Output.shared.convey(content)
        } catch {
            await handleError(error)
        }
    }

    /// Sets the user focus to the first child of this entity.
    public func focusFirstChild() async {
        do {
            guard let oldFocus = focus else {
                let content = [OutputSemantic.noFocus]
                await Output.shared.convey(content)
                return
            }
            guard let child = try await oldFocus.entity.getFirstChild() else {
                var content = [OutputSemantic.boundary]
                content.append(contentsOf: try await oldFocus.reader.read())
                await Output.shared.convey(content)
                return
            }
            let newFocus = try await AccessFocus(on: child)
            self.focus = newFocus
            try await newFocus.entity.setKeyboardFocus()
            var content = [OutputSemantic.entering]
            content.append(contentsOf: try await oldFocus.reader.readSummary())
            content.append(contentsOf: try await newFocus.reader.read())
            await Output.shared.convey(content)
        } catch {
            await handleError(error)
        }
    }

    /// Dumps the system wide element to a property list file chosen by the user.
    @MainActor public func dumpSystemWide() async {
        await dumpElement(system)
    }

    /// Dumps all accessibility elements of the currently active application to a property list file chosen by the user.
    @MainActor public func dumpApplication() async {
        guard let application = await application else {
            let content = [OutputSemantic.noFocus]
            Output.shared.convey(content)
            return
        }
        await dumpElement(application)
    }

    /// Dumps all descendant accessibility elements of the currently focused element to a property list file chosen by the user.
    @MainActor public func dumpFocus() async {
        guard let focus = await focus else {
            let content = [OutputSemantic.noFocus]
            Output.shared.convey(content)
            return
        }
        await dumpElement(focus.entity.element)
    }

    /// Resets the user focus to the system keyboard focusor the first interesting child of the focused window.
    private func refocus(processIdentifier: pid_t?) async {
        do {
            guard let processIdentifier = processIdentifier else {
                application = nil
                self.processIdentifier = 0
                observer = nil
                focus = nil
                let content = [OutputSemantic.noFocus]
                await Output.shared.convey(content)
                return
            }
            var content = [OutputSemantic]()
            if processIdentifier != self.processIdentifier {
                let application = await Element(processIdentifier: processIdentifier)
                let observer = try await ElementObserver(element: application)
                try await observer.subscribe(to: .applicationDidAnnounce)
                try await observer.subscribe(to: .elementDidDisappear)
                try await observer.subscribe(to: .elementDidGetFocus)
                self.application = application
                self.processIdentifier = processIdentifier
                self.observer = observer
                let applicationLabel = try await application.getAttribute(.title) as? String
                content.append(.application(applicationLabel ?? "Application"))
            }
            guard let application = self.application, let observer = self.observer else {
                fatalError("Logic failed")
            }
            if let keyboardFocus = try await application.getAttribute(.focusedElement) as? Element {
                if let window = try await keyboardFocus.getAttribute(.windowElement) as? Element {
                    if let windowLabel = try await window.getAttribute(.title) as? String, !windowLabel.isEmpty {
                        content.append(.window(windowLabel))
                    } else {
                        content.append(.window("Untitled"))
                    }
                }
                let focus = try await AccessFocus(on: keyboardFocus)
                self.focus = focus
                content.append(contentsOf: try await focus.reader.read())
            } else if let window = try await application.getAttribute(.focusedWindow) as? Element, let child = try await AccessEntity(for: window).getFirstChild() {
                if let windowLabel = try await window.getAttribute(.title) as? String, !windowLabel.isEmpty {
                    content.append(.window(windowLabel))
                } else {
                    content.append(.window("Untitled"))
                }
                let focus = try await AccessFocus(on: child)
                self.focus = focus
                content.append(contentsOf: try await focus.reader.read())
            } else {
                self.focus = nil
                try await observer.subscribe(to: .elementDidAppear)
                content.append(.noFocus)
            }
            await Output.shared.convey(content)
        } catch {
            await handleError(error)
        }
    }

    /// Handles events generated by the application element.
    /// - Parameter event: Generated event.
    private func handleEvent(_ event: ElementEvent) async {
        do {
            switch event.notification {
            case .applicationDidAnnounce:
                if let announcement = event.payload?[.announcement] as? String {
                    await Output.shared.announce(announcement)
                }
            case .elementDidAppear:
                guard focus == nil else {
                    try await observer?.unsubscribe(from: .elementDidAppear)
                    break
                }
                await refocus(processIdentifier: processIdentifier)
                if self.focus != nil {
                    try await observer?.unsubscribe(from: .elementDidAppear)
                }
            case .elementDidDisappear:
                guard event.subject == focus?.entity.element else {
                    break
                }
                let entity = try await AccessEntity(for: event.subject)
                guard let isFocusableAncestor = try await focus?.entity.isInFocusGroup(of: entity), !isFocusableAncestor else {
                    break
                }
                focus = nil
                await refocus(processIdentifier: self.processIdentifier)
            case .elementDidGetFocus:
                guard event.subject != focus?.entity.element else {
                    break
                }
                let newFocus = try await AccessFocus(on: event.subject)
                guard let oldFocus = focus, try await !oldFocus.entity.isInFocusGroup(of: newFocus.entity) else {
                    break
                }
                self.focus = newFocus
                await readFocus()
            default:
                fatalError("Received an unexpected event notification \(event.notification)")
            }
        } catch {
            await handleError(error)
        }
    }

    /// Dumps the entire hierarchy of elements rooted at the specified element to a property list file chosen by the user.
    /// - Parameter element: Root element.
    @MainActor private func dumpElement(_ element: Element) async {
        do {
            guard let label = try await application?.getAttribute(.title) as? String, let dump = try await element.dump() else {
                let content = [OutputSemantic.noFocus]
                Output.shared.convey(content)
                return
            }
            let data = try PropertyListSerialization.data(fromPropertyList: dump, format: .binary, options: .zero)
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.message = "Choose a location to dump the selected accessibility elements."
            savePanel.nameFieldLabel = "Accessibility Dump Property List"
            savePanel.nameFieldStringValue = "\(label) Dump.plist"
            savePanel.title = "Save \(label) dump property list"
            let response = await savePanel.begin()
            if response == .OK, let url = savePanel.url {
                try data.write(to: url)
            }
        } catch {
            await handleError(error)
        }
    }

    /// Handles errors returned by the Element module.
    /// - Parameter error: Error to handle.
    private func handleError(_ error: any Error) async {
        guard let error = error as? ElementError else {
            fatalError("Unexpected error \(error)")
        }
        switch error {
        case .apiDisabled:
            let content = [OutputSemantic.apiDisabled]
            await Output.shared.convey(content)
        case .invalidElement:
            await refocus(processIdentifier: processIdentifier)
        case .notImplemented:
            let content = [OutputSemantic.notAccessible]
            await Output.shared.convey(content)
        case .timeout:
            let content = [OutputSemantic.timeout]
            await Output.shared.convey(content)
        default:
            Self.logger.warning("Unexpected error \(error, privacy: .public)")
            return
        }
    }
}
