import AVFAudio

/// Semantic Accessibility descriptions.
public enum OutputSemantic {
    case application(String)
    case window(String)
    case boundary
    case selectedChildrenCount(Int)
    case rowCount(Int)
    case columnCount(Int)
    case label(String)
    case role(String)
    case boolValue(Bool)
    case intValue(Int64)
    case floatValue(Double)
    case stringValue(String)
    case urlValue(String)
    case placeholderValue(String)
    case selectedText(String)
    case selectedTextGrew(String)
    case selectedTextShrank(String)
    case insertedText(String)
    case removedText(String)
    case help(String)
    case updatedLabel(String)
    case edited
    case selected
    case disabled
    case entering
    case exiting
    case next
    case previous
    case noFocus
    case capsLockStatusChanged(Bool)
    case apiDisabled
    case notAccessible
    case timeout

    /// Conveys this semantic information through the provided speech synthesizer.
    /// - Parameter synthesizer: Speech synthesizer to produce the generated utterances.
    func convey(on synthesizer: AVSpeechSynthesizer) {
        switch self {
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
                return
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
                return
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
                return
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
