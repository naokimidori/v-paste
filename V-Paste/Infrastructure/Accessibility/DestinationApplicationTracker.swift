import AppKit
import Foundation

/// 目标应用程序元数据
public struct TargetApplicationInfo: Equatable, Sendable {
    /// 进程 ID
    public let processIdentifier: pid_t
    /// Bundle 标识符
    public let bundleIdentifier: String?
    /// 应用程序友好显示名称
    public let applicationName: String
    /// 记录时间
    public let capturedAt: Date

    public init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        applicationName: String,
        capturedAt: Date = Date()
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.capturedAt = capturedAt
    }
}

/// 目标应用追踪服务协议
public protocol DestinationApplicationTracking: AnyObject, Sendable {
    /// 最近一次合法目标应用信息
    var lastTargetApplication: TargetApplicationInfo? { get }
    /// 解析当前目标应用（支持菜单栏点击等入口下的安全回退）
    func resolveTarget(frontmost: NSRunningApplication?) -> TargetApplicationInfo?
    /// 记录前台激活应用
    func recordActiveApplication(_ app: NSRunningApplication)
}

/// 负责在呼出剪贴板面板前追踪并解析目标应用
public final class DestinationApplicationTracker: DestinationApplicationTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastTargetApplication: TargetApplicationInfo?

    /// 目标有效回退窗口时长（默认 10 秒）
    public let expirationInterval: TimeInterval
    /// 自定义时间提供者（便于单元测试）
    private let dateProvider: @Sendable () -> Date
    /// 系统排除的应用 Bundle Identifier 集合
    private let excludedBundleIdentifiers: Set<String>

    public var lastTargetApplication: TargetApplicationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return _lastTargetApplication
    }

    public init(
        expirationInterval: TimeInterval = 10.0,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        additionalExcludedIdentifiers: Set<String> = []
    ) {
        self.expirationInterval = expirationInterval
        self.dateProvider = dateProvider

        var excluded: Set<String> = [
            "com.apple.systemuiserver",
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.Spotlight",
            "com.apple.notificationcenterui",
            "com.apple.WindowManager",
            "com.apple.loginwindow"
        ]
        if let ownBundleID = Bundle.main.bundleIdentifier {
            excluded.insert(ownBundleID)
        }
        excluded.formUnion(additionalExcludedIdentifiers)
        self.excludedBundleIdentifiers = excluded

        setupWorkspaceObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// 设置工作区前台应用变更通知监听
    private func setupWorkspaceObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleApplicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        recordActiveApplication(app)
    }

    /// 记录前台应用（仅当应用合法且非忽略系统进程时）
    public func recordActiveApplication(_ app: NSRunningApplication) {
        guard isValidTarget(app: app) else { return }

        let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
        let info = TargetApplicationInfo(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            applicationName: name,
            capturedAt: dateProvider()
        )

        lock.lock()
        _lastTargetApplication = info
        lock.unlock()
    }

    /// 解析目标应用：优先使用当前前台应用；若当前为自身或系统托盘UI，则尝试回退到最近合法应用
    public func resolveTarget(frontmost: NSRunningApplication? = nil) -> TargetApplicationInfo? {
        let activeApp = frontmost ?? NSWorkspace.shared.frontmostApplication

        // 1. 若当前前台应用就是合法目标应用，直接采纳并更新缓存
        if let activeApp, isValidTarget(app: activeApp) {
            let name = activeApp.localizedName ?? activeApp.bundleIdentifier ?? "Unknown App"
            let target = TargetApplicationInfo(
                processIdentifier: activeApp.processIdentifier,
                bundleIdentifier: activeApp.bundleIdentifier,
                applicationName: name,
                capturedAt: dateProvider()
            )
            lock.lock()
            _lastTargetApplication = target
            lock.unlock()
            return target
        }

        // 2. 当前应用为自身或系统 UI，尝试从缓存中回退
        lock.lock()
        defer { lock.unlock() }

        guard let cached = _lastTargetApplication else {
            return nil
        }

        let now = dateProvider()
        // 检查时间是否超期（10 秒）
        if now.timeIntervalSince(cached.capturedAt) > expirationInterval {
            return nil
        }

        // 检查目标进程是否仍在存活运行
        if let runningApp = NSRunningApplication(processIdentifier: cached.processIdentifier), runningApp.isTerminated {
            return nil
        }

        return cached
    }

    /// 校验是否为合法目标应用程序
    private func isValidTarget(app: NSRunningApplication) -> Bool {
        // 排除自身进程
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }

        // 排除系统常驻界面与排除列表
        if let bundleID = app.bundleIdentifier, excludedBundleIdentifiers.contains(bundleID) {
            return false
        }

        // 排除已终止进程
        if app.isTerminated {
            return false
        }

        return true
    }

    /// 仅供单元测试直接设置目标缓存
    internal func setCachedTargetForTesting(_ target: TargetApplicationInfo?) {
        lock.lock()
        _lastTargetApplication = target
        lock.unlock()
    }
}
