/// Methods that allow the output module to collect input information.
@MainActor public protocol OutputConveyerDelegate: AnyObject {
    /// Checks the state of the left and right arrow keys.
    /// - Returns: Whether either key is pressed.
    func checkHorizontalArrowKeyState() -> Bool
    /// Checks the state of the down and up arrow keys.
    /// - Returns: Whether either the down or up arrow keys are pressed.
    func checkVerticalArrowKeyState() -> Bool
    /// Checks the state of both Option modifier keys.
    /// - Returns: Whether either Option key modifier is pressed.
    func checkOptionModifierKeyState() -> Bool
}
