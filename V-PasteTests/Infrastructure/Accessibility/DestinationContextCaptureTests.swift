import AppKit
import XCTest
@testable import V_Paste

private final class MockAccessibilityReader: AccessibilityAttributeReading, @unchecked Sendable {
    var stubbedContext: DestinationContext?
    var delayNanoseconds: UInt64 = 0

    func readElementContext(for target: TargetApplicationInfo) -> DestinationContext? {
        if delayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(delayNanoseconds) / 1_000_000_000.0)
        }
        return stubbedContext
    }
}

final class DestinationContextCaptureTests: XCTestCase {

    func testIsSecureElementRecognition() {
        XCTAssertTrue(SystemAccessibilityAttributeReader.isSecureElement(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertTrue(SystemAccessibilityAttributeReader.isSecureElement(role: "AXSecureTextField", subrole: nil))
        XCTAssertTrue(SystemAccessibilityAttributeReader.isSecureElement(role: "CustomField", subrole: "CustomSecureEntryField"))
        XCTAssertFalse(SystemAccessibilityAttributeReader.isSecureElement(role: "AXTextField", subrole: nil))
        XCTAssertFalse(SystemAccessibilityAttributeReader.isSecureElement(role: "AXTextArea", subrole: "AXStandard"))
    }

    func testCaptureReturnsNilWhenTargetIsNil() async {
        let capture = DestinationContextCapture()
        let result = await capture.capture(for: nil)
        XCTAssertNil(result)
    }

    func testCaptureReturnsDetailedContextWhenAvailable() async {
        let mockReader = MockAccessibilityReader()
        let target = TargetApplicationInfo(
            processIdentifier: 1234,
            bundleIdentifier: "com.apple.Notes",
            applicationName: "Notes"
        )
        let detailedContext = DestinationContext(
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            processIdentifier: 1234,
            windowTitle: "My Notes",
            focusedRole: "AXTextArea",
            focusedSubrole: nil,
            placeholder: "Type note...",
            selectedText: "selected portion",
            valueSnippet: "full note content",
            isSecureField: false
        )
        mockReader.stubbedContext = detailedContext

        let capture = DestinationContextCapture(reader: mockReader, timeoutMilliseconds: 200)
        let result = await capture.capture(for: target)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.applicationName, "Notes")
        XCTAssertEqual(result?.windowTitle, "My Notes")
        XCTAssertEqual(result?.focusedRole, "AXTextArea")
        XCTAssertEqual(result?.selectedText, "selected portion")
        XCTAssertEqual(result?.valueSnippet, "full note content")
        XCTAssertFalse(result?.isSecureField ?? true)
    }

    func testCaptureFallbackToApplicationOnlyWhenTimingOut() async {
        let mockReader = MockAccessibilityReader()
        let target = TargetApplicationInfo(
            processIdentifier: 5678,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome"
        )
        // 模拟 150ms 延迟，但超时预算设为 25ms
        mockReader.delayNanoseconds = 150_000_000
        mockReader.stubbedContext = DestinationContext(
            applicationName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 5678,
            windowTitle: "Should be bypassed"
        )

        let capture = DestinationContextCapture(reader: mockReader, timeoutMilliseconds: 25)
        let start = CACurrentMediaTime()
        let result = await capture.capture(for: target)
        let elapsed = CACurrentMediaTime() - start

        // 验证耗时：即便底层 AX 延迟 150ms，整体必须在超时预算内（允许线程调度误差，通常约 25~45ms，严格 < 80ms）
        XCTAssertLessThan(elapsed, 0.08, "异步 capture 耗时 \(elapsed)s 必须受硬性超时预算保护，绝不能等待 150ms")
        XCTAssertNotNil(result, "超时时应返回降级应用级上下文，保证主流程不卡顿")
        XCTAssertEqual(result?.applicationName, "Google Chrome")
        XCTAssertEqual(result?.bundleIdentifier, "com.google.Chrome")
        XCTAssertNil(result?.windowTitle, "降级上下文不包含超时未取得的窗口/控件细节")
        XCTAssertFalse(result?.isSecureField ?? true)
    }

    func testCaptureBeforeActivationEnforcesHardTimeoutWhenReaderHangs() {
        let mockReader = MockAccessibilityReader()
        let target = TargetApplicationInfo(
            processIdentifier: 7890,
            bundleIdentifier: "com.apple.finder",
            applicationName: "Finder"
        )
        // 模拟底层 AX 阻塞 150ms
        mockReader.delayNanoseconds = 150_000_000
        mockReader.stubbedContext = DestinationContext(
            applicationName: "Finder",
            bundleIdentifier: "com.apple.finder",
            processIdentifier: 7890,
            windowTitle: "Downloads"
        )

        let capture = DestinationContextCapture(reader: mockReader, timeoutMilliseconds: 25)
        let start = CACurrentMediaTime()
        let result = capture.captureBeforeActivation(for: target)
        let elapsed = CACurrentMediaTime() - start

        // 验证耗时：即便底层阻塞 150ms，同步捕获必须在 25ms 预算超时后立刻返回（< 80ms，通常 < 45ms）
        XCTAssertLessThan(elapsed, 0.08, "同步 captureBeforeActivation 耗时 \(elapsed)s 必须受硬性超时预算保护，绝不阻塞主线程")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.applicationName, "Finder")
        XCTAssertNil(result?.windowTitle, "超时未完成时应降级为应用级基础上下文")
    }

