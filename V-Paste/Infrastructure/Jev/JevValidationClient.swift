import Foundation

/// Jev API 核心端点与默认配置
enum JevAPIConfiguration {
    /// TypeSafe API 根地址
    static let defaultBaseURL = URL(string: "https://api.typesafe.ai")!
    /// 模型查询端点
    static let modelsPath = "/v1/models"
    /// SystemOne 决策端点
    static let systemOnePath = "/v1/systemone"
    /// 默认支持的推荐模型 ID
    static let supportedModelIDs = ["jev-latest", "jev"]
    /// 验证超时时间（秒）
    static let validationTimeoutInterval: TimeInterval = 5.0
    /// 推荐决策超时时间（秒）
    static let decisionTimeoutInterval: TimeInterval = 2.5
}

/// Jev API Key 验证结果
enum JevValidationResult: Equatable {
    /// 验证通过，Key 有效且账号具备 Jev 访问权限
    case valid
    /// Key 无效（HTTP 401）
    case invalidKey
    /// 权限不足，账号尚未开通 Jev 权限（HTTP 403）
    case permissionDenied
    /// 验证成功但账号模型列表中无可用 Jev 模型
    case modelUnavailable
    /// 网络异常、超时或服务临时不可用（HTTP 429/5xx/断网）
    case networkUnavailable(message: String)
}

/// Jev 整体配置与可用性状态
enum JevConfigurationStatus: Equatable {
    case notConfigured
    case verifying
    case ready
    case enabled
    case invalidKey
    case permissionDenied
    case modelUnavailable
    case networkUnavailable(String?)

    /// 获取展示文案
    func displayTitle(language: AppLanguage) -> String {
        switch self {
        case .notConfigured:
            return SettingsJevDescriptor.statusNotConfigured(language: language)
        case .verifying:
            return SettingsJevDescriptor.statusVerifying(language: language)
        case .ready:
            return SettingsJevDescriptor.statusReady(language: language)
        case .enabled:
            return SettingsJevDescriptor.statusEnabled(language: language)
        case .invalidKey:
            return SettingsJevDescriptor.statusInvalidKey(language: language)
        case .permissionDenied:
            return SettingsJevDescriptor.statusPermissionDenied(language: language)
        case .modelUnavailable:
            return SettingsJevDescriptor.statusModelUnavailable(language: language)
        case .networkUnavailable(let message):
            let base = SettingsJevDescriptor.statusNetworkUnavailable(language: language)
            if let message, !message.isEmpty {
                return "\(base) (\(message))"
            }
            return base
        }
    }
}

/// TypeSafe 模型列表响应模型
struct JevModelsResponse: Codable {
    let models: [JevModelItem]?
}

/// 模型条目
struct JevModelItem: Codable {
    let id: String?
    let name: String?
    let description: String?

    var modelIdentifier: String {
        id ?? name ?? ""
    }
}

/// Jev 验证客户端协议
protocol JevValidationClientProtocol: Sendable {
    /// 验证 API Key 的合法性与可用性
    func validateKey(_ apiKey: String) async -> JevValidationResult
}

/// Jev 验证客户端实现，调用 GET /v1/models 检查凭据与模型访问权
final class JevValidationClient: JevValidationClientProtocol {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = JevAPIConfiguration.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func validateKey(_ apiKey: String) async -> JevValidationResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .invalidKey
        }

        let endpointURL = baseURL.appendingPathComponent(JevAPIConfiguration.modelsPath)
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = JevAPIConfiguration.validationTimeoutInterval
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkUnavailable(message: "Invalid server response")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    let decoded = try JSONDecoder().decode(JevModelsResponse.self, from: data)
                    let modelIDs = Set((decoded.models ?? []).map(\.modelIdentifier).filter { !$0.isEmpty })
                    let hasSupportedModel = modelIDs.contains { ident in
                        JevAPIConfiguration.supportedModelIDs.contains(ident) || ident.lowercased().hasPrefix("jev")
                    }

                    if hasSupportedModel {
                        return .valid
                    } else {
                        return .modelUnavailable
                    }
                } catch {
                    return .networkUnavailable(message: "Failed to decode models response")
                }
            case 401:
                return .invalidKey
            case 403:
                return .permissionDenied
            case 429:
                return .networkUnavailable(message: "Rate limit reached")
            case 500..<600:
                return .networkUnavailable(message: "Server error (\(httpResponse.statusCode))")
            default:
                return .networkUnavailable(message: "HTTP status \(httpResponse.statusCode)")
            }
        } catch {
            return .networkUnavailable(message: error.localizedDescription)
        }
    }
}

/// 用于单元测试与预览的 Mock 验证客户端
final class MockJevValidationClient: JevValidationClientProtocol, @unchecked Sendable {
    var resultToReturn: JevValidationResult

    init(resultToReturn: JevValidationResult = .valid) {
        self.resultToReturn = resultToReturn
    }

    func validateKey(_ apiKey: String) async -> JevValidationResult {
        return resultToReturn
    }
}
