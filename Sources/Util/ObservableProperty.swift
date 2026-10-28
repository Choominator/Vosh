import Synchronization

@propertyWrapper public final class ObservableProperty<T: Sendable>: Sendable {
    public var wrappedValue: T {
        get {state.withLock({$0.value})}
        set {state.withLock({$0.value = newValue})}
    }

    public var projectedValue: AsyncStream<T> {
        let (source, sink) = AsyncStream.makeStream(of: T.self, bufferingPolicy: .bufferingNewest(1))
        state.withLock() {state in
            state.sinks.append(sink)
            sink.yield(state.value)
        }
        return source
    }

    private let state: Mutex<State>

    public init(wrappedValue: T) {
        state = Mutex(State(value: wrappedValue))
    }

    private struct State: ~Copyable {
        var value: T {didSet {sinks = sinks.filter({if case .terminated = $0.yield(value) {false} else {true}})}}
        var sinks = [AsyncStream<T>.Continuation]()

        deinit {
            sinks.forEach({$0.finish()})
        }
    }
}
