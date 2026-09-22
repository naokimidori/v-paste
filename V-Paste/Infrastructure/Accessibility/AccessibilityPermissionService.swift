import AppKit
import ApplicationServices
import Foundation

/// 辅助功能权限管理协议
protocol AccessibilityPermissionServing: Sendable {
    /// 当前是否已被授予辅助功能权限
    var isTrusted: Bool { get }
    /// 请求系统权限（若未授权，系统会弹出授权对话框）
    func requestPermission() -> Bool
    /// 打开系统偏好设置中的“辅助功能”授权面板
    func openAccessibilitySettings()
}

/// 基于 macOS Accessibility API 的权限管理服务
final class AccessibilityPermissionService: AccessibilityPermissionServing {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 单元测试与预览用的 Mock 辅助功能权限服务
final class MockAccessibilityPermissionService: AccessibilityPermissionServing, @unchecked Sendable {
    var isTrusted: Bool
    var didRequestPermission = false
    var didOpenSettings = false

    init(isTrusted: Bool = false) {
        self.isTrusted = isTrusted
    }

    func requestPermission() -> Bool {
        didRequestPermission = true
        return isTrusted
    }

    func openAccessibilitySettings() {
        didOpenSettings = true
    }
}
