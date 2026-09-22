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
                language: appDelegate.currentLanguage(),
                onSetLanguage: { language in
                    appDelegate.setLanguage(language)
                },
                hotKey: appDelegate.currentShowPanelHotKey(),
                onSetHotKey: { hotKey in
                    try appDelegate.setShowPanelHotKey(hotKey)
                },
                retentionPolicy: appDelegate.currentClipboardRetentionPolicy(),
                onSetRetentionPolicy: { policy in
                    appDelegate.setClipboardRetentionPolicy(policy)
                },
                ignoredApplications: appDelegate.currentIgnoredApplications(),
                isApplicationIgnoreEnabled: appDelegate.isApplicationIgnoreEnabled(),
                onSetApplicationIgnoreEnabled: { isEnabled in
                    appDelegate.setApplicationIgnoreEnabled(isEnabled)
                },
                onSetIgnoredApplications: { rules in
                    appDelegate.setIgnoredApplications(rules)
                },
                onClearHistory: {
                    appDelegate.clearHistoryFromSettings()
                },
                isExperimentalFeaturesEnabled: appDelegate.preferences.isExperimentalFeaturesEnabled,
                onSetExperimentalFeaturesEnabled: { isEnabled in
                    appDelegate.setExperimentalFeaturesEnabled(isEnabled)
                },
                hasSavedJevApiKey: appDelegate.hasSavedJevApiKey(),
                jevStatus: appDelegate.currentJevConfigurationStatus(),
                isJevRecommendationEnabled: appDelegate.isJevRecommendationEnabled(),
                onSetJevRecommendationEnabled: { isEnabled in
                    appDelegate.setJevRecommendationEnabled(isEnabled)
                },
                onSaveAndVerifyJevApiKey: { key in
                    await appDelegate.saveAndVerifyJevApiKey(key)
                },
                onRemoveJevApiKey: {
                    appDelegate.removeJevApiKey()
                },
                isAccessibilityTrusted: appDelegate.isAccessibilityTrusted(),
                onRequestAccessibilityPermission: {
                    appDelegate.requestAccessibilityPermission()
                },
                onOpenAccessibilitySettings: {
                    appDelegate.openAccessibilitySettings()
                },
                onFetchJevUsageSummary: {
                    (try? await appDelegate.jevUsageStore.currentMonthSummary(referenceDate: Date())) ?? .zero
                },
                onClearJevUsage: {
                    try? await appDelegate.jevUsageStore.clearAll()
                }
            )
        }
    }
}
