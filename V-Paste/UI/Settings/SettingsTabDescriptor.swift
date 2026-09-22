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
        static let isJevRecommendationEnabled = "settings.isJevRecommendationEnabled"
        static let experimentalFeaturesEnabled = "settings.experimentalFeaturesEnabled"
        static let jevAuthRequirement = "settings.jevAuthRequirement"
    }

    var userDefaults: UserDefaults = .standard

    var isExperimentalFeaturesEnabled: Bool {
        get {
            userDefaults.bool(forKey: Key.experimentalFeaturesEnabled)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.experimentalFeaturesEnabled)
        }
    }

    var isJevRecommendationEnabled: Bool {
        get {
            userDefaults.bool(forKey: Key.isJevRecommendationEnabled)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: Key.isJevRecommendationEnabled)
        }
    }

    /// 持久化记录 Jev 运行时的鉴权失败要求（如 invalidKey 或 permissionDenied），跨应用重启与实验功能开关保持
    var jevAuthRequirement: String? {
        get {
            userDefaults.string(forKey: Key.jevAuthRequirement)
        }
        nonmutating set {
            if let newValue {
                userDefaults.set(newValue, forKey: Key.jevAuthRequirement)
            } else {
                userDefaults.removeObject(forKey: Key.jevAuthRequirement)
            }
        }
    }

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
        case jev
        case ignoredApplications
        case about
    }

    let id: ID
    let title: String
    let systemImageName: String

    static func all(language: AppLanguage) -> [SettingsTabDescriptor] {
        visibleTabs(language: language, isExperimentalEnabled: true)
    }

    /// 根据实验功能开关动态返回可见的设置选项卡
    static func visibleTabs(language: AppLanguage, isExperimentalEnabled: Bool) -> [SettingsTabDescriptor] {
        var tabs = [
            SettingsTabDescriptor(
                id: .general,
                title: language == .english ? "General" : "通用",
                systemImageName: "gearshape"
            )
        ]
        if isExperimentalEnabled {
            tabs.append(
                SettingsTabDescriptor(
                    id: .jev,
                    title: SettingsJevDescriptor.title(language: language),
                    systemImageName: "sparkles"
                )
            )
        }
        tabs.append(contentsOf: [
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
        ])
        return tabs
    }
}

/// 实验功能文案描述符
enum SettingsExperimentalFeaturesDescriptor {
    static func title(language: AppLanguage) -> String {
        language == .english ? "Experimental Features" : "实验功能"
    }

