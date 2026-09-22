import Foundation
import SQLite3

// MARK: - 通知定义

extension Notification.Name {
    /// Jev 本地用量产生新记录或清空时派发的轻量通知
    static let jevUsageDidUpdate = Notification.Name("io.vpaste.jev.usageDidUpdate")
}

// MARK: - 定价常量与版本

/// Jev 本地估算计费规则与版本配置
enum JevPricingConstants {
    /// 定价版本
    static let defaultPricingVersion = "2026-09-v1"
    /// 输入 Token 单价（纳美元/Token）：$0.042 / 1,000,000 Tokens = 42 纳美元/Token
    static let inputPriceNanodollarsPerToken: Int64 = 42
    /// 输出 Token 单价（当前公开价格免费）
    static let outputPriceNanodollarsPerToken: Int64 = 0
}

// MARK: - 数据模型

/// 按日、模型与定价版本聚合的本地用量记录
struct JevUsageDailyAggregate: Codable, Equatable, Sendable {
    /// 本地自然日（yyyy-MM-dd）
    let localDate: String
    /// 调用的模型名称（例如 jev-latest）
    let model: String
    /// 计费定价规则版本
    let pricingVersion: String
    /// 记录时刻的输入单价（纳美元/Token）
    let inputPriceNanodollarsPerToken: Int64
    /// 收到成功响应的请求总次数
    var successfulResponses: Int
    /// usage 字段缺失的请求次数
    var unknownUsageResponses: Int
    /// 累计输入 Token 数
    var inputTokens: Int64
    /// 累计输出 Token 数
    var outputTokens: Int64
    /// 预估总费用（纳美元，1 美元 = 1,000,000,000 纳美元）
    var estimatedCostNanodollars: Int64
}

/// 自然月聚合统计摘要（供 UI 消费展示）
struct JevMonthUsageSummary: Codable, Equatable, Sendable {
    /// 当月成功响应总次数
    let successfulResponses: Int
    /// 当月用量缺失的响应次数
    let unknownUsageResponses: Int
    /// 当月输入 Token 总数
    let inputTokens: Int64
    /// 当月输出 Token 总数
    let outputTokens: Int64
    /// 当月预估总费用（纳美元）
    let estimatedCostNanodollars: Int64

    /// 格式化为美元显示文案
    var formattedEstimatedCost: String {
        if estimatedCostNanodollars <= 0 {
            return "$0.00"
        }
        // 极低费用：大于 0 但小于 1,000 纳美元（即 < $0.000001）
        if estimatedCostNanodollars < 1_000 {
            return "< $0.000001"
        }

        let dollars = Double(estimatedCostNanodollars) / 1_000_000_000.0
        // 若大于等于 $0.01，格式化为常规 2~4 位小数
        if dollars >= 0.01 {
            return String(format: "$%.2f", dollars)
        } else {
            // 小于 $0.01 时保留最多 6 位小数
            let formatted = String(format: "$%.6f", dollars)
            return formatted
        }
    }

    /// 空统计摘要
    static let zero = JevMonthUsageSummary(
        successfulResponses: 0,
        unknownUsageResponses: 0,
        inputTokens: 0,
        outputTokens: 0,
        estimatedCostNanodollars: 0
    )
}

// MARK: - 存储协议

/// Jev 本地用量持久化存储协议
protocol JevUsageStoring: Sendable {
    /// 记录一次成功响应的 Token 用量与费用
    func recordUsage(
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        localDate: Date
    ) async throws

    /// 查询指定基准日期所在自然月的聚合用量摘要
    func currentMonthSummary(referenceDate: Date) async throws -> JevMonthUsageSummary

    /// 清空所有本地记录（不影响 Keychain Key 与历史数据）
    func clearAll() async throws
}

// MARK: - SQLite 本地持久化实现

/// 基于独立 SQLite 数据库文件的 Jev 本地用量存储器
final class SQLiteJevUsageStore: JevUsageStoring, @unchecked Sendable {
    private let database: SQLiteDatabase
    private let lock = NSLock()
    private let dateFormatter: DateFormatter
    private let monthFormatter: DateFormatter

