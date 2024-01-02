/// Methods that allow the input module to communicate information to the user.
@MainActor public protocol InputHandlerDelegate: AnyObject {
    /// Called when a CapsLock state change occurs.
    /// - Parameter state: Whether CapsLock is enabled.
    func capsLockDidChangeState(to state: Bool)
}
