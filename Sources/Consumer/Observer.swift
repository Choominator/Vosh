import ApplicationServices

/// Observes an application's accessibility element for events, passing them down to their respective handlers.
@ConsumerActor public final class Observer {
    /// Element to observe.
    private let element: Element
    /// Accessibility observer's legacy type.
    private let observer: AXObserver
    /// Event handlers.
    private var listeners = [UInt64: AsyncStream<Event>.Continuation]()
    /// Incrementing listener ID generator.
    private var listenerCounter = UInt64(0)

    /// Creates a new accessibility observer for the specified application.
    /// - Parameter processIdentifier: PID of the application to observe.
    public init(processIdentifier: pid_t) async throws {
        element = Element(processIdentifier: processIdentifier)
        let element = element.legacyValue
        var observer: AXObserver?
        let callBack: AXObserverCallbackWithInfo = {(_, element, notification, info, this) in
            let this = Unmanaged<Observer>.fromOpaque(this!).takeUnretainedValue()
            let notification = Event.Notification(rawValue: notification as String)!
            let application = this.element
            let subject = Element(legacyValue: element)!
            let payload = unsafeBitCast(info, to: Int.self) != 0 ? [String: Any](legacyValue: info) : nil
            let event = Event(notification: notification, application: application, subject: subject, payload: payload)
            this.listeners.values.forEach({$0.yield(event)})
        }
        let result = AXObserverCreateWithInfoCallback(processIdentifier, callBack, &observer)
        let error = ConsumerError(from: result)
        guard error == .success, let observer = observer else {
            switch error {
            case .apiDisabled, .notImplemented, .timeout:
                throw error
            default:
                fatalError("Unexpected error creating an accessibility element observer: \(error.localizedDescription)")
            }
        }
        self.observer = observer
        for notification in Event.Notification.allCases {
            let result = AXObserverAddNotification(observer, element, notification.rawValue as CFString, Unmanaged.passUnretained(self).toOpaque())
            let error = ConsumerError(from: result)
            switch error {
            case .success:
                break
            case .notificationAlreadyRegistered, .notificationUnsupported:
                continue
            case .apiDisabled, .invalidElement, .timeout:
                throw error
            default:
                fatalError("Unexpected error registering accessibility element notification \(notification.rawValue): \(error.localizedDescription)")
            }
        }
        await MainActor.run() {
            let runLoopSource = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }

    /// Subscribes to this observer's event stream.
    /// - Parameter handleEventStream: Event stream handler.
    public func subscribe(with handleEventStream: @escaping (AsyncStream<Event>) async -> Void) {
        let (stream: stream, continuation: continuation) = AsyncStream.makeStream(of: Event.self)
        let identifier = listenerCounter
        listeners[identifier] = continuation
        listenerCounter += 1
        Task() {[weak self] in
            await handleEventStream(stream)
            self?.listeners[identifier] = nil
        }
    }

    deinit {
        listeners.values.forEach({$0.finish()})
    }
}
