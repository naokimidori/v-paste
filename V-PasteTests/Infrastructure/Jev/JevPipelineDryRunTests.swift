import XCTest
@testable import V_Paste

final class JevPipelineDryRunTests: XCTestCase {

    func testPipelineDryRunEnsuresZeroLeakageOfSensitiveDataAndLocalPaths() throws {
        let fixedDate = Date()
        let builder = JevCandidateBuilder(dateProvider: { fixedDate })

        // 1. 构造目标上下文
        let destination = DestinationContext(
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 10001,
            windowTitle: "V-Paste - ContentView.swift",
            focusedRole: "AXTextArea",
            focusedSubrole: nil,
            fieldTitle: "Source Editor",
            fieldDescription: "Swift Code",
            placeholder: nil,
            selectedText: "let service = ",
            valueSnippet: "func setup() { let service = ",
            isSecureField: false
        )

        // 2. 构造包含各种类型的真实剪贴板数据池
        let safeItemId = UUID()
        let safeItem = ClipboardItem(
            id: safeItemId,
            contentType: .text,
            sourceHash: "h1",
            displayTitle: "Swift Concurrency Helper",
            plainText: "Task { @MainActor in await updateUI() }",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 50,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: true,
            sourceAppName: "Safari",
            sourceAppBundleIdentifier: "com.apple.Safari"
        )

        let secretItemId = UUID()
        let secretItem = ClipboardItem(
            id: secretItemId,
            contentType: .text,
            sourceHash: "h2",
            displayTitle: "生产环境密钥配置",
            plainText: "export OPENAI_API_KEY=sk-proj-99999888887777766666555554444433333",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 80,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: false,
            sourceAppName: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes"
        )

        let fileItemId = UUID()
        let localSecretPath = "/Users/longzhao/Documents/Confidential/SecretPlan.pdf"
        let fileItem = ClipboardItem(
            id: fileItemId,
            contentType: .file,
            sourceHash: "h3",
            displayTitle: "SecretPlan.pdf",
            plainText: nil,
            urlString: nil,
            fileName: "SecretPlan.pdf",
            filePath: localSecretPath,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 1024,
            utiTypes: ["com.adobe.pdf"],
            isFavorited: false,
            sourceAppName: "Finder",
            sourceAppBundleIdentifier: "com.apple.finder"
        )

        let piiItemId = UUID()
        let piiItem = ClipboardItem(
            id: piiItemId,
            contentType: .text,
            sourceHash: "h4",
            displayTitle: "联系方式",
            plainText: "请拨打电话 13912345678 联系我",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 40,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: false,
            sourceAppName: "WeChat",
            sourceAppBundleIdentifier: "com.tencent.xinWeChat"
        )

        let allItems = [safeItem, secretItem, fileItem, piiItem]

        // 3. 执行候选构建管线
        let prepared = builder.prepareCandidates(
            from: allItems,
            destination: destination,
            ignoredBundleIdentifiers: [],
            userApiKey: "my-custom-jev-key"
        )

        // 4. 验证机密被过滤
        XCTAssertEqual(prepared.candidates.count, 3, "包含硬编码 API Key 的候选必须被整条剔除")
        XCTAssertFalse(prepared.candidates.contains(where: { $0.preview.contains("sk-proj-") }))
        XCTAssertNil(prepared.keyToItemIDMap.first(where: { $0.value == secretItemId }))

        // 5. 序列化为最终发往云端的 JevDecisionRequest
        let request = JevDecisionRequest.makeRequest(
            destination: destination,
            candidates: prepared.candidates
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let requestData = try encoder.encode(request)
        let jsonString = String(data: requestData, encoding: .utf8)!

        // 6. 严苛安全性断言：绝不包含敏感路径、未脱敏手机号、数据库 UUID 等
        XCTAssertFalse(jsonString.contains("/Users/"), "请求载荷严禁包含用户本地绝对路径")
        XCTAssertFalse(jsonString.contains("Confidential"), "请求载荷严禁泄露本地目录结构")
        XCTAssertFalse(jsonString.contains(safeItemId.uuidString), "请求载荷严禁上传本地 SQLite UUID")
        XCTAssertFalse(jsonString.contains(fileItemId.uuidString), "请求载荷严禁上传本地 SQLite UUID")
        XCTAssertFalse(jsonString.contains("13912345678"), "请求载荷中的手机号必须被掩码脱敏")
        XCTAssertTrue(jsonString.contains("139****5678"), "脱敏后的手机号应保留掩码形态")
        XCTAssertFalse(jsonString.contains("my-custom-jev-key"), "请求 JSON Body 严禁出现用户 API Key")

        // 7. 验证映射还原逻辑
        guard let firstCandidate = prepared.candidates.first else {
            XCTFail("应包含候选条目")
            return
        }
        let mappedId = prepared.keyToItemIDMap[firstCandidate.key]
        XCTAssertNotNil(mappedId)
        XCTAssertTrue(mappedId == safeItemId || mappedId == fileItemId || mappedId == piiItemId)
    }

    // MARK: - 阶段 D 全流程集成验证

    /// 测试端到端成功推荐流程：目标应用上下文 -> 候选池 -> 决策判定 -> 置顶投影呈现
    @MainActor
    func testEndToEndRecommendationPipelineLifecycleSuccess() async throws {
        let destination = DestinationContext(
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 1234,
            windowTitle: "AppDelegate.swift",
            focusedRole: "AXTextArea",
            focusedSubrole: nil,
            fieldTitle: "Code Editor",
            fieldDescription: "Swift",
            placeholder: nil,
            selectedText: nil,
            valueSnippet: "func test() {",
            isSecureField: false
        )

        let targetItemID = UUID()
        let matchingItem = ClipboardItem(
            id: targetItemID,
            contentType: .text,
            sourceHash: "match-hash",
            displayTitle: "Matching Code Snippet",
            plainText: "print(\"Matched!\")",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 18,
            utiTypes: [],
            isFavorited: false
        )

        let otherItem = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "other-hash",
            displayTitle: "Other Text",
            plainText: "Something else",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date().addingTimeInterval(-10),
            lastCopiedAt: Date().addingTimeInterval(-10),
            contentSize: 14,
            utiTypes: [],
            isFavorited: false
        )

        let mockClient = MockPipelineDecisionClient()
        // c0 对应由 JevCandidateBuilder 按打分排序后的首个候选
        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: "c0",
                    confidence: 0.95,
                    probabilities: ["c0": 0.95, "c1": 0.05]
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.90)
            ),
            usage: nil
        )

        let mockStore = MockJevCredentialStore()
        try mockStore.saveApiKey("valid-key")

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: mockStore,
            candidateBuilder: JevCandidateBuilder(),
            policy: JevRecommendationPolicy(),
            isEnabledProvider: { true }
        )

        let viewModel = HistoryPanelViewModel(items: [otherItem, matchingItem])
        XCTAssertEqual(viewModel.presentedItems.map(\.id), [otherItem.id, matchingItem.id])

        let expectation = expectation(description: "Recommendation ready")
        service.requestRecommendation(
            destination: destination,
            currentItems: [otherItem, matchingItem],
            ignoredBundleIDs: []
        ) { state in
            if case let .ready(itemID) = state {
                viewModel.applyRecommendation(recommendedItemID: itemID)
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // 验证置顶投影：由于模型选择 c0，对应候选第一位被推荐并置顶
        XCTAssertNotNil(viewModel.recommendationState.recommendedItemID)
        XCTAssertEqual(viewModel.presentedItems.first?.id, viewModel.recommendationState.recommendedItemID)
    }

    /// 测试超时降级与模型放弃：不打扰用户，保持正常历史列表
    @MainActor
    func testTimeoutOrAbstainedDegradesGracefullyToNormalList() async throws {
        let destination = DestinationContext(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            processIdentifier: 5678,
            windowTitle: "Document.txt",
            isSecureField: false
        )

        let item1 = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "h1",
            displayTitle: "Item 1",
            plainText: "Item 1",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 6,
            utiTypes: [],
            isFavorited: false
        )

        let mockClient = MockPipelineDecisionClient()
        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: "none",
                    confidence: 0.85,
                    probabilities: ["none": 0.85]
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.1)
            ),
            usage: nil
        )

        let mockStore = MockJevCredentialStore()
        try mockStore.saveApiKey("valid-key")

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: mockStore,
            isEnabledProvider: { true }
        )

        let viewModel = HistoryPanelViewModel(items: [item1])
        let expectation = expectation(description: "Recommendation abstained")

        service.requestRecommendation(
            destination: destination,
            currentItems: [item1],
            ignoredBundleIDs: []
        ) { state in
            if state == .abstained {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // 列表未被变更，保持常态
        XCTAssertEqual(viewModel.presentedItems.map(\.id), [item1.id])
        XCTAssertEqual(viewModel.recommendationState, .inactive)
    }

    /// 测试用户交互防抢占锁：在推荐在途期间若用户发生任何交互，结果必须被丢弃
    @MainActor
    func testUserInteractionLocksRecommendationFromOverwriting() async throws {
        let destination = DestinationContext(
            applicationName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 9999,
            windowTitle: "zsh",
            isSecureField: false
        )

        let item1 = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "item1",
            displayTitle: "First Item",
            plainText: "First",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 5,
            utiTypes: [],
            isFavorited: false
        )

        let mockClient = MockPipelineDecisionClient()
        mockClient.delayNanoseconds = 50_000_000 // 50ms
        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: "c0",
                    confidence: 0.99,
                    probabilities: ["c0": 0.99]
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.99)
            ),
            usage: nil
        )

        let mockStore = MockJevCredentialStore()
        try mockStore.saveApiKey("valid-key")

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: mockStore,
            isEnabledProvider: { true }
        )

        let viewModel = HistoryPanelViewModel(items: [item1])
        let expectation = expectation(description: "Recommendation task completed")

        service.requestRecommendation(
            destination: destination,
            currentItems: [item1],
            ignoredBundleIDs: []
        ) { state in
            // 如果被防抢占锁拦截，state 会被忽略或者 service 不再通知 ready
            if case .ready = state {
                XCTFail("用户发生交互后，严禁触发 ready 推荐状态覆盖界面")
            }
        }

        // 模拟用户在 5ms 内按下了方向键移动光标
        service.notifyUserInteracted()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.recommendationState, .inactive)
    }
}

