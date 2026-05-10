import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

enum SettingsViewLayoutMetrics {
    static let horizontalPadding: CGFloat = 22
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let tabSwitcherHeight: CGFloat = 28
    static let tabSwitcherBottomSpacing: CGFloat = 12
    static let groupTopPadding: CGFloat = 10
    static let groupBottomPadding: CGFloat = 10
    static let groupHorizontalPadding: CGFloat = 14
    static let groupRowSpacing: CGFloat = 6
    static let statusRowHeight: CGFloat = 26
    static let dividerHeight: CGFloat = 3
    static let toggleRowHeight: CGFloat = 28
    static let shortcutRowHeight: CGFloat = 30
    static let retentionRowHeight: CGFloat = 30
    static let languageRowHeight: CGFloat = 30
    static let ignoredAppIconSize: CGFloat = 24
    static let ignoredAppListRowHeight: CGFloat = 34
    static let ignoredAppsListHeight: CGFloat = 144
    static let ignoredAppsPickerWidth: CGFloat = 0
    static let ignoredAppsTitleRowHeight: CGFloat = 18
    static let ignoredAppsDescriptionHeight: CGFloat = 46
    static let ignoredAppsToggleRowHeight: CGFloat = 28
    static let ignoredAppsButtonRowHeight: CGFloat = 24
    static let valueRowHeight: CGFloat = 26
    static let clearHistoryButtonRowHeight: CGFloat = 28
    static let usesManualTabSwitcher = true
    static let drawsGroupBorder = false

    static let minimumHeightForClearHistoryButton: CGFloat =
        topPadding + bottomPadding
        + tabSwitcherHeight + tabSwitcherBottomSpacing
        + groupTopPadding + groupBottomPadding
        + statusRowHeight
        + dividerHeight
        + toggleRowHeight * 2
        + shortcutRowHeight
        + retentionRowHeight
        + languageRowHeight
        + dividerHeight
        + valueRowHeight
        + clearHistoryButtonRowHeight
        + groupRowSpacing * 9

    static let minimumHeightForIgnoredApplicationsTab: CGFloat =
        topPadding + bottomPadding
        + tabSwitcherHeight + tabSwitcherBottomSpacing
        + groupTopPadding + groupBottomPadding
        + ignoredAppsTitleRowHeight
        + ignoredAppsToggleRowHeight
        + ignoredAppsDescriptionHeight
        + ignoredAppsListHeight
        + ignoredAppsButtonRowHeight
        + 10 * 4
}

enum SettingsClearHistoryConfirmationDescriptor {
    static func title(language: AppLanguage) -> String {
        language == .english ? "Clear history?" : "确认清空历史？"
    }

    static func message(language: AppLanguage) -> String {
        language == .english
            ? "This will delete all clipboard history and cannot be undone."
            : "此操作会删除所有剪贴板记录，无法撤销。"
    }

    static func confirmTitle(language: AppLanguage) -> String {
        language == .english ? "Clear History" : "清空历史"
    }

    static func cancelTitle(language: AppLanguage) -> String {
        language == .english ? "Cancel" : "取消"
    }
}

struct SettingsView: View {
    let onSetLaunchAtLogin: (Bool) throws -> Bool
    let onSetMonitoringEnabled: (Bool) -> Void
    let onSetLanguage: (AppLanguage) -> Void
    let onSetHotKey: (HotKeyPreference) throws -> HotKeyPreference
    let onSetRetentionPolicy: (ClipboardRetentionPolicy) -> Void
    let onSetApplicationIgnoreEnabled: (Bool) -> Void
    let onSetIgnoredApplications: ([IgnoredApplicationRule]) -> Void
    let onClearHistory: () -> Void

    @State private var isLaunchAtLoginEnabled: Bool
    @State private var isMonitoringEnabled: Bool
    @State private var language: AppLanguage
    @State private var hotKey: HotKeyPreference
    @State private var retentionPolicy: ClipboardRetentionPolicy
    @State private var isApplicationIgnoreEnabled: Bool
    @State private var ignoredApplications: [IgnoredApplicationRule]
    @State private var selectedTab = SettingsTabDescriptor.ID.general
    @State private var selectedIgnoredApplicationID: IgnoredApplicationRule.ID?
    @State private var isRecordingShortcut = false
    @State private var shortcutEventMonitor: Any?
    @State private var isShowingClearHistoryConfirmation = false
    @State private var errorMessage: String?

