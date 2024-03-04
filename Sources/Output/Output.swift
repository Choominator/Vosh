import AVFoundation
import ApplicationServices

/// Output conveyer.
@MainActor public final class Output: NSObject {
    /// Speech synthesizer.
    private let synthesizer = AVSpeechSynthesizer()
    /// Queued output.
    private var queued = [OutputSemantic]()
    /// Whether the synthesizer is currently announcing something.
    private var isAnnouncing = false
    /// Shared singleton.
    public static let shared = Output()

    /// Creates a new output.
    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Announces a high priority event.
    /// - Parameter announcement: Event to announce.
    public func announce(_ announcement: String) {
        let announcement = AVSpeechUtterance(string: announcement)
        synthesizer.stopSpeaking(at: .immediate)
        isAnnouncing = true
        synthesizer.speak(announcement)
    }

    /// Conveys the semantic accessibility output to the user.
    /// - Parameter content: Content to output.
    public func convey(_ content: [OutputSemantic]) {
        if isAnnouncing {
            queued = content
            return
        }
        queued = []
        synthesizer.stopSpeaking(at: .immediate)
        for expression in content {
            switch expression {
            case .apiDisabled:
                let utterance = AVSpeechUtterance(string: "Accessibility interface disabled")
                synthesizer.speak(utterance)
            case let .application(label):
                let utterance = AVSpeechUtterance(string: label)
                synthesizer.speak(utterance)
            case let .boolValue(bool):
                let utterance = AVSpeechUtterance(string: bool ? "On" : "Off")
                synthesizer.speak(utterance)
            case .boundary:
                continue
            case let .capsLockStatusChanged(status):
                let utterance = AVSpeechUtterance(string: "CapsLock \(status ? "On" : "Off")")
                synthesizer.speak(utterance)
            case let .columnCount(count):
                let utterance = AVSpeechUtterance(string: "\(count) columns")
                synthesizer.speak(utterance)
            case .disabled:
                let utterance = AVSpeechUtterance(string: "Disabled")
                synthesizer.speak(utterance)
            case .edited:
                let utterance = AVSpeechUtterance(string: "Edited")
                synthesizer.speak(utterance)
            case .entering:
                let utterance = AVSpeechUtterance(string: "Entering")
                synthesizer.speak(utterance)
            case .exiting:
                let utterance = AVSpeechUtterance(string: "Exiting")
                synthesizer.speak(utterance)
            case let .floatValue(float):
                let utterance = AVSpeechUtterance(string: String(format: "%.01.02f", arguments: [float]))
                synthesizer.speak(utterance)
            case let .help(help):
                let utterance = AVSpeechUtterance(string: help)
                synthesizer.speak(utterance)
            case let .insertedText(text):
                let utterance = AVSpeechUtterance(string: text)
                synthesizer.speak(utterance)
            case let .intValue(int):
                let utterance = AVSpeechUtterance(string: String(int))
                synthesizer.speak(utterance)
            case let .label(label):
                let utterance = AVSpeechUtterance(string: label)
                synthesizer.speak(utterance)
            case .next:
                continue
            case .noFocus:
                let utterance = AVSpeechUtterance(string: "Nothing in focus")
                synthesizer.speak(utterance)
            case .notAccessible:
                let utterance = AVSpeechUtterance(string: "Application not accessible")
                synthesizer.speak(utterance)
            case let .placeholderValue(value):
                let utterance = AVSpeechUtterance(string: value)
                synthesizer.speak(utterance)
            case .previous:
                continue
            case let .removedText(text):
                let utterance = AVSpeechUtterance(string: text)
                synthesizer.speak(utterance)
            case let .role(role):
                let utterance = AVSpeechUtterance(string: role)
                synthesizer.speak(utterance)
            case let .rowCount(count):
                let utterance = AVSpeechUtterance(string: "\(count) rows")
                synthesizer.speak(utterance)
            case .selected:
                let utterance = AVSpeechUtterance(string: "Selected")
                synthesizer.speak(utterance)
            case let .selectedChildrenCount(count):
                let utterance = AVSpeechUtterance(string: "\(count) selected \(count == 1 ? "child" : "children")")
                synthesizer.speak(utterance)
            case let .selectedText(text):
                let utterance = AVSpeechUtterance(string: text)
                synthesizer.speak(utterance)
            case let .selectedTextGrew(text):
                let utterance = AVSpeechUtterance(string: text)
                synthesizer.speak(utterance)
            case let .selectedTextShrank(text):
                let utterance = AVSpeechUtterance(string: text)
                synthesizer.speak(utterance)
            case let .stringValue(string):
                let utterance = AVSpeechUtterance(string: string)
                synthesizer.speak(utterance)
            case .timeout:
                let utterance = AVSpeechUtterance(string: "Application is not responding")
                synthesizer.speak(utterance)
            case let .updatedLabel(label):
                let utterance = AVSpeechUtterance(string: label)
                synthesizer.speak(utterance)
            case let .urlValue(url):
                let utterance = AVSpeechUtterance(string: url)
                synthesizer.speak(utterance)
            case let .window(label):
                let utterance = AVSpeechUtterance(string: label)
                synthesizer.speak(utterance)
            }
        }
    }

    /// Interrupts speech.
    public func interrupt() {
        isAnnouncing = false
        queued = []
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension Output: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        if isAnnouncing {
            isAnnouncing = false
            convey(queued)
        }
    }
}
