/// Wrapper around an event produced by the legacy consumer accessibility API.
public struct ElementEvent {
    /// Event notification.
    public let notification: ElementNotification
    /// Element generating this event.
    public let subject: Element
    /// Event payload.
    public let payload: [PayloadKey: Any]?

    /// Creates an event for the specified notification, related to the specified subject, and with the specified payload.
    /// - Parameters:
    ///   - notification: Notification that triggered this event.
    ///   - subject: Element to which this notification belongs.
    ///   - payload: Additional data sent with the notification.
    init?(notification: String, subject: Element, payload: [String: Any]) {
        guard let notification = ElementNotification(rawValue: notification) else {
            return nil
        }
        let payload = payload.reduce([PayloadKey: Any]()) {(previous, value) in
            guard let key = PayloadKey(rawValue: value.key) else {
                return previous
            }
            var next = previous
            next[key] = value.value
            return previous
        }
        self.notification = notification
        self.subject = subject
        self.payload = payload
    }
}
