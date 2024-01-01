import ApplicationServices
import OSLog

/// Swift wrapper for a legacy ``AXUIElement``.
@AccessibilityActor struct AccessibilityElement: Hashable {
    /// Legacy value.
    let legacyValue: AXUIElement
    /// Global timeout to be set on all elements.
    static var timeout: Float = 5.0
    /// System logging facility.
    private static let logger = Logger()

    /// Creates a system-wide element.
    init() {
        legacyValue = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(legacyValue, Self.timeout)
    }

    /// Creates an application element for the specified PID.
    /// - Parameter processIdentifier: PID of the application.
    init(processIdentifier: pid_t) {
        legacyValue = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(legacyValue, Self.timeout)
    }

    /// Wraps a legacy ``AXUIElement`` possibly obtained from an accessibility event.
    /// - Parameter value: Legacy value to wrap.
    nonisolated init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        legacyValue = unsafeBitCast(value, to: AXUIElement.self)
        Task(operation: {[legacyValue] in await AccessibilityActor.run(body: {[legacyValue] in AXUIElementSetMessagingTimeout(legacyValue, Self.timeout)})})
    }

    /// Creates the element corresponding to the application of the specified element.
    /// - Returns: Application element.
    func getApplication() throws -> AccessibilityElement {
        var processIdentifier = pid_t(0)
        let result = AXUIElementGetPid(legacyValue, &processIdentifier)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error getting an accessibility element's associated process identifier: \(error.localizedDescription)")
        }
        return AccessibilityElement(processIdentifier: processIdentifier)
    }

    /// Dumps this element and all of its children to a data structure suitable to be encoded and serialized.
    /// - Returns: Serializable element structure.
    func dump() async throws -> [String: Any]? {
        do {
            var attributes: CFArray?
            let result = AXUIElementCopyAttributeNames(legacyValue, &attributes)
            let error = AccessibilityError(from: result)
            switch error {
            case .success:
                break
            case .apiDisabled, .invalidElement, .notImplemented, .timeout:
                throw error
            default:
                fatalError("Unexpected error reading an accessibility element's attribute names: \(error.localizedDescription)")
            }
            guard let attributes = [Any?](legacyValue: attributes as CFTypeRef) else {
                throw AccessibilityError.systemFailure
            }
            var attributeValues = [String: Any]()
            for attribute in attributes {
                guard let attribute = attribute as? String, let value = readAttribute(attribute) else {
                    continue
                }
                attributeValues[attribute] = try await encode(value: value, readElements: attribute == AccessibilityAttribute.childrenElements.rawValue)
            }
            return attributeValues
        } catch AccessibilityError.invalidElement {
            return nil
        } catch {
            throw error
        }
    }

    /// Creates a list of all the known attributes of this element.
    /// - Returns: List of attributes.
    func listAttributes() throws -> Set<AccessibilityAttribute> {
        var attributes: CFArray?
        let result = AXUIElementCopyAttributeNames(legacyValue, &attributes)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's attribute names: \(error.localizedDescription)")
        }
        guard let attributes = [Any?](legacyValue: attributes as CFTypeRef) else {
            return []
        }
        var attributeSet = Set<AccessibilityAttribute>()
        for attribute in attributes {
            guard let attribute = attribute as? String else {
                continue
            }
            guard let attribute = AccessibilityAttribute(rawValue: attribute) else {
                continue
            }
            attributeSet.insert(attribute)
        }
        return attributeSet
    }

    /// Reads the value associated with a given attribute of this element.
    /// - Parameter attribute: Attribute whose value is to be read.
    /// - Returns: Value of the attribute, if any.
    func readAttribute(_ attribute: AccessibilityAttribute) throws -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(legacyValue, attribute.rawValue as CFString, &value)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .attributeUnsupported, .noValue:
            return nil
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error getting value for accessibility element attribute \(attribute.rawValue): \(error.localizedDescription)")
        }
        guard let value = value else {
            return nil
        }
        return fromLegacy(value: value)
    }

    /// Writes a value to the specified attribute of this element.
    /// - Parameters:
    ///   - attribute: Attribute to be written.
    ///   - value: Value to write.
    func riteAttribute<T: AccessibilityLegacyConvertible>(_ attribute: AccessibilityAttribute, value: T?) throws {
        let value = value.legacyValue
        let result = AXUIElementSetAttributeValue(legacyValue, attribute.rawValue as CFString, value)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .attributeUnsupported, .invalidElement, .notEnoughPrecision, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error setting accessibility element attribute \(attribute.rawValue): \(error.localizedDescription)")
        }
    }

    /// Queries the specified parameterized attribute of this element.
    /// - Parameters:
    ///   - query: Parameterized attribute to query.
    ///   - input: Input value.
    /// - Returns: Output value.
    func query<T: AccessibilityLegacyConvertible>(_ query: AccessibilityQuery, input: T) throws -> Any? {
        let input = input.legacyValue as CFTypeRef
        var output: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(legacyValue, query.rawValue as CFString, input, &output)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .noValue, .queryUnsupported:
            return nil
        case .apiDisabled, .invalidElement, .notEnoughPrecision, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unrecognized error querying parameterized accessibility element attribute \(query.rawValue): \(error.localizedDescription)")
        }
        return fromLegacy(value: output)
    }

    /// Creates a list of all the actions supported by this element along with their respective descriptions.
    /// - Returns: List of actions.
    func listActions() async throws -> [(action: String, description: String)] {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(legacyValue, &actions)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility elenet's action names: \(error.localizedDescription)")
        }
        guard let actions = [Any?](legacyValue: actions as CFTypeRef) else {
            return []
        }
        var actionArray = [(action: String, description: String)]()
        for action in actions {
            guard let action = action as? String else {
                Self.logger.warning("Ignoring non-string action name")
                continue
            }
            await Task.yield()
            var description: CFString?
            let result = AXUIElementCopyActionDescription(legacyValue, action as CFString, &description)
            let error = AccessibilityError(from: result)
            switch error {
            case .success:
                break
            case .actionUnsupported:
                continue
            case .apiDisabled, .invalidElement, .notImplemented, .timeout:
                throw error
            default:
                fatalError("Unexpected error reading an accessibility element's description for action \(action): \(error.localizedDescription)")
            }
            guard let description = String(legacyValue: description as CFTypeRef) else {
                Self.logger.warning("Ignoring non-string action description")
                continue
            }
            actionArray.append((action: action, description: description))
        }
        return actionArray
    }

    /// Performs the specified action on this element.
    /// - Parameter action: Action to perform.
    func performAction(_ action: String) throws {
        let result = AXUIElementPerformAction(legacyValue, action as CFString)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .actionUnsupported, .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error performing accessibility element action \(action): \(error.localizedDescription)")
        }
    }

    /// Checks whether this process is trusted and prompts the user to grant it accessibility privileges if it isn't.
    /// - Returns: Whether this process has accessibility privileges.
    @MainActor static func confirmProcessTrustedStatus() -> Bool {
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    /// Reads the value associated to the specified attribute of this element regardless of whether it's known.
    /// - Parameter attribute: Attribute to read.
    /// - Returns: Associated value.
    private func readAttribute(_ attribute: String) -> Any? {
        if attribute == "AXMakeScreenRectVisible" {
            return nil
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(legacyValue, attribute as CFString, &value)
        let error = AccessibilityError(from: result)
        switch error {
        case .success:
            break
        case .attributeUnsupported, .noValue, .systemFailure:
            return nil
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            Self.logger.debug("Error reading attribute \(attribute, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        default:
            fatalError("Unexpected error getting value for accessibility element attribute \(attribute): \(error.localizedDescription)")
        }
        return fromLegacy(value: value)
    }

    /// Encodes a value into a format suitable to be serialized.
    /// - Parameters:
    ///   - value: Value to encode.
    ///   - readElements: Whether to recursively read the children of element values.
    /// - Returns: Data structure of elements suitable to be serialized.
    func encode(value: Any, readElements: Bool) async throws -> Any? {
        switch value {
        case is Bool, is Int64, is Double, is String:
            return value
        case let array as [Any?]:
            var resultArray = [Any]()
            resultArray.reserveCapacity(array.count)
            for element in array {
                guard let element = element, let element = try await encode(value: element, readElements: readElements) else {
                    continue
                }
                resultArray.append(element)
            }
            return resultArray
        case let dictionary as [String: Any]:
            var resultDictionary = [String: Any]()
            resultDictionary.reserveCapacity(dictionary.count)
            for pair in dictionary {
                guard let value = try await encode(value: pair.value, readElements: readElements) else {
                    continue
                }
                resultDictionary[pair.key] = value
            }
            return resultDictionary
        case let url as URL:
            return url.absoluteString
        case let attributedString as AttributedString:
            return String(attributedString.characters)
        case let point as CGPoint:
            return ["x": point.x, "y": point.y]
        case let size as CGSize:
            return ["width": size.width, "height": size.height]
        case let rect as CGRect:
            return ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
        case let element as AccessibilityElement:
            if readElements {
                return try await element.dump()
            } else {
                return "Element"
            }
        case let error as AccessibilityError:
            return "Error: \(error.localizedDescription)"
        default:
            return nil
        }
    }
}