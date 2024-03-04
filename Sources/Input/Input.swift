import Foundation
import CoreGraphics
import IOKit

import Output

/// Input handler.
@MainActor public final class Input {
    /// Keys currently being pressed.
    public private(set) var regularKeys = Set<InputKeyCode>()
    /// Modifiers currently being pressed.
    public private(set) var modifierKeys = Set<InputModifierKeyCode>()
    /// Input state.
    private let state = State()
    /// CapsLock stream event continuation.
    private let capsLockContinuation: AsyncStream<(timestamp: UInt64, isDown: Bool)>.Continuation
    /// Modifier stream event continuation.
    private var modifierContinuation: AsyncStream<(key: InputModifierKeyCode, isDown: Bool)>.Continuation
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
    /// Shared singleton.
    public static let shared = Input()

    /// Browse mode state.
    public var browseModeEnabled: Bool {get {state.browseModeEnabled} set {state.browseModeEnabled = newValue}}

    /// Creates a new input handler.
    private init() {
        let (capsLockStream, capsLockContinuation) = AsyncStream<(timestamp: UInt64, isDown: Bool)>.makeStream()
        let (modifierStream, modifierContinuation) = AsyncStream<(key: InputModifierKeyCode, isDown: Bool)>.makeStream()
        let (keyboardTapStream, keyboardTapContinuation) = AsyncStream<CGEvent>.makeStream()
        self.capsLockContinuation = capsLockContinuation
        self.modifierContinuation = modifierContinuation
        self.keyboardTapContinuation = keyboardTapContinuation
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = [[kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard], [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad]]
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, matches as CFArray)
        let capsLockCallback: IOHIDValueCallback = {(this, _, _, value) in
            let this = Unmanaged<Input>.fromOpaque(this!).takeUnretainedValue()
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let timestamp = IOHIDValueGetTimeStamp(value)
            let element = IOHIDValueGetElement(value)
            let scanCode = IOHIDElementGetUsage(element)
            guard let modifierKeyCode = InputModifierKeyCode(rawValue: scanCode) else {
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
            let this = Unmanaged<Input>.fromOpaque(this!).takeUnretainedValue()
            guard event.type != CGEventType.tapDisabledByTimeout else {
                CGEvent.tapEnable(tap: this.eventTap, enable: true)
                return nil
            }
            this.keyboardTapContinuation.yield(event)
            guard this.state.capsLockPressed || this.state.browseModeEnabled else {
                return Unmanaged.passUnretained(event)
            }
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
    public func bindKey(browseMode: Bool = false, controlModifier: Bool = false, optionModifier: Bool = false, commandModifier: Bool = false, shiftModifier: Bool = false, key: InputKeyCode, action: @escaping () async -> Void) {
        let keyBinding = KeyBinding(browseMode: browseMode, controlModifier: controlModifier, optionModifier: optionModifier, commandModifier: commandModifier, shiftModifier: shiftModifier, key: key)
        guard state.keyBindings.updateValue(action, forKey: keyBinding) == nil else {
            fatalError("Attempted to bind the same key combination twice")
        }
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
                Output.shared.convey([OutputSemantic.capsLockStatusChanged(state.capsLockEnabled)])
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
    private func handleModifierStream(_ modifierStream: AsyncStream<(key: InputModifierKeyCode, isDown: Bool)>) async {
        for await event in modifierStream {
            if event.isDown {
                state.shouldInterrupt = regularKeys.isEmpty && modifierKeys.isEmpty && (event.key == .leftControl || event.key == .rightControl)
                modifierKeys.insert(event.key)
                continue
            }
            modifierKeys.remove(event.key)
            if state.shouldInterrupt {
                Output.shared.interrupt()
                state.shouldInterrupt = false
            }
        }
    }

    /// Handles the stream of keyboard tap events.
    /// - Parameter keyboardTapStream: Stream of keyboard tap events.
    private func handleKeyboardTapStream(_ keyboardTapStream: AsyncStream<CGEvent>) async {
        for await event in keyboardTapStream {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard let keyCode = InputKeyCode(rawValue: keyCode) else {
                continue
            }
            state.shouldInterrupt = false
            guard event.type == .keyDown else {
                regularKeys.remove(keyCode)
                continue
            }
            regularKeys.insert(keyCode)
            guard state.capsLockPressed || state.browseModeEnabled else {
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
        /// Whether the user wants to interrupt speech.
        var shouldInterrupt = false
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
        let key: InputKeyCode
    }
}
