import Foundation

/// 剪贴板历史面板中的 Jev 推荐展示状态
enum JevRecommendationPresentationState: Equatable, Sendable {
    /// 未启用或面板处于搜索/分类筛选中
    case inactive
    /// 正在后台异步决策中
    case loading(requestID: UUID)
    /// 决策成功，已产生符合置信度门槛的推荐卡片
    case ready(itemID: UUID)
    /// 决策完成，但模型评估无明显匹配项（保持普通列表）
    case abstained
    /// 服务或网络不可用（静默回退）
    case unavailable

    /// 获取当前推荐状态中的卡片 ID（若有）
    var recommendedItemID: UUID? {
        if case let .ready(itemID) = self {
            return itemID
        }
        return nil
    }
}

/// 单次面板展示推荐会话上下文
struct JevRecommendationSession: Equatable, Sendable {
    let requestID: UUID
    let openedAt: Date
    var hasUserInteracted: Bool
}

/// Jev 推荐协调服务协议
protocol JevRecommendationServiceProtocol: AnyObject, Sendable {
    /// 当前会话状态
    var currentSession: JevRecommendationSession? { get }
    /// 用户发生按键、搜索或点击等交互时调用，锁定当前界面防止后续推荐覆盖跳动
    func notifyUserInteracted()
    /// 取消在途请求并清理会话
    func cancelCurrentSession()
    /// 启动一次推荐请求会话
    func requestRecommendation(
        destination: DestinationContext,
        currentItems: [ClipboardItem],
        ignoredBundleIDs: Set<String>,
        onStateChange: @MainActor @escaping (JevRecommendationPresentationState) -> Void
    )
}

/// 负责协调上下文、脱敏候选、SystemOne 决策与防抢占锁的业务核心服务
final class JevRecommendationService: JevRecommendationServiceProtocol, @unchecked Sendable {
    private let client: JevDecisionClient
    private let credentialStore: JevCredentialStoring
    private let candidateBuilder: JevCandidateBuilding
    private let policy: JevRecommendationPolicy
    private let redactor: SensitiveTextRedacting
    private let usageStore: JevUsageStoring?
    private let usageStoreProvider: (@Sendable () -> JevUsageStoring?)?
    private let isEnabledProvider: @Sendable () -> Bool
    private let dateProvider: @Sendable () -> Date
    private let onAuthError: (@Sendable (JevDecisionError) -> Void)?

    private let lock = NSLock()
    private var _currentSession: JevRecommendationSession?
    private var activeTask: Task<Void, Never>?

    var currentSession: JevRecommendationSession? {
        lock.lock()
        defer { lock.unlock() }
        return _currentSession
    }

