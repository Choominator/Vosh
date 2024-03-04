import Foundation
import OSLog

import Element
import Output

/// Unspecialized accessibility reader.
@AccessActor class AccessGenericReader {
    /// Element to read.
    let element: Element
    /// System logging facility.
    private static let logger = Logger()

    /// Creates a generic accessibility reader.
    /// - Parameter element: Element to read.
    init(for element: Element) async throws {
        self.element = element
    }

    /// Reads the accessibility content of the wrapped element.
    /// - Returns: Semantically described output content.
    func read() async throws -> [OutputSemantic] {
        var content = try await readSummary()
        content.append(contentsOf: try await readRole())
        content.append(contentsOf: try await readState())
        content.append(contentsOf: try await readHelp())
        return content
    }

    /// Reads a short description of the wrapped element.
    /// - Returns: Semantically described output content.
    func readSummary() async throws -> [OutputSemantic] {
        var content = [OutputSemantic]()
        content.append(contentsOf: try await readLabel())
        content.append(contentsOf: try await readValue())
        return content
    }

    /// Reads the accessibility label of the wrapped element.
    /// - Returns: Semantically described output content.
    func readLabel() async throws -> [OutputSemantic] {
        if let title = try await element.getAttribute(.title) as? String, !title.isEmpty {
            return [.label(title)]
        }
        if let element = try await element.getAttribute(.titleElement) as? Element, let title = try await element.getAttribute(.title) as? String, !title.isEmpty {
            return [.label(title)]
        }
        if let description = try await element.getAttribute(.description) as? String, !description.isEmpty {
            return [.label(description)]
        }
        return []
    }

    /// Reads the value of the wrapped element.
    /// - Returns: Semantically described output content.
    func readValue() async throws -> [OutputSemantic] {
        var content = [OutputSemantic]()
        let value: Any? = if let value = try await element.getAttribute(.valueDescription) as? String, !value.isEmpty {
            value
        } else if let value = try await element.getAttribute(.value) {
            value
        } else {
            nil
        }
        guard let value = value else {
            return []
        }
        switch value {
        case let bool as Bool:
            content.append(.boolValue(bool))
        case let integer as Int64:
            content.append(.intValue(integer))
        case let float as Double:
            content.append(.floatValue(float))
        case let string as String:
            content.append(.stringValue(string))
            if let selection = try await element.getAttribute(.selectedText) as? String, !selection.isEmpty {
                content.append(.selectedText(selection))
            }
        case let attributedString as AttributedString:
            let string = String(attributedString.characters)
            content.append(.stringValue(string))
            if let selection = try await element.getAttribute(.selectedText) as? String, !selection.isEmpty {
                content.append(.selectedText(selection))
            }
        case let url as URL:
            content.append(.urlValue(url.absoluteString))
        default:
            Self.logger.warning("Unexpected value type: \(type(of: value), privacy: .public)")
        }
        if let edited = try await element.getAttribute(.edited) as? Bool, edited {
            content.append(.edited)
        }
        if let placeholder = try await element.getAttribute(.placeholderValue) as? String, !placeholder.isEmpty {
            content.append(.placeholderValue(placeholder))
        }
        return content
    }

    /// Reads the accessibility role of the wrapped element.
    /// - Returns: Semantically described output content.
    func readRole() async throws -> [OutputSemantic] {
        if let description = try await element.getAttribute(.description) as? String, !description.isEmpty {
            return []
        } else if let role = try await element.getAttribute(.roleDescription) as? String, !role.isEmpty {
            return [.role(role)]
        }
        return []
    }

    /// Reads the state of the wrapped element.
    /// - Returns: Semantically described output content.
    func readState() async throws -> [OutputSemantic] {
        var output = [OutputSemantic]()
        if let selected = try await element.getAttribute(.selected) as? Bool, selected {
            output.append(.selected)
        }
        if let enabled = try await element.getAttribute(.isEnabled) as? Bool, !enabled {
            output.append(.disabled)
        }
        return output
    }

    /// Reads the help information of the wrapped element.
    /// - Returns: Semantically described output content.
    func readHelp() async throws -> [OutputSemantic] {
        if let help = try await element.getAttribute(.help) as? String, !help.isEmpty {
            return [.help(help)]
        }
        return []
    }
}
