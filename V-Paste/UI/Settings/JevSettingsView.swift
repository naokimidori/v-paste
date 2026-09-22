import AppKit
import SwiftUI

/// Jev 设置选项卡视图
struct JevSettingsView: View {
    let language: AppLanguage
    let hasSavedKey: Bool
    let status: JevConfigurationStatus
    @Binding var isRecommendationEnabled: Bool
    let isAccessibilityTrusted: Bool
    let onSaveAndVerify: (String) async -> JevValidationResult
    let onRemoveKey: () -> Void
    let onRequestAccessibilityPermission: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    var onFetchUsageSummary: (() async -> JevMonthUsageSummary)? = nil
    var onClearUsage: (() async -> Void)? = nil

    @State private var apiKeyInput = ""
    @State private var isVerifying = false
    @State private var lastValidationResult: JevValidationResult?
    @State private var activeToast: JevToastMessage?
    @State private var toastTask: Task<Void, Never>?
    @State private var usageSummary: JevMonthUsageSummary?
    @State private var isClearingUsage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSingleGroup {
                // 1. 状态行
                statusRow

                SettingsDivider()

                // 2. API Key 输入行
                apiKeyInputRow

                // 3. 按钮操作行
                actionButtonsRow

                SettingsDivider()

                // 4. 功能启用开关
                toggleRow

                if isRecommendationEnabled {
                    SettingsDivider()

                    // 5. 用量与预估费用卡片
                    usageSummaryRow
                }

                SettingsDivider()

                // 6. 增强上下文权限行
                accessibilityRow

                SettingsDivider()

                // 7. 数据安全说明
                privacyNoticeRow
            }
        }
        .task(id: isRecommendationEnabled) {
            if isRecommendationEnabled {
                await loadUsageSummary()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jevUsageDidUpdate)) { _ in
            if isRecommendationEnabled {
                Task {
                    await loadUsageSummary()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if let activeToast {
                toastView(activeToast)
                    .padding(.bottom, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeToast != nil)
    }

    /// 状态展示行
    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(SettingsJevDescriptor.statusTitle(language: language))
                .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 12)

            Text(status.displayTitle(language: language))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .frame(height: SettingsViewLayoutMetrics.statusRowHeight)
    }

    /// API Key 输入行
    private var apiKeyInputRow: some View {
        HStack(spacing: 12) {
            Text(SettingsJevDescriptor.apiKeyTitle(language: language))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            SecureField(
                hasSavedKey && apiKeyInput.isEmpty
                    ? "••••••••••••••••••••••••"
                    : SettingsJevDescriptor.apiKeyPlaceholder(language: language),
                text: $apiKeyInput
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 260)
            .disabled(isVerifying)
        }
        .frame(height: SettingsViewLayoutMetrics.valueRowHeight)
    }

    /// 验证/保存/移除操作行
    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            Link(destination: SettingsJevDescriptor.getKeyURL) {
                HStack(spacing: 4) {
                    Text(SettingsJevDescriptor.getKeyTitle(language: language))
                        .font(.system(size: 11))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text("•")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button {
                if let url = JevLogger.logFileURL {
                    // 若文件尚未创建，先空写一行确保存在
                    if !FileManager.default.fileExists(atPath: url.path) {
                        JevLogger.log("[Jev] 日志系统初始化完成")
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                    Text(language == .english ? "Diagnostic Logs" : "查看诊断日志")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            if hasSavedKey {
                Button(role: .destructive) {
                    apiKeyInput = ""
                    onRemoveKey()
                    showToast(.info(SettingsJevDescriptor.toastKeyRemoved(language: language)))
                } label: {
                    Text(SettingsJevDescriptor.removeKeyTitle(language: language))
                }
                .controlSize(.small)
                .disabled(isVerifying)
            }

            Button {
                performSaveAndVerify()
            } label: {
                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Text(SettingsJevDescriptor.saveAndVerifyTitle(language: language))
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
        }
        .frame(height: SettingsViewLayoutMetrics.ignoredAppsButtonRowHeight)
    }

    /// 功能开关行
    private var toggleRow: some View {
        HStack(spacing: 12) {
            Text(SettingsJevDescriptor.enableRecommendationTitle(language: language))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            Toggle("", isOn: $isRecommendationEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!canEnableRecommendation)
        }
        .frame(height: SettingsViewLayoutMetrics.toggleRowHeight)
    }

    /// 辅助功能权限状态行
    private var accessibilityRow: some View {
        HStack(spacing: 10) {
            Text(SettingsJevDescriptor.contextPermissionTitle(language: language))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            Circle()
                .fill(isAccessibilityTrusted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(isAccessibilityTrusted
                ? SettingsJevDescriptor.contextPermissionGranted(language: language)
                : SettingsJevDescriptor.contextPermissionNotGranted(language: language)
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isAccessibilityTrusted ? Color.green : Color.secondary)

            Button {
                if isAccessibilityTrusted {
                    onOpenAccessibilitySettings()
                } else {
                    onRequestAccessibilityPermission()
                }
            } label: {
                Text(isAccessibilityTrusted
                    ? SettingsJevDescriptor.openSettingsTitle(language: language)
                    : SettingsJevDescriptor.grantPermissionTitle(language: language)
                )
            }
            .controlSize(.small)
        }
        .frame(height: SettingsViewLayoutMetrics.statusRowHeight)
    }

    /// 隐私说明行
    private var privacyNoticeRow: some View {
        Text(SettingsJevDescriptor.dataNotice(language: language))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    /// 用量与费用估算卡片
    private var usageSummaryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(SettingsJevDescriptor.usageSectionTitle(language: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let onClearUsage {
                    Button(role: .destructive) {
                        Task {
                            isClearingUsage = true
                            await onClearUsage()
                            await loadUsageSummary()
                            isClearingUsage = false
                            showToast(.info(SettingsJevDescriptor.toastUsageCleared(language: language)))
                        }
                    } label: {
                        Text(SettingsJevDescriptor.clearUsageTitle(language: language))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isClearingUsage)
                }
            }

            let summary = usageSummary ?? .zero

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsJevDescriptor.usageRequestsTitle(language: language))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(summary.successfulResponses)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tokens")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(SettingsJevDescriptor.usageInputTokensLabel(language: language)) \(summary.inputTokens) · \(SettingsJevDescriptor.usageOutputTokensLabel(language: language)) \(summary.outputTokens)")
                        .font(.system(size: 12, design: .monospaced))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(SettingsJevDescriptor.usageCostTitle(language: language))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(summary.formattedEstimatedCost)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)

            HStack(spacing: 8) {
                Text(SettingsJevDescriptor.usageDisclaimer(language: language))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Link(destination: SettingsJevDescriptor.officialUsageURL) {
                    HStack(spacing: 2) {
                        Text(SettingsJevDescriptor.officialUsageLinkTitle(language: language))
                            .font(.system(size: 10))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadUsageSummary() async {
        guard let onFetchUsageSummary else { return }
        let summary = await onFetchUsageSummary()
        await MainActor.run {
            self.usageSummary = summary
        }
    }

    /// 是否满足开启推荐的前提条件
    private var canEnableRecommendation: Bool {
        hasSavedKey && (status == .ready || status == .enabled)
    }

    /// 状态指示颜色
    private var statusColor: Color {
        switch status {
        case .enabled:
            return .green
        case .ready:
            return .blue
        case .verifying:
            return .orange
        case .notConfigured:
            return .secondary
        case .invalidKey, .permissionDenied, .modelUnavailable:
            return .red
        case .networkUnavailable:
            return .orange
        }
    }

    /// 执行保存并验证
    private func performSaveAndVerify() {
        let keyToVerify = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyToVerify.isEmpty else { return }

        isVerifying = true
        Task { @MainActor in
            let result = await onSaveAndVerify(keyToVerify)
            isVerifying = false
            lastValidationResult = result
            if result == .valid {
                apiKeyInput = ""
            }
            triggerToast(for: result)
        }
    }

    /// 根据验证结果触发对应 Toast
    private func triggerToast(for result: JevValidationResult) {
        switch result {
        case .valid:
            showToast(.success(SettingsJevDescriptor.toastVerifySuccess(language: language)))
        case .invalidKey:
            showToast(.error(SettingsJevDescriptor.toastInvalidKey(language: language)))
        case .permissionDenied:
            showToast(.error(SettingsJevDescriptor.toastPermissionDenied(language: language)))
        case .modelUnavailable:
            showToast(.warning(SettingsJevDescriptor.toastModelUnavailable(language: language)))
        case .networkUnavailable(let message):
            showToast(.network(SettingsJevDescriptor.toastNetworkUnavailable(language: language, message: message)))
        }
    }

    /// 显示 Toast 提示并在指定时长后自动淡出
    private func showToast(_ toast: JevToastMessage) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            self.activeToast = toast
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.activeToast = nil
            }
        }
    }

    /// Toast 提示气泡组件
    private func toastView(_ toast: JevToastMessage) -> some View {
        HStack(spacing: 7) {
            Image(systemName: toast.iconSystemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toast.iconColor)

            Text(toast.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThickMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 3)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        }
    }
}

/// Jev 设置面板内部 Toast 提示消息模型
struct JevToastMessage: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let iconSystemName: String
    let iconColor: Color

    static func success(_ message: String) -> JevToastMessage {
        JevToastMessage(message: message, iconSystemName: "checkmark.circle.fill", iconColor: .green)
    }

    static func error(_ message: String) -> JevToastMessage {
        JevToastMessage(message: message, iconSystemName: "xmark.circle.fill", iconColor: .red)
    }

    static func warning(_ message: String) -> JevToastMessage {
        JevToastMessage(message: message, iconSystemName: "exclamationmark.triangle.fill", iconColor: .orange)
    }

    static func network(_ message: String) -> JevToastMessage {
        JevToastMessage(message: message, iconSystemName: "wifi.exclamationmark", iconColor: .orange)
    }

    static func info(_ message: String) -> JevToastMessage {
        JevToastMessage(message: message, iconSystemName: "info.circle.fill", iconColor: .secondary)
    }
}
