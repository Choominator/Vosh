import AVFAudio
import Foundation

/// Output conveyer.
public final class Output: NSObject, @unchecked Sendable {
    // Sendable conformance is ensured by the guarding mutex as well as by not sharing access to the speech synthesizer instance.

    /// State guard.
    private let mutex = NSLock()
    /// Mutable state.
    private var state = State()
    /// Shared singleton.
    public static let shared = Output()

    /// Creates a new output.
    private override init() {
        super.init()
        state.synthesizer.delegate = self
    }

    /// Announces a high priority event.
    /// - Parameter announcement: Event to announce.
    public func announce(_ announcement: String) {
        mutex.lock()
        defer {mutex.unlock()}
        let announcement = AVSpeechUtterance(string: announcement)
        state.synthesizer.stopSpeaking(at: .immediate)
        state.isAnnouncing = true
        state.synthesizer.speak(announcement)
    }

    /// Conveys the semantic accessibility output to the user.
    /// - Parameter content: Content to output.
    public func convey(_ content: [OutputSemantic]) {
        mutex.lock()
        defer {mutex.unlock()}
        if state.isAnnouncing {
            state.queued = content
            return
        }
        state.synthesizer.stopSpeaking(at: .immediate)
        content.forEach({$0.convey(on: state.synthesizer)})
    }

    /// Interrupts speech.
    public func interrupt() {
        mutex.lock()
        defer {mutex.unlock()}
        state.isAnnouncing = false
        state.queued = []
        state.synthesizer.stopSpeaking(at: .immediate)
    }
}

extension Output {
    private struct State {
        /// Speech synthesizer.
        let synthesizer = AVSpeechSynthesizer()
        /// Whether the synthesizer is currently announcing something.
        var isAnnouncing = false
        /// Queued output.
        var queued = [OutputSemantic]()
    }
}

extension Output: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        mutex.lock()
        defer {mutex.unlock()}
        guard state.isAnnouncing else {return}
        state.isAnnouncing = false
        state.queued.forEach({$0.convey(on: state.synthesizer)})
        state.queued = []
    }
}
