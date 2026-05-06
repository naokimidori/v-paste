import Foundation

enum ClipboardRetentionPolicy: String, CaseIterable, Identifiable {
    case sevenDays = "sevenDays"
    case thirtyDays = "thirtyDays"
    case unlimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sevenDays:
            return "7 天"
        case .thirtyDays:
            return "30 天"
        case .unlimited:
            return "不限制"
        }
    }

    var dayCount: Int? {
        switch self {
        case .sevenDays:
            return 7
        case .thirtyDays:
            return 30
        case .unlimited:
            return nil
        }
    }

    func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
        guard let dayCount else { return nil }

        return calendar.date(
            byAdding: .day,
            value: -dayCount,
            to: now
        ) ?? Date(timeInterval: TimeInterval(-dayCount * 24 * 60 * 60), since: now)
    }
}

struct AppPreferences {
    private enum Key {
        static let clipboardRetentionPolicy = "settings.clipboardRetentionPolicy"
        static let hotKeyKeyCode = "settings.showPanelHotKey.keyCode"
        static let hotKeyCarbonModifiers = "settings.showPanelHotKey.carbonModifiers"
        static let hotKeyEquivalent = "settings.showPanelHotKey.keyEquivalent"
        static let hotKeyDisplayKey = "settings.showPanelHotKey.displayKey"
    }

    var userDefaults: UserDefaults = .standard

    var clipboardRetentionPolicy: ClipboardRetentionPolicy {
        get {
            guard let rawValue = userDefaults.string(forKey: Key.clipboardRetentionPolicy),
                  let policy = ClipboardRetentionPolicy(rawValue: rawValue)
            else {
                return .thirtyDays
            }

            return policy
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: Key.clipboardRetentionPolicy)
        }
    }

    var showPanelHotKey: HotKeyPreference {
        get {
            guard userDefaults.object(forKey: Key.hotKeyKeyCode) != nil,
                  userDefaults.object(forKey: Key.hotKeyCarbonModifiers) != nil
            else {
                return .defaultShowPanel
            }

            return HotKeyPreference(
                keyCode: UInt32(userDefaults.integer(forKey: Key.hotKeyKeyCode)),
                carbonModifiers: UInt32(userDefaults.integer(forKey: Key.hotKeyCarbonModifiers)),
                keyEquivalent: userDefaults.string(forKey: Key.hotKeyEquivalent)
                    ?? HotKeyPreference.defaultShowPanel.keyEquivalent,
                displayKey: userDefaults.string(forKey: Key.hotKeyDisplayKey)
                    ?? HotKeyPreference.defaultShowPanel.displayKey
            )
        }
        nonmutating set {
            userDefaults.set(Int(newValue.keyCode), forKey: Key.hotKeyKeyCode)
            userDefaults.set(Int(newValue.carbonModifiers), forKey: Key.hotKeyCarbonModifiers)
            userDefaults.set(newValue.keyEquivalent, forKey: Key.hotKeyEquivalent)
            userDefaults.set(newValue.displayKey, forKey: Key.hotKeyDisplayKey)
        }
    }
}

struct SettingsPreferenceDescriptor: Equatable {
    let title: String
    let detail: String?

    static let singleGroup: [SettingsPreferenceDescriptor] = [
        SettingsPreferenceDescriptor(title: "运行状态", detail: nil),
        SettingsPreferenceDescriptor(title: "开机自启", detail: nil),
        SettingsPreferenceDescriptor(title: "监听剪贴板", detail: nil),
        SettingsPreferenceDescriptor(title: SettingsShortcutDescriptor.showPanelTitle, detail: SettingsShortcutDescriptor.currentShortcutLabel),
        SettingsPreferenceDescriptor(title: "历史记录有效期", detail: ClipboardRetentionPolicy.thirtyDays.title),
        SettingsPreferenceDescriptor(title: "关于 V-Paste", detail: "Debug")
    ]
}

enum SettingsShortcutDescriptor {
    static let showPanelTitle = "显示 V-Paste"
    static let currentShortcutLabel = MenuBarMenuDescriptor.defaultShortcutLabel
}
