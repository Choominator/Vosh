import OSLog

import Consumer

/// Reentrant message queue.
@MainActor public struct Queue: ~Copyable {
    /// Accessibility output conveyer instance.
    private weak var output: OutputConveyer?
    /// System logger facility.
    private static let logger = Logger()

    /// Creates a new message queue.
    /// - Parameter output: Output conveyer instance.
    public init(output: OutputConveyer) {
        self.output = output
    }

    /// Conveys a change of focus to an accessibility element.
    /// - Parameter new: Newly focused accessibility element.
    /// - Returns: Whether the message queueing succeeded.
    public consuming func setFocus(to new: Element) async -> Bool {
        guard let output = output else {
            return true
        }
        do {
            let application = output.cache.application
            let focus = output.cache.focus
            output.cache = OutputConveyer.Cache(application: application)
            if let old = focus {
                let oldWindow = try await old.readAttribute(.windowElement) as? Element
                let newWindow = try await new.readAttribute(.windowElement) as? Element
                if newWindow != oldWindow, let newWindow = newWindow {
                    let title = try await newWindow.readAttribute(.title) as? String
                    output.enqueue(title ?? "Untitled window")
                }
            }
            try await readLabel(of: new)
            try await readValue(of: new)
            try await readRole(of: new)
            try await readState(of: new)
            let selection = try await new.readAttribute(.selectedTextRange) as? Range<Int>
            output.cache.focus = new
            output.cache.selection = selection
            output.flush()
            return true
        } catch ConsumerError.apiDisabled {
            output.conveyAPIDisabled()
            return true
        } catch ConsumerError.invalidElement {
            output.clean()
            return false
        } catch ConsumerError.notImplemented {
            output.conveyNotAccessible()
            return true
        } catch ConsumerError.timeout {
            output.conveyNoResponse()
            return true
        } catch {
            fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
        }
    }

    /// Conveys the focusing of a child accessibility element.
    /// - Parameter child: Child accessibility element that gained focus.
    /// - Returns: Whether the queueing succeeded.
    public consuming func focusChild(_ child: Element) async -> Bool {
        guard let output = output else {
            return true
        }
        do {
            guard let focus = output.cache.focus else {
                output.conveyNoFocus()
                return true
            }
            output.enqueue("Entering")
            try await readLabel(of: focus)
            return await setFocus(to: child)
        } catch ConsumerError.invalidElement {
            output.clean()
            return false
        } catch ConsumerError.notImplemented {
            output.conveyNotAccessible()
            return true
        } catch ConsumerError.timeout {
            output.conveyNoResponse()
            return true
        } catch {
            fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
        }
    }

    /// Conveys focusing to the parent accessibility element.
    /// - Parameter parent: Parent accessibility element that gained focus.
    /// - Returns: Whether the queueing succeeded.
    public consuming func focusParent(_ parent: Element) async -> Bool {
        guard let output = output else {
            return true
        }
        output.enqueue("Exiting")
        return await setFocus(to: parent)
    }

