import XCTest
@testable import V_Paste

final class SensitiveTextRedactorTests: XCTestCase {
    private let redactor = SensitiveTextRedactor()

    func testBlocksOpenAIKey() {
        let text = "Here is my token: sk-proj-1234567890abcdef1234567890 for API testing"
        XCTAssertTrue(redactor.containsBlockedSecret(text, userApiKey: nil))
    }

    func testBlocksGitHubToken() {
        let text = "Use ghp_1234567890abcdef1234567890abcdef to push code"
        XCTAssertTrue(redactor.containsBlockedSecret(text, userApiKey: nil))
    }

    func testBlocksAWSKey() {
        let text = "AWS access key: AKIAIOSFODNN7EXAMPLE"
        XCTAssertTrue(redactor.containsBlockedSecret(text, userApiKey: nil))
    }

    func testBlocksTypeSafeKey() {
        let text = "ts-1234567890abcdef12345678"
        XCTAssertTrue(redactor.containsBlockedSecret(text, userApiKey: nil))
    }

    func testBlocksJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        XCTAssertTrue(redactor.containsBlockedSecret("User JWT: \(jwt)", userApiKey: nil))
    }

    func testBlocksPEMPrivateKey() {
        let pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0w==\n-----END RSA PRIVATE KEY-----"
        XCTAssertTrue(redactor.containsBlockedSecret(pem, userApiKey: nil))
    }

    func testBlocksBearerToken() {
        let text = "Authorization: Bearer dXNlcl9zZXNzaW9uX3Rva2VuXzEyMzQ1Njc4OTA="
        XCTAssertTrue(redactor.containsBlockedSecret(text, userApiKey: nil))
    }

    func testBlocksUserConfiguredApiKey() {
        let userKey = "custom-secret-key-999"
        let text = "Some clipboard text mentioning custom-secret-key-999 in sentence"
        XCTAssertTrue(redactor.containsBlockedSecret(text, userApiKey: userKey))
    }

    func testBlocksHighEntropyString() {
        // 32 位高熵随机十六进制串
        let highEntropy = "7f8b2c4e1a9d3f5e0c6a8b7d4e2f1a9c8b7d6e5f"
        XCTAssertTrue(redactor.containsBlockedSecret("secret: \(highEntropy)", userApiKey: nil))
    }

    func testPassesNormalTextAndURLs() {
        let normalText = "你好，这是今天会议讨论的核心纪要：关于第四季度增长策略。"
        XCTAssertFalse(redactor.containsBlockedSecret(normalText, userApiKey: nil))

        let normalURL = "https://github.com/naokimidori/v-paste/pull/42"
        XCTAssertFalse(redactor.containsBlockedSecret(normalURL, userApiKey: nil))

        let codeSnippet = "func calculateTotal(items: [Item]) -> Double { return items.reduce(0) { $0 + $1.price } }"
        XCTAssertFalse(redactor.containsBlockedSecret(codeSnippet, userApiKey: nil))
    }

    func testSanitizesPIIPhoneNumberAndEmail() {
        let input = "联系人电话 13812345678，或者发送邮件到 zhaolong@typesafe.ai 咨询。"
        let sanitized = redactor.sanitizePII(input)

        XCTAssertFalse(sanitized.contains("13812345678"))
        XCTAssertTrue(sanitized.contains("138****5678"))
        XCTAssertFalse(sanitized.contains("zhaolong@typesafe.ai"))
        XCTAssertTrue(sanitized.contains("@typesafe.ai"))
    }

    // MARK: - 目标上下文脱敏与阻断测试 (JEV-001)

    func testBlocksWhenDestinationValueContainsOpenAIKey() {
        let dest = DestinationContext(
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 100,
            windowTitle: "AppDelegate.swift",
            focusedRole: "AXTextArea",
            valueSnippet: "let apiKey = \"sk-proj-1234567890abcdef1234567890abcdef\"",
            isSecureField: false
        )

        XCTAssertTrue(redactor.containsBlockedSecret(in: dest, userApiKey: nil))
    }

    func testBlocksWhenDestinationSelectedTextContainsGitHubToken() {
        let dest = DestinationContext(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 101,
            windowTitle: "GitHub Settings",
            focusedRole: "AXTextField",
            selectedText: "ghp_1234567890abcdef1234567890abcdef",
            isSecureField: false
        )

        XCTAssertTrue(redactor.containsBlockedSecret(in: dest, userApiKey: nil))
    }

    func testBlocksWhenDestinationPlaceholderContainsUserApiKey() {
        let myKey = "ts-testapikey-1234567890abcdef"
        let dest = DestinationContext(
            applicationName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 102,
            placeholder: "Enter key like ts-testapikey-1234567890abcdef",
            isSecureField: false
        )

        XCTAssertTrue(redactor.containsBlockedSecret(in: dest, userApiKey: myKey))
    }

    func testBlocksWhenDestinationContainsHighEntropyToken() {
        let dest = DestinationContext(
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 103,
            valueSnippet: "Token: 7f8b2c4e1a9d3f5e0c6a8b7d4e2f1a9c8b7d6e5f",
            isSecureField: false
        )

        XCTAssertTrue(redactor.containsBlockedSecret(in: dest, userApiKey: nil))
    }

    func testBlocksWhenDestinationIsNativeSecureField() {
        let dest = DestinationContext(
            applicationName: "Login",
            bundleIdentifier: "com.example.login",
            processIdentifier: 104,
            isSecureField: true
        )

        XCTAssertTrue(redactor.containsBlockedSecret(in: dest, userApiKey: nil))
    }

    func testBlocksWhenDestinationSecurityClassificationIsUnknown() {
        let dest = DestinationContext(
            applicationName: "Browser",
            bundleIdentifier: "com.browser.app",
            processIdentifier: 109,
            windowTitle: "Search or type URL",
            securityClassification: .unknown
        )

        XCTAssertFalse(dest.isSafeForRecommendation)
        XCTAssertTrue(redactor.containsBlockedSecret(in: dest, userApiKey: nil))
    }

    func testPassesNormalDestinationWithoutSecrets() {
        let dest = DestinationContext(
            applicationName: "Feishu",
            bundleIdentifier: "com.electron.lark",
            processIdentifier: 105,
            windowTitle: "项目技术方案讨论群",
            focusedRole: "AXTextArea",
            placeholder: "输入消息...",
            selectedText: nil,
            valueSnippet: "关于下周版本发布的排期确认",
            isSecureField: false
        )

        XCTAssertFalse(redactor.containsBlockedSecret(in: dest, userApiKey: nil))
    }

    func testSanitizesPIIAndHomePathsInDestinationPayload() {
        let dest = DestinationContext(
            applicationName: "VSCode",
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 106,
            windowTitle: "/Users/admin/Projects/secret-project/main.py",
            focusedRole: "AXTextArea",
            placeholder: "联系方式 13800138000",
            selectedText: "zhaolong@typesafe.ai",
            valueSnippet: "文件位于 /Users/admin/Downloads/data.csv，请发邮件至 help@vpaste.app",
            isSecureField: false
        )

        let payload = redactor.sanitizeDestinationPayload(destination: dest)

        // 1. 家目录脱敏
        XCTAssertEqual(payload.windowTitle, "~/Projects/secret-project/main.py")
        XCTAssertFalse(payload.windowTitle?.contains("/Users/admin") ?? false)

        // 2. 手机号码脱敏
        XCTAssertEqual(payload.placeholder, "联系方式 138****8000")

        // 3. 邮箱脱敏
        XCTAssertTrue(payload.selectedText?.contains("@typesafe.ai") ?? false)
        XCTAssertFalse(payload.selectedText?.contains("zhaolong@") ?? false)

        // 4. 正文中路径与邮箱同时脱敏
        XCTAssertTrue(payload.valueSnippet?.contains("~/Downloads/data.csv") ?? false)
        XCTAssertFalse(payload.valueSnippet?.contains("/Users/admin") ?? false)
        XCTAssertTrue(payload.valueSnippet?.contains("@vpaste.app") ?? false)
        XCTAssertFalse(payload.valueSnippet?.contains("help@") ?? false)
    }

    func testTruncatesOverlongFieldsInDestinationPayload() {
        let longTitle = String(repeating: "A", count: 120)
        let longPlaceholder = String(repeating: "B", count: 150)
        let longSelected = String(repeating: "C", count: 200)
        let longValue = String(repeating: "D", count: 500)

        let dest = DestinationContext(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            processIdentifier: 107,
            windowTitle: longTitle,
            placeholder: longPlaceholder,
            selectedText: longSelected,
            valueSnippet: longValue,
            isSecureField: false
        )

        let payload = redactor.sanitizeDestinationPayload(destination: dest)

        XCTAssertEqual(payload.windowTitle?.count, 80)
        XCTAssertEqual(payload.placeholder?.count, 100)
        XCTAssertEqual(payload.selectedText?.count, 120)
        XCTAssertEqual(payload.valueSnippet?.count, 120)
    }

    func testMakeRequestAppliesDestinationSanitization() {
        let dest = DestinationContext(
            applicationName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 108,
            windowTitle: "/Users/dev/Documents/index.html",
            valueSnippet: "测试手机号 13911112222",
            isSecureField: false
        )

        let request = JevDecisionRequest.makeRequest(
            destination: dest,
            candidates: []
        )

        XCTAssertEqual(request.state.destination.windowTitle, "~/Documents/index.html")
        XCTAssertEqual(request.state.destination.valueSnippet, "测试手机号 139****2222")
    }
}
