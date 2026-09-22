import Foundation

/// 敏感文本与凭据过滤协议
protocol SensitiveTextRedacting: Sendable {
    /// 检查文本是否包含应阻断上传的秘密信息（命中则候选整条剔除）
    func containsBlockedSecret(_ text: String, userApiKey: String?) -> Bool
    /// 检查目标上下文中的任意字段是否包含应阻断上传的机密信息（命中则整次请求弃权）
    func containsBlockedSecret(in destination: DestinationContext, userApiKey: String?) -> Bool
    /// 对普通个人信息（邮箱、手机等）进行掩码脱敏
    func sanitizePII(_ text: String) -> String
    /// 对目标上下文执行机密脱敏、PII掩码、路径截断与长度限制，生成安全的 JevDestinationPayload
    func sanitizeDestinationPayload(destination: DestinationContext) -> JevDestinationPayload
}

/// 默认敏感内容脱敏与拦截器
final class SensitiveTextRedactor: SensitiveTextRedacting, @unchecked Sendable {
    static let shared = SensitiveTextRedactor()

    // MARK: - 正则规则

    /// 常见 API 密钥与令牌正则
    private let secretPatterns: [NSRegularExpression] = [
        // OpenAI Key
        try! NSRegularExpression(pattern: #"\bsk-[a-zA-Z0-9_\-]{20,}\b"#),
        // GitHub Token (ghp, gho, ghu, ghs, ghr)
        try! NSRegularExpression(pattern: #"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#),
        // AWS Access Key ID
        try! NSRegularExpression(pattern: #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#),
        // TypeSafe API Key
        try! NSRegularExpression(pattern: #"\bts-[a-zA-Z0-9_\-]{20,}\b"#),
        // JWT (三段 base64url)
        try! NSRegularExpression(pattern: #"\bey[A-Za-z0-9_\-]{10,}\.ey[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b"#),
        // PEM 私钥
        try! NSRegularExpression(pattern: #"-----BEGIN ([A-Z ]+)?PRIVATE KEY-----"#),
        // Bearer Token
        try! NSRegularExpression(pattern: #"(?i)bearer\s+[a-z0-9_\-\.]{24,}"#),
        // 密码赋值特征 (如 password=..., passwd: ..., token: ...)
        try! NSRegularExpression(pattern: #"(?i)(password|passwd|pwd|secret|token|api_key|apikey)\s*[:=]\s*[^\s]{6,}"#),
        // 一次性数字验证码 (6-8位)
        try! NSRegularExpression(pattern: #"(?i)(验证码|动态码|code|otp)\D{0,6}(\d{6,8})\b"#)
    ]

    /// 手机号码掩码正则 (中国大陆 11 位手机号)
    private let phoneRegex = try! NSRegularExpression(pattern: #"\b(1[3-9]\d)(\d{4})(\d{4})\b"#)
    /// 邮箱掩码正则
    private let emailRegex = try! NSRegularExpression(pattern: #"\b([A-Za-z0-9._%+-]{1,2})[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+\.[A-Za-z]{2,})\b"#)
    /// 本地家目录脱敏正则 (/Users/username)
    private let homePathRegex = try! NSRegularExpression(pattern: #"/Users/[^/\s]+"#)

    init() {}

    /// 检查文本是否命中明确的机密信息，命中时必须阻断整条候选
    func containsBlockedSecret(_ text: String, userApiKey: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 1. 若文本包含用户自身配置的 Jev API Key
        if let userApiKey, !userApiKey.isEmpty, trimmed.contains(userApiKey) {
            return true
        }

        // 2. 检查常见 Secret 正则
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        for pattern in secretPatterns {
            if pattern.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // 3. 检查单行连续长字符串的高熵特征（如哈希、随机密文、Token）
        if checkHighEntropyTokens(in: trimmed) {
            return true
        }

        return false
    }

    /// 对文本中的普通个人信息进行掩码处理
    func sanitizePII(_ text: String) -> String {
        var result = text
        let fullRange = NSRange(location: 0, length: (result as NSString).length)

        // 手机号码脱敏：保留前 3 位和后 4 位，中间 4 位替换为 ****
        result = phoneRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: fullRange,
            withTemplate: "$1****$3"
        )

        // 电子邮箱脱敏：保留首位字符及域名，中间加 ***
        let emailFullRange = NSRange(location: 0, length: (result as NSString).length)
        result = emailRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: emailFullRange,
            withTemplate: "$1***$2"
        )

        return result
    }

    /// 检查文本中是否包含高熵长随机串（如 API 密文、加密散列值等）
    private func checkHighEntropyTokens(in text: String) -> Bool {
        // 按空白或标点分割出长单词
        let components = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        for token in components {
            // 针对长度在 32 及以上的连续字母数字 token 进行香农熵评估
            if token.count >= 32 && token.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
                let entropy = calculateShannonEntropy(token)
                // 16 进制字符集理论最大熵为 4.0，随机 hex 通常在 3.2~3.9；字母数字随机串通常在 3.5~4.5
                if entropy >= 3.2 {
                    return true
                }
            }
        }
        return false
    }

    /// 计算字符串的香农信息熵
    private func calculateShannonEntropy(_ string: String) -> Double {
        guard !string.isEmpty else { return 0.0 }
        var frequencies: [Character: Int] = [:]
        for char in string {
            frequencies[char, default: 0] += 1
        }
        let length = Double(string.count)
        var entropy: Double = 0.0
        for count in frequencies.values {
            let probability = Double(count) / length
            entropy -= probability * log2(probability)
        }
        return entropy
    }

    // MARK: - 目标上下文脱敏与阻断

    /// 检查目标上下文中的任意字段是否包含应阻断上传的机密信息（命中则整次请求弃权）
    func containsBlockedSecret(in destination: DestinationContext, userApiKey: String? = nil) -> Bool {
        // 若目标上下文未明确确认为非安全（例如安全未知 unknown 或安全密码框 secure），直接阻断
        if destination.securityClassification != .nonSecure {
            return true
        }

        let candidateTexts: [String?] = [
            destination.windowTitle,
            destination.fieldTitle,
            destination.fieldDescription,
            destination.placeholder,
            destination.selectedText,
            destination.valueSnippet
        ]

        for text in candidateTexts {
            if let text, containsBlockedSecret(text, userApiKey: userApiKey) {
                return true
            }
        }

        return false
    }

    /// 对目标上下文执行机密脱敏、PII掩码、路径截断与长度限制，生成安全的 JevDestinationPayload
    func sanitizeDestinationPayload(destination: DestinationContext) -> JevDestinationPayload {
        let safeWindowTitle = destination.windowTitle.map {
            truncate(sanitizePII(sanitizeHomePath($0)), limit: 80)
        }
        let safePlaceholder = destination.placeholder.map {
            truncate(sanitizePII(sanitizeHomePath($0)), limit: 100)
        }
        let safeSelectedText = destination.selectedText.map {
            truncate(sanitizePII(sanitizeHomePath($0)), limit: 120)
        }
        let safeValueSnippet = destination.valueSnippet.map {
            truncate(sanitizePII(sanitizeHomePath($0)), limit: 120)
        }

        return JevDestinationPayload(
            application: destination.applicationName,
            windowTitle: safeWindowTitle,
            fieldRole: destination.focusedRole,
            placeholder: safePlaceholder,
            selectedText: safeSelectedText,
            valueSnippet: safeValueSnippet
        )
    }

    /// 将形如 /Users/username/... 的绝对路径中的用户名脱敏为 ~/...
    func sanitizeHomePath(_ text: String) -> String {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return homePathRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "~"
        )
    }

    /// 安全截断字符串
    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit))
    }
}
