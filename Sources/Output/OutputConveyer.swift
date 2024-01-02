import AVFoundation
import Foundation

import Consumer

/// Accessibility output conveyer.
@MainActor public final class OutputConveyer: NSObject, AVSpeechSynthesizerDelegate {
    public weak var delegate: OutputConveyerDelegate?
    /// Speech synthesizer.
    private let speaker = AVSpeechSynthesizer()
    /// Cache of the currently focused accessibility element.
    var cache = Cache(application: "Application")
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
    public override init() {
        super.init()
        speaker.delegate = self
        announce("Screen-reader on")
    }

    /// Creates a new message queue.
    /// - Returns: New queue.
    public func makeQueue() -> Queue {
        return Queue(output: self)
    }

    /// Interrupts speech and empties all queued utterances.
    public func interrupt() {
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
    public func cacheActiveApplication(_ application: String) {
        cache = Cache(application: application)
        enqueue(application)
    }

    /// Makes a high priority announcement.
    /// - Parameter announcement: Announcement to make.
    public func announce(_ announcement: String) {
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
    public func conveyNoPermission() {
        clean()
        enqueue("Accessibility permission denied")
        flush()
    }

    /// Informs the user that the accessibility API is disabled.
    public func conveyAPIDisabled() {
        clean()
        enqueue("Accessibility API disabled")
        flush()
    }

    /// Informs the user that the specified or cached application is not accessible.
    /// - Parameter application: Optional application name.
    public func conveyNotAccessible(application: String? = nil) {
        clean()
        enqueue("\(application ?? cache.application) is not accessible")
        flush()
    }

    /// Informs the user that the specified or cached application is not responding.
    /// - Parameter application: Optional application name.
    public func conveyNoResponse(application: String? = nil) {
        clean()
        enqueue("\(application ?? cache.application) is not responding")
        flush()
    }

    /// Informs the user that there is currently no accessibility element in focus.
    public func conveyNoFocus() {
        clean()
        enqueue("\(cache.application) has nothing in focus")
        flush()
    }

    /// Informs the user that a boundary was hit.
    public func conveyBoundary() {
        clean()
        enqueue("Bump")
        flush()
    }

    /// Adds a message to the low priority queue.
    /// - Parameter utterance: Message to enqueue.
    func enqueue(_ utterance: String) {
        flushing = false
        utterances.append(utterance)
    }
    
    /// Cleans the low priority message queue.
    func clean() {
        utterances.removeAll(keepingCapacity: true)
    }

    func flush() {
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

    public nonisolated func speechSynthesizer(_ _synthesizer: AVSpeechSynthesizer, didFinish _utterance: AVSpeechUtterance) {
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

    /// Cache of the currently focused element.
    struct Cache {
        /// Named of the application.
        let application: String
        /// Element with focus.
        var focus: Element?
        /// Text selection in the focused element.
        var selection: Range<Int>?
    }
}
