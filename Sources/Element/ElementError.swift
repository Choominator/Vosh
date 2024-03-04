import ApplicationServices

/// Translator of legacy ``AXError`` values to a Swift type.
public enum ElementError: Error, CustomStringConvertible {
    case success
    case systemFailure
    case illegalArgument
    case invalidElement
    case invalidObserver
    case timeout
    case attributeUnsupported
    case actionUnsupported
    case notificationUnsupported
    case notImplemented
    case notificationAlreadyRegistered
    case notificationNotRegistered
    case apiDisabled
    case noValue
    case parameterizedAttributeUnsupported
    case notEnoughPrecision

    public var description: String {
        switch self {
        case .success:
            return "Success"
        case .systemFailure:
            return "System failure"
        case .illegalArgument:
            return "Illegal argument"
        case .invalidElement:
            return "Invalid element"
        case .invalidObserver:
            return "Invalid observer"
        case .timeout:
            return "Request timed out"
        case .attributeUnsupported:
            return "Attribute unsupported"
        case .actionUnsupported:
            return "Action unsupported"
        case .notificationUnsupported:
            return "Notification unsupported"
        case .parameterizedAttributeUnsupported:
            return "Parameterized attribute unsupported"
        case .notImplemented:
            return "Accessibility not supported"
        case .notificationAlreadyRegistered:
            return "Notification already registered"
        case .notificationNotRegistered:
            return "Notification not registered"
        case .apiDisabled:
            return "Accessibility API disabled"
        case .noValue:
            return "No value"
        case .notEnoughPrecision:
            return "Not enough precision"
        }
    }

    /// Creates a new accessibility error from a legacy error value.
    /// - Parameter error: Legacy error value.
    init(from error: AXError) {
        switch error {
        case .success:
            self = .success
        case .failure:
            self = .systemFailure
        case .illegalArgument:
            self = .illegalArgument
        case .invalidUIElement:
            self = .invalidElement
        case .invalidUIElementObserver:
            self = .invalidObserver
        case .cannotComplete:
            self = .timeout
        case .attributeUnsupported:
            self = .attributeUnsupported
        case .actionUnsupported:
            self = .actionUnsupported
        case .notificationUnsupported:
            self = .notificationUnsupported
        case .parameterizedAttributeUnsupported:
            self = .parameterizedAttributeUnsupported
        case .notImplemented:
            self = .notImplemented
        case .notificationAlreadyRegistered:
            self = .notificationAlreadyRegistered
        case .notificationNotRegistered:
            self = .notificationNotRegistered
        case .apiDisabled:
            self = .apiDisabled
        case .noValue:
            self = .noValue
        case .notEnoughPrecision:
            self = .notEnoughPrecision
        @unknown default:
            fatalError("Unrecognized AXError case")
        }
    }

    /// Converts this error to a legacy error value.
    func toAXError() -> AXError {
        switch self {
        case .success:
            return .success
        case .systemFailure:
            return .failure
        case .illegalArgument:
            return .illegalArgument
        case .invalidElement:
            return .invalidUIElement
        case .invalidObserver:
            return .invalidUIElementObserver
        case .timeout:
            return .cannotComplete
        case .attributeUnsupported:
            return .attributeUnsupported
        case .actionUnsupported:
            return .actionUnsupported
        case .notificationUnsupported:
            return .notificationUnsupported
        case .parameterizedAttributeUnsupported:
            return .parameterizedAttributeUnsupported
        case .notImplemented:
            return .notImplemented
        case .notificationAlreadyRegistered:
            return .notificationAlreadyRegistered
        case .notificationNotRegistered:
            return .notificationNotRegistered
        case .apiDisabled:
            return .apiDisabled
        case .noValue:
            return .noValue
        case .notEnoughPrecision:
            return .notEnoughPrecision
        }
    }
}