    func testCaptureBeforeActivationReturnsDetailedContextWhenFast() {
        let mockReader = MockAccessibilityReader()
        let target = TargetApplicationInfo(
            processIdentifier: 8888,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )
        mockReader.stubbedContext = DestinationContext(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 8888,
            windowTitle: "V-Paste Documentation",
            focusedRole: "AXTextArea",
            isSecureField: false
        )

        let capture = DestinationContextCapture(reader: mockReader, timeoutMilliseconds: 25)
        let result = capture.captureBeforeActivation(for: target)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.applicationName, "Safari")
        XCTAssertEqual(result?.windowTitle, "V-Paste Documentation")
        XCTAssertEqual(result?.focusedRole, "AXTextArea")
    }

    func testSecureContextNeverContainsTextContent() {
        let secureContext = DestinationContext(
            applicationName: "1Password",
            bundleIdentifier: "com.1password.app",
            processIdentifier: 9999,
            windowTitle: "Unlock Vault",
            focusedRole: "AXTextField",
            focusedSubrole: "AXSecureTextField",
            selectedText: "super_secret_text",
            valueSnippet: "super_secret_text",
            isSecureField: true
        )

        XCTAssertTrue(secureContext.isSecureField)
        XCTAssertNil(secureContext.selectedText)
        XCTAssertNil(secureContext.valueSnippet)
    }

    // MARK: - JEV-008: 渐进式捕获 (Progressive Capture) 与 80ms 预算测试

    func testProgressiveCapturePreservesMetadataWhenTextSnippetTimesOut() {
        final class MockProgressiveReader: AccessibilityAttributeReading, @unchecked Sendable {
            func readElementContext(for target: TargetApplicationInfo) -> DestinationContext? {
                readElementContext(for: target, onProgress: nil)
            }

            func readElementContext(
                for target: TargetApplicationInfo,
                onProgress: (@Sendable (DestinationContext) -> Void)?
            ) -> DestinationContext? {
                // 阶段 1：窗口
                let stage1 = DestinationContext(
                    applicationName: target.applicationName,
                    bundleIdentifier: target.bundleIdentifier,
                    processIdentifier: target.processIdentifier,
                    windowTitle: "Pull Request #42",
                    isSecureField: false,
                    capturedAt: target.capturedAt
                )
                onProgress?(stage1)

                // 阶段 2：控件与占位符
                let stage2 = DestinationContext(
                    applicationName: target.applicationName,
                    bundleIdentifier: target.bundleIdentifier,
                    processIdentifier: target.processIdentifier,
                    windowTitle: "Pull Request #42",
                    focusedRole: "AXTextArea",
                    focusedSubrole: nil,
                    fieldTitle: "Comment Box",
                    fieldDescription: nil,
                    placeholder: "Leave a comment...",
                    selectedText: nil,
                    valueSnippet: nil,
                    isSecureField: false,
                    capturedAt: target.capturedAt
                )
                onProgress?(stage2)

                // 阶段 3：读取大文本（模拟阻塞 150ms 超时）
                Thread.sleep(forTimeInterval: 0.15)
                let stage3 = DestinationContext(
                    applicationName: target.applicationName,
                    bundleIdentifier: target.bundleIdentifier,
                    processIdentifier: target.processIdentifier,
                    windowTitle: "Pull Request #42",
                    focusedRole: "AXTextArea",
                    focusedSubrole: nil,
                    fieldTitle: "Comment Box",
                    fieldDescription: nil,
                    placeholder: "Leave a comment...",
                    selectedText: "some selected comment",
                    valueSnippet: "full long text snippet",
                    isSecureField: false,
                    capturedAt: target.capturedAt
                )
                onProgress?(stage3)
                return stage3
            }
        }

        let progressiveReader = MockProgressiveReader()
        let target = TargetApplicationInfo(
            processIdentifier: 4567,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome"
        )

        // 预算设为 50ms（小于阶段 3 的 150ms 延迟）
        let capture = DestinationContextCapture(reader: progressiveReader, timeoutMilliseconds: 50)
        let result = capture.captureBeforeActivation(for: target)

        // 关键断言：虽然读取完整正文超时，但必须保留阶段 2 已经取得的窗口和控件元数据，而绝不退化为 applicationOnly
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.applicationName, "Google Chrome")
        XCTAssertEqual(result?.windowTitle, "Pull Request #42")
        XCTAssertEqual(result?.focusedRole, "AXTextArea")
        XCTAssertEqual(result?.placeholder, "Leave a comment...")
        XCTAssertNil(result?.selectedText, "超时未读取完成的选中文本应为 nil")
        XCTAssertNil(result?.valueSnippet, "超时未读取完成的正文片段应为 nil")
    }

    // MARK: - JEV-012: 安全属性识别前超时，标记为 unknown 且不可用于推荐

    func testProgressiveCaptureWhenStage2SecureRecognitionTimesOutClassificationIsUnknown() {
        final class MockStage2HangingReader: AccessibilityAttributeReading, @unchecked Sendable {
            func readElementContext(for target: TargetApplicationInfo) -> DestinationContext? {
                readElementContext(for: target, onProgress: nil)
            }

            func readElementContext(
                for target: TargetApplicationInfo,
                onProgress: (@Sendable (DestinationContext) -> Void)?
            ) -> DestinationContext? {
                // 阶段 1：仅读取到窗口，安全分类明确为 unknown
                let stage1 = DestinationContext(
                    applicationName: target.applicationName,
                    bundleIdentifier: target.bundleIdentifier,
                    processIdentifier: target.processIdentifier,
                    windowTitle: "1Password - Unlock Vault",
                    securityClassification: .unknown,
                    capturedAt: target.capturedAt
                )
                onProgress?(stage1)

                // 阶段 2：模拟安全识别过程卡住 150ms 超时
                Thread.sleep(forTimeInterval: 0.15)
                return stage1
            }
        }

        let reader = MockStage2HangingReader()
        let target = TargetApplicationInfo(
            processIdentifier: 6789,
            bundleIdentifier: "com.1password.app",
            applicationName: "1Password"
        )

        let capture = DestinationContextCapture(reader: reader, timeoutMilliseconds: 40)
        let result = capture.captureBeforeActivation(for: target)

        // 关键断言：阶段 1 的上下文被保留，但安全分类必须为 unknown，且不可用于推荐
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.securityClassification, .unknown)
        XCTAssertFalse(result?.isSafeForRecommendation ?? true)
        XCTAssertEqual(result?.windowTitle, "1Password - Unlock Vault")
    }

    func testSteppedTimeoutsExecutionSafety() {
        let mockReader = MockAccessibilityReader()
        let target = TargetApplicationInfo(
            processIdentifier: 3333,
            bundleIdentifier: "com.microsoft.VSCode",
            applicationName: "Code"
        )
        mockReader.stubbedContext = DestinationContext(
            applicationName: "Code",
            bundleIdentifier: "com.microsoft.VSCode",
            processIdentifier: 3333,
            windowTitle: "main.py",
            focusedRole: "AXTextArea",
            isSecureField: false
        )

        // 阶梯超时测试：10ms, 30ms, 80ms
        for budget: UInt64 in [10, 30, 80] {
            let capture = DestinationContextCapture(reader: mockReader, timeoutMilliseconds: budget)
            let result = capture.captureBeforeActivation(for: target)
            XCTAssertNotNil(result)
            XCTAssertEqual(result?.applicationName, "Code")
            XCTAssertEqual(result?.focusedRole, "AXTextArea")
        }
    }
}
