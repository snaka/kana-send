import Cocoa

final class KeyTapManager {
    // MARK: - Public configuration

    var holdThresholdMs: Int = 500

    var onAlphaTriggered: (() -> Void)?
    var onKanaTriggered: (() -> Void)?
    var onCmdActivated: (() -> Void)?

    // MARK: - Constants

    private static let leftCmdKeyCode: Int64 = 0x37
    private static let rightCmdKeyCode: Int64 = 0x36
    private static let leftCmdFlagMask: UInt64 = 0x00000008   // NX_DEVICELCMDKEYMASK
    private static let rightCmdFlagMask: UInt64 = 0x00000010  // NX_DEVICERCMDKEYMASK
    private static let eisuuVirtualKey: CGKeyCode = 0x66
    private static let kanaVirtualKey: CGKeyCode = 0x68

    // Marker we stamp on synthesized events so we can recognize and pass them
    // through without re-processing.
    private static let syntheticMarker: Int64 = 0x6B616E61  // "kana"

    // MARK: - State

    private enum CmdSide {
        case left, right

        var keyCode: CGKeyCode {
            switch self {
            case .left:  return CGKeyCode(KeyTapManager.leftCmdKeyCode)
            case .right: return CGKeyCode(KeyTapManager.rightCmdKeyCode)
            }
        }

        var deviceFlagMask: UInt64 {
            switch self {
            case .left:  return KeyTapManager.leftCmdFlagMask
            case .right: return KeyTapManager.rightCmdFlagMask
            }
        }
    }

    private var pendingCmd: CmdSide?
    private var pendingCmdInterrupted: Bool = false
    private var cmdActivated: Bool = false
    private var holdTimer: Timer?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<KeyTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        resetPendingState()
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Pass through our own synthesized events.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event: event)
        case .keyDown, .keyUp:
            return handleKey(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rawFlags = event.flags.rawValue

        let side: CmdSide
        switch keyCode {
        case Self.leftCmdKeyCode:
            side = .left
        case Self.rightCmdKeyCode:
            side = .right
        default:
            // Any other modifier change while a Cmd is pending counts as "interrupted".
            if pendingCmd != nil && !cmdActivated {
                pendingCmdInterrupted = true
            }
            return Unmanaged.passUnretained(event)
        }

        let isPressed = (rawFlags & side.deviceFlagMask) != 0
        return isPressed ? handleCmdPress(side: side) : handleCmdRelease(side: side)
    }

    private func handleCmdPress(side: CmdSide) -> Unmanaged<CGEvent>? {
        // If another cmd-tap was already in flight, treat as interrupted.
        if pendingCmd != nil {
            pendingCmdInterrupted = true
        }

        pendingCmd = side
        pendingCmdInterrupted = false
        cmdActivated = false
        startHoldTimer(for: side)

        // Swallow the press; we'll synthesize one later if the threshold fires.
        return nil
    }

    private func handleCmdRelease(side: CmdSide) -> Unmanaged<CGEvent>? {
        cancelHoldTimer()

        if cmdActivated {
            cmdActivated = false
            pendingCmd = nil
            pendingCmdInterrupted = false
            postSyntheticModifier(side: side, isDown: false)
            return nil
        }

        let interrupted = pendingCmdInterrupted
        let pending = pendingCmd
        pendingCmd = nil
        pendingCmdInterrupted = false

        if !interrupted, pending == side {
            switch side {
            case .left:
                postKey(Self.eisuuVirtualKey)
                onAlphaTriggered?()
            case .right:
                postKey(Self.kanaVirtualKey)
                onKanaTriggered?()
            }
        }
        return nil
    }

    private func handleKey(event: CGEvent) -> Unmanaged<CGEvent>? {
        // While Cmd is pending (pre-threshold), the user is mid-tap.
        // Pass the key through but strip Cmd flag so ⌘+key shortcuts don't fire.
        if pendingCmd != nil && !cmdActivated {
            pendingCmdInterrupted = true
            var flags = event.flags
            flags.remove(.maskCommand)
            event.flags = flags
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Timer

    private func startHoldTimer(for side: CmdSide) {
        cancelHoldTimer()
        let delay = TimeInterval(holdThresholdMs) / 1000.0
        holdTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.holdThresholdReached(for: side)
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func holdThresholdReached(for side: CmdSide) {
        guard pendingCmd == side else { return }
        cmdActivated = true
        postSyntheticModifier(side: side, isDown: true)
        onCmdActivated?()
    }

    // MARK: - Event posting

    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            up.post(tap: .cgSessionEventTap)
        }
    }

    private func postSyntheticModifier(side: CmdSide, isDown: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: side.keyCode,
            keyDown: isDown
        ) else { return }
        event.type = .flagsChanged
        if isDown {
            event.flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | side.deviceFlagMask)
        } else {
            event.flags = CGEventFlags(rawValue: 0)
        }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }

    private func resetPendingState() {
        cancelHoldTimer()
        pendingCmd = nil
        pendingCmdInterrupted = false
        cmdActivated = false
    }
}