    /// Conveys the setting of the text selection of an accessibility element.
    /// - Returns: Whether the queueing succeeded.
    public consuming func setSelection() async -> Bool {
        guard let output = output, let delegate = output.delegate else {
            return true
        }
        do {
            guard let focus = output.cache.focus, let old = output.cache.selection else {
                Self.logger.warning("Received a selection changed event without a focused element or selection range in cache")
                output.clean()
                return true
            }
            guard let new = try await focus.readAttribute(.selectedTextRange) as? Range<Int> else {
                Self.logger.warning("Received a selection changed event without a new range")
                output.cache.selection = nil
                output.clean()
                return true
            }
            if old == new {
                // Selection didn't change at all, possibly indicating that the user attempted to move the caret out of bounds.
                if delegate.checkHorizontalArrowKeyState() || delegate.checkVerticalArrowKeyState() {
                    output.conveyBoundary()
                }
                return true
            } else if old.isEmpty && new.isEmpty {
                // Regular caret movement.
                // The intended behavior is to just read the glyphs that the caret passed over, however when the line changes intentially we need to read the content of the new line instead.
                if !delegate.checkOptionModifierKeyState() && delegate.checkVerticalArrowKeyState(), let line = try await focus.query(.lineForIndex, input: Int64(new.lowerBound)) as? Int64, let range = try await focus.query(.rangeForLine, input: line) as? Range<Int>, let content = try await focus.query(.stringForRange, input: range) as? String {
                    output.enqueue(content)
                } else {
                    let skipped = min(old.lowerBound, new.lowerBound) ..< max(old.upperBound, new.upperBound)
                    if let skipped = try await focus.query(.stringForRange, input: skipped) as? String {
                        output.enqueue(skipped)
                    }
                }
            } else if old.lowerBound == new.lowerBound {
                // Selection being changed on the right side.
                let extending = new.upperBound > old.upperBound
                let skipped = extending ? old.upperBound ..< new.upperBound : new.upperBound ..< old.upperBound
                if let skipped = try await focus.query(.stringForRange, input: skipped) as? String {
                    output.enqueue(skipped)
                    output.enqueue(extending ? "Selected" : "Unselected")
                }
            } else if old.upperBound == new.upperBound {
                // Selection being extended or shrunk on the left side.
                let extending = new.lowerBound < old.lowerBound
                let skipped = extending ? new.lowerBound ..< old.lowerBound : old.lowerBound ..< new.lowerBound
                if let skipped = try await focus.query(.stringForRange, input: skipped) as? String {
                    output.enqueue(skipped)
                    output.enqueue(extending ? "Selected" : "Unselected")
                }
            } else {
                if !old.isEmpty, let selection = try await focus.query(.stringForRange, input: old) as? String {
                    output.enqueue(selection)
                    output.enqueue("Unselected")
                }
                if !new.isEmpty, let selection = try await focus.query(.stringForRange, input: new) as? String {
                    output.enqueue(selection)
                    output.enqueue("Selected")
                }
            }
            output.cache.selection = new
            output.flush()
            return true
        } catch ConsumerError.apiDisabled {
            output.conveyAPIDisabled()
            return true
        } catch ConsumerError.invalidElement {
            output.clean()
            return false
        } catch ConsumerError.notImplemented {
            output.conveyNotAccessible()
            return true
        } catch ConsumerError.timeout {
            output.conveyNoResponse()
            return true
        } catch {
            fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
        }
    }

    /// Conveys the performance of an action on an accessibility element.
    /// - Parameter action: Description of the action.
    /// - Returns: Whether the queueing succeeded.
    public consuming func performAction(_ action: String) async -> Bool {
        guard let output = output else {
            return true
        }
        do {
            guard let focus = output.cache.focus else {
                output.conveyNoFocus()
                return true
            }
            output.enqueue(action)
            try await readLabel(of: focus)
            output.flush()
            return true
        } catch ConsumerError.apiDisabled {
            output.conveyAPIDisabled()
            return true
        } catch ConsumerError.invalidElement {
            output.clean()
            return false
        } catch ConsumerError.notImplemented {
            output.conveyNotAccessible()
            return true
        } catch ConsumerError.timeout {
            output.conveyNoResponse()
            return true
        } catch {
            fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
        }
    }

    /// Conveys the update of an accessibility element's label.
    /// - Returns: Whether the queueing succeeded.
    public consuming func updateLabel() async -> Bool {
        guard let output = output else {
            return true
        }
        do {
            guard let focus = output.cache.focus else {
                Self.logger.warning("Received a title update without an accessibility element in focus")
                output.clean()
                return true
            }
            try await readLabel(of: focus)
            output.flush()
            return true
        } catch ConsumerError.apiDisabled {
            output.conveyAPIDisabled()
            return true
        } catch ConsumerError.invalidElement {
            output.clean()
            return false
        } catch ConsumerError.notImplemented {
            output.conveyNotAccessible()
            return true
        } catch ConsumerError.timeout {
            output.conveyNoResponse()
            return true
        } catch {
            fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
        }
    }

