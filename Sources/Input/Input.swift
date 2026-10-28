import IOKit
import CoreGraphics
import Foundation

import Util

/// Input handler.
///
/// ## Discussion
///
/// Do not initialize until either input monitoring or automation permissions are granted.
@MainActor public final class Input {
    /// Shared singleton.
    public static let shared = Input()
    /// Maximum time for a key press and release sequence to be considered a click.
    private static let clickGrace = TimeInterval(0.25)
    /// Browse mode state tracker.
    @ObservableProperty public var isBrowseModeEnabled = false
    /// CapsLock status source of truth.
    @ObservableProperty public private(set) var isCapsLockEnabled = false
    /// Emits an event every time the user presses CapsLock to interrupt speech.
    @ObservableProperty public private(set) var speechInterruptPulse: Void = ()
    /// Configured key bindings.
    private var keyBindings = [KeyBinding: @Sendable () async -> Void]()

    /// Whether the current input state may indicate that the user wants to perform a key binding.
    private var isKeyBinding = false
    /// Keys pressed to execute a key combination whose release status must not be propagated even if the key combination state is disabled.
    private var quarantinedKeys = Set<InputKeyCode>()

    /// Tap into Quartz input events.
    private lazy var inputTap: CFMachPort = setUpInputTap()
    /// Human Interface Devices manager.
    private lazy var hidManager = setUpHIDManager()
    /// IO event kernel handle.
    private var ioConnection = io_connect_t.zero

    /// CapsLock toggle event source.
    private let capsLockToggleSource: AsyncStream<ModifierEvent>
    /// CapsLock toggle event sink.
    private let capsLockToggleSink: AsyncStream<ModifierEvent>.Continuation
    /// CapsLock toggle state machine.
    private var capsLockToggleState: Task<Void, Never>!
    /// Whether a CapsLock toggle series of events is being tracked.
    private var isTrackingCapsLockToggle = false
    /// Last CapsLock status reported downstream as a generated input event.
    private var reportedCapsLockStatus = false

    /// Kernel clock rate to nanoseconds conversion fraction.
    private let timeBase: (numer: UInt64, denom: UInt64)

    /// Creates a new input handler.
    private init() {
        (capsLockToggleSource, capsLockToggleSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
        var timeBase = mach_timebase_info(numer: 0, denom: 0)
        mach_timebase_info(&timeBase)
        self.timeBase = (numer: UInt64(timeBase.numer), denom: UInt64(timeBase.denom))
        let mainLoop = CFRunLoopGetMain()!
        let match = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        IOHIDManagerSetDeviceMatching(hidManager, match as CFDictionary)
        let inputSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, inputTap, 0)
        CFRunLoopAddSource(mainLoop, inputSource, CFRunLoopMode.defaultMode)
        capsLockToggleState = Task(operation: trackCapsLockToggleState)
    }

