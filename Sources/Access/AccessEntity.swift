import Element

/// Convenience wrapper around an accessibility element.
@AccessActor final class AccessEntity {
    /// Wrapped accessibility element.
    let element: Element

    /// Creates an accessibility entity wrapping the specified element.
    /// - Parameter element: Element to wrap.
    init(for element: Element) async throws {
        self.element = element
    }

    /// Retrieves the interesting parent of this entity.
    /// - Returns: Retrieved entity.
    func getParent() async throws -> AccessEntity? {
        guard let parent = try await Self.findParent(of: element) else {
            return nil
        }
        return try await AccessEntity(for: parent)
    }

    /// Retrieves the first interesting child of this entity.
    /// - Returns: Child of this entity.
    func getFirstChild() async throws -> AccessEntity? {
        guard let child = try await Self.findFirstChild(of: element, backwards: false) else {
            return nil
        }
        return try await AccessEntity(for: child)
    }

    /// Retrieves the next interesting sibling of this entity.
    /// - Parameter backwards: Whether to move backwards.
    /// - Returns: Sibling of this entity.
    func getNextSibling(backwards: Bool) async throws -> AccessEntity? {
        guard let element = try await Self.findNextSibling(of: element, backwards: backwards) else {
            return nil
        }
        return try await AccessEntity(for: element)
    }

    /// Attempts to set the keyboard focus to the wrapped element.
    func setKeyboardFocus() async throws {
        do {
            try await element.setAttribute(.isFocused, value: true)
            guard let role = try await element.getAttribute(.role) as? ElementRole else {
                return
            }
            switch role {
            case .button, .checkBox, .colorWell, .comboBox,
                    .dateField, .incrementer, .link, .menuBarItem,
                    .menuButton, .menuItem, .popUpButton, .radioButton,
                    .slider, .textArea, .textField, .timeField:
                break
            default:
                return
            }
            if let isFocused = try await element.getAttribute(.isFocused) as? Bool, isFocused {
                return
            }
            if let focusableAncestor = try await element.getAttribute(.focusableAncestor) as? Element {
                try await focusableAncestor.setAttribute(.isFocused, value: true)
            }
        } catch ElementError.attributeUnsupported {
            return
        } catch {
            throw error
        }
    }

    /// Checks whether this entity is a focusable ancestor of the provided entity.
    /// - Parameter entity: Child entity.
    /// - Returns: Whether the provided entity is a child of this entity.
    func isInFocusGroup(of entity: AccessEntity) async throws -> Bool {
        guard let element = try await element.getAttribute(.focusableAncestor) as? Element else {
            return false
        }
        return element == entity.element
    }

    /// Looks for an interesting parent of the specified element.
    /// - Parameter element: Element whose parent is to be searched.
    /// - Returns: Interesting parent.
    private static func findParent(of element: Element) async throws -> Element? {
        guard let parent = try await element.getAttribute(.parentElement) as? Element, try await !isRoot(element: parent) else {
            return nil
        }
        guard try await isInteresting(element: parent) else {
            return try await findParent(of: parent)
        }
        return parent
    }

    /// Looks for the next interesting sibling of the specified element.
    /// - Parameters:
    ///   - element: Element whose next sibling is to search.
    ///   - backwards: Whehter to walk backwards.
    /// - Returns: Found sibling, if any.
    private static func findNextSibling(of element: Element, backwards: Bool) async throws -> Element? {
        guard let parent = try await element.getAttribute(.parentElement) as? Element else {
            return nil
        }
        let siblings: [Element]? = if let siblings = try await parent.getAttribute(.childElementsInNavigationOrder) as? [Any?] {
            siblings.compactMap({$0 as? Element})
        } else if let siblings = try await element.getAttribute(.childElements) as? [Any?] {
            siblings.compactMap({$0 as? Element})
        } else {
            nil
        }
        guard let siblings = siblings, !siblings.isEmpty else {
            return nil
        }
        var orderedSiblings = siblings
        if backwards {
            orderedSiblings.reverse()
        }
        for sibling in orderedSiblings.drop(while: {$0 != element}).dropFirst() {
            if try await isInteresting(element: sibling) {
                return sibling
            }
            if let child = try await findFirstChild(of: sibling, backwards: backwards) {
                return child
            }
        }
        guard try await !isRoot(element: parent), try await !isInteresting(element: parent) else {
            return nil
        }
        return try await findNextSibling(of: parent, backwards: backwards)
    }

