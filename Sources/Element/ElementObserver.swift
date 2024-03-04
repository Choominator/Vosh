import ApplicationServices

/// Observes an application's accessibility element for events, passing them down to their respective subscribers.
@ElementActor public final class ElementObserver {
    /// Event stream.
    public let eventStream: AsyncStream<ElementEvent>
    /// Legacy accessibility observer.
    private let observer: AXObserver
    /// Legacy accessibility element.
    private let element: AXUIElement
    /// Event stream continuation.
    private let eventContinuation: AsyncStream<ElementEvent>.Continuation

    /// Creates a new accessibility observer for the specified element.
    /// - Parameter element: Element to observe.
    public init(element: Element) async throws {
        self.element = element.legacyValue as! AXUIElement
        let processIdentifier = try element.getProcessIdentifier()
        var observer: AXObserver?
        let callBack: AXObserverCallbackWithInfo = {(_, element, notification, info, this) in
            let this = Unmanaged<ElementObserver>.fromOpaque(this!).takeUnretainedValue()
            let notification = notification as String
            let subject = Element(legacyValue: element)!
            // The following hack is necessary since info is optional but isn't marked as such.
            let payload = unsafeBitCast(info, to: Int.self) != 0 ? [String: Any](legacyValue: info) : nil
            let event = ElementEvent(notification: notification, subject: subject, payload: payload ?? [:])!
            this.eventContinuation.yield(event)
        }
        let result = AXObserverCreateWithInfoCallback(processIdentifier, callBack, &observer)
        let error = ElementError(from: result)
        guard error == .success, let observer = observer else {
            switch error {
            case .apiDisabled, .notImplemented, .timeout:
                throw error
            default:
                fatalError("Unexpected error creating an accessibility element observer: \(error)")
            }
        }
        self.observer = observer
        (eventStream, eventContinuation) = AsyncStream<ElementEvent>.makeStream()
        await MainActor.run() {
            let runLoopSource = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }

    /// Subscribes to be notified of specific state changes of the observed element.
    /// - Parameter notification: Notification to subscribe.
    public func subscribe(to notification: ElementNotification) throws {
        let result = AXObserverAddNotification(observer, element, notification.rawValue as CFString, Unmanaged.passUnretained(self).toOpaque())
        let error = ElementError(from: result)
        switch error {
        case .success, .notificationAlreadyRegistered:
            break
        case .apiDisabled, .invalidElement, .notificationUnsupported, .timeout:
            throw error
        default:
            fatalError("Unexpected error registering accessibility element notification \(notification.rawValue): \(error)")
        }
    }

    /// Unsubscribes from the specified notification of state changes to the observed element.
    /// - Parameter notification: Notification to unsubscribe.
    public func unsubscribe(from notification: ElementNotification) throws {
        let result = AXObserverRemoveNotification(observer, element, notification.rawValue as CFString)
        let error = ElementError(from: result)
        switch error {
        case .success, .notificationNotRegistered:
            break
        case .apiDisabled, .invalidElement, .notificationUnsupported, .timeout:
            throw error
        default:
            fatalError("Unexpected error unregistering accessibility element notification \(notification.rawValue): \(error)")
        }
    }

    deinit {
        eventContinuation.finish()
    }
}
