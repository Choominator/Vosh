import Foundation
@preconcurrency import CoreFoundation

/// Dedicated thread to ensure that all interactions with the accessibility client interface run free of race conditions.
@globalActor public actor ElementActor {
    /// Shared singleton.
    public static let shared = ElementActor()
    /// Executor used by this actor.
    public static let sharedUnownedExecutor = Executor.shared.asUnownedSerialExecutor()

    /// Singleton initializer.
    private init() {}

    /// Convenience method that schedules a function to run on this actor's dedicated thread.
    /// - Parameters:
    ///   - resultType: Return type of the scheduled function.
    ///   - run: Function to run.
    /// - Returns: Whatever the function returns.
    public static func run<T: Sendable>(resultType _: T.Type = T.self, body run: @ElementActor () throws -> T) async rethrows -> T {
        return try await run()
    }
}

extension ElementActor {
    /// Custom executor supporting ``ElementActor``.
    public final class Executor: SerialExecutor, @unchecked Sendable {
        /// Run loop that provides the actual scheduling.
        // Run loops are generally not thread-safe, but scheduling execution and adding event sources to them are safe operations.
        var runLoop: RunLoop!
        /// Dedicated thread on which this executor will schedule jobs.
        // This object is not Sendable, but it's also never dereferenced from a different thread except for comparing its identity with other threads after being constructed.
        private var thread: Thread!
        /// Singleton of this executor.
        public static let shared = Executor()

        /// Singleton initializer.
        private init() {
            // Use an NSConditionLock as a poor man's barrier to prevent the initializer from returning before the thread starts and a run loop is assigned.
            let lock = NSConditionLock(condition: 0)
            thread = Thread() {[self] in
                lock.lock(whenCondition: 0)
                runLoop = RunLoop.current
                let runLoop = runLoop.getCFRunLoop()
                // Add an idle event source to the thread's run loop to prevent it from returning and exiting the thread.
                var context = CFRunLoopSourceContext()
                context.copyDescription = { _ in
                    let description = "Accessibility idle event source"
                    let copy = CFStringCreateCopy(kCFAllocatorDefault, description as CFString)!
                    return Unmanaged.passRetained(copy)
                }
                context.perform = { _ in
                    assertionFailure("Accessibility element idle event source fired unexpectedly")
                }
                context.version = 0
                let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                lock.unlock(withCondition: 1)
                CFRunLoopRun()
            }
            thread.start()
            lock.lock(whenCondition: 1)
            thread.name = "Element"
            lock.unlock(withCondition: 0)
        }

        /// Schedules a job to be perform by this executor.
        /// - Parameter job: Job to be scheduled.
        public func enqueue(_ job: consuming ExecutorJob) {
            // I don't think this code is sound, but it is suggested in the custom actor executors Swift Evolution proposal.
            let job = UnownedJob(job)
            runLoop.perform({[unowned self] in job.runSynchronously(on: asUnownedSerialExecutor())})
        }

        /// Aborts execution if a dynamic strict concurrency verification fails.
        public func checkIsolated() {
            guard Thread.current == thread else {
                fatalError("Accessibility executor context isolation verification failed")
            }
        }

        /// Builds an unowned reference to this executor.
        /// - Returns: Built unowned reference.
        public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
            return UnownedSerialExecutor(ordinary: self)
        }

        /// Performs a job synchronously in this actor's isolation context.
        /// - Parameter job: Job to perform.
        /// - Returns: Whatever the job returns.
        ///
        /// ## Discussion
        ///
        /// This method blocks the calling thread until the provided closure returns. If the calling thread is this executor's dedicated thread, then no scheduling is done, and the closure is invoked immediately.
        public func perform<T : Sendable>(_ job: @ElementActor () -> T) -> T {
            return withoutActuallyEscaping(job) {job in
                let job = unsafeBitCast(job, to: (@Sendable () -> T).self)
                if Thread.current == thread {
                    return job()
                }
                let invocation = UnsafeInvocation(job)
                invocation.perform(#selector(UnsafeInvocation<T>.invoke), on: thread, with: nil, waitUntilDone: true)
                return invocation.result
            }
        }
    }
}

extension ElementActor.Executor {
    /// Takes advantage of the ability to execute code synchronously on other threads already available in ``NSObject``.
    private final class UnsafeInvocation<T: Sendable>: NSObject {
        /// Job to execute.
        private let job: @Sendable () -> T
        /// Execution result.
        var result: T!

        /// Creates a new unsafe invocation for the supplied job.
        /// - Parameter job: Job to invoke.
        init(_ job: @escaping @Sendable () -> T) {
            self.job = job
            super.init()
        }

        /// Invokes the job.
        ///
        /// ## Discussion
        ///
        /// Always make sure to invoke this on the executor's managed thread.
        @objc fileprivate func invoke() {
            result = job()
        }
    }
}
