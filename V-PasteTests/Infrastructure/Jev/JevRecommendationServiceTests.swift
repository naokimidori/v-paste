import XCTest
@testable import V_Paste

private final class MockDecisionClient: JevDecisionClient, @unchecked Sendable {
    var stubbedResponse: JevDecisionResponse?
    var stubbedError: Error?
    var delayNanoseconds: UInt64 = 0

    func decide(_ request: JevDecisionRequest, apiKey: String) async throws -> JevDecisionResponse {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error = stubbedError {
            throw error
        }
        if let response = stubbedResponse {
            return response
        }
        throw JevDecisionError.emptyCandidates
    }
}

final class JevRecommendationServiceTests: XCTestCase {
    private var credentialStore: MockJevCredentialStore!
    private var mockClient: MockDecisionClient!
    private var fixedDate: Date!

    override func setUp() {
        super.setUp()
        credentialStore = MockJevCredentialStore()
        mockClient = MockDecisionClient()
        fixedDate = Date()
    }

    private func makeItem(id: UUID = UUID(), text: String = "Test") -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .text,
            sourceHash: "h-\(id)",
            displayTitle: text,
            plainText: text,
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: fixedDate,
            lastCopiedAt: fixedDate,
            contentSize: 10,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: false
        )
    }

    private func makeDestination(classification: DestinationSecurityClassification = .nonSecure) -> DestinationContext {
        DestinationContext(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 100,
            windowTitle: "Search",
            securityClassification: classification
        )
    }

    func testServiceReportsInactiveWhenSwitchIsDisabled() async {
        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: credentialStore,
            isEnabledProvider: { false }
        )

        let exp = expectation(description: "状态变更为 inactive")
        service.requestRecommendation(
            destination: makeDestination(),
            currentItems: [makeItem()],
            ignoredBundleIDs: []
        ) { state in
            if state == .inactive {
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testServiceReportsInactiveWhenNoAPIKey() async {
        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: credentialStore,
            isEnabledProvider: { true }
        )

        let exp = expectation(description: "未保存 Key 时应为 inactive")
        service.requestRecommendation(
            destination: makeDestination(),
            currentItems: [makeItem()],
            ignoredBundleIDs: []
        ) { state in
            if state == .inactive {
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testServiceRecommendsSuccessfullyWhenEligible() async throws {
        try credentialStore.saveApiKey("valid-api-key")
        let item = makeItem()

        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(
                    type: "choice",
                    choice: "c0",
                    confidence: 0.85,
                    probabilities: ["c0": 0.85, "none": 0.15]
                ),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.80)
            ),
            usage: nil
        )

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: credentialStore,
            isEnabledProvider: { true },
            dateProvider: { self.fixedDate }
        )

        let readyExp = expectation(description: "收到 ready 状态")
        service.requestRecommendation(
            destination: makeDestination(),
            currentItems: [item],
            ignoredBundleIDs: []
        ) { state in
            if case .ready(let recID) = state {
                XCTAssertEqual(recID, item.id)
                readyExp.fulfill()
            }
        }

        await fulfillment(of: [readyExp], timeout: 1.5)
    }

    func testServiceDiscardsLateResultWhenUserHasInteracted() async throws {
        try credentialStore.saveApiKey("valid-api-key")
        let item = makeItem()

        // 模拟网络请求有 100ms 耗时
        mockClient.delayNanoseconds = 100_000_000
        mockClient.stubbedResponse = JevDecisionResponse(
            model: "jev-latest",
            answers: JevDecisionAnswers(
                candidate: JevChoiceAnswer(type: "choice", choice: "c0", confidence: 0.9, probabilities: nil),
                usefulMatch: JevNoulAnswer(type: "noul", noul: 0.9)
            ),
            usage: nil
        )

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: credentialStore,
            isEnabledProvider: { true }
        )

        var receivedReady = false
        service.requestRecommendation(
            destination: makeDestination(),
            currentItems: [item],
            ignoredBundleIDs: []
        ) { state in
            if case .ready = state {
                receivedReady = true
            }
        }

        // 立即模拟用户触发了按键交互
        service.notifyUserInteracted()

        // 等待请求完成
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(receivedReady, "用户已交互时，防抢占锁应彻底阻断 ready 状态的派发")
    }

    // MARK: - JEV-012: 安全分类为 unknown 时直接弃权

    func testServiceAbstainsWhenDestinationClassificationIsUnknown() async throws {
        try credentialStore.saveApiKey("valid-api-key")
        let item = makeItem()

        let service = JevRecommendationService(
            client: mockClient,
            credentialStore: credentialStore,
            isEnabledProvider: { true }
        )

        let exp = expectation(description: "目标为 unknown 分类时直接进入 abstained")
        service.requestRecommendation(
            destination: makeDestination(classification: .unknown),
            currentItems: [item],
            ignoredBundleIDs: []
        ) { state in
            if state == .abstained {
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: 1.0)
    }
}