    static func description(language: AppLanguage) -> String {
        language == .english
            ? "Show experimental features that may change or become temporarily unavailable."
            : "展示仍在试验中的功能。这些功能可能发生变化或暂时不可用。"
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

enum SettingsJevDescriptor {
    static let getKeyURL = URL(string: "https://console.typesafe.ai/keys")!

    static func title(language: AppLanguage) -> String {
        "Jev"
    }

    static func statusTitle(language: AppLanguage) -> String {
        language == .english ? "Status" : "运行状态"
    }

    static func statusNotConfigured(language: AppLanguage) -> String {
        language == .english ? "Not configured" : "未配置"
    }

    static func statusVerifying(language: AppLanguage) -> String {
        language == .english ? "Verifying..." : "正在验证..."
    }

    static func statusReady(language: AppLanguage) -> String {
        language == .english ? "Ready" : "可用"
    }

    static func statusEnabled(language: AppLanguage) -> String {
        language == .english ? "Enabled" : "已启用"
    }

    static func statusInvalidKey(language: AppLanguage) -> String {
        language == .english ? "Invalid API Key" : "Key 无效"
    }

    static func statusPermissionDenied(language: AppLanguage) -> String {
        language == .english ? "Account permission denied" : "账号权限不足"
    }

    static func statusModelUnavailable(language: AppLanguage) -> String {
        language == .english ? "Jev model unavailable" : "Jev 模型不可用"
    }

    static func statusNetworkUnavailable(language: AppLanguage) -> String {
        language == .english ? "Network unavailable" : "网络不可用"
    }

    static func apiKeyTitle(language: AppLanguage) -> String {
        "API Key"
    }

    static func apiKeyPlaceholder(language: AppLanguage) -> String {
        language == .english ? "Paste TypeSafe API Key" : "粘贴 TypeSafe API Key"
    }

    static func saveAndVerifyTitle(language: AppLanguage) -> String {
        language == .english ? "Save & Verify" : "保存并验证"
    }

    static func removeKeyTitle(language: AppLanguage) -> String {
        language == .english ? "Remove Key" : "移除 Key"
    }

    static func getKeyTitle(language: AppLanguage) -> String {
        language == .english ? "Get API Key" : "获取 API Key"
    }

    static func enableRecommendationTitle(language: AppLanguage) -> String {
        language == .english ? "Enable Jev Recommendations" : "启用 Jev 推荐"
    }

    static func contextPermissionTitle(language: AppLanguage) -> String {
        language == .english ? "Context Access" : "增强上下文权限"
    }

    static func contextPermissionGranted(language: AppLanguage) -> String {
        language == .english ? "Granted" : "已授权"
    }

    static func contextPermissionNotGranted(language: AppLanguage) -> String {
        language == .english ? "Not Granted" : "未授权"
    }

    static func grantPermissionTitle(language: AppLanguage) -> String {
        language == .english ? "Grant Access" : "授权增强上下文"
    }

    static func openSettingsTitle(language: AppLanguage) -> String {
        language == .english ? "Open Settings" : "打开系统设置"
    }

    static func refreshPermissionTitle(language: AppLanguage) -> String {
        language == .english ? "Refresh Status" : "重新检测"
    }


    static func dataNotice(language: AppLanguage) -> String {
        language == .english
            ? "When enabled, V-Paste sends limited context from the active destination input and redacted candidate summaries to TypeSafe. Secure text fields and detected secrets are never sent."
            : "启用后，V-Paste 会向 TypeSafe 发送有限的目标输入上下文和经过脱敏的候选摘要。安全输入框和检测到的敏感内容不会发送。"
    }

    // MARK: - Toast 提示文案

    static func toastVerifySuccess(language: AppLanguage) -> String {
        language == .english ? "API Key verified and saved successfully" : "API Key 验证成功，已安全保存"
    }

    static func toastInvalidKey(language: AppLanguage) -> String {
        language == .english ? "Invalid API Key, please check and try again" : "API Key 无效，请检查后重试"
    }

    static func toastPermissionDenied(language: AppLanguage) -> String {
        language == .english ? "Account has no permission for Jev model" : "当前账号尚未开通 Jev 模型访问权限"
    }

    static func toastModelUnavailable(language: AppLanguage) -> String {
        language == .english ? "No supported Jev model found in account" : "账号模型列表中未找到支持的 Jev 模型"
    }

    static func toastNetworkUnavailable(language: AppLanguage, message: String? = nil) -> String {
        let base = language == .english ? "Network unavailable or request timed out" : "网络连接异常或请求超时，请稍后重试"
        if let message, !message.isEmpty {
            return "\(base) (\(message))"
        }
        return base
    }

    static func toastKeyRemoved(language: AppLanguage) -> String {
        language == .english ? "API Key has been removed" : "API Key 已彻底移除"
    }

    // MARK: - 用量与费用统计文案

    static func usageSectionTitle(language: AppLanguage) -> String {
        language == .english ? "Monthly Usage (Estimate)" : "本月用量预估"
    }

    static func usageRequestsTitle(language: AppLanguage) -> String {
        language == .english ? "Requests" : "请求次数"
    }

    static func usageInputTokensLabel(language: AppLanguage) -> String {
        language == .english ? "Input" : "输入"
    }

    static func usageOutputTokensLabel(language: AppLanguage) -> String {
        language == .english ? "Output" : "输出"
    }

    static func usageCostTitle(language: AppLanguage) -> String {
        language == .english ? "Est. Cost" : "预估费用"
    }

    static func usageDisclaimer(language: AppLanguage) -> String {
        language == .english
            ? "Local estimate for reference only. Official usage and charges: TypeSafe Usage."
            : "本地估算，仅供参考。实际用量与费用以 TypeSafe Usage 为准。"
    }

    static func officialUsageLinkTitle(language: AppLanguage) -> String {
        language == .english ? "Official Usage" : "查看官方用量"
    }

    static let officialUsageURL = URL(string: "https://console.typesafe.ai/usage")!

    static func clearUsageTitle(language: AppLanguage) -> String {
        language == .english ? "Clear Local Stats" : "清除本地统计"
    }

    static func toastUsageCleared(language: AppLanguage) -> String {
        language == .english ? "Local usage statistics cleared" : "已清除本地用量统计"
    }
}
