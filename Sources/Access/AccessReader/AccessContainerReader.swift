import Element
import Output

/// Accessibility reader for containers like outlines and tables.
@AccessActor class AccessContainerReader: AccessGenericReader {
    /// Specializes the reader to also read the selected children of the wrapped container element.
    /// - Returns: Semantic accessibility output.
    override func read() async throws -> [OutputSemantic] {
        var content = try await super.read()
        content.append(contentsOf: try await readSelectedChildren())
        return content
    }

    /// Specializes the summary reader to also read the number of rows and columns when available for the wrapped container element.
    /// - Returns: Semantic accessibility output.
    override func readSummary() async throws -> [OutputSemantic] {
        var content = try await super.readSummary()
        if let rows = try await element.getAttribute(.rows) as? [Any?] {
            content.append(.rowCount(rows.count))
        }
        if let columns = try await element.getAttribute(.columns) as? [Any?] {
            content.append(.columnCount(columns.count))
        }
        return content
    }

    /// Reads the selected children of the wrapped container element.
    /// - Returns: Semantic accessibility output.
    private func readSelectedChildren() async throws -> [OutputSemantic] {
        let children = if let children = try await element.getAttribute(.selectedChildrenElements) as? [Any?], !children.isEmpty {
            children.compactMap({$0 as? Element})
        } else if let children = try await element.getAttribute(.selectedCells) as? [Any?] {
            children.compactMap({$0 as? Element})
        } else if let children = try await element.getAttribute(.selectedRows) as? [Any?] {
            children.compactMap({$0 as? Element})
        } else if let children = try await element.getAttribute(.selectedColumns) as? [Any?] {
            children.compactMap({$0 as? Element})
        } else {
            [Element]()
        }
        if children.count == 1, let child = children.first {
            let reader = try await AccessReader(for: child)
            return try await reader.readSummary()
        }
        return [.selectedChildrenCount(children.count)]
    }
}