    init(
        client: JevDecisionClient = JevHTTPClient(),
        credentialStore: JevCredentialStoring = JevCredentialStore(),
        candidateBuilder: JevCandidateBuilding = JevCandidateBuilder(),
        policy: JevRecommendationPolicy = JevRecommendationPolicy(),
        redactor: SensitiveTextRedacting = SensitiveTextRedactor.shared,
        usageStore: JevUsageStoring? = nil,
        usageStoreProvider: (@Sendable () -> JevUsageStoring?)? = nil,
        isEnabledProvider: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "isJevRecommendationEnabled")
        },
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        onAuthError: (@Sendable (JevDecisionError) -> Void)? = nil
    ) {
        self.client = client
        self.credentialStore = credentialStore
        self.candidateBuilder = candidateBuilder
        self.policy = policy
        self.redactor = redactor
        self.usageStore = usageStore
        self.usageStoreProvider = usageStoreProvider
        self.isEnabledProvider = isEnabledProvider
        self.dateProvider = dateProvider
        self.onAuthError = onAuthError
    }

    /// 用户发生按键/交互通知
    func notifyUserInteracted() {
        lock.lock()
        _currentSession?.hasUserInteracted = true
        lock.unlock()
    }

    /// 取消当前正在执行的推荐任务
    func cancelCurrentSession() {
        lock.lock()
        activeTask?.cancel()
        activeTask = nil
        _currentSession = nil
        lock.unlock()
    }

    /// 发起一次新的推荐会话
    func requestRecommendation(
        destination: DestinationContext,
        currentItems: [ClipboardItem],
        ignoredBundleIDs: Set<String>,
        onStateChange: @MainActor @escaping (JevRecommendationPresentationState) -> Void
    ) {
        // 1. 检查总开关是否开启
        guard isEnabledProvider() else {
            Task { @MainActor in
                onStateChange(.inactive)
            }
            return
        }

        // 2. 检查 Keychain 中是否存在 API Key
        guard let apiKey = try? credentialStore.readApiKey(), !apiKey.isEmpty else {
            Task { @MainActor in
                onStateChange(.inactive)
            }
            return
        }

        // 3. 重置并创建新会话
        lock.lock()
        activeTask?.cancel()

        let requestID = UUID()
        let session = JevRecommendationSession(
            requestID: requestID,
            openedAt: dateProvider(),
            hasUserInteracted: false
        )
        _currentSession = session
        lock.unlock()

        Task { @MainActor in
            onStateChange(.loading(requestID: requestID))
        }

        // 4. 异步执行决策请求
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> Void in
            guard let self else { return }

            // 4.1 严格安全阻断检查：若目标上下文未明确确认安全（例如 unknown 或 secure）或包含机密文本，立即阻断并弃权
            if !destination.isSafeForRecommendation || self.redactor.containsBlockedSecret(in: destination, userApiKey: apiKey) {
                JevLogger.log("[Jev] 目标上下文未确认非安全(classification=\(destination.securityClassification.rawValue))或包含机密内容，根据隐私安全策略弃权推荐")
                self.dispatchIfSessionValid(requestID: requestID, newState: .abstained, onStateChange: onStateChange)
                return
            }

            JevLogger.log("[Jev] 开始准备候选集: 历史条数=\(currentItems.count), 目标应用=\(destination.applicationName)")
            // 本地构建脱敏候选
            let prepared = self.candidateBuilder.prepareCandidates(
                from: currentItems,
                destination: destination,
                ignoredBundleIdentifiers: ignoredBundleIDs,
                userApiKey: apiKey
            )

            guard !prepared.candidates.isEmpty else {
                JevLogger.log("[Jev] 候选集为空（可能因应用忽略或候选全为机密），弃权推荐")
                self.dispatchIfSessionValid(requestID: requestID, newState: .abstained, onStateChange: onStateChange)
                return
            }

            guard !Task.isCancelled else { return }

            let request = JevDecisionRequest.makeRequest(
                destination: destination,
                candidates: prepared.candidates
            )

            JevLogger.log("[Jev] 发起 SystemOne 决策请求: 候选条数=\(prepared.candidates.count)")
            do {
                let response = try await self.client.decide(request, apiKey: apiKey)

                // 优先记录用量统计（无论最终推荐是否上屏或在途被取消，成功响应所消耗的 token 必须计入本地统计）
                let resolvedUsageStore = self.usageStoreProvider?() ?? self.usageStore
                if let usageStore = resolvedUsageStore {
                    let modelName = response.model
                    let inTokens = response.usage?.inputTokens
                    let outTokens = response.usage?.outputTokens
                    let now = self.dateProvider()
                    try? await usageStore.recordUsage(
                        model: modelName,
                        inputTokens: inTokens,
                        outputTokens: outTokens,
                        localDate: now
                    )
                }

                guard !Task.isCancelled else { return }

                // 依据策略判定是否符合高置信度推荐门槛
                let decision = self.policy.evaluate(
                    response: response,
                    keyToItemIDMap: prepared.keyToItemIDMap
                )

                let resultState: JevRecommendationPresentationState = {
                    switch decision {
                    case .recommend(let itemID, _, _):
                        return .ready(itemID: itemID)
                    case .abstain:
                        return .abstained
                    }
                }()

                self.dispatchIfSessionValid(requestID: requestID, newState: resultState, onStateChange: onStateChange)
            } catch let decisionError as JevDecisionError {
                JevLogger.log("[Jev] 决策请求业务错误: \(decisionError)")
                if decisionError == .invalidAPIKey || decisionError == .permissionDenied {
                    self.onAuthError?(decisionError)
                }
                self.dispatchIfSessionValid(requestID: requestID, newState: .unavailable, onStateChange: onStateChange)
            } catch {
                JevLogger.log("[Jev] 决策请求底层网络异常: \(error)")
                self.dispatchIfSessionValid(requestID: requestID, newState: .unavailable, onStateChange: onStateChange)
            }
        }

        lock.lock()
        activeTask = task
        lock.unlock()
    }

    /// 检查会话是否仍然合法有效（防抢占、防旧会话覆盖、防超时跳动）
    private func isSessionStillValid(requestID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let session = _currentSession, session.requestID == requestID else {
            JevLogger.log("[Jev] 会话已失效或被新会话替换")
            return false
        }
        // 若用户已发生交互，阻断结果
        if session.hasUserInteracted {
            JevLogger.log("[Jev] 用户已操作界面，为防抢占阻断推荐上屏")
            return false
        }
        // 若已超过展示期限，阻断结果
        let elapsed = dateProvider().timeIntervalSince(session.openedAt)
        if elapsed > JevAPIConfiguration.decisionTimeoutInterval {
            JevLogger.log("[Jev] 推荐决策耗时 \(String(format: "%.2f", elapsed))s 超过阈值 \(JevAPIConfiguration.decisionTimeoutInterval)s，丢弃超时结果")
            return false
        }
        return true
    }

    /// 同步验证会话后回到主线程派发结果
    private func dispatchIfSessionValid(
        requestID: UUID,
        newState: JevRecommendationPresentationState,
        onStateChange: @MainActor @escaping (JevRecommendationPresentationState) -> Void
    ) {
        guard isSessionStillValid(requestID: requestID) else { return }

        Task { @MainActor in
            onStateChange(newState)
        }
    }
}