    init(
        appState: AppState,
        isLaunchAtLoginEnabled: Bool,
        onSetLaunchAtLogin: @escaping (Bool) throws -> Bool,
        onSetMonitoringEnabled: @escaping (Bool) -> Void,
        language: AppLanguage,
        onSetLanguage: @escaping (AppLanguage) -> Void,
        hotKey: HotKeyPreference,
        onSetHotKey: @escaping (HotKeyPreference) throws -> HotKeyPreference,
        retentionPolicy: ClipboardRetentionPolicy,
        onSetRetentionPolicy: @escaping (ClipboardRetentionPolicy) -> Void,
        ignoredApplications: [IgnoredApplicationRule],
        isApplicationIgnoreEnabled: Bool,
        onSetApplicationIgnoreEnabled: @escaping (Bool) -> Void,
        onSetIgnoredApplications: @escaping ([IgnoredApplicationRule]) -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.onSetMonitoringEnabled = onSetMonitoringEnabled
        self.onSetLanguage = onSetLanguage
        self.onSetHotKey = onSetHotKey
        self.onSetRetentionPolicy = onSetRetentionPolicy
        self.onSetApplicationIgnoreEnabled = onSetApplicationIgnoreEnabled
        self.onSetIgnoredApplications = onSetIgnoredApplications
        self.onClearHistory = onClearHistory
        _isLaunchAtLoginEnabled = State(initialValue: isLaunchAtLoginEnabled)
        _isMonitoringEnabled = State(initialValue: !appState.isMonitoringPaused)
        _language = State(initialValue: language)
        _hotKey = State(initialValue: hotKey)
        _retentionPolicy = State(initialValue: retentionPolicy)
        _isApplicationIgnoreEnabled = State(initialValue: isApplicationIgnoreEnabled)
        _ignoredApplications = State(initialValue: ignoredApplications)
        _selectedIgnoredApplicationID = State(initialValue: ignoredApplications.first?.id)
    }

    var body: some View {
        let tabs = SettingsTabDescriptor.all(language: language)

        VStack(alignment: .leading, spacing: SettingsViewLayoutMetrics.tabSwitcherBottomSpacing) {
            SettingsTabSwitcher(tabs: tabs, selection: $selectedTab)

            Group {
                switch selectedTab {
                case .general:
                    generalTab(descriptors: SettingsPreferenceDescriptor.singleGroup(language: language))
                case .ignoredApplications:
                    ignoredApplicationsTab(title: tabs[1].title)
                }
            }
        }
        .padding(.horizontal, SettingsViewLayoutMetrics.horizontalPadding)
        .padding(.top, SettingsViewLayoutMetrics.topPadding)
        .padding(.bottom, SettingsViewLayoutMetrics.bottomPadding)
        .frame(
            width: SettingsPanelDescriptor.contentSize.width,
            height: SettingsPanelDescriptor.contentSize.height,
            alignment: .topLeading
        )
        .alert(
            SettingsClearHistoryConfirmationDescriptor.title(language: language),
            isPresented: $isShowingClearHistoryConfirmation
        ) {
            Button(SettingsClearHistoryConfirmationDescriptor.cancelTitle(language: language), role: .cancel) {}
            Button(SettingsClearHistoryConfirmationDescriptor.confirmTitle(language: language), role: .destructive) {
                onClearHistory()
            }
        } message: {
            Text(SettingsClearHistoryConfirmationDescriptor.message(language: language))
        }
        .onChange(of: isRecordingShortcut) { _, isRecording in
            if isRecording {
                installShortcutEventMonitor()
            } else {
                removeShortcutEventMonitor()
            }
        }
        .onDisappear {
            removeShortcutEventMonitor()
        }
    }

