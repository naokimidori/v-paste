import AppKit
import Carbon
import XCTest
@testable import V_Paste

@MainActor
final class MenuBarSettingsDescriptorTests: XCTestCase {
    func testMenuBarDescriptorUsesRequestedSettingsMenu() {
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            shortcut: .defaultShowPanel
        )

        XCTAssertEqual(items.map(\.title), [
            "Show V-Paste",
            nil,
            "Preferences...",
            "About",
            nil,
            "Quit"
        ])
        XCTAssertEqual(items[0].keyEquivalent, "~")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.option])
        XCTAssertEqual(items[0].shortcutDisplay, "⌥~")
        XCTAssertEqual(items[2].keyEquivalent, ",")
        XCTAssertEqual(items[2].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(items[5].keyEquivalent, "q")
        XCTAssertEqual(items[5].keyEquivalentModifierMask, [.command])
    }

    func testMenuBarDescriptorUsesChineseLanguage() {
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            language: .simplifiedChinese,
            shortcut: .defaultShowPanel
        )

        XCTAssertEqual(items.map(\.title), [
            "显示 V-Paste",
            nil,
            "偏好设置...",
            "关于",
            nil,
            "退出"
        ])
        XCTAssertEqual(items[0].keyEquivalent, "~")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.option])
        XCTAssertEqual(items[0].shortcutDisplay, "⌥~")
        XCTAssertEqual(items[2].keyEquivalent, ",")
        XCTAssertEqual(items[2].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(items[5].keyEquivalent, "q")
        XCTAssertEqual(items[5].keyEquivalentModifierMask, [.command])
    }

    func testMenuBarDescriptorUsesCustomShowPanelShortcut() {
        let shortcut = HotKeyPreference(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(shiftKey | cmdKey),
            keyEquivalent: "k",
            displayKey: "K"
        )
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            shortcut: shortcut
        )

        XCTAssertEqual(items[0].keyEquivalent, "k")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(items[0].shortcutDisplay, "⇧⌘K")
    }

    func testMenuBarDescriptorRemovesDangerActionsFromStatusMenu() {
        let titles = MenuBarMenuDescriptor.items(appName: "V-Paste", shortcut: .defaultShowPanel)
            .compactMap(\.title)

        XCTAssertFalse(titles.contains("Pause Monitoring"))
        XCTAssertFalse(titles.contains("Resume Monitoring"))
        XCTAssertFalse(titles.contains("Clear History"))
    }

    func testPanelOverflowMenuDescriptorOmitsShowPanelAction() {
        let items = MenuBarMenuDescriptor.panelOverflowItems(
            appName: "V-Paste",
            shortcut: .defaultShowPanel
        )

        XCTAssertEqual(items.map(\.title), [
            "Preferences...",
            "About",
            nil,
            "Quit"
        ])
        XCTAssertEqual(items.map(\.action), [
            .openPreferences,
            .openAbout,
            nil,
            .quit
        ])
        XCTAssertFalse(items.contains { $0.action == .showPanel })
    }

    func testPanelOverflowMenuDescriptorUsesRequestedLanguage() {
        let items = MenuBarMenuDescriptor.panelOverflowItems(
            appName: "V-Paste",
            language: .simplifiedChinese,
            shortcut: .defaultShowPanel,
            appVersion: "1.1.0"
        )

        XCTAssertEqual(items.map(\.title), [
            "偏好设置...",
            "关于",
            nil,
            "退出"
        ])
        XCTAssertEqual(items[1].children.map(\.title), [
        ])
        XCTAssertEqual(items[1].shortcutDisplay, "1.1.0")
        XCTAssertEqual(
            MenuBarAboutDescriptor.repositoryURL.absoluteString,
            "https://github.com/naokimidori/v-paste"
        )
    }

    func testMenuBarAboutDescriptorShowsVersionInlineWithoutSubmenu() throws {
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            language: .english,
            shortcut: .defaultShowPanel,
            appVersion: "1.1.0"
        )

        let aboutItem = try XCTUnwrap(items.first { $0.action == .openAbout })
        XCTAssertEqual(aboutItem.title, "About")
        XCTAssertEqual(aboutItem.shortcutDisplay, "1.1.0")
        XCTAssertTrue(aboutItem.children.isEmpty)
    }

    func testSettingsPreferencesUseSingleGroupOrder() {
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .english).map(\.title), [
            "Status",
            "Launch at Login",
            "Monitor Clipboard",
            "Show V-Paste",
            "History Retention",
            "Language"
        ])
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .english).map(\.detail), [
            nil,
            nil,
            nil,
            "⌥~",
            "30 days",
            "English"
        ])
    }

    func testSettingsPreferencesUseChineseLanguage() {
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .simplifiedChinese).map(\.title), [
            "运行状态",
            "开机自启",
            "监听剪贴板",
            "显示 V-Paste",
            "历史记录有效期",
            "语言"
        ])
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .simplifiedChinese).map(\.detail), [
            nil,
            nil,
            nil,
            "⌥~",
            "30 天",
            "简体中文"
        ])
    }

    func testSettingsTabsSeparateApplicationIgnoreGroup() {
        XCTAssertEqual(SettingsTabDescriptor.all(language: .english).map(\.id), [
            .general,
            .ignoredApplications,
            .about
        ])
        XCTAssertEqual(SettingsTabDescriptor.all(language: .english).map(\.title), [
            "General",
            "App Ignore",
            "About"
        ])
        XCTAssertEqual(SettingsTabDescriptor.all(language: .simplifiedChinese).map(\.title), [
            "通用",
            "应用忽略",
            "关于"
        ])
        XCTAssertEqual(SettingsTabDescriptor.all(language: .english).map(\.systemImageName), [
            "gearshape",
            "hand.raised",
            "info.circle"
        ])
    }

    func testSettingsAboutDescriptorUsesAppMetadataAndRepository() {
        XCTAssertEqual(SettingsAboutDescriptor.title(language: .english), "About")
        XCTAssertEqual(SettingsAboutDescriptor.title(language: .simplifiedChinese), "关于")
        XCTAssertEqual(SettingsAboutDescriptor.appName(info: ["CFBundleDisplayName": "Custom Paste"]), "Custom Paste")
        XCTAssertEqual(SettingsAboutDescriptor.appName(info: ["CFBundleName": "Bundle Paste"]), "Bundle Paste")
        XCTAssertEqual(SettingsAboutDescriptor.appName(info: [:]), "V-Paste")
        XCTAssertEqual(SettingsAboutDescriptor.repositoryTitle(language: .english), "GitHub Repository")
        XCTAssertEqual(SettingsAboutDescriptor.repositoryTitle(language: .simplifiedChinese), "GitHub 仓库")
        XCTAssertEqual(SettingsAboutDescriptor.githubHelpTitle(language: .english), "Open GitHub Repository")
        XCTAssertEqual(SettingsAboutDescriptor.githubHelpTitle(language: .simplifiedChinese), "打开 GitHub 仓库")
        XCTAssertEqual(SettingsAboutDescriptor.repositoryURL, MenuBarAboutDescriptor.repositoryURL)
    }

    func testMenuBarAboutDescriptorFormatsReleaseAndDevelopmentVersionLabels() {
        let info = [
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "1"
        ]

        XCTAssertEqual(
            MenuBarAboutDescriptor.currentVersionLabel(info: info, isDevelopmentBuild: false),
            "1.1.0"
        )
        XCTAssertEqual(
            MenuBarAboutDescriptor.currentVersionLabel(info: info, isDevelopmentBuild: true),
            "1.1.0-dev"
        )
        XCTAssertEqual(
            MenuBarAboutDescriptor.currentVersionLabel(
                info: ["CFBundleShortVersionString": "1.1.0-dev"],
                isDevelopmentBuild: true
            ),
            "1.1.0-dev"
        )
    }

    func testMenuBarAboutDescriptorStandardPanelOptionsSuppressBuildVersion() {
        let options = MenuBarAboutDescriptor.standardPanelOptions(versionLabel: "1.1.0")

        XCTAssertEqual(
            options[.applicationVersion] as? String,
            "1.1.0"
        )
        XCTAssertEqual(
            options[.version] as? String,
            ""
        )
    }

    func testIgnoredApplicationsUseVerticalListMetrics() {
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppIconSize, 24)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppListRowHeight, 34)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsListHeight, 144)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsPickerWidth, 0)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsDescriptionHeight, 46)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsToggleRowHeight, 28)
    }

    func testIgnoredApplicationsDescriptorLocalizesListActions() {
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.title(language: .english), "App Ignore")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.title(language: .simplifiedChinese), "应用忽略")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.enabledTitle(language: .english), "Enable App Ignore")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.enabledTitle(language: .simplifiedChinese), "启用应用忽略")
        XCTAssertEqual(
            SettingsIgnoredAppsDescriptor.explanation(language: .english),
            "When enabled, V-Paste will not save clipboard content copied from the apps below. Use it for Keychain Access, password managers, or other sensitive apps."
        )
        XCTAssertEqual(
            SettingsIgnoredAppsDescriptor.explanation(language: .simplifiedChinese),
            "开启后，V-Paste 不会保存下列应用产生的剪贴板内容。适合钥匙串、密码管理器等敏感应用。"
        )
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.addTitle(language: .english), "Add...")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.addTitle(language: .simplifiedChinese), "添加...")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.removeTitle(language: .english), "Remove")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.removeTitle(language: .simplifiedChinese), "移除")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.resetTitle(language: .english), "Defaults")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.resetTitle(language: .simplifiedChinese), "恢复默认")
    }

    func testShortcutSettingsDescriptorShowsCurrentShortcut() {
        XCTAssertEqual(SettingsShortcutDescriptor.showPanelTitle(language: .english), "Show V-Paste")
        XCTAssertEqual(SettingsShortcutDescriptor.showPanelTitle(language: .simplifiedChinese), "显示 V-Paste")
        XCTAssertEqual(SettingsShortcutDescriptor.currentShortcutLabel, "⌥~")
    }

    func testShortcutRecordingCopyLocalizes() {
        XCTAssertEqual(SettingsShortcutDescriptor.recordingPrompt(language: .english), "Press shortcut")
        XCTAssertEqual(SettingsShortcutDescriptor.recordingPrompt(language: .simplifiedChinese), "按下快捷键")
        XCTAssertEqual(SettingsShortcutDescriptor.invalidShortcutMessage(language: .english), "Shortcut requires a modifier key")
        XCTAssertEqual(SettingsShortcutDescriptor.invalidShortcutMessage(language: .simplifiedChinese), "快捷键需要包含修饰键")
    }

    func testHotKeyPreferenceCapturesModifiedKeyboardShortcut() {
        let shortcut = HotKeyPreference.capture(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: [.command, .shift],
            charactersIgnoringModifiers: "k"
        )

        XCTAssertEqual(shortcut?.displayLabel, "⇧⌘K")
        XCTAssertEqual(shortcut?.keyEquivalent, "k")
        XCTAssertEqual(shortcut?.keyEquivalentModifierMask, [.command, .shift])
    }

    func testHotKeyPreferenceRejectsShortcutWithoutModifier() {
        XCTAssertNil(HotKeyPreference.capture(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: [],
            charactersIgnoringModifiers: "k"
        ))
    }

    func testClipboardRetentionPolicyUsesRequestedOptions() {
        XCTAssertEqual(ClipboardRetentionPolicy.allCases.map { $0.title(language: .english) }, [
            "7 days",
            "30 days",
            "Unlimited"
        ])
        XCTAssertEqual(ClipboardRetentionPolicy.allCases.map { $0.title(language: .simplifiedChinese) }, [
            "7 天",
            "30 天",
            "不限制"
        ])
        XCTAssertEqual(ClipboardRetentionPolicy.sevenDays.dayCount, 7)
        XCTAssertEqual(ClipboardRetentionPolicy.thirtyDays.dayCount, 30)
        XCTAssertNil(ClipboardRetentionPolicy.unlimited.dayCount)
    }

    func testAppPreferencesRoundTripsLanguageRetentionAndShortcut() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferences(userDefaults: defaults)
        let shortcut = HotKeyPreference(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey),
            keyEquivalent: "k",
            displayKey: "K"
        )

        XCTAssertEqual(preferences.language, .english)
        preferences.language = .simplifiedChinese
        preferences.clipboardRetentionPolicy = .sevenDays
        preferences.showPanelHotKey = shortcut

        let loadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(loadedPreferences.language, .simplifiedChinese)
        XCTAssertEqual(loadedPreferences.clipboardRetentionPolicy, .sevenDays)
        XCTAssertEqual(loadedPreferences.showPanelHotKey, shortcut)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testIgnoredApplicationDefaultsIncludeSecureApps() {
        XCTAssertTrue(IgnoredApplicationRule.defaultRules.contains {
            $0.bundleIdentifier == "com.apple.keychainaccess"
        })
        XCTAssertTrue(IgnoredApplicationRule.defaultRules.contains {
            $0.bundleIdentifier == "com.apple.SecurityAgent"
        })
    }

    func testIgnoredApplicationRuleMatchesBundleIdentifierCaseInsensitively() {
        let rule = IgnoredApplicationRule(
            name: "Keychain Access",
            bundleIdentifier: "com.apple.keychainaccess"
        )
        let sourceApplication = ClipboardSourceApplication(
            name: "Keychain Access",
            bundleIdentifier: "COM.APPLE.KEYCHAINACCESS"
        )

        XCTAssertTrue(rule.matches(sourceApplication))
    }

    func testIgnoredApplicationMatchingCanBeDisabled() {
        let sourceApplication = ClipboardSourceApplication(
            name: "Keychain Access",
            bundleIdentifier: "com.apple.keychainaccess"
        )

        XCTAssertTrue(IgnoredApplicationRule.isIgnored(
            sourceApplication,
            rules: IgnoredApplicationRule.defaultRules,
            isEnabled: true
        ))
        XCTAssertFalse(IgnoredApplicationRule.isIgnored(
            sourceApplication,
            rules: IgnoredApplicationRule.defaultRules,
            isEnabled: false
        ))
    }

    func testApplicationIgnorePreferenceDefaultsOnAndCanBeDisabled() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferences(userDefaults: defaults)

        XCTAssertTrue(preferences.isApplicationIgnoreEnabled)

        preferences.isApplicationIgnoreEnabled = false

        let loadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertFalse(loadedPreferences.isApplicationIgnoreEnabled)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAppPreferencesRoundTripsIgnoredApplications() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferences(userDefaults: defaults)
        let customRules = [
            IgnoredApplicationRule(
                name: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        ]

        XCTAssertGreaterThanOrEqual(preferences.ignoredApplications.count, 2)

        preferences.ignoredApplications = customRules

        let loadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(loadedPreferences.ignoredApplications, customRules)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSettingsPanelDescriptorUsesPopupContentMetrics() {
        XCTAssertEqual(SettingsPanelDescriptor.title(language: .english), "Preferences")
        XCTAssertEqual(SettingsPanelDescriptor.title(language: .simplifiedChinese), "偏好设置")
        XCTAssertEqual(SettingsPanelDescriptor.contentSize, CGSize(width: 580, height: 380))
    }

    func testSettingsPanelPlacementKeepsHorizontalCenterAndUsesUpperThirdVerticalPosition() {
        let frame = SettingsPanelPlacement.preferredFrame(
            contentSize: CGSize(width: 580, height: 420),
            screenFrame: NSRect(x: 100, y: 60, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, NSRect(x: 530, y: 450, width: 580, height: 420))
    }

    func testSettingsViewUsesCompactBorderlessContentLayout() {
        XCTAssertEqual(SettingsViewLayoutMetrics.horizontalPadding, 22)
        XCTAssertEqual(SettingsViewLayoutMetrics.topPadding, 8)
        XCTAssertEqual(SettingsViewLayoutMetrics.bottomPadding, 8)
        XCTAssertEqual(SettingsViewLayoutMetrics.topPadding, SettingsViewLayoutMetrics.bottomPadding)
        XCTAssertEqual(SettingsViewLayoutMetrics.groupTopPadding, 10)
        XCTAssertEqual(SettingsViewLayoutMetrics.groupBottomPadding, 10)
        XCTAssertFalse(SettingsViewLayoutMetrics.drawsGroupBorder)
    }

    func testSettingsViewUsesManualTabSwitcherToAvoidNativeTabContainerCycle() {
        XCTAssertTrue(SettingsViewLayoutMetrics.usesManualTabSwitcher)
        XCTAssertEqual(SettingsViewLayoutMetrics.tabSwitcherCornerRadius, 8)
        XCTAssertEqual(SettingsViewLayoutMetrics.tabItemCornerRadius, 6)
        XCTAssertEqual(SettingsViewLayoutMetrics.tabIconSize, 13)
        XCTAssertEqual(SettingsViewLayoutMetrics.tabFontSize, 13)
    }

    func testSettingsAboutLayoutUsesCenteredBrandingAndIconOnlyGitHubAction() {
        XCTAssertTrue(SettingsViewLayoutMetrics.aboutHeaderUsesCenteredBranding)
        XCTAssertFalse(SettingsViewLayoutMetrics.aboutGitHubShowsRepositoryText)
        XCTAssertEqual(SettingsViewLayoutMetrics.aboutIconSize, 78)
        XCTAssertEqual(SettingsViewLayoutMetrics.aboutGitHubButtonSize, 34)
        XCTAssertEqual(SettingsViewLayoutMetrics.aboutGitHubIconSize, 18)
    }

    func testSettingsPanelHeightKeepsClearHistoryButtonVisible() {
        XCTAssertEqual(SettingsViewLayoutMetrics.clearHistoryButtonRowHeight, 28)
        XCTAssertGreaterThanOrEqual(
            SettingsPanelDescriptor.contentSize.height,
            SettingsViewLayoutMetrics.minimumHeightForClearHistoryButton
        )
    }

    func testSettingsPanelHeightFitsIgnoredApplicationsTab() {
        XCTAssertGreaterThanOrEqual(
            SettingsPanelDescriptor.contentSize.height,
            SettingsViewLayoutMetrics.minimumHeightForIgnoredApplicationsTab
        )
    }

    func testSettingsPanelHeightFitsAboutTab() {
        XCTAssertGreaterThanOrEqual(
            SettingsPanelDescriptor.contentSize.height,
            SettingsViewLayoutMetrics.minimumHeightForAboutTab
        )
    }

    func testClearHistoryUsesDestructiveConfirmationCopy() {
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.title(language: .english), "Clear history?")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.title(language: .simplifiedChinese), "确认清空历史？")
        XCTAssertEqual(
            SettingsClearHistoryConfirmationDescriptor.message(language: .simplifiedChinese),
            "此操作会删除所有剪贴板记录，无法撤销。"
        )
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.confirmTitle(language: .english), "Clear History")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.confirmTitle(language: .simplifiedChinese), "清空历史")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.cancelTitle(language: .english), "Cancel")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.cancelTitle(language: .simplifiedChinese), "取消")
    }

    func testMenuBarDescriptorMapsItemsToActions() {
        XCTAssertEqual(MenuBarMenuAction.showPanel.selectorName, "openClipboardHistory")
        XCTAssertEqual(MenuBarMenuAction.openPreferences.selectorName, "openPreferences")
        XCTAssertEqual(MenuBarMenuAction.openAbout.selectorName, "openAbout")
        XCTAssertEqual(MenuBarMenuAction.openGitHub.selectorName, "openGitHub")
        XCTAssertEqual(MenuBarMenuAction.quit.selectorName, "quit")
    }
}
