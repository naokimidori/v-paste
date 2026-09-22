import Foundation

/// 基于 URLSession 的 TypeSafe Jev SystemOne 决策网络客户端
final class JevHTTPClient: JevDecisionClient, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let timeoutInterval: TimeInterval

    init(
        baseURL: URL = JevAPIConfiguration.defaultBaseURL,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = JevAPIConfiguration.decisionTimeoutInterval
    ) {
        self.baseURL = baseURL
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    func decide(
        _ request: JevDecisionRequest,
        apiKey: String
    ) async throws -> JevDecisionResponse {
        guard !request.state.candidates.isEmpty else {
            throw JevDecisionError.emptyCandidates
        }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw JevDecisionError.invalidAPIKey
        }

        let endpoint = baseURL.appendingPathComponent(JevAPIConfiguration.systemOnePath)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw JevDecisionError.decodingError("序列化请求数据失败: \(error.localizedDescription)")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JevDecisionError.networkUnavailable("无效的 HTTP 响应")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    let decoder = JSONDecoder()
                    let decodedResponse = try decoder.decode(JevDecisionResponse.self, from: data)
                    return decodedResponse
                } catch {
                    throw JevDecisionError.decodingError("响应结构解析失败: \(error.localizedDescription)")
                }

            case 401:
                throw JevDecisionError.invalidAPIKey

            case 403:
                throw JevDecisionError.permissionDenied

            case 429:
                let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                let retrySeconds = retryAfterHeader.flatMap { Double($0) }
                throw JevDecisionError.rateLimited(retryAfterSeconds: retrySeconds)

            case 500...599:
                throw JevDecisionError.serverError(statusCode: httpResponse.statusCode)

            default:
                throw JevDecisionError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let decisionError as JevDecisionError {
            throw decisionError
        } catch is CancellationError {
            throw JevDecisionError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw JevDecisionError.cancelled
            } else if urlError.code == .timedOut {
                throw JevDecisionError.timedOut
            } else {
                throw JevDecisionError.networkUnavailable(urlError.localizedDescription)
            }
        } catch {
            throw JevDecisionError.networkUnavailable(error.localizedDescription)
        }
    }
}
