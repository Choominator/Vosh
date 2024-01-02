import Foundation

/// Dedicated thread to ensure that all interactions with the accessibility client interface run free of race conditions.
@globalActor public actor ConsumerActor {
    /// Shared singleton.
    public static let shared = ConsumerActor()
    /// Executor used by this actor.
    public static let sharedUnownedExecutor = Executor.shared.asUnownedSerialExecutor()

    /// Singleton initializer.
    private init() {}

    /// Convenience method that schedules a function to run on this actor's dedicated thread.
    /// - Parameters:
    ///   - resultType: Return type of the scheduled function.
    ///   - run: Function to run.
    /// - Returns: Whatever the function returns.
    public static func run<T: Sendable>(resultType _: T.Type = T.self, body run: @ConsumerActor () throws -> T) async rethrows -> T {
        return try await run()
    }

    /// Custom executor supporting ``ConsumerActor``.
    public final class Executor: SerialExecutor, @unchecked Sendable {
        /// Dedicated thread on which this executor will schedule jobs.
        // This object is not Sendable, but it's also never dereferenced from a different thread after being constructed.
        private var thread: Thread!
        /// Run loop that provides the actual scheduling.
        // Run loops are generally not thread-safe, but their perform method is.
        private var runLoop: RunLoop!
        /// Singleton of this executor.
        public static let shared = Executor()

        /// Singleton initializer.
        private init() {
            // Use an NSConditionLock as a poor man's barrier to prevent the initializer from returning before the thread starts and a run loop is assigned.
            let lock = NSConditionLock(condition: 0)
            thread = Thread() {[self] in
                lock.lock(whenCondition: 0)
                runLoop = RunLoop.current
                lock.unlock(withCondition: 1)
                runLoop.run()
            }
            lock.lock(whenCondition: 1)
            thread.name = "Accessibility"
            lock.unlock(withCondition: 0)
        }

        /// Schedules a job to be perform by this executor.
        /// - Parameter job: Job to be scheduled.
        public func enqueue(_ job: consuming ExecutorJob) {
            // I don't think this code is sound, but it is suggested in the custom actor executors Swift Evolution proposal.
            let job = UnownedJob(job)
            runLoop.perform({[unowned self] in job.runSynchronously(on: asUnownedSerialExecutor())})
        }
    }
}
