/// Actor for the accessibility framework.
@globalActor public actor AccessActor {
    /// Shared singleton.
    public static let shared = AccessActor()

    /// Singleton initializer.
    private init() {}

    /// Convenience method that schedules a function to run on this actor's dedicated thread.
    /// - Parameters:
    ///   - resultType: Return type of the scheduled function.
    ///   - run: Function to run.
    /// - Returns: Whatever the function returns.
    public static func run<T: Sendable>(resultType _: T.Type = T.self, body run: @AccessActor () throws -> T) async rethrows -> T {
        return try await run()
    }
}
