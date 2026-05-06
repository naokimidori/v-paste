import AppKit
import SwiftUI

enum SettingsPanelDescriptor {
    static let title = "偏好设置"
    static let contentSize = CGSize(width: 520, height: 300)
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
    private let currentHotKey: () -> HotKeyPreference
    private let onSetHotKey: (HotKeyPreference) throws -> HotKeyPreference
    private let currentRetentionPolicy: () -> ClipboardRetentionPolicy
    private let onSetRetentionPolicy: (ClipboardRetentionPolicy) -> Void
    private let onClearHistory: () -> Void
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SettingsView>?

    init(
        appState: AppState,
        isLaunchAtLoginEnabled: @escaping () -> Bool,
        onSetLaunchAtLogin: @escaping (Bool) throws -> Bool,
        onSetMonitoringEnabled: @escaping (Bool) -> Void,
        currentHotKey: @escaping () -> HotKeyPreference,
        onSetHotKey: @escaping (HotKeyPreference) throws -> HotKeyPreference,
        currentRetentionPolicy: @escaping () -> ClipboardRetentionPolicy,
        onSetRetentionPolicy: @escaping (ClipboardRetentionPolicy) -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.appState = appState
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.onSetLaunchAtLogin = onSetLaunchAtLogin
        self.onSetMonitoringEnabled = onSetMonitoringEnabled
        self.currentHotKey = currentHotKey
        self.onSetHotKey = onSetHotKey
        self.currentRetentionPolicy = currentRetentionPolicy
        self.onSetRetentionPolicy = onSetRetentionPolicy
        self.onClearHistory = onClearHistory
        super.init()
    }

    func show() {
        let panel = makePanelIfNeeded()

        hostingController?.rootView = makeSettingsView()
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

        panel.title = SettingsPanelDescriptor.title
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
            hotKey: currentHotKey(),
            onSetHotKey: onSetHotKey,
            retentionPolicy: currentRetentionPolicy(),
            onSetRetentionPolicy: onSetRetentionPolicy,
            onClearHistory: onClearHistory
        )
    }
}
