import AVFoundation
import Foundation
import OSLog

/// Accessibility output conveyer.
@MainActor final class AccessibilityOutput: NSObject, AVSpeechSynthesizerDelegate {
    /// Speech synthesizer.
    private let speaker = AVSpeechSynthesizer()
    /// Cache of the currently focused accessibility element.
    private var cache = Cache(application: "Application")
    /// Whether the message being currently spoken has priority.
    private var priority = false
    /// Whether there are low priority messages to speak after the currently high priority messages are done.
    private var flushing = false
    /// List of low priority messages to speak.
    private var utterances = [String]()
    /// List of high priority messages to speak.
    private var priorityUtterances = [String]()
    /// Whether the latest queue is nested inside an earlier living queue.
    private var nested = false

    /// Creates a new accessibility output conveyer.
    override init() {
        super.init()
        speaker.delegate = self
        announce("Screen-reader on")
    }

    /// Creates a new message queue.
    /// - Returns: New queue.
    func makeQueue() -> Queue {
        return Queue(output: self)
    }

    /// Interrupts speech and empties all queued utterances.
    func interrupt() {
        if flushing {
            flushing = false
            utterances.removeAll(keepingCapacity: true)
        }
        priority = false
        priorityUtterances.removeAll(keepingCapacity: true)
        speaker.stopSpeaking(at: .immediate)
    }

    /// Caches a new active application.
    /// - Parameter application: Name of the application to cache.
    func cacheActiveApplication(_ application: String) {
        cache = Cache(application: application)
        enqueue(application)
    }

    /// Makes a high priority announcement.
    /// - Parameter announcement: Announcement to make.
    func announce(_ announcement: String) {
        guard !priority else {
            priorityUtterances.append(announcement)
            return
        }
        speaker.stopSpeaking(at: .immediate)
        priority = true
        let utterance = AVSpeechUtterance(string: announcement)
        speaker.speak(utterance)
    }

    /// informs the user about the lack of accessibility permissions.
    func conveyNoPermission() {
        clean()
        enqueue("Accessibility permission denied")
        flush()
    }

    /// Informs the user that the accessibility API is disabled.
    func conveyAPIDisabled() {
        clean()
        enqueue("Accessibility API disabled")
        flush()
    }

    /// Informs the user that the specified or cached application is not accessible.
    /// - Parameter application: Optional application name.
    func conveyNotAccessible(application: String? = nil) {
        clean()
        enqueue("\(application ?? cache.application) is not accessible")
        flush()
    }

    /// Informs the user that the specified or cached application is not responding.
    /// - Parameter application: Optional application name.
    func conveyNoResponse(application: String? = nil) {
        clean()
        enqueue("\(application ?? cache.application) is not responding")
        flush()
    }

    /// Informs the user that there is currently no accessibility element in focus.
    func conveyNoFocus() {
        clean()
        enqueue("\(cache.application) has nothing in focus")
        flush()
    }

    /// Informs the user that a boundary was hit.
    func conveyBoundary() {
        clean()
        enqueue("Bump")
        flush()
    }

    /// Adds a message to the low priority queue.
    /// - Parameter utterance: Message to enqueue.
    private func enqueue(_ utterance: String) {
        flushing = false
        utterances.append(utterance)
    }
    
    /// Cleans the low priority message queue.
    private func clean() {
        utterances.removeAll(keepingCapacity: true)
    }

    private func flush() {
        guard !utterances.isEmpty else {
            flushing = false
            return
        }
        guard !priority else {
            flushing = true
            return
        }
        speaker.stopSpeaking(at: .immediate)
        flushing = false
        for utterance in utterances {
            let utterance = AVSpeechUtterance(string: utterance)
            speaker.speak(utterance)
        }
        utterances.removeAll(keepingCapacity: true)
    }

    nonisolated func speechSynthesizer(_ _synthesizer: AVSpeechSynthesizer, didFinish _utterance: AVSpeechUtterance) {
        Task() {
            await MainActor.run() {
                if !priorityUtterances.isEmpty {
                    let utterance = AVSpeechUtterance(string: priorityUtterances.removeFirst())
                    speaker.speak(utterance)
                } else {
                    priority = false
                    if flushing {
                        flush()
                    }
                }
            }
        }
    }

