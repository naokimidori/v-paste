import Foundation

/// Jev 推荐判定策略阈值
struct JevPolicyThresholds: Equatable, Sendable {
    /// 最高候选最低置信度/概率（默认 0.50）
    let minConfidence: Double
    /// 最优候选与次优候选的最小差距（默认 0.10）
    let minMargin: Double
    /// useful_match 总体匹配程度最低评分（默认 0.45，实测强相关约 0.60~0.70，弱相关 0.20~0.30）
    let minUsefulScore: Double

    static let `default` = JevPolicyThresholds(
        minConfidence: 0.50,
        minMargin: 0.10,
        minUsefulScore: 0.45
    )
}

/// Jev 策略评估弃权原因
enum JevAbstainReason: String, Equatable, Sendable {
    case chosenNone = "模型选择了 none"
    case lowConfidence = "候选置信度未达到阈值"
    case ambiguousMargin = "最优候选与次优候选区分度不足"
    case lowUsefulScore = "匹配度评分低于有用阈值"
    case missingCandidateKey = "返回的候选键在本地映射中未找到"
    case emptyAnswers = "响应中缺少有效回答"
}

/// Jev 策略评估决策结论
enum JevPolicyDecision: Equatable, Sendable {
    /// 满足所有高置信度门槛，采纳推荐
    case recommend(itemID: UUID, candidateKey: String, confidence: Double)
    /// 未满足门槛，策略性弃权（保持普通历史顺序）
    case abstain(reason: JevAbstainReason)
}

/// 负责对 TypeSafe SystemOne 响应进行多维度置信度评估与安全策略校验
final class JevRecommendationPolicy: Sendable {
    let thresholds: JevPolicyThresholds

    init(thresholds: JevPolicyThresholds = .default) {
        self.thresholds = thresholds
    }

    /// 评估 SystemOne 决策响应是否满足展示推荐卡的严格门槛
    func evaluate(
        response: JevDecisionResponse,
        keyToItemIDMap: [String: UUID]
    ) -> JevPolicyDecision {
        let candidateAnswer = response.answers.candidate
        let usefulAnswer = response.answers.usefulMatch

        // 1. 检查选择是否为 none
        let chosenKey = candidateAnswer.choice.trimmingCharacters(in: .whitespacesAndNewlines)
        if chosenKey.lowercased() == "none" {
            JevLogger.log("[Jev] 策略弃权: 模型返回 choice=none")
            return .abstain(reason: .chosenNone)
        }

        // 2. 检查候选键是否存在于当前请求的本地映射中
        guard let itemID = keyToItemIDMap[chosenKey] else {
            JevLogger.log("[Jev] 策略弃权: 候选键 \(chosenKey) 不在本地 ID 映射中")
            return .abstain(reason: .missingCandidateKey)
        }

        // 3. 检查 useful_match 评分是否达到有用门槛
        if usefulAnswer.noul < thresholds.minUsefulScore {
            JevLogger.log("[Jev] 策略弃权: 有用评分过低 noul=\(usefulAnswer.noul) < \(thresholds.minUsefulScore)")
            return .abstain(reason: .lowUsefulScore)
        }

        // 4. 检查最高候选的概率或置信度
        let bestConfidence: Double = {
            if let probabilities = candidateAnswer.probabilities, let prob = probabilities[chosenKey] {
                return prob
            }
            return candidateAnswer.confidence
        }()

        if bestConfidence < thresholds.minConfidence {
            JevLogger.log("[Jev] 策略弃权: 置信度未达标 confidence=\(bestConfidence) < \(thresholds.minConfidence)")
            return .abstain(reason: .lowConfidence)
        }

        // 5. 检查与次优候选的置信度差距 (>= 0.15)，防止模棱两可误选
        if let probabilities = candidateAnswer.probabilities, probabilities.count > 1 {
            // 取除当前选中项之外的最高概率
            let otherProbabilities = probabilities.filter { $0.key != chosenKey }.values
            if let secondBest = otherProbabilities.max() {
                let margin = bestConfidence - secondBest
                if margin < thresholds.minMargin {
                    JevLogger.log("[Jev] 策略弃权: 区分度不足 best=\(bestConfidence), second=\(secondBest), margin=\(margin) < \(thresholds.minMargin)")
                    return .abstain(reason: .ambiguousMargin)
                }
            }
        }

        JevLogger.log("[Jev] 策略采纳推荐: candidate=\(chosenKey), confidence=\(bestConfidence), usefulScore=\(usefulAnswer.noul)")
        return .recommend(itemID: itemID, candidateKey: chosenKey, confidence: bestConfidence)
    }
}
