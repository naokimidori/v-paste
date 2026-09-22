import AppKit
import ApplicationServices
import Foundation

/// 目标应用无障碍上下文采集协议
public protocol DestinationContextCapturing: Sendable {
    /// 在唤起剪贴板面板前捕获目标应用及聚焦输入框的上下文信息
    func capture(for target: TargetApplicationInfo?) async -> DestinationContext?
    /// 在激活 V-Paste 面板前同步快速捕获目标应用无障碍上下文
    func captureBeforeActivation(for target: TargetApplicationInfo?) -> DestinationContext?
}

/// 底层无障碍元素属性读取协议，便于单元测试隔离
public protocol AccessibilityAttributeReading: Sendable {
    /// 检查指定目标是否可读取其 AX 元素树
    func readElementContext(for target: TargetApplicationInfo) -> DestinationContext?
    /// 支持渐进式阶段汇报的读取接口（超时时可保留已安全取得的元数据）
    func readElementContext(for target: TargetApplicationInfo, onProgress: (@Sendable (DestinationContext) -> Void)?) -> DestinationContext?
}

extension AccessibilityAttributeReading {
    public func readElementContext(for target: TargetApplicationInfo, onProgress: (@Sendable (DestinationContext) -> Void)?) -> DestinationContext? {
        let result = readElementContext(for: target)
        if let result {
            onProgress?(result)
        }
        return result
    }
}

/// 默认系统无障碍属性读取器
public final class SystemAccessibilityAttributeReader: AccessibilityAttributeReading, @unchecked Sendable {
    private let maxSnippetLength: Int
    private let axMessageTimeoutSeconds: Float

    public init(maxSnippetLength: Int = 1000, axMessageTimeoutSeconds: Float = 0.08) {
        self.maxSnippetLength = maxSnippetLength
        self.axMessageTimeoutSeconds = axMessageTimeoutSeconds
    }

    public func readElementContext(for target: TargetApplicationInfo) -> DestinationContext? {
        readElementContext(for: target, onProgress: nil)
    }

    public func readElementContext(
        for target: TargetApplicationInfo,
        onProgress: (@Sendable (DestinationContext) -> Void)?
    ) -> DestinationContext? {
        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        // 设置 AX 消息单次超时（如 80ms），防止目标应用失去响应时挂起调用方
        AXUIElementSetMessagingTimeout(appElement, axMessageTimeoutSeconds)

        var focusedElementValue: AnyObject?
        let focusedError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

        var focusedWindowValue: AnyObject?
        _ = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        let windowTitle: String? = {
            if let focusedWindow = focusedWindowValue {
                let windowElement = focusedWindow as! AXUIElement
                AXUIElementSetMessagingTimeout(windowElement, axMessageTimeoutSeconds)
                return copyStringAttribute(element: windowElement, attribute: kAXTitleAttribute as CFString)
            }
            return nil
        }()

        // 阶段 1：已获取到窗口级上下文，但尚未识别焦点控件，安全分类明确标记为 unknown
        let stage1Context = DestinationContext(
            applicationName: target.applicationName,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier,
            windowTitle: windowTitle,
            securityClassification: .unknown,
            capturedAt: target.capturedAt
        )

        guard focusedError == .success, let focusedElement = focusedElementValue else {
            // 无法取得焦点元素，回退到应用与窗口级上下文（安全分类仍为 unknown，阻断推荐）
            return stage1Context
        }

        let element = focusedElement as! AXUIElement
        AXUIElementSetMessagingTimeout(element, axMessageTimeoutSeconds)

        let role = copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element: element, attribute: kAXSubroleAttribute as CFString)
        let fieldTitle = copyStringAttribute(element: element, attribute: kAXTitleAttribute as CFString)
        let fieldDescription = copyStringAttribute(element: element, attribute: kAXDescriptionAttribute as CFString)
        let placeholder = copyStringAttribute(element: element, attribute: kAXPlaceholderValueAttribute as CFString)

        // 严格安全检查：若为密码或安全输入框，立即阻断内容读取，并标记为 secure
        let isSecure = Self.isSecureElement(role: role, subrole: subrole)
        if isSecure {
            let secureContext = DestinationContext(
                applicationName: target.applicationName,
                bundleIdentifier: target.bundleIdentifier,
                processIdentifier: target.processIdentifier,
                windowTitle: windowTitle,
                focusedRole: role,
                focusedSubrole: subrole,
                fieldTitle: fieldTitle,
                fieldDescription: fieldDescription,
                placeholder: placeholder,
                selectedText: nil,
                valueSnippet: nil,
                securityClassification: .secure,
                capturedAt: target.capturedAt
            )
            onProgress?(secureContext)
            return secureContext
        }

        // 阶段 2：已明确确认为普通非安全控件，发布可用元数据（标记为 nonSecure）
        let stage2Context = DestinationContext(
            applicationName: target.applicationName,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier,
            windowTitle: windowTitle,
            focusedRole: role,
            focusedSubrole: subrole,
            fieldTitle: fieldTitle,
            fieldDescription: fieldDescription,
            placeholder: placeholder,
            selectedText: nil,
            valueSnippet: nil,
            securityClassification: .nonSecure,
            capturedAt: target.capturedAt
        )
        onProgress?(stage2Context)

