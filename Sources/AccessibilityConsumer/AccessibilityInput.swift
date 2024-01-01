import Foundation
import CoreGraphics
import IOKit

/// Input handler.
@MainActor final class AccessibilityInput {
    /// Input state.
    private let state = State()
    /// CapsLock stream event continuation.
    private let capsLockContinuation: AsyncStream<(timestamp: UInt64, isDown: Bool)>.Continuation
    /// Modifier stream event continuation.
    private var modifierContinuation: AsyncStream<(key: ModifierKeyCode, isDown: Bool)>.Continuation
    /// Keyboard tap event stream continuation.
    private let keyboardTapContinuation: AsyncStream<CGEvent>.Continuation
    /// Legacy Human Interface Device manager instance.
    private let hidManager: IOHIDManager
    /// CapsLock event service handle.
    private var connect = io_connect_t(0)
    /// Tap into the windoe server's input events.
    private var eventTap: CFMachPort!
    /// Task handling CapsLock events.
    private var capsLockTask: Task<Void, Never>!
    /// Task handling modifier key events.
    private var modifierTask: Task<Void, Never>!
    /// Task handling keyboard window server tap events.
    private var keyboardTapTask: Task<Void, Never>!

    /// Browse mode state.
    var browseModeEnabled: Bool {get {state.browseModeEnabled} set {state.browseModeEnabled = newValue}}

