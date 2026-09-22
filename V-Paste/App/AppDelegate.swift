import AppKit
import QuartzCore
import ServiceManagement
import SwiftUI

/// 线程安全的 JevUsageStore 容器，解耦 MainActor 隔离与后台 Sendable 闭包
final class JevUsageStoreBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _store: JevUsageStoring

    var store: JevUsageStoring {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _store
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _store = newValue
        }
    }

    init(_ store: JevUsageStoring) {
        self._store = store
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState = AppState.preview()

    var preferences = AppPreferences()
    private var launchAtLoginManager: LaunchAtLoginManaging = SystemLaunchAtLoginManager()
    private lazy var historyPanelController = HistoryPanelController(appState: appState)
    private lazy var copyToastController = CopyToastController()
    private var assetCache: AssetCache?
    private var store: ClipboardStore?
    private var linkMetadataFetcher: LinkMetadataFetcher?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKeyMonitor: GlobalHotKeyMonitor?
    private var menuBarController: MenuBarController?
    private lazy var settingsPanelController = SettingsPanelController(
        appState: appState,
        isLaunchAtLoginEnabled: { [weak self] in
            self?.launchAtLoginManager.isEnabled ?? false
        },
        onSetLaunchAtLogin: { [weak self] isEnabled in
            try self?.setLaunchAtLoginEnabled(isEnabled) ?? false
        },
        onSetMonitoringEnabled: { [weak self] isEnabled in
            self?.setMonitoringEnabled(isEnabled)
        },
        currentLanguage: { [weak self] in
            self?.preferences.language ?? .english
        },
        onSetLanguage: { [weak self] language in
            self?.setLanguage(language)
        },
        currentHotKey: { [weak self] in
            self?.preferences.showPanelHotKey ?? .defaultShowPanel
        },
        onSetHotKey: { [weak self] hotKey in
            try self?.setShowPanelHotKey(hotKey) ?? .defaultShowPanel
        },
        currentRetentionPolicy: { [weak self] in
            self?.preferences.clipboardRetentionPolicy ?? .thirtyDays
        },
        onSetRetentionPolicy: { [weak self] policy in
            self?.setClipboardRetentionPolicy(policy)
        },
        currentIgnoredApplications: { [weak self] in
            self?.preferences.ignoredApplications ?? IgnoredApplicationRule.defaultRules
        },
        isApplicationIgnoreEnabled: { [weak self] in
            self?.preferences.isApplicationIgnoreEnabled ?? true
        },
        onSetApplicationIgnoreEnabled: { [weak self] isEnabled in
            self?.setApplicationIgnoreEnabled(isEnabled)
        },
        onSetIgnoredApplications: { [weak self] rules in
            self?.setIgnoredApplications(rules)
        },
        onClearHistory: { [weak self] in
            self?.clearHistoryFromSettings()
        },
        isExperimentalFeaturesEnabled: { [weak self] in
            self?.preferences.isExperimentalFeaturesEnabled ?? false
        },
        onSetExperimentalFeaturesEnabled: { [weak self] isEnabled in
            self?.setExperimentalFeaturesEnabled(isEnabled)
        },
        hasSavedJevApiKey: { [weak self] in
            self?.hasSavedJevApiKey() ?? false
        },
        currentJevStatus: { [weak self] in
            self?.currentJevConfigurationStatus() ?? .notConfigured
        },
        isJevRecommendationEnabled: { [weak self] in
            self?.isJevRecommendationEnabled() ?? false
        },
        onSetJevRecommendationEnabled: { [weak self] isEnabled in
            self?.setJevRecommendationEnabled(isEnabled)
        },
        onSaveAndVerifyJevApiKey: { [weak self] key in
            await self?.saveAndVerifyJevApiKey(key) ?? .invalidKey
        },
        onRemoveJevApiKey: { [weak self] in
            self?.removeJevApiKey()
        },
        isAccessibilityTrusted: { [weak self] in
            self?.isAccessibilityTrusted() ?? false
        },
        onRequestAccessibilityPermission: { [weak self] in
            self?.requestAccessibilityPermission()
        },
        onOpenAccessibilitySettings: { [weak self] in
            self?.openAccessibilitySettings()
        },
        onFetchJevUsageSummary: { [weak self] in
            guard let self else { return .zero }
            return (try? await self.jevUsageStore.currentMonthSummary(referenceDate: Date())) ?? .zero
        },
        onClearJevUsage: { [weak self] in
            guard let self else { return }
            try? await self.jevUsageStore.clearAll()
        }
    )
    private let writebackService = ClipboardWritebackService()
    var jevCredentialStore: JevCredentialStoring = JevCredentialStore()
    var jevValidationClient: JevValidationClientProtocol = JevValidationClient()
    private let jevUsageStoreBox = JevUsageStoreBox(MockJevUsageStore())

    var jevUsageStore: JevUsageStoring {
        get { jevUsageStoreBox.store }
        set { jevUsageStoreBox.store = newValue }
    }
    var accessibilityPermissionService: AccessibilityPermissionServing = AccessibilityPermissionService()
    var destinationTracker: DestinationApplicationTracking = DestinationApplicationTracker()
    var destinationContextCapture: DestinationContextCapturing = DestinationContextCapture()
    lazy var recommendationService: JevRecommendationServiceProtocol = JevRecommendationService(
        credentialStore: jevCredentialStore,
        usageStoreProvider: { [box = jevUsageStoreBox] in box.store },
        isEnabledProvider: { [jevCredentialStore] in
            UserDefaults.standard.bool(forKey: "settings.experimentalFeaturesEnabled")
                && UserDefaults.standard.bool(forKey: "settings.isJevRecommendationEnabled")
                && jevCredentialStore.hasApiKey()
        },
        onAuthError: { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleJevAuthError(error)
            }
        }
    )
    private var lastJevValidationStatus: JevConfigurationStatus?

    override init() {
        super.init()
    }

    init(
        appState: AppState? = nil,
        preferences: AppPreferences = AppPreferences(),
        launchAtLoginManager: LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
        jevCredentialStore: JevCredentialStoring = JevCredentialStore(),
        jevValidationClient: JevValidationClientProtocol = JevValidationClient(),
        jevUsageStore: JevUsageStoring? = nil,
        accessibilityPermissionService: AccessibilityPermissionServing = AccessibilityPermissionService(),
        destinationTracker: DestinationApplicationTracking = DestinationApplicationTracker(),
        destinationContextCapture: DestinationContextCapturing = DestinationContextCapture(),
        recommendationService: JevRecommendationServiceProtocol? = nil
    ) {
        self.appState = appState ?? AppState.preview()
        self.preferences = preferences
        self.launchAtLoginManager = launchAtLoginManager
        self.jevCredentialStore = jevCredentialStore
        self.jevValidationClient = jevValidationClient
        super.init()
        if let jevUsageStore {
            self.jevUsageStore = jevUsageStore
        }
        self.accessibilityPermissionService = accessibilityPermissionService
        self.destinationTracker = destinationTracker
        self.destinationContextCapture = destinationContextCapture
        if let recommendationService {
            self.recommendationService = recommendationService
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.setLanguage(preferences.language)
        configureJevInitialState()
        configureServices()
        configureJevRecommendationLifecycle()
    }

    func toggleHistoryPanel() {
        if appState.isPanelVisible {
            historyPanelController.hide()
            return
        }

        // 1. 在面板激活前（NSApp.activate 之前）捕获目标前台应用与输入框无障碍上下文
        let target = destinationTracker.resolveTarget(frontmost: NSWorkspace.shared.frontmostApplication)
        let capturedContext = target.flatMap { destinationContextCapture.captureBeforeActivation(for: $0) }

        // 2. 显示面板
        showHistoryPanel()

        // 3. 发起 Jev 智能推荐
        let isEnabled = isJevRecommendationEnabled()
        let effectiveContext = capturedContext ?? DestinationContext.applicationOnly(
            applicationName: target?.applicationName ?? "General",
            bundleIdentifier: target?.bundleIdentifier,
            processIdentifier: target?.processIdentifier ?? 0
        )

        if isEnabled {
            JevLogger.log("[Jev] 呼出历史面板，触发推荐: 目标应用=\(effectiveContext.applicationName)")
            let currentItems = appState.panelViewModel.allItems
            let isIgnoreEnabled = preferences.isApplicationIgnoreEnabled
            let ignoredRules = preferences.ignoredApplications
            let ignoredBundleIDs: Set<String> = isIgnoreEnabled ? Set(ignoredRules.map { $0.bundleIdentifier }) : []

            recommendationService.requestRecommendation(
                destination: effectiveContext,
                currentItems: currentItems,
                ignoredBundleIDs: ignoredBundleIDs
            ) { [weak self] state in
                Task { @MainActor in
                    guard let self, self.appState.isPanelVisible else {
                        JevLogger.log("[Jev] 收到结果但面板已关闭或实例已释放，丢弃结果")
                        return
                    }
                    switch state {
                    case .ready(let itemID):
                        JevLogger.log("[Jev] 推荐生效，应用卡片置顶")
                        self.appState.panelViewModel.applyRecommendation(recommendedItemID: itemID)
                    case .abstained:
                        JevLogger.log("[Jev] 决策结果: 弃权（保持原有历史顺序）")
                    case .unavailable:
                        JevLogger.log("[Jev] 决策结果: 服务暂不可用或超时")
                    case .inactive:
                        JevLogger.log("[Jev] 决策结果: 未激活")
                    case .loading:
                        JevLogger.log("[Jev] 决策正在进行中...")
                    }
                }
            }
        } else {
            JevLogger.log("[Jev] Jev 推荐未启用或未配置可用 API Key，跳过推荐")
        }
    }

    private func showHistoryPanel() {
        historyPanelController.show(
            onCopy: { [weak self] item in
                if self?.copyToPasteboard(item) == true {
                    self?.copyToastController.show()
                }
            },
            onToggleFavorite: { [weak self] item in
                self?.toggleFavorite(item)
            },
            onCreateGroup: { [weak self] in
                guard let self else { return nil }

                return self.createGroup()
            },
            onSelectGroup: { [weak self] groupID in
                self?.selectGroup(groupID)
            },
            onUpdateGroup: { [weak self] group in
                self?.updateGroup(group)
            },
            onAssignItemToGroup: { [weak self] itemID, groupID in
                self?.assignItem(itemID: itemID, to: groupID)
            },
            onDeleteGroup: { [weak self] groupID in
                self?.deleteGroup(groupID)
            },
            onDeleteItem: { [weak self] item in
                self?.deleteItem(item)
            },
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onOpenAbout: { [weak self] in
                self?.openAbout()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }

    private func configureJevRecommendationLifecycle() {
        // 监听前台应用激活，供目标应用追踪服务记录
        let tracker = destinationTracker
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            tracker.recordActiveApplication(app)
        }

        // 面板关闭时，清理推荐会话与临时推荐状态
        historyPanelController.onDismiss = { [weak self] in
            self?.recommendationService.cancelCurrentSession()
            self?.appState.panelViewModel.clearRecommendation()
        }

        // 用户在面板内发生交互（按键、搜索、切换筛选等），通知推荐服务锁定防抢占
        appState.panelViewModel.onUserInteraction = { [weak self] in
            self?.recommendationService.notifyUserInteracted()
        }
    }

    private func configureServices() {
        do {
            let paths = try AppPaths.make(
                fileManager: .default,
                bundleID: Bundle.main.bundleIdentifier ?? "io.vpaste.app"
            )
            let store = try ClipboardStore(paths: paths)
            let assetCache = AssetCache(
                assetsDirectoryURL: paths.assetsDirectoryURL,
                thumbnailsDirectoryURL: paths.thumbnailsDirectoryURL
            )
            let normalizer = ClipboardNormalizer(assetCache: assetCache)
            let monitor = ClipboardMonitor(
                pasteboard: .general,
                now: Date.init,
                isSourceApplicationIgnored: { [weak self] sourceApplication in
                    self?.isSourceApplicationIgnored(sourceApplication) ?? false
                }
            ) { pasteboard, copiedAt, sourceApplication in
                try normalizer.normalize(
                    pasteboard: pasteboard,
                    copiedAt: copiedAt,
                    sourceApplication: sourceApplication
                )
            }

            self.store = store
            self.assetCache = assetCache
            self.linkMetadataFetcher = LinkMetadataFetcher(assetCache: assetCache)
            let usageDatabaseURL = paths.appSupportDirectoryURL.appendingPathComponent("jev_usage.sqlite3")
            if !(self.jevUsageStore is SQLiteJevUsageStore) {
                if let store = try? SQLiteJevUsageStore(databaseURL: usageDatabaseURL) {
                    self.jevUsageStore = store
                }
            }
            configureMenuBar()
            configureHotKey()
            loadHistory(from: store)
            configureClipboardMonitor(monitor, store: store)
            monitor.start()
        } catch {
            NSLog("V-Paste failed to configure services: \(String(describing: error))")
            configureMenuBar()
        }
    }

    private func configureMenuBar() {
        let menuBarController = MenuBarController(
            onTogglePanel: { [weak self] in
                self?.toggleHistoryPanel()
            },
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onOpenAbout: { [weak self] in
                self?.openAbout()
            }
        )
        menuBarController.rebuildMenu(
            isMonitoringPaused: appState.isMonitoringPaused,
            language: preferences.language,
            shortcut: preferences.showPanelHotKey
        )
        self.menuBarController = menuBarController
    }

    private func configureHotKey() {
        let hotKeyMonitor = makeHotKeyMonitor()

        do {
            try hotKeyMonitor.register(preferences.showPanelHotKey)
            self.hotKeyMonitor = hotKeyMonitor
        } catch {
            NSLog("V-Paste failed to register Option+~ hotkey: \(String(describing: error))")
        }
    }

    private func makeHotKeyMonitor() -> GlobalHotKeyMonitor {
        GlobalHotKeyMonitor { [weak self] in
            Task { @MainActor in
                self?.toggleHistoryPanel()
            }
        }
    }

    private func loadHistory(from store: ClipboardStore) {
        do {
            try deleteExpiredHistory(
                from: store,
                retentionPolicy: preferences.clipboardRetentionPolicy
            )
            appState.loadGroups(try store.fetchGroups())
            appState.loadItems(try store.fetchRecent(limit: 200))
        } catch {
            NSLog("V-Paste failed to load clipboard history: \(String(describing: error))")
        }
    }

    private func deleteExpiredHistory(
        from store: ClipboardStore,
        retentionPolicy: ClipboardRetentionPolicy
    ) throws {
        guard let cutoff = retentionPolicy.cutoff(now: Date()) else { return }

        let expiredAssetPaths = try store.assetPathsForItems(olderThan: cutoff)
        try store.deleteItems(olderThan: cutoff)
        do {
            try assetCache?.deleteCachedFiles(at: expiredAssetPaths)
        } catch {
            NSLog("V-Paste failed to delete expired cached assets: \(String(describing: error))")
        }
    }

    private func configureClipboardMonitor(
        _ monitor: ClipboardMonitor,
        store: ClipboardStore
    ) {
        monitor.onItem = { [weak self] item in
            guard let self else { return }
            let item = item.groupID == nil
                ? (appState.activeGroupID.map { item.withGroup($0) } ?? item)
                : item

            do {
                try store.upsert(item)
            } catch {
                NSLog("V-Paste failed to persist clipboard item: \(String(describing: error))")
            }
            appState.ingest(item)
            enrichLinkPreviewIfNeeded(for: item, store: store)
        }
        monitor.onError = { error in
            NSLog("V-Paste failed to normalize clipboard item: \(String(describing: error))")
        }
        clipboardMonitor = monitor
    }

    private func enrichLinkPreviewIfNeeded(
        for item: ClipboardItem,
        store: ClipboardStore
    ) {
        guard
            item.contentType == .text,
            let urlString = item.urlString,
            let url = URL(string: urlString),
            ["http", "https"].contains(url.scheme?.lowercased()),
            let linkMetadataFetcher
        else {
            return
        }

        Task { [weak self] in
            do {
                guard let preview = try await linkMetadataFetcher.preview(for: url, itemID: item.id),
                      let self,
                      let updatedItem = self.appState.updateLinkPreview(
                        sourceHash: item.sourceHash,
                        title: preview.title,
                        assetPath: preview.assetPath,
                        thumbnailPath: preview.thumbnailPath
                      )
                else {
                    return
                }

                try store.upsert(updatedItem)
            } catch {
                NSLog("V-Paste failed to fetch link preview: \(String(describing: error))")
            }
        }
    }

    private func toggleMonitoring() {
        setMonitoringEnabled(appState.isMonitoringPaused)
    }

    func setMonitoringEnabled(_ isEnabled: Bool) {
        let currentlyEnabled = !appState.isMonitoringPaused
        guard currentlyEnabled != isEnabled else { return }

        if isEnabled {
            appState.resumeMonitoring()
            clipboardMonitor?.start()
        } else {
            appState.pauseMonitoring()
            clipboardMonitor?.stop()
        }
        menuBarController?.rebuildMenu(
            isMonitoringPaused: appState.isMonitoringPaused,
            language: preferences.language,
            shortcut: preferences.showPanelHotKey
        )
    }

    func isLaunchAtLoginEnabled() -> Bool {
        launchAtLoginManager.isEnabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws -> Bool {
        try launchAtLoginManager.setEnabled(isEnabled)
    }

    func currentShowPanelHotKey() -> HotKeyPreference {
        preferences.showPanelHotKey
    }

    func currentLanguage() -> AppLanguage {
        preferences.language
    }

    func setLanguage(_ language: AppLanguage) {
        preferences.language = language
        appState.setLanguage(language)
        menuBarController?.rebuildMenu(
            isMonitoringPaused: appState.isMonitoringPaused,
            language: language,
            shortcut: preferences.showPanelHotKey
        )
    }

    func setShowPanelHotKey(_ hotKey: HotKeyPreference) throws -> HotKeyPreference {
        let previousHotKey = preferences.showPanelHotKey
        let monitor = hotKeyMonitor ?? makeHotKeyMonitor()

        do {
            try monitor.register(hotKey)
            hotKeyMonitor = monitor
            preferences.showPanelHotKey = hotKey
            menuBarController?.rebuildMenu(
                isMonitoringPaused: appState.isMonitoringPaused,
                language: preferences.language,
                shortcut: hotKey
            )
            return hotKey
        } catch {
            try? monitor.register(previousHotKey)
            throw error
        }
    }

    func currentClipboardRetentionPolicy() -> ClipboardRetentionPolicy {
        preferences.clipboardRetentionPolicy
    }

    func currentIgnoredApplications() -> [IgnoredApplicationRule] {
        preferences.ignoredApplications
    }

    func isApplicationIgnoreEnabled() -> Bool {
        preferences.isApplicationIgnoreEnabled
    }

    func setApplicationIgnoreEnabled(_ isEnabled: Bool) {
        preferences.isApplicationIgnoreEnabled = isEnabled
    }

    func setIgnoredApplications(_ rules: [IgnoredApplicationRule]) {
        preferences.ignoredApplications = rules
    }

    private func isSourceApplicationIgnored(_ sourceApplication: ClipboardSourceApplication?) -> Bool {
        IgnoredApplicationRule.isIgnored(
            sourceApplication,
            rules: preferences.ignoredApplications,
            isEnabled: preferences.isApplicationIgnoreEnabled
        )
    }

    func setClipboardRetentionPolicy(_ policy: ClipboardRetentionPolicy) {
        preferences.clipboardRetentionPolicy = policy

        guard let store else { return }
        do {
            try deleteExpiredHistory(from: store, retentionPolicy: policy)
            appState.loadItems(try store.fetchRecent(limit: 200))
        } catch {
            NSLog("V-Paste failed to apply clipboard retention policy: \(String(describing: error))")
        }
    }

    // MARK: - Jev 设置与凭据管理

    func configureJevInitialState() {
        let isExperimental = preferences.isExperimentalFeaturesEnabled
        appState.setExperimentalFeaturesEnabled(isExperimental)

        // 启动自愈：若实验功能未开启，强制重置 Jev 开关为 false
        if !isExperimental && preferences.isJevRecommendationEnabled {
            preferences.isJevRecommendationEnabled = false
        }

        let hasKey = hasSavedJevApiKey()
        if !hasKey && preferences.isJevRecommendationEnabled {
            // 自愈：若未配置 API Key 但开关为 true，自动修正并关闭开关
            preferences.isJevRecommendationEnabled = false
        }

        // 启动自愈：若之前记录了鉴权失败（401/403），跨重启保持开关关闭并恢复错误状态
        if let requirement = preferences.jevAuthRequirement {
            preferences.isJevRecommendationEnabled = false
            let status: JevConfigurationStatus = (requirement == "permissionDenied") ? .permissionDenied : .invalidKey
            lastJevValidationStatus = status
            appState.setJevConfigurationStatus(status)
        } else {
            let status: JevConfigurationStatus = hasKey
                ? (preferences.isJevRecommendationEnabled ? .enabled : .ready)
                : .notConfigured
            lastJevValidationStatus = status
            appState.setJevConfigurationStatus(status)
        }

        appState.setHasSavedJevApiKey(hasKey)
        appState.setIsAccessibilityTrusted(isAccessibilityTrusted())
        appState.setJevRecommendationEnabled(preferences.isJevRecommendationEnabled)
    }

    func setExperimentalFeaturesEnabled(_ isEnabled: Bool) {
        preferences.isExperimentalFeaturesEnabled = isEnabled
        appState.setExperimentalFeaturesEnabled(isEnabled)
        if !isEnabled {
            // 关闭实验功能时，必须同时关闭 Jev 推荐、取消在途请求并清除面板推荐卡，但不删除 Keychain 中的 API Key
            setJevRecommendationEnabled(false)
            recommendationService.cancelCurrentSession()
            appState.panelViewModel.clearRecommendation()
        }
    }

    func hasSavedJevApiKey() -> Bool {
        guard let key = try? jevCredentialStore.readApiKey(), !key.isEmpty else {
            return false
        }
        return true
    }

    func currentJevConfigurationStatus() -> JevConfigurationStatus {
        guard hasSavedJevApiKey() else {
            return .notConfigured
        }
        if let requirement = preferences.jevAuthRequirement {
            return (requirement == "permissionDenied") ? .permissionDenied : .invalidKey
        }
        if let lastJevValidationStatus {
            return lastJevValidationStatus
        }
        return preferences.isJevRecommendationEnabled ? .enabled : .ready
    }

    func isJevRecommendationEnabled() -> Bool {
        preferences.isExperimentalFeaturesEnabled &&
        preferences.isJevRecommendationEnabled &&
        hasSavedJevApiKey() &&
        preferences.jevAuthRequirement == nil
    }

    func setJevRecommendationEnabled(_ isEnabled: Bool) {
        // 门槛校验：仅在已保存 Key 且不存在未解决的鉴权失败状态时允许开启
        guard !isEnabled || (hasSavedJevApiKey() && preferences.jevAuthRequirement == nil) else {
            preferences.isJevRecommendationEnabled = false
            appState.setJevRecommendationEnabled(false)
            return
        }

        preferences.isJevRecommendationEnabled = isEnabled
        appState.setJevRecommendationEnabled(isEnabled)

        // 若为关闭推荐，不应覆盖已有的鉴权失败状态（避免把失效 Key 重置为 ready）
        if !isEnabled {
            if preferences.jevAuthRequirement != nil {
                return
            }
            let newStatus: JevConfigurationStatus = .ready
            lastJevValidationStatus = newStatus
            appState.setJevConfigurationStatus(newStatus)
        } else {
            let newStatus: JevConfigurationStatus = .enabled
            lastJevValidationStatus = newStatus
            appState.setJevConfigurationStatus(newStatus)
        }
    }

    func saveAndVerifyJevApiKey(_ key: String) async -> JevValidationResult {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .invalidKey
        }

        let result = await jevValidationClient.validateKey(trimmedKey)
        let status: JevConfigurationStatus
        switch result {
        case .valid:
            status = preferences.isJevRecommendationEnabled ? .enabled : .ready
        case .invalidKey:
            status = .invalidKey
        case .permissionDenied:
            status = .permissionDenied
        case .modelUnavailable:
            status = .modelUnavailable
        case .networkUnavailable(let message):
            status = .networkUnavailable(message)
        }

        if result == .valid {
            // 验证成功，清除鉴权失败持久化标记
            preferences.jevAuthRequirement = nil
            do {
                try jevCredentialStore.saveApiKey(trimmedKey)
                lastJevValidationStatus = status
                appState.setHasSavedJevApiKey(true)
                appState.setJevConfigurationStatus(status)
            } catch {
                NSLog("V-Paste 保存 Jev API Key 到 Keychain 失败: \(String(describing: error))")
                let failureResult = JevValidationResult.networkUnavailable(message: "Keychain storage failed")
                lastJevValidationStatus = .networkUnavailable("Keychain storage failed")
                appState.setHasSavedJevApiKey(false)
                appState.setJevConfigurationStatus(.networkUnavailable("Keychain storage failed"))
                return failureResult
            }
        } else {
            if result == .invalidKey {
                preferences.jevAuthRequirement = "invalidKey"
            } else if result == .permissionDenied {
                preferences.jevAuthRequirement = "permissionDenied"
            }
            lastJevValidationStatus = status
            appState.setJevConfigurationStatus(status)
            if status == .invalidKey || status == .permissionDenied {
                // 若凭据明确无效或被拒绝访问，关闭推荐开关
                preferences.isJevRecommendationEnabled = false
                appState.setJevRecommendationEnabled(false)
            }
        }
        return result
    }

    /// 处理运行时鉴权错误（401/403），关闭推荐开关并同步设置视图状态，保留现有 Key 便于用户查看和修改
    @MainActor
    func handleJevAuthError(_ error: JevDecisionError) {
        let status: JevConfigurationStatus
        let requirementKey: String
        switch error {
        case .invalidAPIKey:
            status = .invalidKey
            requirementKey = "invalidKey"
        case .permissionDenied:
            status = .permissionDenied
            requirementKey = "permissionDenied"
        default:
            return
        }

        // 持久化记录鉴权失败状态，跨应用重启与实验功能开关保持
        preferences.jevAuthRequirement = requirementKey
        preferences.isJevRecommendationEnabled = false
        appState.setJevRecommendationEnabled(false)
        lastJevValidationStatus = status
        appState.setJevConfigurationStatus(status)
        recommendationService.cancelCurrentSession()
        appState.panelViewModel.clearRecommendation()
    }

    func removeJevApiKey() {
        // 取消当前在途推荐会话并清除面板临时卡片
        recommendationService.cancelCurrentSession()
        appState.panelViewModel.clearRecommendation()

        // 清除持久化的鉴权失败状态
        preferences.jevAuthRequirement = nil

        do {
            try jevCredentialStore.deleteApiKey()
        } catch {
            NSLog("V-Paste 删除 Jev API Key 失败: \(String(describing: error))")
        }
        appState.setHasSavedJevApiKey(false)
        preferences.isJevRecommendationEnabled = false
        appState.setJevRecommendationEnabled(false)
        lastJevValidationStatus = .notConfigured
        appState.setJevConfigurationStatus(.notConfigured)
    }

    // MARK: - 辅助功能权限

    func isAccessibilityTrusted() -> Bool {
        accessibilityPermissionService.isTrusted
    }

    func requestAccessibilityPermission() {
        _ = accessibilityPermissionService.requestPermission()
    }

    func openAccessibilitySettings() {
        accessibilityPermissionService.openAccessibilitySettings()
    }

    private func openPreferences() {
        settingsPanelController.show()
    }

    private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(
            options: MenuBarAboutDescriptor.standardPanelOptions()
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private func clearHistory() {
        do {
            try store?.deleteAll()
        } catch {
            NSLog("V-Paste failed to clear clipboard history: \(String(describing: error))")
            return
        }

        do {
            try assetCache?.deleteAllAssets()
        } catch {
            NSLog("V-Paste failed to clear cached clipboard assets: \(String(describing: error))")
        }

        appState.clearHistory()
    }

    func clearHistoryFromSettings() {
        clearHistory()
    }

    @discardableResult
    private func copyToPasteboard(_ item: ClipboardItem) -> Bool {
        do {
            try writebackService.write(item: item)
            return true
        } catch {
            NSLog("V-Paste failed to write clipboard item: \(String(describing: error))")
            return false
        }
    }

    private func toggleFavorite(_ item: ClipboardItem) {
        guard let updatedItem = appState.toggleFavorite(for: item.id) else {
            return
        }

        do {
            try store?.setFavorite(
                id: updatedItem.id,
                isFavorited: updatedItem.isFavorited
            )
        } catch {
            NSLog("V-Paste failed to update favorite state: \(String(describing: error))")
        }
    }

    @discardableResult
    private func createGroup() -> ClipboardGroup? {
        do {
            guard let store else {
                return appState.createGroup()
            }

            let colorHex = ClipboardGroupColorPalette.firstUnusedColor(
                usedColorHexes: appState.groups.map(\.colorHex)
            )
            let group = try store.createGroup(
                name: ClipboardGroup.defaultName(language: preferences.language),
                colorHex: colorHex
            )
            appState.loadGroups(try store.fetchGroups())
            appState.setActiveGroup(group.id)
            return group
        } catch {
            NSLog("V-Paste failed to create clipboard group: \(String(describing: error))")
            return nil
        }
    }

    private func selectGroup(_ groupID: ClipboardGroup.ID?) {
        appState.setActiveGroup(groupID)
    }

    private func updateGroup(_ group: ClipboardGroup) {
        do {
            try store?.updateGroup(group)
            appState.updateGroup(group)
        } catch {
            NSLog("V-Paste failed to update clipboard group: \(String(describing: error))")
        }
    }

    private func assignItem(
        itemID: ClipboardItem.ID,
        to groupID: ClipboardGroup.ID
    ) {
        do {
            try store?.assignItem(id: itemID, to: groupID)
            appState.assignItem(id: itemID, to: groupID)
        } catch {
            NSLog("V-Paste failed to assign clipboard item to group: \(String(describing: error))")
        }
    }

    private func deleteGroup(_ groupID: ClipboardGroup.ID) {
        do {
            try store?.deleteGroup(id: groupID)
            appState.deleteGroup(id: groupID)
        } catch {
            NSLog("V-Paste failed to delete clipboard group: \(String(describing: error))")
        }
    }

    private func deleteItem(_ item: ClipboardItem) {
        do {
            let assetPaths = try store?.assetPaths(for: item.id) ?? []
            try store?.deleteItem(id: item.id)
            appState.deleteItem(id: item.id)
            do {
                try assetCache?.deleteCachedFiles(at: assetPaths)
            } catch {
                NSLog("V-Paste failed to delete cached item assets: \(String(describing: error))")
            }
        } catch {
            NSLog("V-Paste failed to delete clipboard item: \(String(describing: error))")
        }
    }
}

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) throws -> Bool
}

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) throws -> Bool {
        if isEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }

        return self.isEnabled
    }
}

