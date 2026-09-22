import XCTest
@testable import V_Paste

@MainActor
final class JevSettingsStateTests: XCTestCase {
    private var appState: AppState!
    private var mockCredentialStore: MockJevCredentialStore!
    private var mockValidationClient: MockJevValidationClient!
    private var mockAccessibilityService: MockAccessibilityPermissionService!
    private var testUserDefaults: UserDefaults!
    private var preferences: AppPreferences!
    private var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appState = AppState.preview()
        mockCredentialStore = MockJevCredentialStore()
        mockValidationClient = MockJevValidationClient(resultToReturn: .valid)
        mockAccessibilityService = MockAccessibilityPermissionService(isTrusted: true)

        let suiteName = "test.vpaste.jev.settings.\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: suiteName)!
        preferences = AppPreferences(userDefaults: testUserDefaults)

        appDelegate = AppDelegate(
            appState: appState,
            preferences: preferences,
            jevCredentialStore: mockCredentialStore,
            jevValidationClient: mockValidationClient,
            accessibilityPermissionService: mockAccessibilityService
        )
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: testUserDefaults.description)
        appDelegate = nil
        preferences = nil
        testUserDefaults = nil
        mockAccessibilityService = nil
        mockValidationClient = nil
        mockCredentialStore = nil
        appState = nil
        super.tearDown()
    }

    func testInitialStateAutoHealingWhenNoKeySaved() {
        // 模拟外部异常情况：UserDefaults 开关为 true，但 Keychain 中无 Key
        preferences.isExperimentalFeaturesEnabled = true
        preferences.isJevRecommendationEnabled = true

        appDelegate.configureJevInitialState()

        // 验证自愈机制：开关被关闭，状态为 notConfigured
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .notConfigured)
        XCTAssertEqual(appState.jevConfigurationStatus, .notConfigured)
    }

    func testInitialStateAutoHealingWhenExperimentalFeaturesDisabled() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        // 模拟外部异常：未开启实验功能，但 Jev 开关持久化为 true
        preferences.isExperimentalFeaturesEnabled = false
        preferences.isJevRecommendationEnabled = true

        appDelegate.configureJevInitialState()

        // 启动自愈：Jev 开关必须强制关闭
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
    }

    func testInitialStatePreservesEnabledWhenKeyExists() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        preferences.isExperimentalFeaturesEnabled = true
        preferences.isJevRecommendationEnabled = true

        appDelegate.configureJevInitialState()

        XCTAssertTrue(appDelegate.isJevRecommendationEnabled())
        XCTAssertTrue(preferences.isJevRecommendationEnabled)
        XCTAssertTrue(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .enabled)
    }

    func testCannotEnableRecommendationWithoutSavedKey() {
        appDelegate.setExperimentalFeaturesEnabled(true)
        // 无 Key 时尝试开启
        appDelegate.setJevRecommendationEnabled(true)

        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
    }

    func testCanEnableRecommendationWithSavedKey() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)

        appDelegate.setJevRecommendationEnabled(true)

        XCTAssertTrue(appDelegate.isJevRecommendationEnabled())
        XCTAssertTrue(preferences.isJevRecommendationEnabled)
        XCTAssertTrue(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .enabled)

        // 可以手动关闭，关闭后状态变为 ready
        appDelegate.setJevRecommendationEnabled(false)
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .ready)
    }

    func testExperimentalFeaturesGateControlsTabVisibility() {
        // 默认关闭实验功能时，不包含 Jev 标签
        let defaultTabs = SettingsTabDescriptor.visibleTabs(language: .english, isExperimentalEnabled: false)
        XCTAssertFalse(defaultTabs.contains { $0.id == .jev })
        XCTAssertEqual(defaultTabs.map(\.id), [.general, .ignoredApplications, .about])

        // 开启实验功能后，在通用和应用忽略之间包含 Jev 标签
        let experimentalTabs = SettingsTabDescriptor.visibleTabs(language: .english, isExperimentalEnabled: true)
        XCTAssertTrue(experimentalTabs.contains { $0.id == .jev })
        XCTAssertEqual(experimentalTabs.map(\.id), [.general, .jev, .ignoredApplications, .about])
    }

    func testDisablingExperimentalFeaturesDisablesJevRecommendation() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)
        XCTAssertTrue(appDelegate.isJevRecommendationEnabled())

        // 关闭实验功能：Jev 开关立即关闭并联动停用
        appDelegate.setExperimentalFeaturesEnabled(false)
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(appState.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isExperimentalFeaturesEnabled)
        // 但保留 Keychain 中的 Key
        XCTAssertTrue(appDelegate.hasSavedJevApiKey())
    }

    func testSaveAndVerifyJevApiKeySuccess() async throws {
        appDelegate.setExperimentalFeaturesEnabled(true)
        mockValidationClient.resultToReturn = .valid

        let status = await appDelegate.saveAndVerifyJevApiKey("my-new-key")

        XCTAssertEqual(status, .valid)
        XCTAssertEqual(try mockCredentialStore.readApiKey(), "my-new-key")
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .ready)
        XCTAssertEqual(appState.jevConfigurationStatus, .ready)
    }

    func testSaveAndVerifyJevApiKeyFailureInvalidKey() async throws {
        mockValidationClient.resultToReturn = .invalidKey

        let status = await appDelegate.saveAndVerifyJevApiKey("bad-key")

        XCTAssertEqual(status, .invalidKey)
        // 未成功保存到 Keychain
        XCTAssertNil(try mockCredentialStore.readApiKey())
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .notConfigured)
    }

    func testSaveAndVerifyJevApiKeyPermissionDeniedDisablesRecommendation() async throws {
        try mockCredentialStore.saveApiKey("existing-key")
        preferences.isJevRecommendationEnabled = true
        appState.setJevRecommendationEnabled(true)

        mockValidationClient.resultToReturn = .permissionDenied

        let status = await appDelegate.saveAndVerifyJevApiKey("no-perm-key")

        XCTAssertEqual(status, .permissionDenied)
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
    }

    func testRemoveJevApiKey() throws {
        try mockCredentialStore.saveApiKey("key-to-remove")
        preferences.isJevRecommendationEnabled = true
        appState.setJevRecommendationEnabled(true)

        appDelegate.removeJevApiKey()

        XCTAssertFalse(appDelegate.hasSavedJevApiKey())
        XCTAssertNil(try mockCredentialStore.readApiKey())
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .notConfigured)
        XCTAssertEqual(appState.jevConfigurationStatus, .notConfigured)
    }

    func testJevConfigurationStatusDisplayTitles() {
        let statuses: [JevConfigurationStatus] = [
            .notConfigured,
            .verifying,
            .ready,
            .enabled,
            .invalidKey,
            .permissionDenied,
            .modelUnavailable,
            .networkUnavailable("Timeout")
        ]

        for status in statuses {
            let enTitle = status.displayTitle(language: .english)
            let zhTitle = status.displayTitle(language: .simplifiedChinese)
            XCTAssertFalse(enTitle.isEmpty, "英文文案不应为空: \(status)")
            XCTAssertFalse(zhTitle.isEmpty, "中文文案不应为空: \(status)")
            XCTAssertNotEqual(enTitle, zhTitle, "中英文文案应有区分: \(status)")
        }
    }

    func testJevToastMessagesLocalization() {
        let enSuccess = SettingsJevDescriptor.toastVerifySuccess(language: .english)
        let zhSuccess = SettingsJevDescriptor.toastVerifySuccess(language: .simplifiedChinese)
        XCTAssertFalse(enSuccess.isEmpty)
        XCTAssertFalse(zhSuccess.isEmpty)
        XCTAssertNotEqual(enSuccess, zhSuccess)

        let enInvalid = SettingsJevDescriptor.toastInvalidKey(language: .english)
        let zhInvalid = SettingsJevDescriptor.toastInvalidKey(language: .simplifiedChinese)
        XCTAssertFalse(enInvalid.isEmpty)
        XCTAssertFalse(zhInvalid.isEmpty)
        XCTAssertNotEqual(enInvalid, zhInvalid)

        let enDenied = SettingsJevDescriptor.toastPermissionDenied(language: .english)
        let zhDenied = SettingsJevDescriptor.toastPermissionDenied(language: .simplifiedChinese)
        XCTAssertFalse(enDenied.isEmpty)
        XCTAssertFalse(zhDenied.isEmpty)
        XCTAssertNotEqual(enDenied, zhDenied)

        let enRemoved = SettingsJevDescriptor.toastKeyRemoved(language: .english)
        let zhRemoved = SettingsJevDescriptor.toastKeyRemoved(language: .simplifiedChinese)
        XCTAssertFalse(enRemoved.isEmpty)
        XCTAssertFalse(zhRemoved.isEmpty)
        XCTAssertNotEqual(enRemoved, zhRemoved)
    }

    // MARK: - JEV-002: 设置页响应式状态联动测试

    func testSaveAndVerifyKeySynchronouslyUpdatesAppStateAndEnablesRecommendationWithoutRestart() async {
        appDelegate.setExperimentalFeaturesEnabled(true)
        // 初始状态：无 Key
        appDelegate.configureJevInitialState()
        XCTAssertFalse(appState.hasSavedJevApiKey)
        XCTAssertEqual(appState.jevConfigurationStatus, .notConfigured)
        XCTAssertFalse(appState.isJevRecommendationEnabled)

        // 执行保存并验证
        let result = await appDelegate.saveAndVerifyJevApiKey("ts-valid-test-key-1234567890")
        XCTAssertEqual(result, .valid)

        // 验证：AppState 必须立即响应式更新，无需重启应用或关闭设置窗口
        XCTAssertTrue(appState.hasSavedJevApiKey)
        XCTAssertEqual(appState.jevConfigurationStatus, .ready)

        // 验证：此时可直接在同一会话中开启推荐
        appDelegate.setJevRecommendationEnabled(true)
        XCTAssertTrue(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appState.jevConfigurationStatus, .enabled)
    }

    func testRemoveKeySynchronouslyUpdatesAppStateAndDisablesRecommendation() async {
        appDelegate.setExperimentalFeaturesEnabled(true)
        // 预设：已保存有效 Key 且已开启推荐
        _ = await appDelegate.saveAndVerifyJevApiKey("ts-valid-test-key-1234567890")
        appDelegate.setJevRecommendationEnabled(true)
        XCTAssertTrue(appState.hasSavedJevApiKey)
        XCTAssertTrue(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appState.jevConfigurationStatus, .enabled)

        // 执行移除 Key
        appDelegate.removeJevApiKey()

        // 验证：AppState 必须立即清除 Key 状态、重置推荐开关并变更为 notConfigured
        XCTAssertFalse(appState.hasSavedJevApiKey)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appState.jevConfigurationStatus, .notConfigured)
    }

    func testAccessibilityPermissionSyncsWithAppState() {
        mockAccessibilityService.isTrusted = true
        appDelegate.configureJevInitialState()
        XCTAssertTrue(appState.isAccessibilityTrusted)

        mockAccessibilityService.isTrusted = false
        appDelegate.configureJevInitialState()
        XCTAssertFalse(appState.isAccessibilityTrusted)
    }

    // MARK: - JEV-007: 运行时 401/403 错误处理与状态联动

    func testRuntimeAuthErrorHandlesInvalidKey() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)
        XCTAssertTrue(appDelegate.isJevRecommendationEnabled())

        // 模拟运行时 SystemOne 返回 401 invalidAPIKey
        appDelegate.handleJevAuthError(.invalidAPIKey)

        // 验证：推荐开关被自动关闭
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())

        // 验证：状态更新为 invalidKey，以便在设置页显示红点与相应文案
        XCTAssertEqual(appState.jevConfigurationStatus, .invalidKey)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .invalidKey)

        // 验证：Keychain 中的 Key 保持完好，不自动删除，允许用户查看状态并修改
        XCTAssertTrue(mockCredentialStore.hasApiKey())
        XCTAssertEqual(try mockCredentialStore.readApiKey(), "typesafe-test-key")
    }

    func testRuntimeAuthErrorHandlesPermissionDenied() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)

        // 模拟运行时 SystemOne 返回 403 permissionDenied
        appDelegate.handleJevAuthError(.permissionDenied)

        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(appState.isJevRecommendationEnabled)
        XCTAssertEqual(appState.jevConfigurationStatus, .permissionDenied)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .permissionDenied)

        // Keychain 中的 Key 依然保留
        XCTAssertTrue(mockCredentialStore.hasApiKey())
    }

    // MARK: - JEV-009: 移除 Key 联动取消在途推荐与清理面板推荐

    func testRemoveApiKeyCancelsSessionAndClearsRecommendationCard() async throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)

        // 模拟面板当前有正在展示的推荐卡片
        let dummyID = UUID()
        appState.panelViewModel.setRecommendationState(.ready(itemID: dummyID))
        XCTAssertEqual(appState.panelViewModel.recommendationState, .ready(itemID: dummyID))

        // 执行删除 Key
        appDelegate.removeJevApiKey()

        // 验证：面板推荐状态被立即清除为 inactive
        XCTAssertEqual(appState.panelViewModel.recommendationState, .inactive)
        // 验证：会话被取消
        XCTAssertNil(appDelegate.recommendationService.currentSession)
    }

    // MARK: - JEV-011: 用量更新通知机制

    func testUsageDidUpdateNotificationBroadcasting() async throws {
        let expectation = expectation(forNotification: .jevUsageDidUpdate, object: nil, handler: nil)

        // 模拟记账触发通知
        let mockUsageStore = MockJevUsageStore()
        try await mockUsageStore.recordUsage(model: "jev-latest", inputTokens: 10, outputTokens: 2, localDate: Date())

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - JEV-013: 运行时鉴权失败状态跨重启与实验功能切换保持测试

    func testRuntimeAuthErrorPersistsAcrossAppRestart() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)

        // 模拟运行时 401 错误
        appDelegate.handleJevAuthError(.invalidAPIKey)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .invalidKey)
        XCTAssertEqual(preferences.jevAuthRequirement, "invalidKey")

        // 模拟应用重启：创建全新的 AppState 和 AppDelegate 并执行 configureJevInitialState
        let newAppState = AppState.preview()
        let newAppDelegate = AppDelegate(
            appState: newAppState,
            preferences: preferences,
            jevCredentialStore: mockCredentialStore,
            jevValidationClient: mockValidationClient,
            accessibilityPermissionService: mockAccessibilityService
        )
        newAppDelegate.configureJevInitialState()

        // 验证：重启后鉴权失败状态成功恢复为 invalidKey，且开关依然保持关闭
        XCTAssertEqual(newAppDelegate.currentJevConfigurationStatus(), .invalidKey)
        XCTAssertEqual(newAppState.jevConfigurationStatus, .invalidKey)
        XCTAssertFalse(newAppDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertFalse(newAppState.isJevRecommendationEnabled)
    }

    func testRuntimeAuthErrorPersistsAcrossExperimentalToggleAndBlocksReenable() throws {
        try mockCredentialStore.saveApiKey("typesafe-test-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)

        // 模拟运行时 403 错误
        appDelegate.handleJevAuthError(.permissionDenied)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .permissionDenied)

        // 切换实验功能：关闭 -> 再次打开
        appDelegate.setExperimentalFeaturesEnabled(false)
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        // 关键断言：关闭实验功能不应覆盖鉴权失败状态
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .permissionDenied)

        appDelegate.setExperimentalFeaturesEnabled(true)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .permissionDenied)

        // 尝试在未重新验证的情况下再次开启推荐
        appDelegate.setJevRecommendationEnabled(true)

        // 关键断言：鉴权异常未解除时，必须拒绝开启推荐，保持开关关闭与错误状态
        XCTAssertFalse(appDelegate.isJevRecommendationEnabled())
        XCTAssertFalse(preferences.isJevRecommendationEnabled)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .permissionDenied)
    }

    func testRuntimeAuthErrorClearedAfterSavingValidKey() async throws {
        try mockCredentialStore.saveApiKey("typesafe-invalid-key")
        appDelegate.setExperimentalFeaturesEnabled(true)
        appDelegate.setJevRecommendationEnabled(true)

        // 模拟运行时 401
        appDelegate.handleJevAuthError(.invalidAPIKey)
        XCTAssertEqual(preferences.jevAuthRequirement, "invalidKey")

        // 用户输入并验证新的有效 Key
        mockValidationClient.resultToReturn = .valid
        let result = await appDelegate.saveAndVerifyJevApiKey("new-valid-key")
        XCTAssertEqual(result, .valid)

        // 验证：持久化标记已被清除，状态恢复为 ready（开关此前已被关闭）
        XCTAssertNil(preferences.jevAuthRequirement)
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .ready)
        XCTAssertEqual(appState.jevConfigurationStatus, .ready)

        // 重新开启推荐
        appDelegate.setJevRecommendationEnabled(true)
        XCTAssertTrue(appDelegate.isJevRecommendationEnabled())
        XCTAssertEqual(appDelegate.currentJevConfigurationStatus(), .enabled)
    }
}
