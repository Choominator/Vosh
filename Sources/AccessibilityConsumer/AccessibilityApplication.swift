import AppKit

/// Handles the state of an application currently running on the system.
actor AccessibilityApplication {
    /// Name of the application.
    private let name: String
    /// Accessibility element of the application.
    private let application: AccessibilityElement
    /// Observer for accessibility events.
    private let observer: AccessibilityObserver
    /// Current window with focus.
    private var focusedWindow: AccessibilityElement?
    /// Saved state of focus elements and their ancestors.
    private var windowFoci = [AccessibilityElement: [AccessibilityElement]]()
    /// Input event handler.
    private unowned var input: AccessibilityInput
    /// Output conveyer.
    private weak var output: AccessibilityOutput?

    /// Creates a new instance to handle events from a running application.
    /// - Parameters:
    ///   - processIdentifier: PID of the application.
    ///   - input: Input event handler.
    init(processIdentifier: pid_t, input: AccessibilityInput) async throws {
        guard let runningApplication = NSRunningApplication(processIdentifier: processIdentifier) else {
            throw AccessibilityError.invalidElement
        }
        name = runningApplication.localizedName ?? "application"
        self.input = input
        do {
            observer = try await AccessibilityObserver(processIdentifier: processIdentifier)
            application = observer.element
            try await refocus()
            await observer.subscribe(with: {[unowned self] in await handleEventStream($0)})
        } catch AccessibilityError.apiDisabled {
            throw AccessibilityError.apiDisabled
        } catch AccessibilityError.invalidElement {
            throw AccessibilityError.invalidElement
        } catch AccessibilityError.notImplemented {
            throw AccessibilityError.notImplemented
        } catch AccessibilityError.timeout {
            throw AccessibilityError.timeout
        } catch {
            fatalError("Unexpected error creating an application object: \(error.localizedDescription)")
        }
    }

    /// Dumps the entire accessibility element hierarchy of this application to a property list file selected by the user.
    @MainActor func dump() async {
        await dumpElement(application)
    }

    /// Dumps the hierarchy of accessibility elements rooted in the currently focused element to a property list file chosen by the user.
    @MainActor func dumpFocus() async {
        guard let output = await output else {
            return
        }
        guard let focusedWindow = await focusedWindow, let focus = await windowFoci[focusedWindow]?.last else {
            output.conveyNoFocus()
            return
        }
        await dumpElement(focus)
    }

    /// Reads the current element with focus.
    func readFocus() async {
        guard let output = output else {
            return
        }
        while true {
            let queue = await output.makeQueue()
            do {
                try await refocus()
                let focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                guard let focusedWindow = focusedWindow, let focus = focusStack.last else {
                    await output.conveyNoFocus()
                    return
                }
                windowFoci[focusedWindow] = focusStack
                if await queue.setFocus(to: focus) {
                    return
                }
            } catch AccessibilityError.invalidElement {
                continue
            } catch AccessibilityError.notImplemented {
                await output.conveyNotAccessible(application: name)
                return
            } catch AccessibilityError.apiDisabled {
                await output.conveyAPIDisabled()
                return
            } catch AccessibilityError.timeout {
                await output.conveyNoResponse(application: name)
                return
            } catch {
                fatalError("Unexpected error accessing an accessibility element: \(error.localizedDescription)")
            }
        }
    }

    /// Focuses the next sibling of the currentl focused element.
    /// - Parameter backward: Whether to focus the previous sibling instead.
    func focusNext(backward: Bool) async {
        guard let output = output else {
            return
        }
        while true {
            let queue = await output.makeQueue()
            do {
                // Retrieve the current focused element, refocusing if necessary.
                var focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                let oldFocus = focusStack.last
                try await refocus()
                focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                let focus = focusStack.last
                guard let focusedWindow = focusedWindow, focus == oldFocus, let focus = focus else {
                    guard let focus = focus else {
                        await output.conveyNoFocus()
                        return
                    }
                    if await queue.setFocus(to: focus) {
                        return
                    }
                    continue
                }
                // Finally focus the sibling, if it exists.
                focusStack.removeLast()
                let parent = focusStack.last ?? focusedWindow
                guard let focus = try await Self.findFirstChild(of: parent, after: focus, backward: backward) else {
                    focusStack.append(focus)
                    windowFoci[focusedWindow] = focusStack
                    await output.conveyBoundary()
                    return
                }
                focusStack.append(focus)
                windowFoci[focusedWindow] = focusStack
                if await queue.setFocus(to: focus) {
                    return
                }
            } catch AccessibilityError.invalidElement {
                continue
            } catch AccessibilityError.notImplemented {
                await output.conveyNotAccessible(application: name)
                return
            } catch AccessibilityError.apiDisabled {
                await output.conveyAPIDisabled()
                return
            } catch AccessibilityError.timeout {
                await output.conveyNoResponse(application: name)
                return
            } catch {
                fatalError("Unexpected error accessing an accessibility element: \(error.localizedDescription)")
            }
        }
    }

    /// Enters the currently focused element, focusing its first child.
    func enterFocus() async {
        guard let output = output else {
            return
        }
        while true {
            let queue = await output.makeQueue()
            do {
                // Retrieve the current focused element, refocusing if necessary.
                var focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                let oldFocus = focusStack.last
                try await refocus()
                focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                let focus = focusStack.last
                guard let focusedWindow = focusedWindow, focus == oldFocus, let focus = focus else {
                    guard let focus = focus else {
                        await output.conveyNoFocus()
                        return
                    }
                    if await queue.setFocus(to: focus) {
                        return
                    }
                    continue
                }
                // Finally focus the first child, if it exists.
                guard let child = try await Self.findFirstChild(of: focus, backward: false) else {
                    await output.conveyBoundary()
                    return
                }
                focusStack.append(child)
                windowFoci[focusedWindow] = focusStack
                if await queue.focusChild(child) {
                    return
                }
            } catch AccessibilityError.invalidElement {
                continue
            } catch AccessibilityError.notImplemented {
                await output.conveyNotAccessible(application: name)
                return
            } catch AccessibilityError.apiDisabled {
                await output.conveyAPIDisabled()
                return
            } catch AccessibilityError.timeout {
                await output.conveyNoResponse(application: name)
                return
            } catch {
                fatalError("Unexpected error accessing an accessibility element: \(error.localizedDescription)")
            }
        }
    }

    /// Moves the focus to the parent of the currently focused element.
    func exitFocus() async {
        guard let output = output else {
            return
        }
        while true {
            let queue = await output.makeQueue()
            do {
                // Retrieve the current focused element, refocusing if necessary.
                var focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                let oldFocus = focusStack.last
                try await refocus()
                focusStack = if let focusedWindow = focusedWindow {windowFoci[focusedWindow] ?? [AccessibilityElement]()} else {[AccessibilityElement]()}
                let focus = focusStack.last
                guard let focusedWindow = focusedWindow, focus == oldFocus, focus != nil else {
                    guard let focus = focus else {
                        await output.conveyNoFocus()
                        return
                    }
                    if await queue.setFocus(to: focus) {
                        return
                    }
                    continue
                }
                // Finally focus the parent, if it exists.
                focusStack.removeLast()
                guard let parent = focusStack.last else {
                    await output.conveyBoundary()
                    return
                }
                windowFoci[focusedWindow] = focusStack
                if await queue.focusParent(parent) {
                    return
                }
            } catch AccessibilityError.invalidElement {
                continue
            } catch AccessibilityError.notImplemented {
                await output.conveyNotAccessible(application: name)
                return
            } catch AccessibilityError.apiDisabled {
                await output.conveyAPIDisabled()
                return
            } catch AccessibilityError.timeout {
                await output.conveyNoResponse(application: name)
                return
            } catch {
                fatalError("Unexpected error accessing an accessibility element: \(error.localizedDescription)")
            }
        }
    }

    /// Sets this application as active.
    func setActive(output: AccessibilityOutput) async {
        self.output = output
        await output.cacheActiveApplication(name)
        await readFocus()
    }

    /// Clears the active status of this application.
    func clearActive() {
        self.output = nil
    }

    /// Handles the stream of accessibility events.
    /// - Parameter eventStream: Stream of accessibility events.
    private func handleEventStream(_ eventStream: AsyncStream<AccessibilityEvent>) async {
        for await event in eventStream {
            guard let output = output else {
                continue
            }
            let queue = await output.makeQueue()
            switch event.notification {
            case .applicationDidAnnounce:
                if let announcement = event.payload?["AXAnnouncementKey"] as? String {
                    await output.announce(announcement)
                }
            case .elementDidGetFocus:
                focusedWindow = nil
                await readFocus()
            case .textSelectionDidUpdate:
                guard let focusedWindow = focusedWindow, let focus = windowFoci[focusedWindow]?.last, focus == event.subject else {
                    continue
                }
                _ = await queue.setSelection(input: input)
            case .titleDidUpdate:
                guard let focusedWindow = focusedWindow, let focus = windowFoci[focusedWindow]?.last, focus == event.subject else {
                    continue
                }
                _ = await queue.updateLabel()
            case .valueDidUpdate:
                guard let focusedWindow = focusedWindow, let focus = windowFoci[focusedWindow]?.last, focus == event.subject else {
                    continue
                }
                _ = await queue.updateValue()
            case .windowDidGetFocus:
                self.focusedWindow = event.subject
                await readFocus()
            default:
                break
            }
        }
    }

    /// Resets the accessibility focus in response to a focus change event.
    private func setFocus() async {
        while true {
            do {
                guard let focus = try await application.readAttribute(.focusedElement) as? AccessibilityElement else {
                    await output?.conveyNoFocus()
                    return
                }
                guard let focusedWindow = try await focus.readAttribute(.focusedWindow) as? AccessibilityElement else {
                    await output?.conveyNoFocus()
                    return
                }
                windowFoci[focusedWindow] = try await Self.findAncestors(of: focus)
                self.focusedWindow = focusedWindow
            } catch AccessibilityError.invalidElement {
                continue
            } catch AccessibilityError.notImplemented {
                await output?.conveyNotAccessible(application: name)
                return
            } catch AccessibilityError.apiDisabled {
                await output?.conveyAPIDisabled()
                return
            } catch AccessibilityError.timeout {
                await output?.conveyNoResponse(application: name)
                return
            } catch {
                fatalError("Unexpected error accessing an accessibility element: \(error.localizedDescription)")
            }
        }
    }

    /// Resets the accessibility focus when for some reason the screen-reader becomes lost.
    private func refocus() async throws {
        guard let focusedWindow = focusedWindow else {
            guard let focus = try await application.readAttribute(.focusedElement) as? AccessibilityElement, let focusedWindow = try await focus.readAttribute(.windowElement) as? AccessibilityElement else {
                self.focusedWindow = nil
                windowFoci.removeAll(keepingCapacity: true)
                return
            }
            windowFoci[focusedWindow] = try await Self.findAncestors(of: focus)
            self.focusedWindow = focusedWindow
            return
        }
        var focusStack = windowFoci[focusedWindow] ?? []
        while let focus = focusStack.last {
            if try await Self.isInterestingElement(focus) {
                break
            }
            focusStack.removeLast()
        }
        if focusStack.isEmpty, let focus = try await Self.findFirstChild(of: focusedWindow, backward: false) {
            focusStack = try await Self.findAncestors(of: focus)
        }
        windowFoci[focusedWindow] = focusStack
        return
    }

    /// Recursively searches the element tree for the first interesting child element before or after the specified sibling.
    /// - Parameters:
    ///   - element: Parent element.
    ///   - previous: Previous sibling.
    ///   - backward: Whether to search backwards.
    /// - Returns: The element that was found, if any.
    private static func findFirstChild(of element: AccessibilityElement, after previous: AccessibilityElement? = nil, backward: Bool) async throws -> AccessibilityElement? {
        let children = if let children = try await element.readAttribute(.navigationOrderedChildrenElements) as? [Any?] {
            children
        } else if let children = try await element.readAttribute(.childrenElements) as? [Any?] {
            children
        } else {
            []
        }
        var found = previous == nil
        if !backward {
            for child in children {
                guard let child = child as? AccessibilityElement else {
                    continue
                }
                let interesting = try await Self.isInterestingElement(child)
                if found && interesting {
                    return child
                }
                if child == previous {
                    found = true
                    continue
                }
                if !interesting, let grandChild = try await Self.findFirstChild(of: child, after: previous, backward: backward) {
                    return grandChild
                }
            }
            return nil
        }
        for child in children.lazy.reversed() {
            guard let child = child as? AccessibilityElement else {
                continue
            }
            let interesting = try await Self.isInterestingElement(child)
            if found && interesting {
                return child
            }
            if child == previous {
                found = true
                continue
            }
            if !interesting, let grandChild = try await Self.findFirstChild(of: child, after: previous, backward: backward) {
                return grandChild
            }
        }
        return nil
    }

    /// Builds a list of interesting ancestors of the specified element.
    /// - Parameter element: Element whose interesting ancestors are to be searched.
    /// - Returns: The list of ancestors.
    private static func findAncestors(of element: AccessibilityElement) async throws -> [AccessibilityElement] {
        guard let window = try await element.readAttribute(.windowElement) as? AccessibilityElement else {
            fatalError("Element has no window ancestor")
        }
        var ancestors = [AccessibilityElement]()
        var element = element
        while let parent = try await element.readAttribute(.parentElement) as? AccessibilityElement, parent != window {
            if try await Self.isInterestingElement(parent) {
                ancestors.append(element)
            }
            element = parent
        }
        return ancestors.reversed()
    }

    /// Applies some criteria to heuristically determine whether an element has any accessibility relevance.
    /// - Parameter element: Element to be checked.
    /// - Returns: whether the element is interesting.
    private static func isInterestingElement(_ element: AccessibilityElement) async throws -> Bool {
        let attributes = try await element.listAttributes()
        if attributes.contains(.hasWebApplicationAncestor), let children = try await element.readAttribute(.childrenElements) as? [Any?], !children.isEmpty {
            return false
        }
        if attributes.contains(.isFocused) {
            return true
        }
        if attributes.contains(.title), let title = try await element.readAttribute(.title) as? String, !title.isEmpty {
            return true
        }
        if attributes.contains(.titleElement), let element = try await element.readAttribute(.titleElement) as? AccessibilityElement, let title = try await element.readAttribute(.title) as? String, !title.isEmpty {
            return true
        }
        if attributes.contains(.value) {
            return true
        }
        return false
    }

    /// Dumps the entire hierarchy of elements rooted at the specified element to a property list file chosen by the user.
    /// - Parameter element: Root element.
    @MainActor private func dumpElement(_ element: AccessibilityElement) async {
        guard let output = await output else {
            return
        }
        do {
            guard let dump = try await element.dump() else {
                output.conveyNoFocus()
                return
            }
            let data = try PropertyListSerialization.data(fromPropertyList: dump, format: .binary, options: .zero)
            let name = name
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.message = "Choose a location to dump the selected accessibility elements."
            savePanel.nameFieldLabel = "Accessibility Dump Property List"
            savePanel.nameFieldStringValue = "\(name) Dump.plist"
            savePanel.title = "Save \(name) dump property list"
            let response = await savePanel.begin()
            if response == .OK, let url = savePanel.url {
                try data.write(to: url)
            }
        } catch let error as NSError {
            let alert = NSAlert()
            alert.messageText = "There was an error generating the property list: \(error.localizedDescription)"
            alert.runModal()
            return
        } catch AccessibilityError.notImplemented {
            let alert = NSAlert()
            alert.messageText = "\(name) is not accessible"
            alert.runModal()
            return
        } catch AccessibilityError.apiDisabled {
            let alert = NSAlert()
            alert.messageText = "Accessibility API disabled."
            alert.runModal()
            return
        } catch AccessibilityError.timeout {
            let alert = NSAlert()
            alert.messageText = "\(name) is not responding."
            alert.runModal()
            return
        } catch {
            fatalError("Unexpected error accessing an accessibility element: \(error.localizedDescription)")
        }
    }
}