private final class MockPipelineDecisionClient: JevDecisionClient, @unchecked Sendable {
    var stubbedResponse: JevDecisionResponse?
    var delayNanoseconds: UInt64 = 0
    var onDecideReturned: (@Sendable () -> Void)?
    var requestCount: Int = 0

    func decide(_ request: JevDecisionRequest, apiKey: String) async throws -> JevDecisionResponse {
        requestCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        onDecideReturned?()
        if let stubbedResponse {
            return stubbedResponse
        }
        throw JevDecisionError.emptyCandidates
    }
}

// MARK: - JEV-006: 日志轮转与清理测试

final class JevLoggerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("jev_logger_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLogWritesToFile() {
        let logFile = tempDir.appendingPathComponent("test.log")
        let logger = JevLogger(fileURL: logFile, maxFileSizeBytes: 10_000)

        logger.write("测试日志内容第一行")
        logger.syncForTesting()

        let content = try? String(contentsOf: logFile, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("测试日志内容第一行") ?? false)
    }

    func testLogRotatesWhenExceedingMaxSize() {
        let logFile = tempDir.appendingPathComponent("test.log")
        let backupFile = tempDir.appendingPathComponent("test.log.1")
        // 设置较小的单文件上限 80 字节
        let logger = JevLogger(fileURL: logFile, maxFileSizeBytes: 80)

        logger.write("1. 较长的一段初始日志写入以迅速占满文件空间")
        logger.syncForTesting()

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))

        // 写入第二条，触发轮转
        logger.write("2. 触发轮转的日志行")
        logger.syncForTesting()

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path), "超限后应生成 .log.1 轮转备份")
        let backupContent = try? String(contentsOf: backupFile, encoding: .utf8)
        XCTAssertTrue(backupContent?.contains("1. 较长的一段初始日志") ?? false)

        let currentContent = try? String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(currentContent?.contains("2. 触发轮转") ?? false)
    }

    func testClearLogsRemovesFiles() {
        let logFile = tempDir.appendingPathComponent("test.log")
        let logger = JevLogger(fileURL: logFile, maxFileSizeBytes: 10_000)

        logger.write("待清理日志")
        logger.syncForTesting()
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))

        logger.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path))
    }
}

