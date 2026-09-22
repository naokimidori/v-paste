import AppKit
import XCTest
@testable import V_Paste

final class DestinationApplicationTrackerTests: XCTestCase {

    func testDestinationContextSecureFieldClearsContent() {
        let secureContext = DestinationContext(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 1234,
            windowTitle: "Login",
            focusedRole: "AXTextField",
            focusedSubrole: "AXSecureTextField",
            selectedText: "my_secret_password",
            valueSnippet: "my_secret_password",
            isSecureField: true
        )

        XCTAssertTrue(secureContext.isSecureField)
        XCTAssertNil(secureContext.selectedText, "安全输入框严禁保留选中文本")
        XCTAssertNil(secureContext.valueSnippet, "安全输入框严禁保留内容片段")
        XCTAssertEqual(secureContext.applicationName, "Safari")
    }

    func testDestinationContextApplicationOnlyFallback() {
        let fallback = DestinationContext.applicationOnly(
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 9999
        )

        XCTAssertEqual(fallback.applicationName, "Xcode")
        XCTAssertEqual(fallback.bundleIdentifier, "com.apple.dt.Xcode")
        XCTAssertEqual(fallback.processIdentifier, 9999)
        XCTAssertNil(fallback.windowTitle)
        XCTAssertNil(fallback.focusedRole)
        XCTAssertFalse(fallback.isSecureField)
    }

    func testTrackerResolvesCachedTargetWithinExpiration() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let tracker = DestinationApplicationTracker(
            expirationInterval: 10.0,
            dateProvider: { currentTime }
        )

        let target = TargetApplicationInfo(
            processIdentifier: 2000,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            capturedAt: currentTime
        )
        tracker.setCachedTargetForTesting(target)

        // 5秒后，使用自身作为 frontmost（模拟点击菜单栏或唤起剪贴板）
        currentTime = Date(timeIntervalSince1970: 1005)
        let ownApp = NSRunningApplication.current
        let resolved = tracker.resolveTarget(frontmost: ownApp)

        XCTAssertNotNil(resolved, "在10秒有效期内应成功回退到缓存目标应用")
        XCTAssertEqual(resolved?.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(resolved?.processIdentifier, 2000)
    }

    func testTrackerDiscardsExpiredCachedTarget() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let tracker = DestinationApplicationTracker(
            expirationInterval: 10.0,
            dateProvider: { currentTime }
        )

        let target = TargetApplicationInfo(
            processIdentifier: 2000,
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            capturedAt: currentTime
        )
        tracker.setCachedTargetForTesting(target)

        // 11秒后，发生超时
        currentTime = Date(timeIntervalSince1970: 1011)
        let ownApp = NSRunningApplication.current
        let resolved = tracker.resolveTarget(frontmost: ownApp)

        XCTAssertNil(resolved, "超出10秒有效期的缓存目标应自动失效，返回 nil")
    }

    func testTrackerIgnoresSystemUIBundleIdentifiers() {
        let tracker = DestinationApplicationTracker(
            expirationInterval: 10.0,
            additionalExcludedIdentifiers: ["com.test.systemui"]
        )

        // 模拟直接使用已排查的 bundle ID
        let resolved = tracker.resolveTarget(frontmost: NSRunningApplication.current)
        XCTAssertNil(resolved, "自身应用或系统 UI 不应被作为合法前台目标")
    }
}
