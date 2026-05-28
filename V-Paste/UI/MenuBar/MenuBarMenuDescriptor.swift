import AppKit

enum MenuBarMenuAction: Equatable {
    case showPanel
    case openPreferences
    case openAbout
    case openGitHub
    case quit

    var selectorName: String {
        switch self {
        case .showPanel:
            return "openClipboardHistory"
        case .openPreferences:
            return "openPreferences"
        case .openAbout:
            return "openAbout"
        case .openGitHub:
            return "openGitHub"
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
    let iconAssetName: String?
    let children: [MenuBarMenuItemDescriptor]

    init(
        title: String?,
        action: MenuBarMenuAction?,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = [],
        shortcutDisplay: String? = nil,
        iconAssetName: String? = nil,
        children: [MenuBarMenuItemDescriptor] = []
    ) {
        self.title = title
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifierMask = keyEquivalentModifierMask
        self.shortcutDisplay = shortcutDisplay
        self.iconAssetName = iconAssetName
        self.children = children
    }

    static func separator() -> MenuBarMenuItemDescriptor {
        MenuBarMenuItemDescriptor(
            title: nil,
            action: nil
        )
    }
}

enum MenuBarAboutDescriptor {
    static let repositoryURL = URL(string: "https://github.com/naokimidori/v-paste")!
    static let githubIconAssetName = "GitHubIcon"
    static var isDevelopmentBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func versionText(
        language: AppLanguage,
        versionLabel: String = currentVersionLabel()
    ) -> String {
        language == .english
            ? "Version \(versionLabel)"
            : "版本 \(versionLabel)"
    }

    static func githubTitle(language: AppLanguage) -> String {
        language == .english ? "GitHub Repository" : "GitHub 仓库"
    }

    static func currentVersionLabel(
        bundle: Bundle = .main,
        isDevelopmentBuild: Bool = Self.isDevelopmentBuild
    ) -> String {
        currentVersionLabel(
            info: bundle.infoDictionary,
            isDevelopmentBuild: isDevelopmentBuild
        )
    }

    static func currentVersionLabel(
        info: [String: Any]?,
        isDevelopmentBuild: Bool
    ) -> String {
        let version = normalizedInfoString(info?["CFBundleShortVersionString"])
        let build = normalizedInfoString(info?["CFBundleVersion"])
        let baseVersion = version ?? build ?? "Debug"

        guard isDevelopmentBuild,
              baseVersion != "Debug",
              !baseVersion.hasSuffix("-dev")
        else {
            return baseVersion
        }

        return "\(baseVersion)-dev"
    }

    static func standardPanelOptions(
        versionLabel: String = currentVersionLabel()
    ) -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationVersion: versionLabel,
            .version: ""
        ]
    }

    private static func normalizedInfoString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MenuBarMenuDescriptor {
    static let defaultShortcutLabel = "⌥~"

    static func panelOverflowItems(
        appName: String,
        language: AppLanguage = .english,
        shortcut: HotKeyPreference = .defaultShowPanel,
        appVersion: String = MenuBarAboutDescriptor.currentVersionLabel()
    ) -> [MenuBarMenuItemDescriptor] {
        items(appName: appName, language: language, shortcut: shortcut, appVersion: appVersion)
            .filter { $0.action != .showPanel }
            .trimmedSeparators()
    }

    static func items(
        appName: String,
        language: AppLanguage = .english,
        shortcut: HotKeyPreference = .defaultShowPanel,
        appVersion: String = MenuBarAboutDescriptor.currentVersionLabel()
    ) -> [MenuBarMenuItemDescriptor] {
        [
            MenuBarMenuItemDescriptor(
                title: language == .english ? "Show \(appName)" : "显示 \(appName)",
                action: .showPanel,
                keyEquivalent: shortcut.keyEquivalent,
                keyEquivalentModifierMask: shortcut.keyEquivalentModifierMask,
                shortcutDisplay: shortcut.displayLabel
            ),
            .separator(),
            MenuBarMenuItemDescriptor(
                title: language == .english ? "Preferences..." : "偏好设置...",
                action: .openPreferences,
                keyEquivalent: ",",
                keyEquivalentModifierMask: [.command],
                shortcutDisplay: "⌘,"
            ),
            MenuBarMenuItemDescriptor(
                title: language == .english ? "About" : "关于",
                action: .openAbout,
                shortcutDisplay: appVersion
            ),
            .separator(),
            MenuBarMenuItemDescriptor(
                title: language == .english ? "Quit" : "退出",
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