// MARK: - Jev 用量与预估费用统计测试

final class JevUsageStoreTests: XCTestCase {
    private var tempDir: URL!
    private var dbURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("jev_usage_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("jev_usage_test.sqlite3")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// 测试同日多次请求原子 UPSERT 累计与费用计算
    func testUsageStoreAtomicUpsertAndAccumulation() async throws {
        let store = try SQLiteJevUsageStore(databaseURL: dbURL)
        let now = Date()

        // 第一次请求：100 输入 token，20 输出 token
        try await store.recordUsage(
            model: "jev-latest",
            inputTokens: 100,
            outputTokens: 20,
            localDate: now
        )

        // 第二次请求：50 输入 token，10 输出 token
        try await store.recordUsage(
            model: "jev-latest",
            inputTokens: 50,
            outputTokens: 10,
            localDate: now
        )

        let summary = try await store.currentMonthSummary(referenceDate: now)
        XCTAssertEqual(summary.successfulResponses, 2)
        XCTAssertEqual(summary.unknownUsageResponses, 0)
        XCTAssertEqual(summary.inputTokens, 150)
        XCTAssertEqual(summary.outputTokens, 30)
        // 150 * 42 = 6300 纳美元
        XCTAssertEqual(summary.estimatedCostNanodollars, 6300)
    }

    /// 测试缺失 usage 字段时记录 unknownUsageResponses 而不抛弃
    func testUsageStoreMissingUsageRecordsUnknown() async throws {
        let store = try SQLiteJevUsageStore(databaseURL: dbURL)
        let now = Date()

        try await store.recordUsage(
            model: "jev-latest",
            inputTokens: nil,
            outputTokens: nil,
            localDate: now
        )

        let summary = try await store.currentMonthSummary(referenceDate: now)
        XCTAssertEqual(summary.successfulResponses, 1)
        XCTAssertEqual(summary.unknownUsageResponses, 1)
        XCTAssertEqual(summary.inputTokens, 0)
        XCTAssertEqual(summary.outputTokens, 0)
        XCTAssertEqual(summary.estimatedCostNanodollars, 0)
    }

    /// 测试跨月统计过滤：仅聚合当前自然月数据
    func testUsageStoreCrossMonthFiltering() async throws {
        let store = try SQLiteJevUsageStore(databaseURL: dbURL)
        let calendar = Calendar.current
        let now = Date()
        let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!

        // 上个月记录 200 tokens
        try await store.recordUsage(
            model: "jev-latest",
            inputTokens: 200,
            outputTokens: 50,
            localDate: previousMonthDate
        )

        // 当月记录 100 tokens
        try await store.recordUsage(
            model: "jev-latest",
            inputTokens: 100,
            outputTokens: 25,
            localDate: now
        )

        let currentSummary = try await store.currentMonthSummary(referenceDate: now)
        XCTAssertEqual(currentSummary.successfulResponses, 1)
        XCTAssertEqual(currentSummary.inputTokens, 100)
        XCTAssertEqual(currentSummary.outputTokens, 25)

        let previousSummary = try await store.currentMonthSummary(referenceDate: previousMonthDate)
        XCTAssertEqual(previousSummary.successfulResponses, 1)
        XCTAssertEqual(previousSummary.inputTokens, 200)
        XCTAssertEqual(previousSummary.outputTokens, 50)
    }

    /// 测试费用格式化规则（零值、极低值、高精度与常规美元）
    func testUsageCostFormatting() {
        let zero = JevMonthUsageSummary.zero
        XCTAssertEqual(zero.formattedEstimatedCost, "$0.00")

        // 500 纳美元（< 1000 纳美元，即 < $0.000001）
        let micro = JevMonthUsageSummary(
            successfulResponses: 1,
            unknownUsageResponses: 0,
            inputTokens: 10,
            outputTokens: 0,
            estimatedCostNanodollars: 500
        )
        XCTAssertEqual(micro.formattedEstimatedCost, "< $0.000001")

        // 42,000 纳美元 = $0.000042
        let lowCost = JevMonthUsageSummary(
            successfulResponses: 1,
            unknownUsageResponses: 0,
            inputTokens: 1000,
            outputTokens: 0,
            estimatedCostNanodollars: 42_000
        )
        XCTAssertEqual(lowCost.formattedEstimatedCost, "$0.000042")

        // 50,000,000 纳美元 = $0.05
        let normalCost = JevMonthUsageSummary(
            successfulResponses: 1,
            unknownUsageResponses: 0,
            inputTokens: 1_190_476,
            outputTokens: 0,
            estimatedCostNanodollars: 50_000_000
        )
        XCTAssertEqual(normalCost.formattedEstimatedCost, "$0.05")
    }

    /// 测试清空所有用量统计
    func testUsageStoreClearAll() async throws {
        let store = try SQLiteJevUsageStore(databaseURL: dbURL)
        let now = Date()

        try await store.recordUsage(
            model: "jev-latest",
            inputTokens: 100,
            outputTokens: 20,
            localDate: now
        )

        var summary = try await store.currentMonthSummary(referenceDate: now)
        XCTAssertEqual(summary.successfulResponses, 1)

        try await store.clearAll()

        summary = try await store.currentMonthSummary(referenceDate: now)
        XCTAssertEqual(summary, JevMonthUsageSummary.zero)
    }

    /// 测试推荐服务在决策成功返回后无论是否最终展示卡片都记录用量
    @MainActor
    func testRecommendationServiceRecordsUsageEvenWhenAbstained() async throws {
        let mockUsageStore = MockJevUsageStore()
        let mockClient = MockPipelineDecisionClient()
        // 模拟返回 useful_match 极低导致策略弃权的结果
        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: "none",
                    confidence: 0.90,
                    probabilities: ["none": 0.90]
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.05)
            ),
            usage: JevDecisionUsage(inputTokens: 120, outputTokens: 15)
        )

        let mockCredStore = MockJevCredentialStore()
        try mockCredStore.saveApiKey("test-key")

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: mockCredStore,
            candidateBuilder: JevCandidateBuilder(),
            policy: JevRecommendationPolicy(),
            usageStore: mockUsageStore,
            isEnabledProvider: { true }
        )

        let item = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "h1",
            displayTitle: "Item",
            plainText: "Item text",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 4,
            utiTypes: [],
            isFavorited: false
        )

        let destination = DestinationContext(
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 1234,
            isSecureField: false
        )

        let expectation = expectation(description: "Recommendation abstained")
        service.requestRecommendation(
            destination: destination,
            currentItems: [item],
            ignoredBundleIDs: []
        ) { state in
            if state == .abstained {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // 等待后台异步 Task.detached 写入完成
        try? await Task.sleep(nanoseconds: 50_000_000)

        let summary = try await mockUsageStore.currentMonthSummary(referenceDate: Date())
        XCTAssertEqual(summary.successfulResponses, 1)
        XCTAssertEqual(summary.inputTokens, 120)
        XCTAssertEqual(summary.outputTokens, 15)
        XCTAssertEqual(summary.estimatedCostNanodollars, 120 * 42)
    }

    /// JEV-010: 测试成功响应到达后，即使会话由于面板关闭等原因被立即取消，用量依然成功入账
    @MainActor
    func testSuccessfulResponseRecordsUsageEvenWhenSessionCancelled() async throws {
        let mockUsageStore = MockJevUsageStore()
        let mockClient = MockPipelineDecisionClient()
        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: "c0",
                    confidence: 0.88,
                    probabilities: ["c0": 0.88]
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.90)
            ),
            usage: JevDecisionUsage(inputTokens: 350, outputTokens: 25)
        )

        let mockCredStore = MockJevCredentialStore()
        try mockCredStore.saveApiKey("test-key")

        var capturedService: JevRecommendationService?
        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: mockCredStore,
            candidateBuilder: JevCandidateBuilder(),
            policy: JevRecommendationPolicy(),
            usageStore: mockUsageStore,
            isEnabledProvider: { true }
        )
        capturedService = service

        // 在 Client 返回响应的瞬间立即取消会话（模拟面板恰好在此时被关闭）
        mockClient.onDecideReturned = {
            capturedService?.cancelCurrentSession()
        }

        let item = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "h1",
            displayTitle: "Item",
            plainText: "Item text",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 4,
            utiTypes: [],
            isFavorited: false
        )

        let destination = DestinationContext(
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 1234,
            isSecureField: false
        )

        service.requestRecommendation(
            destination: destination,
            currentItems: [item],
            ignoredBundleIDs: []
        ) { _ in
            // 因已取消，不应派发 UI 更新
        }

        // 等待底层异步任务完成记账
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 关键断言：即使推荐会话在响应返回时被 cancel，成功返回的模型 token 必须完整记录在本地统计中
        let summary = try await mockUsageStore.currentMonthSummary(referenceDate: Date())
        XCTAssertEqual(summary.successfulResponses, 1, "即使会话取消，已消耗 token 的成功响应也必须计入本地用量")
        XCTAssertEqual(summary.inputTokens, 350)
        XCTAssertEqual(summary.outputTokens, 25)
        XCTAssertEqual(summary.estimatedCostNanodollars, 350 * 42)
    }

    // MARK: - JEV-012: 目标上下文未确认非安全（unknown/secure）时直接弃权推荐且不发起客户端调用

    @MainActor
    func testRecommendationServiceAbstainsWhenDestinationClassificationIsUnknown() async throws {
        let mockClient = MockPipelineDecisionClient()
        let mockCredStore = MockJevCredentialStore()
        try mockCredStore.saveApiKey("test-key")

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: mockCredStore,
            candidateBuilder: JevCandidateBuilder(),
            policy: JevRecommendationPolicy(),
            usageStore: MockJevUsageStore(),
            isEnabledProvider: { true }
        )

        let item = ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: "h1",
            displayTitle: "Item",
            plainText: "Item text",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 4,
            utiTypes: [],
            isFavorited: false
        )

        let unknownDestination = DestinationContext(
            applicationName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1234,
            windowTitle: "Unknown Security Field",
            securityClassification: .unknown
        )

        let expectation = expectation(description: "等待进入弃权状态")
        var finalState: JevRecommendationPresentationState?

        service.requestRecommendation(
            destination: unknownDestination,
            currentItems: [item],
            ignoredBundleIDs: []
        ) { state in
            if case .abstained = state {
                finalState = state
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // 验证：客户端绝对没有收到请求，状态直接为弃权
        XCTAssertEqual(mockClient.requestCount, 0, "安全状态未确认时严禁发起网络请求")
        if case .abstained = finalState {
            // 通过断言
        } else {
            XCTFail("预期为 abstained，实际为 \(String(describing: finalState))")
        }
    }
}
