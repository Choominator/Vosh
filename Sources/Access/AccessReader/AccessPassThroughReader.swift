import Element
import Output

/// Accessibility reader for elements that must be ignored and have all of their children's summaries read instead.
@AccessActor class AccessPassThroughReader: AccessGenericReader {
    /// Reads all of this element's children summaries.
    /// - Returns: Semantic accessibility output.
    override func readSummary() async throws -> [OutputSemantic] {
        let children = if let children = try await element.getAttribute(.childElementsInNavigationOrder) as? [Any?] {
            children
        } else if let children = try await element.getAttribute(.childElements) as? [Any?] {
            children
        } else {
            []
        }
        var content = [OutputSemantic]()
        for child in children.lazy.compactMap({$0 as? Element}) {
            let reader = try await AccessReader(for: child)
            content.append(contentsOf: try await reader.readSummary())
        }
        return content
    }
}
