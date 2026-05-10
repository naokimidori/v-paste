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

    static func currentVersionLabel(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where !build.isEmpty:
            return "\(version) (\(build))"
        case let (.some(version), _):
            return version
        default:
            return "Debug"
        }
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
                title: language == .english ? "About \(appName)" : "关于 \(appName)",
                action: .openAbout,
                children: aboutItems(language: language, appVersion: appVersion)
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

    private static func aboutItems(
        language: AppLanguage,
        appVersion: String
    ) -> [MenuBarMenuItemDescriptor] {
        [
            MenuBarMenuItemDescriptor(
                title: MenuBarAboutDescriptor.versionText(
                    language: language,
                    versionLabel: appVersion
                ),
                action: nil
            ),
            MenuBarMenuItemDescriptor(
                title: MenuBarAboutDescriptor.githubTitle(language: language),
                action: .openGitHub,
                iconAssetName: MenuBarAboutDescriptor.githubIconAssetName
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
