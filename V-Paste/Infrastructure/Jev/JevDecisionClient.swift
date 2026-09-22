import Foundation

/// Jev 推荐决策阶段错误
enum JevDecisionError: LocalizedError, Equatable {
    /// API Key 无效或未授权 (401)
    case invalidAPIKey
    /// 账号未开通该模型访问权限 (403)
    case permissionDenied
    /// 接口调用频率超限 (429)
    case rateLimited(retryAfterSeconds: TimeInterval?)
    /// 服务端内部错误 (5xx)
    case serverError(statusCode: Int)
    /// 网络异常或不可达
    case networkUnavailable(String)
    /// 响应数据解码失败
    case decodingError(String)
    /// 请求超时（超过 1.5 秒预算）
    case timedOut
    /// 候选列表为空
    case emptyCandidates
    /// 请求被用户主动或会话切换取消
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key 无效，请检查设置中的 Jev 密钥"
        case .permissionDenied:
            return "当前账号未获得 Jev 模型访问权限"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "请求过于频繁，请在 \(Int(seconds)) 秒后重试"
            }
            return "请求过于频繁，请稍后重试"
        case .serverError(let code):
            return "TypeSafe 服务响应异常 (HTTP \(code))"
        case .networkUnavailable(let message):
            return "网络不可用: \(message)"
        case .decodingError(let detail):
            return "数据解析异常: \(detail)"
        case .timedOut:
            return "请求超时"
        case .emptyCandidates:
            return "无可用候选"
        case .cancelled:
            return "请求已取消"
        }
    }
}

/// Jev 决策客户端协议
protocol JevDecisionClient: Sendable {
    /// 发送 Jev 决策请求并获取预测答案
    func decide(
        _ request: JevDecisionRequest,
        apiKey: String
    ) async throws -> JevDecisionResponse
}
