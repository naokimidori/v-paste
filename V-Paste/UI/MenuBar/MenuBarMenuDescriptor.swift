import AppKit

enum MenuBarMenuAction: Equatable {
    case showPanel
    case openPreferences
    case openAbout
    case quit

    var selectorName: String {
        switch self {
        case .showPanel:
            return "openClipboardHistory"
        case .openPreferences:
            return "openPreferences"
        case .openAbout:
            return "openAbout"
        case .quit:
            return "quit"
        }
    }
}

struct MenuBarMenuItemDescriptor: Equatable {
    let title: String?
    let action: MenuBarMenuAction?
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags
    let shortcutDisplay: String?

    static func separator() -> MenuBarMenuItemDescriptor {
        MenuBarMenuItemDescriptor(
            title: nil,
            action: nil,
            keyEquivalent: "",
            keyEquivalentModifierMask: [],
            shortcutDisplay: nil
        )
    }
}

enum MenuBarMenuDescriptor {
    static let defaultShortcutLabel = "⌥~"

    static func panelOverflowItems(
        appName: String,
        shortcut: HotKeyPreference = .defaultShowPanel
    ) -> [MenuBarMenuItemDescriptor] {
        items(appName: appName, shortcut: shortcut)
            .filter { $0.action != .showPanel }
            .trimmedSeparators()
    }

    static func items(
        appName: String,
        shortcut: HotKeyPreference = .defaultShowPanel
    ) -> [MenuBarMenuItemDescriptor] {
        [
            MenuBarMenuItemDescriptor(
                title: "显示 \(appName)",
                action: .showPanel,
                keyEquivalent: shortcut.keyEquivalent,
                keyEquivalentModifierMask: shortcut.keyEquivalentModifierMask,
                shortcutDisplay: shortcut.displayLabel
            ),
            .separator(),
            MenuBarMenuItemDescriptor(
                title: "偏好设置...",
                action: .openPreferences,
                keyEquivalent: ",",
                keyEquivalentModifierMask: [.command],
                shortcutDisplay: "⌘,"
            ),
            MenuBarMenuItemDescriptor(
                title: "关于 \(appName)",
                action: .openAbout,
                keyEquivalent: "",
                keyEquivalentModifierMask: [],
                shortcutDisplay: nil
            ),
            .separator(),
            MenuBarMenuItemDescriptor(
                title: "退出",
                action: .quit,
                keyEquivalent: "q",
                keyEquivalentModifierMask: [.command],
                shortcutDisplay: "⌘Q"
            )
        ]
    }
}

private extension Array where Element == MenuBarMenuItemDescriptor {
    func trimmedSeparators() -> [MenuBarMenuItemDescriptor] {
        var items = self

        while !items.isEmpty && items.first?.title == nil {
            items.removeFirst()
        }
        while !items.isEmpty && items.last?.title == nil {
            items.removeLast()
        }

        return items
    }
}