    /// Conveys the update of an accessibility element's value.
    /// - Returns: Whether the queueing succeeded.
    public consuming func updateValue() async -> Bool {
        guard let output = output else {
            return true
        }
        do {
            guard let focus = output.cache.focus else {
                Self.logger.warning("Received a value update without a focused accessibility element")
                output.clean()
                return true
            }
            guard let value = try await focus.readAttribute(.value) else {
                output.clean()
                return true
            }
            switch value {
            case let value as Bool:
                output.enqueue(value ? "On" : "Off")
            case let value as Int64:
                output.enqueue(String(value))
            case let value as Double:
                output.enqueue(String(value))
            default:
                break
            }
            output.flush()
            return true
        } catch ConsumerError.apiDisabled {
            output.conveyAPIDisabled()
            return true
        } catch ConsumerError.invalidElement {
            output.clean()
            return false
        } catch ConsumerError.notImplemented {
            output.conveyNotAccessible()
            return true
        } catch ConsumerError.timeout {
            output.conveyNoResponse()
            return true
        } catch {
            fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
        }
    }

    /// Reads the label of an accessibility element.
    /// - Parameter element: Element to read.
    private func readLabel(of element: Element) async throws {
        guard let output = output else {
            return
        }
        if let title = try await element.readAttribute(.title) as? String, !title.isEmpty {
            output.enqueue(title)
        } else if let element = try await element.readAttribute(.titleElement) as? Element, let title = try await element.readAttribute(.title) as? String, !title.isEmpty {
            output.enqueue(title)
        } else {
            let children = if let children = try await element.readAttribute(.navigationOrderedChildrenElements) as? [Any?] {
                children
            } else if let children = try await element.readAttribute(.childrenElements) as? [Any?] {
                children
            } else {
                []
            }
            for child in children {
                guard let child = child as? Element else {
                    continue
                }
                try await readLabel(of: child)
            }
        }
    }

    /// Conveys the role of an accessibility element.
    /// - Parameter element: Element to describe.
    private func readRole(of element: Element) async throws {
        guard let output = output else {
            return
        }
        if let role = try await element.readAttribute(.roleDescription) as? String {
            output.enqueue(role)
        }
    }

    /// Conveys the value of an accessibility element.
    /// - Parameter element: Element whose value is to be conveyed.
    private func readValue(of element: Element) async throws {
        guard let output = output else {
            return
        }
        let value = if let value = try await element.readAttribute(.valueDescription) as? String, !value.isEmpty {
            Optional.some(value)
        } else if let value = try await element.readAttribute(.value) {
            Optional.some(value)
        } else {
            Optional<Any>.none
        }
        guard let value = value else {
            return
        }
        switch value {
        case let bool as Bool:
            output.enqueue(bool ? "On" : "Off")
        case let integer as Int64:
            output.enqueue(String(integer))
        case let float as Double:
            output.enqueue(String(float))
        case let string as String:
            output.enqueue(string)
            if let selection = try await element.readAttribute(.selectedText) as? String, !selection.isEmpty {
                output.enqueue(selection)
                output.enqueue("selected text")
            }
        case let attributedString as AttributedString:
            output.enqueue(String(attributedString.characters))
            if let selection = try await element.readAttribute(.selectedText) as? String, !selection.isEmpty {
                output.enqueue(selection)
                output.enqueue("selected text")
            }
        case let url as URL:
            output.enqueue(url.absoluteString)
        default:
            Self.logger.warning("Unexpected value type: \(type(of: value), privacy: .public)")
        }
        if let edited = try await element.readAttribute(.edited) as? Bool, edited {
            output.enqueue("Edited")
        }
    }

    /// Conveys whether an element is enabled or disabled.
    /// - Parameter element: Element whose state is to be conveyed.
    private func readState(of element: Element) async throws {
        guard let output = output else {
            return
        }
        if let selected = try await element.readAttribute(.selected) as? Bool, selected {
            output.enqueue("Selected")
        }
        if let enabled = try await element.readAttribute(.isEnabled) as? Bool, !enabled {
            output.enqueue("Disabled")
        }
    }
}
