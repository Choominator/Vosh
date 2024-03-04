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
}
