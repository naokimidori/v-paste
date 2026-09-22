import Foundation

/// 准备发往 Jev 决策服务的脱敏候选条目载荷
struct JevCandidatePayload: Codable, Equatable, Sendable {
    /// 会话内临时匿名标识（如 "c0", "c1"）
    let key: String
    /// 剪贴板类型（"text" | "link" | "file" | "image"）
    let type: String
    /// 经过脱敏与截断的安全文本预览（绝不包含本地路径、二进制或密码）
    let preview: String
    /// 来源应用程序名称（如 "Xcode", "Safari"）
    let sourceApplication: String?
    /// 相对时间分桶（"recent" | "today" | "earlier"）
    let ageBucket: String
    /// 是否已收藏
    let favorited: Bool

    enum CodingKeys: String, CodingKey {
        case key
        case type
        case preview
        case sourceApplication = "source_application"
        case ageBucket = "age_bucket"
        case favorited
    }

    init(
        key: String,
        type: String,
        preview: String,
        sourceApplication: String?,
        ageBucket: String,
        favorited: Bool
    ) {
        self.key = key
        self.type = type
        self.preview = preview
        self.sourceApplication = sourceApplication
        self.ageBucket = ageBucket
        self.favorited = favorited
    }
}

/// 准备好的候选结果集与客户端本地 UUID 反向映射表
struct JevPreparedCandidates: Equatable, Sendable {
    /// 供上报给 Jev API 的脱敏候选列表（上限 40 条）
    let candidates: [JevCandidatePayload]
    /// 本地会话内的临时 key 到数据库 ClipboardItem ID 的映射表（仅存内存，严禁上传）
    let keyToItemIDMap: [String: UUID]

    init(
        candidates: [JevCandidatePayload],
        keyToItemIDMap: [String: UUID]
    ) {
        self.candidates = candidates
        self.keyToItemIDMap = keyToItemIDMap
    }
}

/// Jev 候选构建协议
protocol JevCandidateBuilding: Sendable {
    func prepareCandidates(
        from items: [ClipboardItem],
        destination: DestinationContext,
        ignoredBundleIdentifiers: Set<String>,
        userApiKey: String?
    ) -> JevPreparedCandidates
}

/// 负责从用户历史剪贴板中预筛选、脱敏并构建匿名化候选集
final class JevCandidateBuilder: JevCandidateBuilding, @unchecked Sendable {
    static let maxCandidateLimit = 40
    static let maxPreviewLength = 300

    private let redactor: SensitiveTextRedacting
    private let dateProvider: @Sendable () -> Date

    init(
        redactor: SensitiveTextRedacting = SensitiveTextRedactor.shared,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.redactor = redactor
        self.dateProvider = dateProvider
    }

    /// 准备脱敏候选集合
    func prepareCandidates(
        from items: [ClipboardItem],
        destination: DestinationContext,
        ignoredBundleIdentifiers: Set<String> = [],
        userApiKey: String? = nil
    ) -> JevPreparedCandidates {
        // 1. 安全前置阻断：安全输入框或处于忽略应用名单时，绝不构建或发送任何候选
        if destination.isSecureField {
            return JevPreparedCandidates(candidates: [], keyToItemIDMap: [:])
        }
        if let bundleID = destination.bundleIdentifier, ignoredBundleIdentifiers.contains(bundleID) {
            return JevPreparedCandidates(candidates: [], keyToItemIDMap: [:])
        }

        guard !items.isEmpty else {
            return JevPreparedCandidates(candidates: [], keyToItemIDMap: [:])
        }

        let now = dateProvider()

        // 2. 提取目标上下文词项（用于相关性打分）
        let targetTokens = extractTokens(from: [
            destination.windowTitle,
            destination.fieldTitle,
            destination.placeholder,
            destination.valueSnippet
        ])

        // 3. 本地启发式打分与预筛选
        let scoredItems: [(item: ClipboardItem, score: Double)] = items.compactMap { item in
            // 安全过滤：若明确包含硬编码机密信息，整条候选直接丢弃
            let textContent = item.plainText ?? item.displayTitle
            if redactor.containsBlockedSecret(textContent, userApiKey: userApiKey) {
                return nil
            }
            if redactor.containsBlockedSecret(item.displayTitle, userApiKey: userApiKey) {
                return nil
            }

            let score = calculateScore(for: item, targetTokens: targetTokens, destination: destination, now: now)
            return (item, score)
        }

        // 按得分从高到低排序，取前最多 40 条
        let topItems = scoredItems
            .sorted { $0.score > $1.score }
            .prefix(Self.maxCandidateLimit)
            .map(\.item)

        // 4. 构建匿名候选与内存映射表
        var candidates: [JevCandidatePayload] = []
        var keyToIDMap: [String: UUID] = [:]

        for (index, item) in topItems.enumerated() {
            let key = "c\(index)"
            keyToIDMap[key] = item.id

            let typeString: String = {
                switch item.contentType {
                case .file:
                    return "file"
                case .image:
                    return "image"
                case .text, .mixed:
                    if let urlString = item.urlString,
                       let url = URL(string: urlString),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        return "link"
                    }
                    return "text"
                }
            }()

            let previewText = makeSafePreview(for: item)
            let ageBucket = determineAgeBucket(copiedAt: item.lastCopiedAt, now: now)

            candidates.append(JevCandidatePayload(
                key: key,
                type: typeString,
                preview: previewText,
                sourceApplication: item.sourceAppName,
                ageBucket: ageBucket,
                favorited: item.isFavorited
            ))
        }

