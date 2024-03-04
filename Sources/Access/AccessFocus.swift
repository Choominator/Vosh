import Element
import Output

/// User focus state.
@AccessActor struct AccessFocus {
    /// Focused entity.
    let entity: AccessEntity
    /// Reader for the focused entity.
    let reader: AccessReader

    /// Creates a new focus on the specified element.
    /// - Parameter element: Element to focus.
    init(on element: Element) async throws {
        let entity = try await AccessEntity(for: element)
        try await self.init(on: entity)
    }

    /// Creates a new focus on the specified entity.
    /// - Parameter entity: Entity to focus.
    init(on entity: AccessEntity) async throws {
        self.entity = entity
        reader = try await AccessReader(for: entity.element)
    }
}
