import AppKit
import Carbon
import Foundation

struct HotKeyPreference: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let displayKey: String

    static let defaultShowPanel = HotKeyPreference(
        keyCode: UInt32(kVK_ANSI_Grave),
        carbonModifiers: UInt32(optionKey),
        keyEquivalent: "~",
        displayKey: "~"
    )

    var displayLabel: String {
        Self.modifierSymbols(for: carbonModifiers) + displayKey
    }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        Self.modifierFlags(fromCarbonModifiers: carbonModifiers)
    }

    static func capture(event: NSEvent) -> HotKeyPreference? {
        capture(
            keyCode: UInt32(event.keyCode),
            modifierFlags: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? ""
        )
    }

    static func capture(
        keyCode: UInt32,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String
    ) -> HotKeyPreference? {
        let carbonModifiers = carbonModifiers(from: modifierFlags)
        guard carbonModifiers != 0,
              let key = keyEquivalentAndDisplayKey(
                keyCode: keyCode,
                charactersIgnoringModifiers: charactersIgnoringModifiers
              )
        else {
            return nil
        }

        return HotKeyPreference(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers,
            keyEquivalent: key.equivalent,
            displayKey: key.display
        )
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        orderedModifiers.reduce(UInt32(0)) { partialResult, modifier in
            flags.contains(modifier.flags)
                ? partialResult | modifier.carbonValue
                : partialResult
        }
    }

    private static func modifierFlags(fromCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        orderedModifiers.reduce([]) { partialResult, modifier in
            modifiers & modifier.carbonValue != 0
                ? partialResult.union(modifier.flags)
                : partialResult
        }
    }

    private static func modifierSymbols(for modifiers: UInt32) -> String {
        orderedModifiers
            .filter { modifiers & $0.carbonValue != 0 }
            .map(\.symbol)
            .joined()
    }

    private static func keyEquivalentAndDisplayKey(
        keyCode: UInt32,
        charactersIgnoringModifiers: String
    ) -> (equivalent: String, display: String)? {
        switch Int(keyCode) {
        case kVK_ANSI_Grave:
            return ("~", "~")
        case kVK_Space:
            return (" ", "Space")
        case kVK_Return:
            return ("\r", "Return")
        case kVK_Tab:
            return ("\t", "Tab")
        case kVK_Delete:
            return ("\u{7F}", "Delete")
        case kVK_Escape:
            return ("\u{1B}", "Esc")
        case kVK_LeftArrow:
            return (String(UnicodeScalar(NSLeftArrowFunctionKey)!), "←")
        case kVK_RightArrow:
            return (String(UnicodeScalar(NSRightArrowFunctionKey)!), "→")
        case kVK_UpArrow:
            return (String(UnicodeScalar(NSUpArrowFunctionKey)!), "↑")
        case kVK_DownArrow:
            return (String(UnicodeScalar(NSDownArrowFunctionKey)!), "↓")
        default:
            guard let firstCharacter = charactersIgnoringModifiers.first else {
                return nil
            }
            let equivalent = String(firstCharacter).lowercased()
            return (equivalent, equivalent.uppercased())
        }
    }

    private static let orderedModifiers: [(flags: NSEvent.ModifierFlags, carbonValue: UInt32, symbol: String)] = [
        (.control, UInt32(controlKey), "⌃"),
        (.option, UInt32(optionKey), "⌥"),
        (.shift, UInt32(shiftKey), "⇧"),
        (.command, UInt32(cmdKey), "⌘")
    ]
}

enum GlobalHotKeyMonitorError: Error {
    case eventHandlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)
}

final class GlobalHotKeyMonitor {
    fileprivate static let hotKeyID = EventHotKeyID(
        signature: OSType(
            UInt32(Character("V").asciiValue!) << 24
                | UInt32(Character("P").asciiValue!) << 16
                | UInt32(Character("S").asciiValue!) << 8
                | UInt32(Character("T").asciiValue!)
        ),
        id: 1
    )

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    deinit {
        unregister()
    }

    func register(_ hotKey: HotKeyPreference = .defaultShowPanel) throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            vPasteHotKeyEventHandler,
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            throw GlobalHotKeyMonitorError.eventHandlerInstallFailed(handlerStatus)
        }

        let hotKeyID = Self.hotKeyID
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            throw GlobalHotKeyMonitorError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    fileprivate func fire() {
        onPress()
    }
}

private func vPasteHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalHotKeyMonitor.hotKeyID.signature,
          hotKeyID.id == GlobalHotKeyMonitor.hotKeyID.id else {
        return status
    }

    let monitor = Unmanaged<GlobalHotKeyMonitor>
        .fromOpaque(userData)
        .takeUnretainedValue()
    monitor.fire()
    return noErr
}