enum CopyToastLayout {
    static let size = CGSize(width: 96, height: 32)
    static let bottomInset: CGFloat = 88
    static let contentPadding: CGFloat = 8
    static let hiddenOffset: CGFloat = -10
    static let windowLevel = NSWindow.Level(rawValue: HistoryPanelLayout.windowLevel.rawValue + 1)

    static func frame(screenFrame: NSRect) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + bottomInset,
            width: size.width,
            height: size.height
        )
    }
}

enum CopyToastContent {
    static let iconSystemName = "checkmark"
    static let message = "Copied"
}

@MainActor
final class CopyToastController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<CopyToastView>?
    private var presentationGeneration = 0

    func show() {
        guard let screen = activeScreen() else { return }

        presentationGeneration += 1
        let generation = presentationGeneration
        let panel = makePanelIfNeeded()
        let visibleFrame = CopyToastLayout.frame(screenFrame: screen.frame)
        let hiddenFrame = visibleFrame.offsetBy(dx: 0, dy: CopyToastLayout.hiddenOffset)

        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(visibleFrame, display: true)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard self.presentationGeneration == generation else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(hiddenFrame, display: true)
            } completionHandler: {
                Task { @MainActor in
                    guard self.presentationGeneration == generation else { return }

                    panel.orderOut(nil)
                }
            }
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let view = CopyToastView()
        let hostingController = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.level = CopyToastLayout.windowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]

        self.hostingController = hostingController
        self.panel = panel
        return panel
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

struct CopyToastView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: CopyToastContent.iconSystemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(CopyToastContent.message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(CopyToastLayout.contentPadding)
        .frame(width: CopyToastLayout.size.width, height: CopyToastLayout.size.height)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .fill(backgroundScrim)
                }
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 1)
        }
    }

    private var backgroundScrim: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.46)
            : Color.black.opacity(0.24)
    }
}
