import AppKit
import QuartzCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.preview()

    private var preferences = AppPreferences()
    private let launchAtLoginManager: LaunchAtLoginManaging = SystemLaunchAtLoginManager()
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
        }
    )
    private let writebackService = ClipboardWritebackService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.setLanguage(preferences.language)
        configureServices()
    }

    func toggleHistoryPanel() {
        historyPanelController.toggle(
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