        // 阶段 3：普通输入控件，安全提取选中文本与内容片段，并强制截断
        let rawSelected = copyStringAttribute(element: element, attribute: kAXSelectedTextAttribute as CFString)
        let rawValue = copyStringAttribute(element: element, attribute: kAXValueAttribute as CFString)

        let selectedText = rawSelected.map { truncate($0, limit: maxSnippetLength) }
        let valueSnippet = rawValue.map { truncate($0, limit: maxSnippetLength) }

        let fullContext = DestinationContext(
            applicationName: target.applicationName,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier,
            windowTitle: windowTitle,
            focusedRole: role,
            focusedSubrole: subrole,
            fieldTitle: fieldTitle,
            fieldDescription: fieldDescription,
            placeholder: placeholder,
            selectedText: selectedText,
            valueSnippet: valueSnippet,
            securityClassification: .nonSecure,
            capturedAt: target.capturedAt
        )
        onProgress?(fullContext)
        return fullContext
    }

    /// 判定是否为安全密码框
    public static func isSecureElement(role: String?, subrole: String?) -> Bool {
        if let subrole, subrole == "AXSecureTextField" || subrole.localizedCaseInsensitiveContains("Secure") {
            return true
        }
        if let role, role == "AXSecureTextField" || role.localizedCaseInsensitiveContains("Secure") {
            return true
        }
        return false
    }

    private func copyStringAttribute(element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard err == .success, let value else { return nil }
        if let str = value as? String, !str.isEmpty {
            return str
        }
        if let attrStr = value as? NSAttributedString, !attrStr.string.isEmpty {
            return attrStr.string
        }
        return nil
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit))
    }
}

/// 负责协调前台目标无障碍上下文捕获与超时保护
public final class DestinationContextCapture: DestinationContextCapturing, @unchecked Sendable {
    private let reader: AccessibilityAttributeReading
    private let timeoutMilliseconds: UInt64
    private let captureQueue = DispatchQueue(label: "io.vpaste.destination-capture", qos: .userInteractive)

    public init(
        reader: AccessibilityAttributeReading = SystemAccessibilityAttributeReader(),
        timeoutMilliseconds: UInt64 = 80
    ) {
        self.reader = reader
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public func capture(for target: TargetApplicationInfo?) async -> DestinationContext? {
        guard let target else { return nil }
        return await withCheckedContinuation { continuation in
            captureQueue.async {
                let context = self.performCaptureWithTimeout(for: target)
                continuation.resume(returning: context)
            }
        }
    }

    public func captureBeforeActivation(for target: TargetApplicationInfo?) -> DestinationContext? {
        guard let target else { return nil }
        return performCaptureWithTimeout(for: target)
    }

    /// 执行带硬性总超时的无障碍属性读取，超时后保留渐进式已取得的字段（Progressive Capture），未获取到任何字段时降级为应用级上下文
    private func performCaptureWithTimeout(for target: TargetApplicationInfo) -> DestinationContext {
        let semaphore = DispatchSemaphore(value: 0)
        let stateBox = CaptureStateBox()

        // 派发到专用后台队列执行阻塞式 AX 属性读取
        DispatchQueue.global(qos: .userInteractive).async { [reader] in
            let result = reader.readElementContext(for: target) { progressContext in
                stateBox.publish(progressContext)
            }
            if stateBox.finish(with: result) {
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + .milliseconds(Int(timeoutMilliseconds)))

        let context = stateBox.markTimedOut()

        // 无论是正常完成还是超时，若已有阶段性捕获的有效上下文（例如 role/placeholder/windowTitle），优先保留并返回
        if let context {
            return context
        }

        // 超时且未获取到任何有效上下文，立即返回应用级降级上下文，绝不拖延主线程
        return DestinationContext.applicationOnly(
            applicationName: target.applicationName,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier,
            capturedAt: target.capturedAt
        )
    }
}

/// 线程安全的渐进式上下文捕获状态容器，彻底避免并发闭包直接捕获可变局部变量
private final class CaptureStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedContext: DestinationContext?
    private var isFinishedOrTimedOut = false

    /// 渐进式更新已捕获的阶段性上下文
    func publish(_ context: DestinationContext) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinishedOrTimedOut else { return }
        capturedContext = context
    }

    /// 后台读取完毕，提交最终结果并标记完成
    func finish(with result: DestinationContext?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinishedOrTimedOut else { return false }
        if let result {
            capturedContext = result
        }
        isFinishedOrTimedOut = true
        return true
    }

    /// 标记超时结束，并获取当前已捕获的最新上下文
    func markTimedOut() -> DestinationContext? {
        lock.lock()
        defer { lock.unlock() }
        isFinishedOrTimedOut = true
        return capturedContext
    }
}
