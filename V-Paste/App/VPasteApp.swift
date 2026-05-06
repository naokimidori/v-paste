import SwiftUI

@main
struct VPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                appState: appDelegate.appState,
                isLaunchAtLoginEnabled: appDelegate.isLaunchAtLoginEnabled(),
                onSetLaunchAtLogin: { isEnabled in
                    try appDelegate.setLaunchAtLoginEnabled(isEnabled)
                },
                onSetMonitoringEnabled: { isEnabled in
                    appDelegate.setMonitoringEnabled(isEnabled)
                },
                hotKey: appDelegate.currentShowPanelHotKey(),
                onSetHotKey: { hotKey in
                    try appDelegate.setShowPanelHotKey(hotKey)
                },
                retentionPolicy: appDelegate.currentClipboardRetentionPolicy(),
                onSetRetentionPolicy: { policy in
                    appDelegate.setClipboardRetentionPolicy(policy)
                },
                onClearHistory: {
                    appDelegate.clearHistoryFromSettings()
                }
            )
        }
    }
}