    /// Creates a new input handler.
    init() {
        let (capsLockStream, capsLockContinuation) = AsyncStream<(timestamp: UInt64, isDown: Bool)>.makeStream()
        let (modifierStream, modifierContinuation) = AsyncStream<(key: ModifierKeyCode, isDown: Bool)>.makeStream()
        let (keyboardTapStream, keyboardTapContinuation) = AsyncStream<CGEvent>.makeStream()
        self.capsLockContinuation = capsLockContinuation
        self.modifierContinuation = modifierContinuation
        self.keyboardTapContinuation = keyboardTapContinuation
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = [[kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard], [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad]]
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, matches as CFArray)
        let capsLockCallback: IOHIDValueCallback = {(this, _, _, value) in
            let this = Unmanaged<AccessibilityInput>.fromOpaque(this!).takeUnretainedValue()
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let timestamp = IOHIDValueGetTimeStamp(value)
            let element = IOHIDValueGetElement(value)
            let scanCode = IOHIDElementGetUsage(element)
            guard let modifierKeyCode = ModifierKeyCode(rawValue: Int64(scanCode)) else {
                return
            }
            if modifierKeyCode == .capsLock {
                this.capsLockContinuation.yield((timestamp: timestamp, isDown: isDown))
            }
            this.modifierContinuation.yield((key: modifierKeyCode, isDown: isDown))
        }
        IOHIDManagerRegisterInputValueCallback(hidManager, capsLockCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state.capsLockEnabled)
        let keyboardTapCallback: CGEventTapCallBack = {(_, _, event, this) in
            let this = Unmanaged<AccessibilityInput>.fromOpaque(this!).takeUnretainedValue()
            guard this.state.capsLockPressed || this.state.browseModeEnabled else {
                return Unmanaged.passUnretained(event)
            }
            this.keyboardTapContinuation.yield(event)
            return nil
        }
        guard let eventTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: 1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue | 1 << CGEventType.flagsChanged.rawValue, callback: keyboardTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fatalError("Failed to create a keyboard event tap")
        }
        let eventRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventRunLoopSource, CFRunLoopMode.defaultMode)
        capsLockTask = Task(operation: {[unowned self] in await handleCapsLockStream(capsLockStream)})
        modifierTask = Task(operation: {[unowned self] in await handleModifierStream(modifierStream)})
        keyboardTapTask = Task(operation: {[unowned self] in await handleKeyboardTapStream(keyboardTapStream)})
    }

    deinit {
        capsLockTask.cancel()
        modifierTask.cancel()
        keyboardTapTask.cancel()
        IOServiceClose(connect)
    }

    /// Binds a key to an action with optional modifiers.
    /// - Parameters:
    ///   - browseMode: Requires browse mode.
    ///   - controlModifier: Requires the Control modifier key to be pressed.
    ///   - optionModifier: Requires the Option modifier key to be pressed.
    ///   - commandModifier: Requires the Command modifier key to be pressed.
    ///   - shiftModifier: Requires the Shift modifier key to be pressed.
    ///   - key: Key to bind.
    ///   - action: Action to perform when the key combination is pressed.
    func bindKey(browseMode: Bool = false, controlModifier: Bool = false, optionModifier: Bool = false, commandModifier: Bool = false, shiftModifier: Bool = false, key: KeyCode, action: @escaping () async -> Void) {
        let keyBinding = KeyBinding(browseMode: browseMode, controlModifier: controlModifier, optionModifier: optionModifier, commandModifier: commandModifier, shiftModifier: shiftModifier, key: key)
        guard state.keyBindings.updateValue(action, forKey: keyBinding) == nil else {
            fatalError("Attempted to bind the same key combination twice")
        }
    }

    /// Binds the specified modifier key to an action.
    /// - Parameters:
    ///   - key: Modifier key to bind.
    ///   - action: Action to execute when the key is pressed.
    func bindModifierKey(_ key: ModifierKeyCode, action: @escaping () async -> Void) {
        guard state.modifierKeyBindings.updateValue(action, forKey: key) == nil else {
            fatalError("Attempted to bind the same key modifier twice")
        }
    }

    func checkKeyState(_ key: KeyCode) -> Bool {
        return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key.rawValue))
    }

    /// Checks the current state of the Control modifier key.
    /// - Returns: Whether the key is pressed.
    func checkControlState() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return flags.contains(.maskControl)
    }

    /// Checks the current state of the Option modifier key.
    /// - Returns: Whether the key is pressed.
    func checkOptionState() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return flags.contains(.maskAlternate)
    }

    /// Checks the current state of the Command modifier key.
    /// - Returns: Whether the key is pressed.
    func checkCommandState() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return flags.contains(.maskCommand)
    }

    /// Checks the current state of the Shift modifier key.
    /// - Returns: Whether the key is pressed.
    func checkShiftState() -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return flags.contains(.maskShift)
    }

    /// Handles the stream of CapsLock events.
    /// - Parameter capsLockStream: Stream of CapsLock events.
    private func handleCapsLockStream(_ capsLockStream: AsyncStream<(timestamp: UInt64, isDown: Bool)>) async {
        for await (timestamp: timestamp, isDown: isDown) in capsLockStream {
            state.capsLockPressed = isDown
            var timeBase = mach_timebase_info(numer: 0, denom: 0)
            mach_timebase_info(&timeBase)
            let timestamp = timestamp / UInt64(timeBase.denom) * UInt64(timeBase.numer)
            if state.lastCapsLockEvent + 250000000 > timestamp && isDown {
                state.lastCapsLockEvent = 0
                state.capsLockEnabled.toggle()
                IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), state.capsLockEnabled)
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x39, keyDown: state.capsLockEnabled)
                event?.post(tap: .cghidEventTap)
                continue
            }
            IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), state.capsLockEnabled)
            if isDown {
                state.lastCapsLockEvent = timestamp
            }
        }
    }

    /// Handles the stream of modifier key events.
    /// - Parameter modifierStream: Stream of modifier key events.
    func handleModifierStream(_ modifierStream: AsyncStream<(key: ModifierKeyCode, isDown: Bool)>) async {
        for await event in modifierStream {
            if event.isDown {
                state.lastModifierPressed = event.key
                continue
            }
            if let lastModifierPressed = state.lastModifierPressed, lastModifierPressed == event.key, let action = state.modifierKeyBindings[event.key] {
                await action()
            }
            state.lastModifierPressed = nil
        }
    }

    /// Handles the stream of keyboard tap events.
    /// - Parameter keyboardTapStream: Stream of keyboard tap events.
    private func handleKeyboardTapStream(_ keyboardTapStream: AsyncStream<CGEvent>) async {
        for await event in keyboardTapStream {
            state.lastModifierPressed = nil
            guard event.type == .keyDown else {
                continue
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard let keyCode = KeyCode(rawValue: keyCode) else {
                continue
            }
            let browseMode = state.browseModeEnabled && !state.capsLockPressed
            let controlModifier = event.flags.contains(.maskControl)
            let optionModifier = event.flags.contains(.maskAlternate)
            let commandModifier = event.flags.contains(.maskCommand)
            let shiftModifier = event.flags.contains(.maskShift)
            let keyBinding = KeyBinding(browseMode: browseMode, controlModifier: controlModifier, optionModifier: optionModifier, commandModifier: commandModifier, shiftModifier: shiftModifier, key: keyCode)
            guard let action = state.keyBindings[keyBinding] else {
                continue
            }
            await action()
        }
    }

    /// Window server tap event key codes for US ANSI keyboards.
    enum KeyCode: Int64 {
        case keyboardA = 0x0
        case keyboardB = 0xb
        case keyboardC = 0x8
        case keyboardD = 0x2
        case keyboardE = 0xe
        case keyboardF = 0x3
        case keyboardG = 0x5
        case keyboardH = 0x4
        case keyboardI = 0x22
        case keyboardJ = 0x26
        case keyboardK = 0x28
        case keyboardL = 0x25
        case keyboardM = 0x2e
        case keyboardN = 0x2d
        case keyboardO = 0x1f
        case keyboardP = 0x23
        case keyboardQ = 0xc
        case keyboardR = 0xf
        case keyboardS = 0x1
        case keyboardT = 0x11
        case keyboardU = 0x20
        case keyboardV = 0x9
        case keyboardW = 0xd
        case keyboardX = 0x7
        case keyboardY = 0x10
        case keyboardZ = 0x6
        case keyboard1AndExclamation = 0x12
        case keyboard2AndAtt = 0x13
        case keyboard3AndHash = 0x14
        case keyboard4AndDollar = 0x15
        case keyboard5AndPercent = 0x17
        case keyboard6AndCaret = 0x16
        case keyboard7AndAmp = 0x1a
        case keyboard8AndStar = 0x1c
        case keyboard9AndLeftParen = 0x19
        case keyboard0AndRightParen = 0x1d
        case keyboardReturn = 0x24
        case keyboardEscape = 0x35
        case keyboardBackDelete = 0x33
        case keyboardTab = 0x30
        case keyboardSpace = 0x31
        case keyboardMinusAndUnderscore = 0x1b
        case keyboardEqualsAndPlus = 0x18
        case keyboardLeftBracketAndBrace = 0x21
        case keyboardRightBracketAndBrace = 0x1e
        case keyboardBackSlashAndVertical = 0x2a
        case keyboardSemiColonAndColon = 0x29
        case keyboardApostropheAndQuote = 0x27
        case keyboardGraveAccentAndTilde = 0x32
        case keyboardCommaAndLeftAngle = 0x2b
        case keyboardPeriodAndRightAngle = 0x2f
        case keyboardSlashAndQuestion = 0x2c
        case keyboardF1 = 0x7a
        case keyboardF2 = 0x78
        case keyboardF3 = 0x63
        case keyboardF4 = 0x76
        case keyboardF5 = 0x60
        case keyboardF6 = 0x61
        case keyboardF7 = 0x62
        case keyboardF8 = 0x64
        case keyboardF9 = 0x65
        case keyboardF10 = 0x6d
        case keyboardF11 = 0x67
        case keyboardF12 = 0x6f
        case keyboardHome = 0x73
        case keyboardPageUp = 0x74
        case keyboardDelete = 0x75
        case keyboardEnd = 0x77
        case keyboardPageDown = 0x79
        case keyboardLeftArrow = 0x7b
        case keyboardRightArrow = 0x7c
        case keyboardDownArrow = 0x7d
        case keyboardUpArrow = 0x7e
        case keypadNumLock = 0x47
        case keypadDivide = 0x4b
        case keypadMultiply = 0x43
        case keypadSubtract = 0x4e
        case keypadAdd = 0x45
        case keypadEnter = 0x4c
        case keypad1AndEnd = 0x53
        case keypad2AndDownArrow = 0x54
        case keypad3AndPageDown = 0x55
        case keypad4AndLeftArrow = 0x56
        case keypad5 = 0x57
        case keypad6AndRightArrow = 0x58
        case keypad7AndHome = 0x59
        case keypad8AndUpArrow = 0x5b
        case keypad9AndPageUp = 0x5c
        case keypad0 = 0x52
        case keypadDecimalAndDelete = 0x41
        case keypadEquals = 0x51
        case keyboardF13 = 0x69
        case keyboardF14 = 0x6b
        case keyboardF15 = 0x71
        case keyboardF16 = 0x6a
        case keyboardF17 = 0x40
        case keyboardF18 = 0x4f
        case keyboardF19 = 0x50
        case keyboardF20 = 0x5a
        case keyboardVolumeUp = 0x48
        case keyboardVolumeDown = 0x49
        case keyboardVolumeMute = 0x4a
        case keyboardHelp = 0x72
    }

    /// Low level system key codes for modifier keys.
    enum ModifierKeyCode: Int64 {
        case capsLock = 0x39
        case leftShift = 0xe1
        case leftControl = 0xe0
        case leftOption = 0xe2
        case leftCommand = 0xe3
        case rightShift = 0xe5
        case rightControl = 0xe4
        case rightOption = 0xe6
        case rightCommand = 0xe7
        case function = 0x3
    }

    /// Input state.
    private final class State {
        /// Whether browse mode is enabled.
        var browseModeEnabled = false
        /// Mach timestamp of the last CapsLock key press event.
        var lastCapsLockEvent = UInt64(0)
        /// Whether CapsLock is enabled.
        var capsLockEnabled = false
        /// Whether CapsLock is being pressed.
        var capsLockPressed = false
        /// Map of key bindings to their respective actions.
        var keyBindings = [KeyBinding: () async -> Void]()
        /// Map of modifier key bindings to their respective actions.
        var modifierKeyBindings = [ModifierKeyCode: () async -> Void]()
        /// Key code of the last modifier key pressed.
        var lastModifierPressed: ModifierKeyCode?
    }
    
    /// Key to the key bindings map.
    private struct KeyBinding: Hashable {
        /// Whether browse mode is required.
        let browseMode: Bool
        /// Whether the Control key modifier is required.
        let controlModifier: Bool
        /// Whether the Option key modifier is required.
        let optionModifier: Bool
        /// Whether the Command key modifier is required.
        let commandModifier: Bool
        /// Whether the Shift key modifier is required.
        let shiftModifier: Bool
        /// Bound key.
        let key: KeyCode
    }
}
