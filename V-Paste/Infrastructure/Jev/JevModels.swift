import Foundation

/// 发往 TypeSafe SystemOne 决策端点的完整请求载荷
struct JevDecisionRequest: Codable, Equatable, Sendable {
    let model: String
    let state: JevDecisionState
    let questions: JevDecisionQuestions

    /// 构建标准决策请求
    static func makeRequest(
        destination: DestinationContext,
        candidates: [JevCandidatePayload],
        model: String = "jev-latest"
    ) -> JevDecisionRequest {
        let destPayload = SensitiveTextRedactor.shared.sanitizeDestinationPayload(destination: destination)

        var criteria: [String: String] = [:]
        for candidate in candidates {
            criteria[candidate.key] = "Candidate \(candidate.key)"
        }
        criteria["none"] = "No candidate is a sufficiently plausible match"

        let questions = JevDecisionQuestions(
            candidate: JevChoiceQuestion(
                type: "choice",
                instructions: "Choose the clipboard candidate the user is most likely to paste into the focused destination now.",
                criteria: criteria
            ),
            usefulMatch: JevNoulQuestion(
                type: "noul",
                instructions: "There is a clearly useful clipboard candidate for the focused destination."
            )
        )

        return JevDecisionRequest(
            model: model,
            state: JevDecisionState(destination: destPayload, candidates: candidates),
            questions: questions
        )
    }
}

/// 决策上下文状态（包含脱敏的目标上下文和脱敏候选列表）
struct JevDecisionState: Codable, Equatable, Sendable {
    let destination: JevDestinationPayload
    let candidates: [JevCandidatePayload]
}

/// 目标上下文脱敏载荷
struct JevDestinationPayload: Codable, Equatable, Sendable {
    let application: String
    let windowTitle: String?
    let fieldRole: String?
    let placeholder: String?
    let selectedText: String?
    let valueSnippet: String?

    enum CodingKeys: String, CodingKey {
        case application
        case windowTitle = "window_title"
        case fieldRole = "field_role"
        case placeholder
        case selectedText = "selected_text"
        case valueSnippet = "value_snippet"
    }
}

/// 决策问题集合
struct JevDecisionQuestions: Codable, Equatable, Sendable {
    let candidate: JevChoiceQuestion
    let usefulMatch: JevNoulQuestion

    enum CodingKeys: String, CodingKey {
        case candidate
        case usefulMatch = "useful_match"
    }
}

/// 选择题定义
struct JevChoiceQuestion: Codable, Equatable, Sendable {
    let type: String
    let instructions: String
    let criteria: [String: String]
}

/// 连续概率（noul）问题定义
struct JevNoulQuestion: Codable, Equatable, Sendable {
    let type: String
    let instructions: String
}

// MARK: - 响应模型

/// TypeSafe SystemOne 决策响应
struct JevDecisionResponse: Codable, Equatable, Sendable {
    let model: String
    let answers: JevDecisionAnswers
    let usage: JevDecisionUsage?
}

/// 决策答案集合
struct JevDecisionAnswers: Codable, Equatable, Sendable {
    let candidate: JevChoiceAnswer
    let usefulMatch: JevNoulAnswer

    enum CodingKeys: String, CodingKey {
        case candidate
        case usefulMatch = "useful_match"
    }
}

/// 候选选择回答
struct JevChoiceAnswer: Codable, Equatable, Sendable {
    let type: String
    let choice: String
    let confidence: Double
    let probabilities: [String: Double]?
}

/// 有效匹配程度评分回答
struct JevNoulAnswer: Codable, Equatable, Sendable {
    let type: String
    let noul: Double
}

/// Token 消耗统计
struct JevDecisionUsage: Codable, Equatable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

import os

/// Jev 结构化诊断日志器（同时输出到 os.Logger 与本地 Application Support/io.vpaste.app/jev.log 文件）
/// Jev 结构化诊断日志器（同时输出到 os.Logger 与本地 Application Support/io.vpaste.app/jev.log 文件，支持 1MB 自动轮转）
final class JevLogger: Sendable {
    static let shared = JevLogger()
    private let logger = os.Logger(subsystem: "io.vpaste.app", category: "Jev")
    let fileURL: URL?
    let maxFileSizeBytes: Int64
    private let fileQueue = DispatchQueue(label: "io.vpaste.jevlogger", qos: .utility)

    init(fileURL: URL? = nil, maxFileSizeBytes: Int64 = 1_048_576) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("io.vpaste.app", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("jev.log")
        } else {
            self.fileURL = nil
        }
        self.maxFileSizeBytes = maxFileSizeBytes
    }

    static func log(_ message: String) {
        shared.write(message)
    }

    func write(_ message: String) {
        // 1. 系统统一日志使用默认私有策略（防止用户敏感内容在控制台明文暴露）
        logger.notice("\(message)")

        // 2. 本地日志文件写入与轮转
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        fileQueue.async { [fileURL, maxFileSizeBytes] in
            guard let fileURL, let data = line.data(using: .utf8) else { return }
            let fileManager = FileManager.default

            // 检查大小是否超限，若超限则轮转为 .log.1
            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let currentSize = attrs[.size] as? Int64,
               currentSize + Int64(data.count) > maxFileSizeBytes {
                let backupURL = fileURL.deletingPathExtension().appendingPathExtension("log.1")
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.moveItem(at: fileURL, to: backupURL)
            }

            if fileManager.fileExists(atPath: fileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? fileHandle.close() }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// 清空本地日志文件
    static func clearLogs() {
        shared.clear()
    }

    func clear() {
        fileQueue.sync { [fileURL] in
            guard let fileURL else { return }
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: fileURL)
            let backupURL = fileURL.deletingPathExtension().appendingPathExtension("log.1")
            try? fileManager.removeItem(at: backupURL)
        }
    }

    /// 等待后台文件写入完成（主要用于测试验证）
    func syncForTesting() {
        fileQueue.sync {}
    }

    static var logFileURL: URL? {
        shared.fileURL
    }
}