    init(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.database = try SQLiteDatabase(url: databaseURL)

        let dFormatter = DateFormatter()
        dFormatter.calendar = Calendar(identifier: .gregorian)
        dFormatter.locale = Locale(identifier: "en_US_POSIX")
        dFormatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = dFormatter

        let mFormatter = DateFormatter()
        mFormatter.calendar = Calendar(identifier: .gregorian)
        mFormatter.locale = Locale(identifier: "en_US_POSIX")
        mFormatter.dateFormat = "yyyy-MM"
        self.monthFormatter = mFormatter

        try bootstrapSchema()
        try cleanupExpiredRecords(beforeMonths: 12)
    }

    private func bootstrapSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS jev_usage_daily (
            local_date TEXT NOT NULL,
            model TEXT NOT NULL,
            pricing_version TEXT NOT NULL,
            input_price_nanos INTEGER NOT NULL,
            successful_responses INTEGER NOT NULL DEFAULT 0,
            unknown_usage_responses INTEGER NOT NULL DEFAULT 0,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            estimated_cost_nanos INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(local_date, model, pricing_version)
        );
        CREATE INDEX IF NOT EXISTS idx_jev_usage_date ON jev_usage_daily(local_date);
        """
        try database.execute(sql)
    }

    /// 自动清理超过指定自然月期限的旧记录（默认保留 12 个月）
    private func cleanupExpiredRecords(beforeMonths months: Int) throws {
        guard let cutoffDate = Calendar.current.date(byAdding: .month, value: -months, to: Date()) else { return }
        let cutoffString = dateFormatter.string(from: cutoffDate)

        let statement = try database.prepare("DELETE FROM jev_usage_daily WHERE local_date < ?;")
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (cutoffString as NSString).utf8String, -1, nil)
        _ = sqlite3_step(statement)
    }

    func recordUsage(
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        localDate: Date
    ) async throws {
        lock.lock()
        defer { lock.unlock() }

        let dateString = dateFormatter.string(from: localDate)
        let pricingVersion = JevPricingConstants.defaultPricingVersion
        let inputPrice = JevPricingConstants.inputPriceNanodollarsPerToken

        let isUnknown = (inputTokens == nil)
        let unknownUsageCount = isUnknown ? 1 : 0
        let inTokens = Int64(inputTokens ?? 0)
        let outTokens = Int64(outputTokens ?? 0)
        let costNanos = inTokens * inputPrice

        let upsertSQL = """
        INSERT INTO jev_usage_daily (
            local_date,
            model,
            pricing_version,
            input_price_nanos,
            successful_responses,
            unknown_usage_responses,
            input_tokens,
            output_tokens,
            estimated_cost_nanos
        ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?)
        ON CONFLICT(local_date, model, pricing_version) DO UPDATE SET
            successful_responses = successful_responses + 1,
            unknown_usage_responses = unknown_usage_responses + excluded.unknown_usage_responses,
            input_tokens = input_tokens + excluded.input_tokens,
            output_tokens = output_tokens + excluded.output_tokens,
            estimated_cost_nanos = estimated_cost_nanos + excluded.estimated_cost_nanos;
        """

        let statement = try database.prepare(upsertSQL)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (dateString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (model as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (pricingVersion as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 4, inputPrice)
        sqlite3_bind_int(statement, 5, Int32(unknownUsageCount))
        sqlite3_bind_int64(statement, 6, inTokens)
        sqlite3_bind_int64(statement, 7, outTokens)
        sqlite3_bind_int64(statement, 8, costNanos)

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            throw SQLiteDatabaseError.stepFailed("Failed to record jev usage: \(stepResult)")
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .jevUsageDidUpdate, object: nil)
        }
    }

    func currentMonthSummary(referenceDate: Date) async throws -> JevMonthUsageSummary {
        lock.lock()
        defer { lock.unlock() }

        let monthPrefix = monthFormatter.string(from: referenceDate) + "%"

        let querySQL = """
        SELECT
            COALESCE(SUM(successful_responses), 0),
            COALESCE(SUM(unknown_usage_responses), 0),
            COALESCE(SUM(input_tokens), 0),
            COALESCE(SUM(output_tokens), 0),
            COALESCE(SUM(estimated_cost_nanos), 0)
        FROM jev_usage_daily
        WHERE local_date LIKE ?;
        """

        let statement = try database.prepare(querySQL)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (monthPrefix as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .zero
        }

        let successful = Int(sqlite3_column_int(statement, 0))
        let unknown = Int(sqlite3_column_int(statement, 1))
        let inputTokens = sqlite3_column_int64(statement, 2)
        let outputTokens = sqlite3_column_int64(statement, 3)
        let estimatedCost = sqlite3_column_int64(statement, 4)

        return JevMonthUsageSummary(
            successfulResponses: successful,
            unknownUsageResponses: unknown,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostNanodollars: estimatedCost
        )
    }

    func clearAll() async throws {
        lock.lock()
        defer { lock.unlock() }

        try database.execute("DELETE FROM jev_usage_daily;")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .jevUsageDidUpdate, object: nil)
        }
    }
}

// MARK: - Mock 实现（供单测使用）

/// 内存模拟用量存储器
final class MockJevUsageStore: JevUsageStoring, @unchecked Sendable {
    var aggregates: [String: JevUsageDailyAggregate] = [:]
    private let lock = NSLock()

    func recordUsage(
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        localDate: Date
    ) async throws {
        lock.lock()
        defer { lock.unlock() }

        let dFormatter = DateFormatter()
        dFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dFormatter.string(from: localDate)

        let isUnknown = (inputTokens == nil)
        let inTokens = Int64(inputTokens ?? 0)
        let outTokens = Int64(outputTokens ?? 0)
        let cost = inTokens * JevPricingConstants.inputPriceNanodollarsPerToken

        if var existing = aggregates[dateKey] {
            existing.successfulResponses += 1
            if isUnknown { existing.unknownUsageResponses += 1 }
            existing.inputTokens += inTokens
            existing.outputTokens += outTokens
            existing.estimatedCostNanodollars += cost
            aggregates[dateKey] = existing
        } else {
            aggregates[dateKey] = JevUsageDailyAggregate(
                localDate: dateKey,
                model: model,
                pricingVersion: JevPricingConstants.defaultPricingVersion,
                inputPriceNanodollarsPerToken: JevPricingConstants.inputPriceNanodollarsPerToken,
                successfulResponses: 1,
                unknownUsageResponses: isUnknown ? 1 : 0,
                inputTokens: inTokens,
                outputTokens: outTokens,
                estimatedCostNanodollars: cost
            )
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .jevUsageDidUpdate, object: nil)
        }
    }

    func currentMonthSummary(referenceDate: Date) async throws -> JevMonthUsageSummary {
        lock.lock()
        defer { lock.unlock() }

        let mFormatter = DateFormatter()
        mFormatter.dateFormat = "yyyy-MM"
        let prefix = mFormatter.string(from: referenceDate)

        var successful = 0
        var unknown = 0
        var inTokens: Int64 = 0
        var outTokens: Int64 = 0
        var cost: Int64 = 0

        for (dateKey, agg) in aggregates where dateKey.hasPrefix(prefix) {
            successful += agg.successfulResponses
            unknown += agg.unknownUsageResponses
            inTokens += agg.inputTokens
            outTokens += agg.outputTokens
            cost += agg.estimatedCostNanodollars
        }

        return JevMonthUsageSummary(
            successfulResponses: successful,
            unknownUsageResponses: unknown,
            inputTokens: inTokens,
            outputTokens: outTokens,
            estimatedCostNanodollars: cost
        )
    }

    func clearAll() async throws {
        lock.lock()
        defer { lock.unlock() }
        aggregates.removeAll()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .jevUsageDidUpdate, object: nil)
        }
    }
}