        return JevPreparedCandidates(candidates: candidates, keyToItemIDMap: keyToIDMap)
    }

    // MARK: - 启发式评分计算

    private func calculateScore(
        for item: ClipboardItem,
        targetTokens: Set<String>,
        destination: DestinationContext,
        now: Date
    ) -> Double {
        var score: Double = 0.0

        // 1. 时间衰减分（越近得分越高，衰减基数）
        let elapsedHours = max(0.0, now.timeIntervalSince(item.lastCopiedAt) / 3600.0)
        score += max(0.0, 10.0 / (1.0 + elapsedHours * 0.1))

        // 2. 收藏加权
        if item.isFavorited {
            score += 3.0
        }

        // 3. 来源应用相同或相近
        if let destBundle = destination.bundleIdentifier,
           let sourceBundle = item.sourceAppBundleIdentifier,
           !destBundle.isEmpty && destBundle == sourceBundle {
            score += 2.0
        }

        // 4. 上下文与文本词项重合匹配（Token Overlap）
        if !targetTokens.isEmpty {
            let itemTokens = extractTokens(from: [item.displayTitle, item.plainText, item.urlString, item.fileName])
            let overlapCount = targetTokens.intersection(itemTokens).count
            score += min(10.0, Double(overlapCount) * 1.5)
        }

        // 5. 焦点控件类型兼容度加分
        if let role = destination.focusedRole {
            if role.contains("Text") && (item.contentType == .text || item.contentType == .mixed) {
                score += 1.0
            }
        }

        return score
    }

    // MARK: - 辅助脱敏与特征提取

    /// 为候选生成安全的预览文本，严格防止路径与二进制泄漏
    private func makeSafePreview(for item: ClipboardItem) -> String {
        switch item.contentType {
        case .text, .mixed:
            let raw = item.plainText ?? item.displayTitle
            let sanitized = redactor.sanitizePII(raw)
            return truncate(sanitized, limit: Self.maxPreviewLength)

        case .file:
            // 文件仅上报文件名，绝不上报本地绝对路径（filePath）
            let name = item.fileName ?? item.displayTitle
            return truncate(name, limit: Self.maxPreviewLength)

        case .image:
            // 图片仅上报 displayTitle，绝不上报二进制数据或缓存路径
            return truncate(item.displayTitle, limit: Self.maxPreviewLength)
        }
    }

    /// 截断过长字符
    private func truncate(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit {
            return trimmed
        }
        return String(trimmed.prefix(limit))
    }

    /// 计算时间分桶
    private func determineAgeBucket(copiedAt: Date, now: Date) -> String {
        let diff = max(0.0, now.timeIntervalSince(copiedAt))
        if diff < 600 {
            return "recent"
        } else if diff < 86400 {
            return "today"
        } else {
            return "earlier"
        }
    }

    /// 从可选字符串列表中提取用于词项匹配的有效词汇
    private func extractTokens(from strings: [String?]) -> Set<String> {
        var tokens = Set<String>()
        let separator = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

        for str in strings.compactMap({ $0 }) {
            let parts = str.components(separatedBy: separator)
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // 仅保留有意义长度的词元，过滤纯单字符或纯符号
                if trimmed.count >= 2 {
                    tokens.insert(trimmed)
                }
            }
        }
        return tokens
    }
}
