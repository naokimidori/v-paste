import AppKit
import SwiftUI

enum SettingsPanelDescriptor {
    static func title(language: AppLanguage) -> String {
        language == .english ? "Preferences" : "偏好设置"
    }

    static var title: String {
        title(language: .english)
    }

    static let contentSize = CGSize(width: 580, height: 380)
}

enum SettingsPanelPlacement {
    static func preferredFrame(contentSize: CGSize, screenFrame: NSRect) -> NSRect {
        let preferredY = screenFrame.maxY - screenFrame.height / 3 - contentSize.height / 2
        let clampedY = min(
            max(preferredY, screenFrame.minY),
            screenFrame.maxY - contentSize.height
        )

        return NSRect(
            x: screenFrame.midX - contentSize.width / 2,
            y: clampedY,
            width: contentSize.width,
            height: contentSize.height
        )
    }
}

@MainActor
final class SettingsPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let isLaunchAtLoginEnabled: () -> Bool
    private let onSetLaunchAtLogin: (Bool) throws -> Bool
    private let onSetMonitoringEnabled: (Bool) -> Void
    private let currentLanguage: () -> AppLanguage
    private let onSetLanguage: (AppLanguage) -> Void
    private let currentHotKey: () -> HotKeyPreference
    private let onSetHotKey: (HotKeyPreference) throws -> HotKeyPreference
    private let currentRetentionPolicy: () -> ClipboardRetentionPolicy
    private let onSetRetentionPolicy: (ClipboardRetentionPolicy) -> Void
    private let currentIgnoredApplications: () -> [IgnoredApplicationRule]
    private let isApplicationIgnoreEnabled: () -> Bool
    private let onSetApplicationIgnoreEnabled: (Bool) -> Void
    private let onSetIgnoredApplications: ([IgnoredApplicationRule]) -> Void
    private let onClearHistory: () -> Void
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SettingsView>?

    init(
        appState: AppState,
        isLaunchAtLoginEnabled: @escaping () -> Bool,
        onSetLaunchAtLogin: @escaping (Bool) throws -> Bool,
        onSetMonitoringEnabled: @escaping (Bool) -> Void,
        currentLanguage: @escaping () -> AppLanguage,
        onSetLanguage: @escaping (AppLanguage) -> Void,
        currentHotKey: @escaping () -> HotKeyPreference,
        onSetHotKey: @escaping (HotKeyPreference) throws -> HotKeyPreference,
        currentRetentionPolicy: @escaping () -> ClipboardRetentionPolicy,
        onSetRetentionPolicy: @escaping (ClipboardRetentionPolicy) -> Void,
        currentIgnoredApplications: @escaping () -> [IgnoredApplicationRule],
        isApplicationIgnoreEnabled: @escaping () -> Bool,
        onSetApplicationIgnoreEnabled: @escaping (Bool) -> Void,
        onSetIgnoredApplications: @escaping ([IgnoredApplicationRule]) -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.appState = appState
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.onSetMonitoringEnabled = onSetMonitoringEnabled
        self.currentLanguage = currentLanguage
        self.onSetLanguage = onSetLanguage
        self.currentHotKey = currentHotKey
        self.onSetHotKey = onSetHotKey
        self.currentRetentionPolicy = currentRetentionPolicy
        self.onSetRetentionPolicy = onSetRetentionPolicy
        self.currentIgnoredApplications = currentIgnoredApplications
        self.isApplicationIgnoreEnabled = isApplicationIgnoreEnabled
        self.onSetApplicationIgnoreEnabled = onSetApplicationIgnoreEnabled
        self.onSetIgnoredApplications = onSetIgnoredApplications
        self.onClearHistory = onClearHistory
        super.init()
    }

    func show() {
        let panel = makePanelIfNeeded()

        hostingController?.rootView = makeSettingsView()
        panel.title = SettingsPanelDescriptor.title(language: currentLanguage())
        centerPanelOnCurrentScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerPanelOnCurrentScreen(_ panel: NSPanel) {
        let screenFrame = screenContainingMouse()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.screen?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(origin: .zero, size: SettingsPanelDescriptor.contentSize)

        panel.setFrame(
            SettingsPanelPlacement.preferredFrame(
                contentSize: SettingsPanelDescriptor.contentSize,
                screenFrame: screenFrame
            ),
            display: false
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: SettingsPanelDescriptor.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let view = makeSettingsView()
        let hostingController = NSHostingController(rootView: view)

        panel.title = SettingsPanelDescriptor.title(language: currentLanguage())
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self

        self.hostingController = hostingController
        self.panel = panel
        return panel
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(
            appState: appState,
            isLaunchAtLoginEnabled: isLaunchAtLoginEnabled(),
            onSetLaunchAtLogin: onSetLaunchAtLogin,
            onSetMonitoringEnabled: onSetMonitoringEnabled,
            language: currentLanguage(),
            onSetLanguage: { [weak self] language in
                self?.onSetLanguage(language)
                self?.panel?.title = SettingsPanelDescriptor.title(language: language)
            },
            hotKey: currentHotKey(),
            onSetHotKey: onSetHotKey,
            retentionPolicy: currentRetentionPolicy(),
            onSetRetentionPolicy: onSetRetentionPolicy,
            ignoredApplications: currentIgnoredApplications(),
            isApplicationIgnoreEnabled: isApplicationIgnoreEnabled(),
            onSetApplicationIgnoreEnabled: onSetApplicationIgnoreEnabled,
            onSetIgnoredApplications: onSetIgnoredApplications,
            onClearHistory: onClearHistory
        )
    }
}
