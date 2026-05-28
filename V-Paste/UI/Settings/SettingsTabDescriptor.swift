import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }
}

enum ClipboardRetentionPolicy: String, CaseIterable, Identifiable {
    case sevenDays = "sevenDays"
    case thirtyDays = "thirtyDays"
    case unlimited

    var id: String { rawValue }

    var title: String {
        title(language: .english)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .sevenDays:
            return language == .english ? "7 days" : "7 天"
        case .thirtyDays:
            return language == .english ? "30 days" : "30 天"
        case .unlimited:
            return language == .english ? "Unlimited" : "不限制"
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
        static let language = "settings.language"
        static let clipboardRetentionPolicy = "settings.clipboardRetentionPolicy"
        static let hotKeyKeyCode = "settings.showPanelHotKey.keyCode"
        static let hotKeyCarbonModifiers = "settings.showPanelHotKey.carbonModifiers"
        static let hotKeyEquivalent = "settings.showPanelHotKey.keyEquivalent"
        static let hotKeyDisplayKey = "settings.showPanelHotKey.displayKey"
        static let isApplicationIgnoreEnabled = "settings.isApplicationIgnoreEnabled"
        static let ignoredApplications = "settings.ignoredApplications"
    }

    var userDefaults: UserDefaults = .standard

    var language: AppLanguage {
        get {
            guard let rawValue = userDefaults.string(forKey: Key.language),
                  let language = AppLanguage(rawValue: rawValue)
            else {
                return .english
            }

            return language
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: Key.language)
        }
    }

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

    var isApplicationIgnoreEnabled: Bool {
        get {
            guard userDefaults.object(forKey: Key.isApplicationIgnoreEnabled) != nil else {
                return true
            }

            return userDefaults.bool(forKey: Key.isApplicationIgnoreEnabled)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.isApplicationIgnoreEnabled)
        }
    }

    var ignoredApplications: [IgnoredApplicationRule] {
        get {
            guard let data = userDefaults.data(forKey: Key.ignoredApplications) else {
                return IgnoredApplicationRule.defaultRules
            }

            do {
                return try JSONDecoder().decode([IgnoredApplicationRule].self, from: data)
            } catch {
                return IgnoredApplicationRule.defaultRules
            }
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }

            userDefaults.set(data, forKey: Key.ignoredApplications)
        }
    }
}

struct IgnoredApplicationRule: Codable, Equatable, Identifiable {
    let name: String
    let bundleIdentifier: String

    var id: String {
        bundleIdentifier.lowercased()
    }

    func matches(_ sourceApplication: ClipboardSourceApplication?) -> Bool {
        guard let sourceBundleIdentifier = sourceApplication?.bundleIdentifier else {
            return false
        }

        return sourceBundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }

    static func isIgnored(
        _ sourceApplication: ClipboardSourceApplication?,
        rules: [IgnoredApplicationRule],
        isEnabled: Bool = true
    ) -> Bool {
        guard isEnabled else {
            return false
        }

        return rules.contains { $0.matches(sourceApplication) }
    }

    static let defaultRules: [IgnoredApplicationRule] = [
        IgnoredApplicationRule(
            name: "Keychain Access",
            bundleIdentifier: "com.apple.keychainaccess"
        ),
        IgnoredApplicationRule(
            name: "SecurityAgent",
            bundleIdentifier: "com.apple.SecurityAgent"
        ),
        IgnoredApplicationRule(
            name: "Passwords",
            bundleIdentifier: "com.apple.Passwords"
        )
    ]
}

struct SettingsPreferenceDescriptor: Equatable {
    let title: String
    let detail: String?

    static var singleGroup: [SettingsPreferenceDescriptor] {
        singleGroup(language: .english)
    }

    static func singleGroup(language: AppLanguage) -> [SettingsPreferenceDescriptor] {
        [
            SettingsPreferenceDescriptor(
                title: language == .english ? "Status" : "运行状态",
                detail: nil
            ),
            SettingsPreferenceDescriptor(
                title: language == .english ? "Launch at Login" : "开机自启",
                detail: nil
            ),
            SettingsPreferenceDescriptor(
                title: language == .english ? "Monitor Clipboard" : "监听剪贴板",
                detail: nil
            ),
            SettingsPreferenceDescriptor(
                title: SettingsShortcutDescriptor.showPanelTitle(language: language),
                detail: SettingsShortcutDescriptor.currentShortcutLabel
            ),
            SettingsPreferenceDescriptor(
                title: language == .english ? "History Retention" : "历史记录有效期",
                detail: ClipboardRetentionPolicy.thirtyDays.title(language: language)
            ),
            SettingsPreferenceDescriptor(
                title: language == .english ? "Language" : "语言",
                detail: language.title
            )
        ]
    }
}