    private func generalTab(descriptors: [SettingsPreferenceDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSingleGroup {
                SettingsStatusRow(
                    title: descriptors[0].title,
                    value: isMonitoringEnabled
                        ? (language == .english ? "Running" : "运行中")
                        : (language == .english ? "Paused" : "已暂停"),
                    isRunning: isMonitoringEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: descriptors[1].title,
                    isOn: launchAtLoginBinding
                )

                SettingsToggleRow(
                    title: descriptors[2].title,
                    isOn: monitoringBinding
                )

                SettingsShortcutRow(
                    title: descriptors[3].title,
                    shortcutLabel: isRecordingShortcut
                        ? SettingsShortcutDescriptor.recordingPrompt(language: language)
                        : hotKey.displayLabel,
                    isRecording: isRecordingShortcut,
                    action: beginRecordingShortcut
                )

                SettingsRetentionRow(
                    title: descriptors[4].title,
                    language: language,
                    selection: retentionBinding
                )

                SettingsLanguageRow(
                    title: descriptors[5].title,
                    selection: languageBinding
                )

                SettingsDivider()

                SettingsValueRow(
                    title: descriptors[6].title,
                    value: versionLabel
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button(role: .destructive) {
                        isShowingClearHistoryConfirmation = true
                    } label: {
                        Text(SettingsClearHistoryConfirmationDescriptor.confirmTitle(language: language))
                            .foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: SettingsViewLayoutMetrics.clearHistoryButtonRowHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ignoredApplicationsTab(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSingleGroup {
                SettingsIgnoredAppsRow(
                    title: title,
                    isEnabled: applicationIgnoreEnabledBinding,
                    rules: ignoredApplications,
                    selectedID: ignoredApplicationSelectionBinding,
                    language: language,
                    onAdd: addIgnoredApplication,
                    onRemove: removeSelectedIgnoredApplication,
                    onReset: resetIgnoredApplications
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        case (.none, .none):
            return SettingsPreferenceDescriptor.singleGroup(language: language)[6].detail ?? "Debug"
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { newValue in
                guard isLaunchAtLoginEnabled != newValue else { return }

                let previousValue = isLaunchAtLoginEnabled
                do {
                    isLaunchAtLoginEnabled = try onSetLaunchAtLogin(newValue)
                    errorMessage = nil
                } catch {
                    isLaunchAtLoginEnabled = previousValue
                    errorMessage = "开机自启设置失败"
                }
            }
        )
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { isMonitoringEnabled },
            set: { newValue in
                guard isMonitoringEnabled != newValue else { return }

                isMonitoringEnabled = newValue
                onSetMonitoringEnabled(newValue)
                errorMessage = nil
            }
        )
    }

    private var retentionBinding: Binding<ClipboardRetentionPolicy> {
        Binding(
            get: { retentionPolicy },
            set: { newValue in
                guard retentionPolicy != newValue else { return }

                retentionPolicy = newValue
                onSetRetentionPolicy(newValue)
                errorMessage = nil
            }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: { newValue in
                guard language != newValue else { return }

                language = newValue
                onSetLanguage(newValue)
                errorMessage = nil
            }
        )
    }

    private var ignoredApplicationSelectionBinding: Binding<IgnoredApplicationRule.ID?> {
        Binding(
            get: { selectedIgnoredApplicationID },
            set: { selectedIgnoredApplicationID = $0 }
        )
    }

    private var applicationIgnoreEnabledBinding: Binding<Bool> {
        Binding(
            get: { isApplicationIgnoreEnabled },
            set: { newValue in
                guard isApplicationIgnoreEnabled != newValue else { return }

                isApplicationIgnoreEnabled = newValue
                onSetApplicationIgnoreEnabled(newValue)
                errorMessage = nil
            }
        )
    }

    private func beginRecordingShortcut() {
        errorMessage = nil
        isRecordingShortcut = true
    }

    private func installShortcutEventMonitor() {
        removeShortcutEventMonitor()
        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                Task { @MainActor in
                    isRecordingShortcut = false
                }
                return nil
            }

            guard let shortcut = HotKeyPreference.capture(event: event) else {
                Task { @MainActor in
                    errorMessage = SettingsShortcutDescriptor.invalidShortcutMessage(language: language)
                }
                return nil
            }

            Task { @MainActor in
                applyShortcut(shortcut)
            }
            return nil
        }
    }

    private func removeShortcutEventMonitor() {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
            self.shortcutEventMonitor = nil
        }
    }

    private func applyShortcut(_ shortcut: HotKeyPreference) {
        do {
            hotKey = try onSetHotKey(shortcut)
            isRecordingShortcut = false
            errorMessage = nil
        } catch {
            isRecordingShortcut = false
            errorMessage = SettingsShortcutDescriptor.registrationFailedMessage(language: language)
        }
    }

    private func addIgnoredApplication() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.applicationBundle]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        guard openPanel.runModal() == .OK,
              let url = openPanel.url
        else {
            return
        }

        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier
            ?? url.deletingPathExtension().lastPathComponent
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let rule = IgnoredApplicationRule(
            name: displayName,
            bundleIdentifier: bundleIdentifier
        )
        var rules = ignoredApplications.filter { $0.id != rule.id }
        rules.append(rule)
        applyIgnoredApplications(rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        selectedIgnoredApplicationID = rule.id
    }

    private func removeSelectedIgnoredApplication() {
        guard let selectedIgnoredApplicationID else { return }

        let rules = ignoredApplications.filter { $0.id != selectedIgnoredApplicationID }
        applyIgnoredApplications(rules)
        self.selectedIgnoredApplicationID = rules.first?.id
    }

    private func resetIgnoredApplications() {
        applyIgnoredApplications(IgnoredApplicationRule.defaultRules)
        selectedIgnoredApplicationID = IgnoredApplicationRule.defaultRules.first?.id
    }

    private func applyIgnoredApplications(_ rules: [IgnoredApplicationRule]) {
        ignoredApplications = rules
        onSetIgnoredApplications(rules)
        errorMessage = nil
    }
}

private struct SettingsTabSwitcher: View {
    let tabs: [SettingsTabDescriptor]
    @Binding var selection: SettingsTabDescriptor.ID

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(tabs) { tab in
                Text(tab.title).tag(tab.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(height: SettingsViewLayoutMetrics.tabSwitcherHeight)
    }
}

private struct SettingsSingleGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsViewLayoutMetrics.groupRowSpacing) {
            content
        }
        .padding(.top, SettingsViewLayoutMetrics.groupTopPadding)
        .padding(.bottom, SettingsViewLayoutMetrics.groupBottomPadding)
        .padding(.horizontal, SettingsViewLayoutMetrics.groupHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
        )
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isRunning ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isRunning ? .green : .secondary)
        }
        .frame(height: SettingsViewLayoutMetrics.statusRowHeight)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(height: SettingsViewLayoutMetrics.toggleRowHeight)
    }
}

