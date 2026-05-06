import AppKit
import Carbon
import SwiftUI

enum SettingsViewLayoutMetrics {
    static let horizontalPadding: CGFloat = 22
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let groupTopPadding: CGFloat = 10
    static let groupBottomPadding: CGFloat = 10
    static let groupHorizontalPadding: CGFloat = 14
    static let groupRowSpacing: CGFloat = 6
    static let statusRowHeight: CGFloat = 26
    static let dividerHeight: CGFloat = 3
    static let toggleRowHeight: CGFloat = 28
    static let shortcutRowHeight: CGFloat = 30
    static let retentionRowHeight: CGFloat = 30
    static let valueRowHeight: CGFloat = 26
    static let clearHistoryButtonRowHeight: CGFloat = 28
    static let drawsGroupBorder = false

    static let minimumHeightForClearHistoryButton: CGFloat =
        topPadding + bottomPadding
        + groupTopPadding + groupBottomPadding
        + statusRowHeight
        + dividerHeight
        + toggleRowHeight * 2
        + shortcutRowHeight
        + retentionRowHeight
        + dividerHeight
        + valueRowHeight
        + clearHistoryButtonRowHeight
        + groupRowSpacing * 8
}

enum SettingsClearHistoryConfirmationDescriptor {
    static let title = "确认清空历史？"
    static let message = "此操作会删除所有剪贴板记录，无法撤销。"
    static let confirmTitle = "清空历史"
    static let cancelTitle = "取消"
}

struct SettingsView: View {
    let onSetLaunchAtLogin: (Bool) throws -> Bool
    let onSetMonitoringEnabled: (Bool) -> Void
    let onSetHotKey: (HotKeyPreference) throws -> HotKeyPreference
    let onSetRetentionPolicy: (ClipboardRetentionPolicy) -> Void
    let onClearHistory: () -> Void

    @State private var isLaunchAtLoginEnabled: Bool
    @State private var isMonitoringEnabled: Bool
    @State private var hotKey: HotKeyPreference
    @State private var retentionPolicy: ClipboardRetentionPolicy
    @State private var isRecordingShortcut = false
    @State private var shortcutEventMonitor: Any?
    @State private var isShowingClearHistoryConfirmation = false
    @State private var errorMessage: String?

    init(
        appState: AppState,
        isLaunchAtLoginEnabled: Bool,
        onSetLaunchAtLogin: @escaping (Bool) throws -> Bool,
        onSetMonitoringEnabled: @escaping (Bool) -> Void,
        hotKey: HotKeyPreference,
        onSetHotKey: @escaping (HotKeyPreference) throws -> HotKeyPreference,
        retentionPolicy: ClipboardRetentionPolicy,
        onSetRetentionPolicy: @escaping (ClipboardRetentionPolicy) -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.onSetMonitoringEnabled = onSetMonitoringEnabled
        self.onSetHotKey = onSetHotKey
        self.onSetRetentionPolicy = onSetRetentionPolicy
        self.onClearHistory = onClearHistory
        _isLaunchAtLoginEnabled = State(initialValue: isLaunchAtLoginEnabled)
        _isMonitoringEnabled = State(initialValue: !appState.isMonitoringPaused)
        _hotKey = State(initialValue: hotKey)
        _retentionPolicy = State(initialValue: retentionPolicy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSingleGroup {
                SettingsStatusRow(
                    title: SettingsPreferenceDescriptor.singleGroup[0].title,
                    value: isMonitoringEnabled ? "运行中" : "已暂停",
                    isRunning: isMonitoringEnabled
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: SettingsPreferenceDescriptor.singleGroup[1].title,
                    isOn: launchAtLoginBinding
                )

                SettingsToggleRow(
                    title: SettingsPreferenceDescriptor.singleGroup[2].title,
                    isOn: monitoringBinding
                )

                SettingsShortcutRow(
                    title: SettingsPreferenceDescriptor.singleGroup[3].title,
                    shortcutLabel: isRecordingShortcut ? "按下快捷键" : hotKey.displayLabel,
                    isRecording: isRecordingShortcut,
                    action: beginRecordingShortcut
                )

                SettingsRetentionRow(
                    title: SettingsPreferenceDescriptor.singleGroup[4].title,
                    selection: retentionBinding
                )

                SettingsDivider()

                SettingsValueRow(
                    title: SettingsPreferenceDescriptor.singleGroup[5].title,
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
                        Text(SettingsClearHistoryConfirmationDescriptor.confirmTitle)
                            .foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: SettingsViewLayoutMetrics.clearHistoryButtonRowHeight)
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
            SettingsClearHistoryConfirmationDescriptor.title,
            isPresented: $isShowingClearHistoryConfirmation
        ) {
            Button(SettingsClearHistoryConfirmationDescriptor.cancelTitle, role: .cancel) {}
            Button(SettingsClearHistoryConfirmationDescriptor.confirmTitle, role: .destructive) {
                onClearHistory()
            }
        } message: {
            Text(SettingsClearHistoryConfirmationDescriptor.message)
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
            return SettingsPreferenceDescriptor.singleGroup[5].detail ?? "Debug"
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
                    errorMessage = "快捷键需要包含修饰键"
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
            errorMessage = "快捷键注册失败"
        }
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
    @Binding var selection: ClipboardRetentionPolicy

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            Picker("", selection: $selection) {
                ForEach(ClipboardRetentionPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .frame(height: SettingsViewLayoutMetrics.retentionRowHeight)
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
