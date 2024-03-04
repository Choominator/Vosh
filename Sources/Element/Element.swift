import ApplicationServices

/// Swift wrapper for a legacy ``AXUIElement``.
@ElementActor public struct Element {
    /// Legacy value.
    let legacyValue: CFTypeRef

    /// Creates a system-wide element.
    public init() {
        legacyValue = AXUIElementCreateSystemWide()
    }

    /// Creates an application element for the specified PID.
    /// - Parameter processIdentifier: PID of the application.
    public init(processIdentifier: pid_t) {
        legacyValue = AXUIElementCreateApplication(processIdentifier)
    }

    /// Wraps a legacy ``AXUIElement``.
    /// - Parameter value: Legacy value to wrap.
    nonisolated init?(legacyValue value: CFTypeRef) {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        legacyValue = unsafeBitCast(value, to: AXUIElement.self)
    }

    /// Creates the element corresponding to the application of the specified element.
    /// - Returns: Application element.
    public func getApplication() throws -> Element {
        let processIdentifier = try getProcessIdentifier()
        return Element(processIdentifier: processIdentifier)
    }

    /// Reads the process identifier of this element.
    /// - Returns: Process identifier.
    public func getProcessIdentifier() throws -> pid_t {
        let legacyValue = legacyValue as! AXUIElement
        var processIdentifier = pid_t(0)
        let result = AXUIElementGetPid(legacyValue, &processIdentifier)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's process identifier: \(error)")
        }
        return processIdentifier
    }

    /// Sets the timeout of requests made to this element.
    /// - Parameter seconds: Timeout in seconds.
    public func setTimeout(seconds: Float) throws {
        let legacyValue = legacyValue as! AXUIElement
        let result = AXUIElementSetMessagingTimeout(legacyValue, seconds)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error setting an accessibility element's request timeout: \(error)")
        }
    }

    /// Dumps this element to a data structure suitable to be encoded and serialized.
    /// - Parameters:
    ///   - recursiveParents: Whether to recursively dump this element's parents.
    ///   - recursiveChildren: Whether to recursively dump this element's children.
    /// - Returns: Serializable element structure.
    public func dump(recursiveParents: Bool = true, recursiveChildren: Bool = true) async throws -> [String: Any]? {
        do {
            var root = [String: Any]()
            let attributes = try listAttributes()
            var attributeValues = [String: Any]()
            for attribute in attributes {
                guard let value = try getAttribute(attribute) else {
                    continue
                }
                attributeValues[attribute] = encode(value: value)
            }
            root["attributes"] = attributeValues
            guard legacyValue as! AXUIElement != AXUIElementCreateSystemWide() else {
                return root
            }
            let parameterizedAttributes = try listParameterizedAttributes()
            root["parameterizedAttributes"] = parameterizedAttributes
            root["actions"] = try listActions()
            if recursiveParents, let parent = try getAttribute("AXParent") as? Element {
                root["parent"] = try await parent.dump(recursiveParents: true, recursiveChildren: false)
            }
            if recursiveChildren, let children = try getAttribute("AXChildren") as? [Any?] {
                var resultingChildren = [Any]()
                for child in children.lazy.compactMap({$0 as? Element}) {
                    guard let child = try await child.dump(recursiveParents: false, recursiveChildren: true) else {
                        continue
                    }
                    resultingChildren.append(child)
                }
                root["children"] = resultingChildren
            }
            return root
        } catch ElementError.invalidElement {
            return nil
        } catch {
            throw error
        }
    }

    /// Retrieves the set of attributes supported by this element.
    /// - Returns: Set of attributes.
    public func getAttributeSet() throws -> Set<ElementAttribute> {
        let attributes = try listAttributes()
        return Set(attributes.lazy.compactMap({ElementAttribute(rawValue: $0)}))
    }

    /// Reads the value associated with a given attribute of this element.
    /// - Parameter attribute: Attribute whose value is to be read.
    /// - Returns: Value of the attribute, if any.
    public func getAttribute(_ attribute: ElementAttribute) throws -> Any? {
        let output = try getAttribute(attribute.rawValue)
        if attribute == .role, let output = output as? String {
            return ElementRole(rawValue: output)
        }
        if attribute == .subrole, let output = output as? String {
            return ElementSubrole(rawValue: output)
        }
        return output
    }

    /// Writes a value to the specified attribute of this element.
    /// - Parameters:
    ///   - attribute: Attribute to be written.
    ///   - value: Value to write.
    public func setAttribute(_ attribute: ElementAttribute, value: Any) throws {
        return try setAttribute(attribute.rawValue, value: value)
    }

    /// Retrieves the set of parameterized attributes supported by this element.
    /// - Returns: Set of parameterized attributes.
    public func getParameterizedAttributeSet() throws -> Set<ElementParameterizedAttribute> {
        let attributes = try listParameterizedAttributes()
        return Set(attributes.lazy.compactMap({ElementParameterizedAttribute(rawValue: $0)}))
    }

    /// Queries the specified parameterized attribute of this element.
    /// - Parameters:
    ///   - attribute: Parameterized attribute to query.
    ///   - input: Input value.
    /// - Returns: Output value.
    public func queryParameterizedAttribute(_ attribute: ElementParameterizedAttribute, input: Any) throws -> Any? {
        return try queryParameterizedAttribute(attribute.rawValue, input: input)
    }

    /// Creates a list of all the actions supported by this element.
    /// - Returns: List of actions.
    public func listActions() throws -> [String] {
        let legacyValue = legacyValue as! AXUIElement
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(legacyValue, &actions)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .systemFailure, .illegalArgument:
            return []
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility elenet's action names: \(error)")
        }
        guard let actions = [Any?](legacyValue: actions as CFTypeRef) else {
            return []
        }
        return actions.compactMap({$0 as? String})
    }

    /// Queries for a localized description of the specified action.
    /// - Parameter action: Action to query.
    /// - Returns: Description of the action.
    public func describeAction(_ action: String) throws -> String? {
        let legacyValue = legacyValue as! AXUIElement
        var description: CFString?
        let result = AXUIElementCopyActionDescription(legacyValue, action as CFString, &description)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .actionUnsupported, .illegalArgument, .systemFailure:
            return nil
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's description for action \(action)")
        }
        guard let description = description else {
            return nil
        }
        return description as String
    }

    /// Performs the specified action on this element.
    /// - Parameter action: Action to perform.
    public func performAction(_ action: String) throws {
        let legacyValue = legacyValue as! AXUIElement
        let result = AXUIElementPerformAction(legacyValue, action as CFString)
        let error = ElementError(from: result)
        switch error {
        case .success, .systemFailure, .illegalArgument:
            break
        case .actionUnsupported, .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error performing accessibility element action \(action): \(error.localizedDescription)")
        }
    }

    /// Creates a list of all the known attributes of this element.
    /// - Returns: List of attributes.
    private func listAttributes() throws -> [String] {
        let legacyValue = legacyValue as! AXUIElement
        var attributes: CFArray?
        let result = AXUIElementCopyAttributeNames(legacyValue, &attributes)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's attribute names: \(error)")
        }
        guard let attributes = [Any?](legacyValue: attributes as CFTypeRef) else {
            return []
        }
        return attributes.compactMap({$0 as? String})
    }

    /// Reads the value associated with a given attribute of this element.
    /// - Parameter attribute: Attribute whose value is to be read.
    /// - Returns: Value of the attribute, if any.
    private func getAttribute(_ attribute: String) throws -> Any? {
        let legacyValue = legacyValue as! AXUIElement
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(legacyValue, attribute as CFString, &value)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .attributeUnsupported, .noValue, .systemFailure, .illegalArgument:
            return nil
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error getting value for accessibility element attribute \(attribute): \(error)")
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
    private func setAttribute(_ attribute: String, value: Any) throws {
        let legacyValue = legacyValue as! AXUIElement
        guard let value = value as? any ElementLegacy else {
            throw ElementError.illegalArgument
        }
        let result = AXUIElementSetAttributeValue(legacyValue, attribute as CFString, value.legacyValue as CFTypeRef)
        let error = ElementError(from: result)
        switch error {
        case .success, .systemFailure, .attributeUnsupported, .illegalArgument:
            break
        case .apiDisabled, .invalidElement, .notEnoughPrecision, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error setting accessibility element attribute \(attribute): \(error)")
        }
    }

    /// Lists the parameterized attributes available to this element.
    /// - Returns: List of parameterized attributes.
    private func listParameterizedAttributes() throws -> [String] {
        let legacyValue = legacyValue as! AXUIElement
        var parameterizedAttributes: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(legacyValue, &parameterizedAttributes)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's parameterized attribute names: \(error)")
        }
        guard let parameterizedAttributes = [Any?](legacyValue: parameterizedAttributes as CFTypeRef) else {
            return []
        }
        return parameterizedAttributes.compactMap({$0 as? String})
    }

    /// Queries the specified parameterized attribute of this element.
    /// - Parameters:
    ///   - attribute: Parameterized attribute to query.
    ///   - input: Input value.
    /// - Returns: Output value.
    private func queryParameterizedAttribute(_ attribute: String, input: Any) throws -> Any? {
        let legacyValue = legacyValue as! AXUIElement
        guard let input = input as? any ElementLegacy else {
            throw ElementError.illegalArgument
        }
        var output: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(legacyValue, attribute as CFString, input.legacyValue as CFTypeRef, &output)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .noValue, .parameterizedAttributeUnsupported, .systemFailure, .illegalArgument:
            return nil
        case .apiDisabled, .invalidElement, .notEnoughPrecision, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unrecognized error querying parameterized accessibility element attribute \(attribute): \(error)")
        }
        return fromLegacy(value: output)
    }

    /// Encodes a value into a format suitable to be serialized.
    /// - Parameter value: Value to encode.
    /// - Returns: Data structure suitable to be serialized.
    private func encode(value: Any) -> Any? {
        switch value {
        case is Bool, is Int64, is Double, is String:
            return value
        case let array as [Any?]:
            var resultArray = [Any]()
            resultArray.reserveCapacity(array.count)
            for element in array {
                guard let element = element, let element = encode(value: element) else {
                    continue
                }
                resultArray.append(element)
            }
            return resultArray
        case let dictionary as [String: Any]:
            var resultDictionary = [String: Any]()
            resultDictionary.reserveCapacity(dictionary.count)
            for pair in dictionary {
                guard let value = encode(value: pair.value) else {
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
        case let element as Element:
            return String(describing: element.legacyValue)
        case let error as ElementError:
            return "Error: \(error.localizedDescription)"
        default:
            return nil
        }
    }

    /// Checks whether this process is trusted and prompts the user to grant it accessibility privileges if it isn't.
    /// - Returns: Whether this process has accessibility privileges.
    @MainActor public static func confirmProcessTrustedStatus() -> Bool {
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}

extension Element: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(legacyValue as! AXUIElement)
    }

    public static nonisolated func ==(_ lhs: Element, _ rhs: Element) -> Bool {
        let lhs = lhs.legacyValue as! AXUIElement
        let rhs = rhs.legacyValue as! AXUIElement
        return lhs == rhs
    }
}
