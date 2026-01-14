@preconcurrency import ApplicationServices

/// Swift wrapper for a legacy ``AXUIElement``.
@ElementActor public struct Element {
    // Legacy element.
    let element: AXUIElement

    /// Creates a system-wide element.
    public init() {
        element = AXUIElementCreateSystemWide()
    }

    /// Creates an application element for the specified PID.
    /// - Parameter processIdentifier: PID of the application.
    public init(processIdentifier: pid_t) {
        element = AXUIElementCreateApplication(processIdentifier)
    }

    /// Wraps a legacy ``AXUIElement``.
    /// - Parameter value: Legacy value to wrap.
    init(element: AXUIElement) {
        self.element = element
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
        var processIdentifier = pid_t(0)
        let result = AXUIElementGetPid(element, &processIdentifier)
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
        let result = AXUIElementSetMessagingTimeout(element, seconds)
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
    public func dump(recursiveParents: Bool = true, recursiveChildren: Bool = true) async throws -> [String: Sendable]? {
        do {
            var root = [String: Sendable]()
            let attributes = try listAttributes()
            var attributeValues = [String: Sendable]()
            for attribute in attributes {
                guard let value = try getAttribute(attribute) else {
                    continue
                }
                attributeValues[attribute] = encode(value: value)
            }
            root["attributes"] = attributeValues
            guard element != AXUIElementCreateSystemWide() else {
                return root
            }
            let parameterizedAttributes = try listParameterizedAttributes()
            root["parameterizedAttributes"] = parameterizedAttributes
            root["actions"] = try listActions()
            if recursiveParents, let parent = try getAttribute("AXParent") as? Element {
                root["parent"] = try await parent.dump(recursiveParents: true, recursiveChildren: false)
            }
            if recursiveChildren, let children = try getAttribute("AXChildren") as? [Any?] {
                var resultingChildren = [Sendable]()
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
    public func getAttribute(_ attribute: ElementAttribute) throws -> Sendable? {
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
    public func setAttribute(_ attribute: ElementAttribute, value: Sendable) throws {
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
    public func queryParameterizedAttribute(_ attribute: ElementParameterizedAttribute, input: Sendable) throws -> Sendable? {
        return try queryParameterizedAttribute(attribute.rawValue, input: input)
    }

    /// Creates a list of all the actions supported by this element.
    /// - Returns: List of actions.
    public func listActions() throws -> [String] {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
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
        guard let actions = [Sendable?](legacyValue: actions as CFTypeRef) else {
            return []
        }
        return actions.compactMap({$0 as? String})
    }

    /// Queries for a localized description of the specified action.
    /// - Parameter action: Action to query.
    /// - Returns: Description of the action.
    public func describeAction(_ action: String) throws -> String? {
        var description: CFString?
        let result = AXUIElementCopyActionDescription(element, action as CFString, &description)
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
        let result = AXUIElementPerformAction(element, action as CFString)
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
        var attributes: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &attributes)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's attribute names: \(error)")
        }
        guard let attributes = [Sendable?](legacyValue: attributes as CFTypeRef) else {
            return []
        }
        return attributes.compactMap({$0 as? String})
    }

    /// Reads the value associated with a given attribute of this element.
    /// - Parameter attribute: Attribute whose value is to be read.
    /// - Returns: Value of the attribute, if any.
    private func getAttribute(_ attribute: String) throws -> Sendable? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
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
    private func setAttribute(_ attribute: String, value: Sendable) throws {
        guard let value = value as? any ElementLegacy else {
            throw ElementError.illegalArgument
        }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef)
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
        var parameterizedAttributes: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(element, &parameterizedAttributes)
        let error = ElementError(from: result)
        switch error {
        case .success:
            break
        case .apiDisabled, .invalidElement, .notImplemented, .timeout:
            throw error
        default:
            fatalError("Unexpected error reading an accessibility element's parameterized attribute names: \(error)")
        }
        guard let parameterizedAttributes = [Sendable?](legacyValue: parameterizedAttributes as CFTypeRef) else {
            return []
        }
        return parameterizedAttributes.compactMap({$0 as? String})
    }

    /// Queries the specified parameterized attribute of this element.
    /// - Parameters:
    ///   - attribute: Parameterized attribute to query.
    ///   - input: Input value.
    /// - Returns: Output value.
    private func queryParameterizedAttribute(_ attribute: String, input: Sendable) throws -> Sendable? {
        guard let input = input as? any ElementLegacy else {
            throw ElementError.illegalArgument
        }
        var output: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, input.legacyValue as CFTypeRef, &output)
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
    private func encode(value: Sendable) -> Sendable? {
        switch value {
        case is Bool, is Int64, is Double, is String:
            return value
        case let array as [Sendable?]:
            var resultArray = [Sendable]()
            resultArray.reserveCapacity(array.count)
            for element in array {
                guard let element = element, let element = encode(value: element) else {
                    continue
                }
                resultArray.append(element)
            }
            return resultArray
        case let dictionary as [String: Sendable]:
            var resultDictionary = [String: Sendable]()
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
            return String(describing: element.element)
        case let error as ElementError:
            return "Error: \(error.localizedDescription)"
        default:
            return nil
        }
    }

    /// Checks whether this process is trusted, prompts the user to grant accessibility privileges if it isn't, and waits until they do or the task is cancelled.
    /// - Returns: Whether this process has accessibility privileges.
    @MainActor public static func confirmProcessTrustedStatus() async -> Bool {
        if AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            print("Permission already granted")
            return true
        }
        print("Permission denied")
        return false
    }
}

extension Element: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        let hashValue = ElementActor.Executor.shared.perform({element.hashValue})
        hasher.combine(hashValue)
    }

    public static nonisolated func ==(_ lhs: Element, _ rhs: Element) -> Bool {
        return ElementActor.Executor.shared.perform({lhs.element == rhs.element})
    }
}