private struct SettingsShortcutRow: View {
    let title: String
    let shortcutLabel: String
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button(action: action) {
                Text(shortcutLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .frame(minWidth: 74)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.22))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(height: SettingsViewLayoutMetrics.shortcutRowHeight)
    }
}

private struct SettingsRetentionRow: View {
    let title: String
    let language: AppLanguage
    @Binding var selection: ClipboardRetentionPolicy

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Picker("", selection: $selection) {
                ForEach(ClipboardRetentionPolicy.allCases) { policy in
                    Text(policy.title(language: language)).tag(policy)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .frame(height: SettingsViewLayoutMetrics.retentionRowHeight)
    }
}

private struct SettingsLanguageRow: View {
    let title: String
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Picker("", selection: $selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .frame(height: SettingsViewLayoutMetrics.languageRowHeight)
    }
}

private struct SettingsIgnoredAppsRow: View {
    let title: String
    @Binding var isEnabled: Bool
    let rules: [IgnoredApplicationRule]
    @Binding var selectedID: IgnoredApplicationRule.ID?
    let language: AppLanguage
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(height: SettingsViewLayoutMetrics.ignoredAppsTitleRowHeight)

            HStack(spacing: 12) {
                Text(SettingsIgnoredAppsDescriptor.enabledTitle(language: language))
                    .lineLimit(1)

                Spacer(minLength: 12)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .frame(height: SettingsViewLayoutMetrics.ignoredAppsToggleRowHeight)

            Text(SettingsIgnoredAppsDescriptor.explanation(language: language))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: SettingsViewLayoutMetrics.ignoredAppsDescriptionHeight,
                    alignment: .topLeading
                )

            SettingsIgnoredAppsList(
                rules: rules,
                selectedID: $selectedID,
                language: language
            )

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(addTitle, action: onAdd)
                Button(removeTitle, action: onRemove)
                    .disabled(selectedID == nil)
                Button(resetTitle, action: onReset)
            }
            .controlSize(.small)
            .frame(height: SettingsViewLayoutMetrics.ignoredAppsButtonRowHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addTitle: String {
        SettingsIgnoredAppsDescriptor.addTitle(language: language)
    }

    private var removeTitle: String {
        SettingsIgnoredAppsDescriptor.removeTitle(language: language)
    }

    private var resetTitle: String {
        SettingsIgnoredAppsDescriptor.resetTitle(language: language)
    }
}

private struct SettingsIgnoredAppsList: View {
    let rules: [IgnoredApplicationRule]
    @Binding var selectedID: IgnoredApplicationRule.ID?
    let language: AppLanguage

    var body: some View {
        Group {
            if rules.isEmpty {
                Text(SettingsIgnoredAppsDescriptor.emptyTitle(language: language))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rules) { rule in
                            SettingsIgnoredAppListRow(
                                rule: rule,
                                isSelected: selectedID == rule.id
                            ) {
                                selectedID = rule.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(height: SettingsViewLayoutMetrics.ignoredAppsListHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }
}

private struct SettingsIgnoredAppListRow: View {
    let rule: IgnoredApplicationRule
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: SettingsViewLayoutMetrics.ignoredAppIconSize,
                        height: SettingsViewLayoutMetrics.ignoredAppIconSize
                    )

                Text(rule.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: SettingsViewLayoutMetrics.ignoredAppListRowHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return NSImage(named: NSImage.applicationIconName)
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: SettingsViewLayoutMetrics.valueRowHeight)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 1)
            .frame(height: SettingsViewLayoutMetrics.dividerHeight)
    }
}