    /// Looks for the first interesting child of the specified element.
    /// - Parameters:
    ///   - element: Element to search.
    ///   - backwards: Whether to walk backwards.
    /// - Returns: Suitable child element.
    private static func findFirstChild(of element: Element, backwards: Bool) async throws -> Element? {
        if try await isLeaf(element: element) {
            return nil
        }
        let children: [Element]? = if let children = try await element.getAttribute(.childElementsInNavigationOrder) as? [Any?] {
            children.compactMap({$0 as? Element})
        } else if let children = try await element.getAttribute(.childElements) as? [Any?] {
            children.compactMap({$0 as? Element})
        } else {
            nil
        }
        guard let children = children, !children.isEmpty else {
            return nil
        }
        var orderedChildren = children
        if backwards {
            orderedChildren.reverse()
        }
        for child in orderedChildren {
            if try await isInteresting(element: child) {
                return child
            }
            if try await isLeaf(element: child) {
                return nil
            }
            if let child = try await findFirstChild(of: child, backwards: backwards) {
                return child
            }
        }
        return nil
    }

    /// Checks whether the specified element has accessibility relevance.
    /// - Parameter element: Element to test.
    /// - Returns: Result of the test.
    private static func isInteresting(element: Element) async throws -> Bool {
        if let isFocused = try await element.getAttribute(.isFocused) as? Bool, isFocused {
            return true
        }
        if let title = try await element.getAttribute(.title) as? String, !title.isEmpty {
            return true
        }
        if let description = try await element.getAttribute(.description) as? String, !description.isEmpty {
            return true
        }
        guard let role = try await element.getAttribute(.role) as? ElementRole else {
            return false
        }
        switch role {
        case .browser, .busyIndicator, .button, .cell,
                .checkBox, .colorWell, .comboBox, .dateField,
                .disclosureTriangle, .dockItem, .drawer, .grid,
                .growArea, .handle, .heading, .image,
                .levelIndicator, .link, .list, .menuBarItem,
                .menuItem, .menuButton, .outline, .popUpButton, .popover,
                .progressIndicator, .radioButton, .relevanceIndicator, .sheet,
                .slider, .staticText, .tabGroup, .table,
                .textArea, .textField, .timeField, .toolbar,
                .valueIndicator, .webArea:
            let isLeaf = try await isLeaf(element: element)
            let hasWebAncestor = try await hasWebAncestor(element: element)
            return !hasWebAncestor || hasWebAncestor && isLeaf
        default:
            return false
        }
    }

    /// Checks whether the specified element is considered to not have parents.
    /// - Parameter element: Element to test.
    /// - Returns: Result of the test.
    private static func isRoot(element: Element) async throws -> Bool {
        guard let role = try await element.getAttribute(.role) as? ElementRole else {
            return false
        }
        switch role {
        case .menu, .menuBar, .window:
            return true
        default:
            return false
        }
    }

    /// Checks whether the specified element is considered to not have children.
    /// - Parameter element: Element to test.
    /// - Returns: Result of the test.
    private static func isLeaf(element: Element) async throws -> Bool {
        guard let role = try await element.getAttribute(.role) as? ElementRole else {
            return false
        }
        switch role {
        case .busyIndicator, .button, .checkBox, .colorWell,
                .comboBox, .dateField, .disclosureTriangle, .dockItem,
                .heading, .image, .incrementer, .levelIndicator,
                .link, .menuBarItem, .menuButton, .menuItem,
                .popUpButton, .progressIndicator, .radioButton, .relevanceIndicator,
                .scrollBar, .slider, .staticText, .textArea,
                .textField, .timeField, .valueIndicator:
            return true
        default:
            return false
        }
    }

    /// Checks whether the specified element has web area ancestry.
    /// - Parameter element: Element to verify.
    /// - Returns: Whether the element has a web ancestor.
    private static func hasWebAncestor(element: Element) async throws -> Bool {
        guard let parent = try await element.getAttribute(.parentElement) as? Element else {
            return false
        }
        guard let role = try await parent.getAttribute(.role) as? ElementRole else {
            return false
        }
        if role == .webArea {
            return true
        }
        return try await hasWebAncestor(element: parent)
    }
}