    deinit {
        Task() {[speaker] in
            speaker.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: "Screen-reader off")
            speaker.speak(utterance)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// Reentrant message queue.
    @MainActor struct Queue: ~Copyable {
        /// Accessibility output conveyer instance.
        private weak var output: AccessibilityOutput?
        /// System logger facility.
        private static let logger = Logger()

        /// Creates a new message queue.
        /// - Parameter output: Output conveyer instance.
        fileprivate init(output: AccessibilityOutput) {
            self.output = output
        }

        /// Conveys a change of focus to an accessibility element.
        /// - Parameter new: Newly focused accessibility element.
        /// - Returns: Whether the message queueing succeeded.
        consuming func setFocus(to new: AccessibilityElement) async -> Bool {
            guard let output = output else {
                return true
            }
            do {
                let application = output.cache.application
                let focus = output.cache.focus
                output.cache = Cache(application: application)
                if let old = focus {
                    let oldWindow = try await old.readAttribute(.windowElement) as? AccessibilityElement
                    let newWindow = try await new.readAttribute(.windowElement) as? AccessibilityElement
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
            } catch AccessibilityError.apiDisabled {
                output.conveyAPIDisabled()
                return true
            } catch AccessibilityError.invalidElement {
                output.clean()
                return false
            } catch AccessibilityError.notImplemented {
                output.conveyNotAccessible()
                return true
            } catch AccessibilityError.timeout {
                output.conveyNoResponse()
                return true
            } catch {
                fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
            }
        }

        /// Conveys the focusing of a child accessibility element.
        /// - Parameter child: Child accessibility element that gained focus.
        /// - Returns: Whether the queueing succeeded.
        consuming func focusChild(_ child: AccessibilityElement) async -> Bool {
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
            } catch AccessibilityError.invalidElement {
                output.clean()
                return false
            } catch AccessibilityError.notImplemented {
                output.conveyNotAccessible()
                return true
            } catch AccessibilityError.timeout {
                output.conveyNoResponse()
                return true
            } catch {
                fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
            }
        }

        /// Conveys focusing to the parent accessibility element.
        /// - Parameter parent: Parent accessibility element that gained focus.
        /// - Returns: Whether the queueing succeeded.
        consuming func focusParent(_ parent: AccessibilityElement) async -> Bool {
            guard let output = output else {
                return true
            }
            output.enqueue("Exiting")
            return await setFocus(to: parent)
        }

        /// Conveys the setting of the text selection of an accessibility element.
        /// - Parameter input: Input handler instance.
        /// - Returns: Whether the queueing succeeded.
        consuming func setSelection(input: AccessibilityInput) async -> Bool {
            guard let output = output else {
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
                    let left = input.checkKeyState(.keyboardLeftArrow)
                    let right = input.checkKeyState(.keyboardRightArrow)
                    let down = input.checkKeyState(.keyboardDownArrow)
                    let up = input.checkKeyState(.keyboardUpArrow)
                    if left || right || down || up {
                        output.conveyBoundary()
                    }
                    return true
                } else if old.isEmpty && new.isEmpty {
                    // Regular caret movement.
                    // The intended behavior is to just read the glyphs that the caret passed over, however when the line changes intentially we need to read the content of the new line instead.
                    let down = input.checkKeyState(.keyboardDownArrow)
                    let up = input.checkKeyState(.keyboardUpArrow)
                    let option = input.checkOptionState()
                    if !option && (down || up), let line = try await focus.query(.lineForIndex, input: Int64(new.lowerBound)) as? Int64, let range = try await focus.query(.rangeForLine, input: line) as? Range<Int>, let content = try await focus.query(.stringForRange, input: range) as? String {
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
            } catch AccessibilityError.apiDisabled {
                output.conveyAPIDisabled()
                return true
            } catch AccessibilityError.invalidElement {
                output.clean()
                return false
            } catch AccessibilityError.notImplemented {
                output.conveyNotAccessible()
                return true
            } catch AccessibilityError.timeout {
                output.conveyNoResponse()
                return true
            } catch {
                fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
            }
        }

        /// Conveys the performance of an action on an accessibility element.
        /// - Parameter action: Description of the action.
        /// - Returns: Whether the queueing succeeded.
        consuming func performAction(_ action: String) async -> Bool {
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
            } catch AccessibilityError.apiDisabled {
                output.conveyAPIDisabled()
                return true
            } catch AccessibilityError.invalidElement {
                output.clean()
                return false
            } catch AccessibilityError.notImplemented {
                output.conveyNotAccessible()
                return true
            } catch AccessibilityError.timeout {
                output.conveyNoResponse()
                return true
            } catch {
                fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
            }
        }

        /// Conveys the update of an accessibility element's label.
        /// - Returns: Whether the queueing succeeded.
        consuming func updateLabel() async -> Bool {
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
            } catch AccessibilityError.apiDisabled {
                output.conveyAPIDisabled()
                return true
            } catch AccessibilityError.invalidElement {
                output.clean()
                return false
            } catch AccessibilityError.notImplemented {
                output.conveyNotAccessible()
                return true
            } catch AccessibilityError.timeout {
                output.conveyNoResponse()
                return true
            } catch {
                fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
            }
        }

        /// Conveys the update of an accessibility element's value.
        /// - Returns: Whether the queueing succeeded.
        consuming func updateValue() async -> Bool {
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
            } catch AccessibilityError.apiDisabled {
                output.conveyAPIDisabled()
                return true
            } catch AccessibilityError.invalidElement {
                output.clean()
                return false
            } catch AccessibilityError.notImplemented {
                output.conveyNotAccessible()
                return true
            } catch AccessibilityError.timeout {
                output.conveyNoResponse()
                return true
            } catch {
                fatalError("Unexpected error reading an accessibility element's attributes: \(error.localizedDescription)")
            }
        }

        /// Reads the label of an accessibility element.
        /// - Parameter element: Element to read.
        private func readLabel(of element: AccessibilityElement) async throws {
            guard let output = output else {
                return
            }
            if let title = try await element.readAttribute(.title) as? String, !title.isEmpty {
                output.enqueue(title)
            } else if let element = try await element.readAttribute(.titleElement) as? AccessibilityElement, let title = try await element.readAttribute(.title) as? String, !title.isEmpty {
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
                    guard let child = child as? AccessibilityElement else {
                        continue
                    }
                    try await readLabel(of: child)
                }
            }
        }

        /// Conveys the role of an accessibility element.
        /// - Parameter element: Element to describe.
        private func readRole(of element: AccessibilityElement) async throws {
            guard let output = output else {
                return
            }
            if let role = try await element.readAttribute(.roleDescription) as? String {
                output.enqueue(role)
            }
        }

        /// Conveys the value of an accessibility element.
        /// - Parameter element: Element whose value is to be conveyed.
        private func readValue(of element: AccessibilityElement) async throws {
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
        private func readState(of element: AccessibilityElement) async throws {
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

    /// Cache of the currently focused element.
    private struct Cache {
        /// Named of the application.
        let application: String
        /// Element with focus.
        var focus: AccessibilityElement?
        /// Text selection in the focused element.
        var selection: Range<Int>?
    }
}