struct SettingsTabDescriptor: Equatable, Identifiable {
    enum ID: String, Hashable {
        case general
        case ignoredApplications
        case about
    }

    let id: ID
    let title: String
    let systemImageName: String

    static func all(language: AppLanguage) -> [SettingsTabDescriptor] {
        [
            SettingsTabDescriptor(
                id: .general,
                title: language == .english ? "General" : "通用",
                systemImageName: "gearshape"
            ),
            SettingsTabDescriptor(
                id: .ignoredApplications,
                title: SettingsIgnoredAppsDescriptor.title(language: language),
                systemImageName: "hand.raised"
            ),
            SettingsTabDescriptor(
                id: .about,
                title: SettingsAboutDescriptor.title(language: language),
                systemImageName: "info.circle"
            )
        ]
    }
}

enum SettingsAboutDescriptor {
    static let fallbackAppName = "V-Paste"
    static let repositoryURL = MenuBarAboutDescriptor.repositoryURL
    static let githubIconAssetName = MenuBarAboutDescriptor.githubIconAssetName

    static var repositoryDisplayText: String {
        repositoryURL.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func title(language: AppLanguage) -> String {
        language == .english ? "About" : "关于"
    }

    static func appName(bundle: Bundle = .main) -> String {
        appName(info: bundle.infoDictionary)
    }

    static func appName(info: [String: Any]?) -> String {
        normalizedInfoString(info?["CFBundleDisplayName"])
            ?? normalizedInfoString(info?["CFBundleName"])
            ?? fallbackAppName
    }

    static func versionText(
        language: AppLanguage,
        versionLabel: String = MenuBarAboutDescriptor.currentVersionLabel()
    ) -> String {
        MenuBarAboutDescriptor.versionText(
            language: language,
            versionLabel: versionLabel
        )
    }

    static func repositoryTitle(language: AppLanguage) -> String {
        MenuBarAboutDescriptor.githubTitle(language: language)
    }

    static func githubHelpTitle(language: AppLanguage) -> String {
        language == .english ? "Open GitHub Repository" : "打开 GitHub 仓库"
    }

    private static func normalizedInfoString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SettingsIgnoredAppsDescriptor {
    static func title(language: AppLanguage) -> String {
        language == .english ? "App Ignore" : "应用忽略"
    }

    static func enabledTitle(language: AppLanguage) -> String {
        language == .english ? "Enable App Ignore" : "启用应用忽略"
    }

    static func explanation(language: AppLanguage) -> String {
        language == .english
            ? "When enabled, V-Paste will not save clipboard content copied from the apps below. Use it for Keychain Access, password managers, or other sensitive apps."
            : "开启后，V-Paste 不会保存下列应用产生的剪贴板内容。适合钥匙串、密码管理器等敏感应用。"
    }

    static func addTitle(language: AppLanguage) -> String {
        language == .english ? "Add..." : "添加..."
    }

    static func removeTitle(language: AppLanguage) -> String {
        language == .english ? "Remove" : "移除"
    }

    static func resetTitle(language: AppLanguage) -> String {
        language == .english ? "Defaults" : "恢复默认"
    }

    static func emptyTitle(language: AppLanguage) -> String {
        language == .english ? "No ignored apps" : "没有忽略应用"
    }
}

enum SettingsShortcutDescriptor {
    static func showPanelTitle(language: AppLanguage) -> String {
        language == .english ? "Show V-Paste" : "显示 V-Paste"
    }

    static let currentShortcutLabel = MenuBarMenuDescriptor.defaultShortcutLabel

    static func recordingPrompt(language: AppLanguage) -> String {
        language == .english ? "Press shortcut" : "按下快捷键"
    }

    static func invalidShortcutMessage(language: AppLanguage) -> String {
        language == .english
            ? "Shortcut requires a modifier key"
            : "快捷键需要包含修饰键"
    }

    static func registrationFailedMessage(language: AppLanguage) -> String {
        language == .english
            ? "Shortcut registration failed"
            : "快捷键注册失败"
    }
}
