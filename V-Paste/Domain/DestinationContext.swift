import Foundation

/// 目标输入框的安全属性识别分类
public enum DestinationSecurityClassification: String, Codable, Sendable {
    /// 明确识别为安全密码输入框（如 AXSecureTextField）
    case secure
    /// 明确识别为普通非安全输入框（如普通 AXTextField、AXTextArea）
    case nonSecure
    /// 尚未完成安全控件识别或降级未能确定（如仅读取了窗口/应用、或超时截断）
    case unknown
}

/// 触发推荐时捕获的前台目标应用与焦点控件上下文
public struct DestinationContext: Equatable, Sendable {
    /// 目标应用名称（如 "Google Chrome"、"Xcode"）
    public let applicationName: String
    /// 目标应用的 Bundle Identifier（如 "com.google.Chrome"）
    public let bundleIdentifier: String?
    /// 目标应用的系统进程 ID
    public let processIdentifier: pid_t
    /// 当前聚焦窗口的标题
    public let windowTitle: String?
    /// 当前聚焦控件的无障碍角色（如 "AXTextField"、"AXTextArea"、"AXWebArea"）
    public let focusedRole: String?
    /// 当前聚焦控件的子角色（如 "AXSecureTextField"）
    public let focusedSubrole: String?
    /// 输入框关联的标题或无障碍标签
    public let fieldTitle: String?
    /// 输入框的无障碍描述
    public let fieldDescription: String?
    /// 输入框的占位提示符（Placeholder）
    public let placeholder: String?
    /// 当前选中的文本（经过长度截断保护）
    public let selectedText: String?
    /// 当前输入框内的内容片段（经过长度截断保护）
    public let valueSnippet: String?
    /// 目标输入框的安全属性分类（三态）
    public let securityClassification: DestinationSecurityClassification
    /// 是否为密码/敏感安全输入框（保留兼容旧代码）
    public var isSecureField: Bool {
        securityClassification == .secure
    }
    /// 是否已明确确认为安全的普通非敏感输入框，可发起智能推荐
    public var isSafeForRecommendation: Bool {
        securityClassification == .nonSecure
    }
    /// 捕获时间戳
    public let capturedAt: Date

    public init(
        applicationName: String,
        bundleIdentifier: String? = nil,
        processIdentifier: pid_t,
        windowTitle: String? = nil,
        focusedRole: String? = nil,
        focusedSubrole: String? = nil,
        fieldTitle: String? = nil,
        fieldDescription: String? = nil,
        placeholder: String? = nil,
        selectedText: String? = nil,
        valueSnippet: String? = nil,
        securityClassification: DestinationSecurityClassification = .unknown,
        isSecureField: Bool? = nil,
        capturedAt: Date = Date()
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowTitle = windowTitle
        self.focusedRole = focusedRole
        self.focusedSubrole = focusedSubrole
        self.fieldTitle = fieldTitle
        self.fieldDescription = fieldDescription
        self.placeholder = placeholder

        let resolvedClassification: DestinationSecurityClassification = {
            if let isSecureField {
                return isSecureField ? .secure : .nonSecure
            }
            return securityClassification
        }()
        self.securityClassification = resolvedClassification
        let isSecure = (resolvedClassification == .secure)
        // 若为安全输入框，强制清空选中文本与内容片段
        self.selectedText = isSecure ? nil : selectedText
        self.valueSnippet = isSecure ? nil : valueSnippet
        self.capturedAt = capturedAt
    }

    /// 仅包含应用程序元数据的降级上下文（用于无辅助功能权限或读取超时情况）
    public static func applicationOnly(
        applicationName: String,
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        capturedAt: Date = Date()
    ) -> DestinationContext {
        DestinationContext(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            securityClassification: .unknown,
            capturedAt: capturedAt
        )
    }
}