    /// Creates and configures the Human Interface Devices manager for lower level input monitoring.
    /// - Returns: Human Interface Devices connection handle.
    private func setUpHIDManager() -> IOHIDManager {
        let mainLoop = CFRunLoopGetMain()!
        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let ioCallBack: IOHIDValueCallback = {(this, _, _, value) in
            let this = Unmanaged<Input>.fromOpaque(this!).takeUnretainedValue()
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let timestamp = IOHIDValueGetTimeStamp(value)
            let element = IOHIDValueGetElement(value)
            let code = IOHIDElementGetUsage(element)
            MainActor.assumeIsolated({this.handleIOEvent(code: code, timestamp: timestamp, isDown: isDown)})
        }
        IOHIDManagerRegisterInputValueCallback(hidManager, ioCallBack, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(hidManager, mainLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &ioConnection)
        IOHIDGetModifierLockState(ioConnection, Int32(kIOHIDCapsLockState), &isCapsLockEnabled)
        reportedCapsLockStatus = isCapsLockEnabled
        return hidManager
    }

    /// Sets up a tap into input events.
    /// - Returns: input tap instance.
    private func setUpInputTap() -> CFMachPort {
        let keyboardTapCallback: CGEventTapCallBack = {(_, _, event, this) in
            let this = Unmanaged<Input>.fromOpaque(this!).takeUnretainedValue()
            let shouldForward = MainActor.assumeIsolated() {[this] in
                guard event.type != CGEventType.tapDisabledByTimeout else {
                    this.reset()
                    CGEvent.tapEnable(tap: this.inputTap, enable: true)
                    return false
                }
                return this.handleTapEvent(event)
            }
            return shouldForward ? Unmanaged.passUnretained(event) : nil
        }
        let eventTypes = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue | 1 << CGEventType.flagsChanged.rawValue)
        guard let inputTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: eventTypes, callback: keyboardTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fatalError("Failed to tap into keyboard input events")
        }
        return inputTap
    }

    isolated deinit {
        IOServiceClose(ioConnection)
        // Terminate the event stream along with its task.
        capsLockToggleSink.finish()
    }

    /// Binds a key to an action with optional modifiers.
    /// - Parameters:
    ///   - browseMode: Requires browse mode instead of CapsLock.
    ///   - controlModifier: Requires the Control modifier key to be pressed.
    ///   - optionModifier: Requires the Option modifier key to be pressed.
    ///   - commandModifier: Requires the Command modifier key to be pressed.
    ///   - shiftModifier: Requires the Shift modifier key to be pressed.
    ///   - key: Key to bind.
    ///   - action: Action to perform when the key combination is pressed.
    public func bindKey(browseMode: Bool = false, controlModifier: Bool = false, optionModifier: Bool = false, commandModifier: Bool = false, shiftModifier: Bool = false, key: InputKeyCode, action: @escaping @Sendable () async -> Void) {
        let keyBinding = KeyBinding(browseMode: browseMode, controlModifier: controlModifier, optionModifier: optionModifier, commandModifier: commandModifier, shiftModifier: shiftModifier, key: key)
        guard keyBindings.updateValue(action, forKey: keyBinding) == nil else {
            fatalError("Attempted to bind the same key combination twice")
        }
    }

    /// CapsLock status toggle state machine.
    private func trackCapsLockToggleState() async {
        var cursor = capsLockToggleSource.makeAsyncIterator()
        var savedEvent = await cursor.next(isolation: #isolation)
        while savedEvent != nil {
            guard let event = savedEvent else {break}
            isTrackingCapsLockToggle = false
            // Check whether this is a CapsLock key press event.
            guard event.isActive, event.keyCode == .capsLock else {
                // Unexpected first event so discard it, wait for the next event, and start over.
                savedEvent = await cursor.next(isolation: #isolation)
                continue
            }
            isTrackingCapsLockToggle = true
            var timeout = event.timestamp + Input.clickGrace
            savedEvent = await cursor.next(isolation: #isolation)
            guard let event = savedEvent else {break}
            // Check whether this is a CapsLock key release event.
            guard isTrackingCapsLockToggle && event.timestamp < timeout && !event.isActive && event.keyCode == .capsLock else {
                // Restart the state machine without consuming another event since this one may make sense as the start event of a new sequence.
                continue
            }
            timeout = event.timestamp + Input.clickGrace
            savedEvent = await cursor.next(isolation: #isolation)
            guard let event = savedEvent else {break}
            // Check whether this is another CapsLock key press event.
            guard isTrackingCapsLockToggle && event.timestamp < timeout && event.isActive && event.keyCode == .capsLock else {
                // Restart the state machine without consuming another event since this one may make sense as the start event of a new sequence.
                continue
            }
            timeout = event.timestamp + Input.clickGrace
            savedEvent = await cursor.next(isolation: #isolation)
            guard let event = savedEvent else {break}
            // Check whether this is another CapsLock key release event.
            guard isTrackingCapsLockToggle && event.timestamp < timeout && !event.isActive && event.keyCode == .capsLock else {
                // Restart the state machine without consuming another event since this one may make sense as the start event of a new sequence.
                continue
            }
            // CapsLock toggle sequence recognized.
            isTrackingCapsLockToggle = false
            isCapsLockEnabled.toggle()
            updateCapsLockStatus()
            savedEvent = await cursor.next(isolation: #isolation)
        }
    }

    /// Handles lower level IO events.
    /// - Parameters:
    ///   - code: Scan code of the raw event.
    ///   - timestamp: Kernel timestamp of the event.
    ///   - isDown: Whether the key or button is being pressed.
    private func handleIOEvent(code: UInt32, timestamp: UInt64, isDown: Bool) {
        // Make sure that we're only dealing with modifiers.
        guard let modifier = InputModifierKeyCode(rawValue: code) else {return}
        updateCapsLockStatus()
        // Compute the timestamp with as much precision as possible but making sure to not cause an integer overflow.
        let timestamp = TimeInterval(.max / timeBase.numer >= timeBase.denom ? timestamp * timeBase.numer / timeBase.denom : timestamp / timeBase.denom * timeBase.numer) * 1e-9
        switch modifier {
        case .leftControl, .rightControl:
            if isDown {
                speechInterruptPulse = ()
            }
        case .capsLock:
            isKeyBinding = isDown
            capsLockToggleSink.yield(ModifierEvent(keyCode: modifier, isActive: isDown, timestamp: timestamp))
            if isDown {
                speechInterruptPulse = ()
            }
        default:
            isTrackingCapsLockToggle = false
        }
    }

    /// Handles input tap events.
    /// - Parameter event: Input event to handle.
    /// - Returns: Whether the event should be forwarded downstream.
    private func handleTapEvent(_ event: CGEvent) -> Bool {
        if event.flags.contains(.maskAlphaShift) == isCapsLockEnabled && reportedCapsLockStatus != isCapsLockEnabled {
            // Generate CapsLock key down and up events for intentional CapsLock status changes.
            reportedCapsLockStatus = isCapsLockEnabled
            let source = CGEventSource(event: event)
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(InputKeyCode.keyboardCapsLock.rawValue), keyDown: isCapsLockEnabled)
            event?.post(tap: .cghidEventTap)
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Make sure that we actually understand the key code.
        guard let keyCode = InputKeyCode(rawValue: keyCode) else {return true}
        // Make sure that key codes are not spurious or CapsLock events that we are already handling and producing ourselves.
        guard keyCode != .keyboardCapsLock && keyCode != .unidentified else {return false}
        // Reset the CapsLock state machine.
        isTrackingCapsLockToggle = false
        // Let all the input that we don't handle through to downstream listeners.
        guard isKeyBinding || isBrowseModeEnabled || quarantinedKeys.contains(keyCode) else {return true}
        guard event.type == .keyUp else {
            if event.type == .keyDown {
                // Quarantine the key so that its release event is now allowed through even if the user releases the key binding modifier or browse mode is disabled while the key is held.
                quarantinedKeys.insert(keyCode)
            }
            return false
        }
        guard quarantinedKeys.contains(keyCode) else {
            // We didn't catch the key press event, so let the key release event through to ensure that downstream listeners don't assume that keys are still being held.
            return true
        }
        quarantinedKeys.remove(keyCode)
        // Perform the action bound to the key.
        let isControlDown = event.flags.contains(.maskControl)
        let isOptionDown = event.flags.contains(.maskAlternate)
        let isCommandDown = event.flags.contains(.maskCommand)
        let isShiftDown = event.flags.contains(.maskShift)
        let keyBinding = KeyBinding(browseMode: isBrowseModeEnabled, controlModifier: isControlDown, optionModifier: isOptionDown, commandModifier: isCommandDown, shiftModifier: isShiftDown, key: keyCode)
        guard let action = keyBindings[keyBinding] else {return false}
        Task.detached(operation: action)
        return false
    }

    /// Forces the system CapsLock status to update to our own value.
    private func updateCapsLockStatus() {
        var wasCapsLockEnabled = false
        IOHIDGetModifierLockState(ioConnection, Int32(kIOHIDCapsLockState), &wasCapsLockEnabled)
        guard isCapsLockEnabled != wasCapsLockEnabled else {return}
        IOHIDSetModifierLockState(ioConnection, Int32(kIOHIDCapsLockState), isCapsLockEnabled)
    }

    /// Resets the cached input state.
    private func reset() {
        reportedCapsLockStatus = isCapsLockEnabled
        isTrackingCapsLockToggle = false
        quarantinedKeys.removeAll(keepingCapacity: true)
    }
}

extension Input {
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

extension Input {
    /// Keyboard modifier event.
    private struct ModifierEvent {
        /// Key code of the event.
        let keyCode: InputModifierKeyCode
        /// Whether the event reports a key being pressed.
        let isActive: Bool
        /// Timestamp of the event.
        let timestamp: TimeInterval
    }
}
