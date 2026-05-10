import AppKit
import XCTest
@testable import V_Paste

private enum MonitorTestError: Error, Equatable {
    case normalizeFailed
}

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testMonitorIgnoresCurrentPasteboardChangeCountAfterInitialization() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-monitor-initial-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("existing", forType: .string)
        let initialChangeCount = pasteboard.changeCount
        var normalizeCallCount = 0
        let monitor = ClipboardMonitor(
            pollInterval: 0.01,
            pasteboard: pasteboard,
            now: { Date(timeIntervalSince1970: 1) },
            normalize: { _, _ in
                normalizeCallCount += 1
                return .text(plainText: "copy", copiedAt: Date(timeIntervalSince1970: 1))
            }
        )

        monitor.process(changeCount: initialChangeCount)

        XCTAssertEqual(normalizeCallCount, 0)
    }

    func testMonitorEmitsOnceWhenSameChangeCountIsProcessedTwice() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-monitor-repeat-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let repeatedChangeCount = pasteboard.changeCount + 1
        let monitor = ClipboardMonitor(
            pollInterval: 0.01,
            pasteboard: pasteboard,
            now: { Date(timeIntervalSince1970: 1) },
            normalize: { _, copiedAt in .text(plainText: "copy", copiedAt: copiedAt) }
        )
        var received: [ClipboardItem] = []
        monitor.onItem = { received.append($0) }

        monitor.process(changeCount: repeatedChangeCount)
        monitor.process(changeCount: repeatedChangeCount)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.plainText, "copy")
        XCTAssertEqual(received.first?.lastCopiedAt, Date(timeIntervalSince1970: 1))
    }

    func testMonitorReportsErrorAndRetriesSameChangeCountAfterNormalizeFailure() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-monitor-error-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let changedCount = pasteboard.changeCount + 1
        var shouldThrow = true
        let monitor = ClipboardMonitor(
            pollInterval: 0.01,
            pasteboard: pasteboard,
            now: { Date(timeIntervalSince1970: 1) },
            normalize: { _, copiedAt in
                if shouldThrow {
                    shouldThrow = false
                    throw MonitorTestError.normalizeFailed
                }
                return .text(plainText: "retry", copiedAt: copiedAt)
            }
        )
        var errors: [MonitorTestError] = []
        var received: [ClipboardItem] = []
        monitor.onError = { error in errors.append(error as! MonitorTestError) }
        monitor.onItem = { received.append($0) }

        monitor.process(changeCount: changedCount)
        monitor.process(changeCount: changedCount)

        XCTAssertEqual(errors, [.normalizeFailed])
        XCTAssertEqual(received.map(\.plainText), ["retry"])
    }

    func testMonitorDoesNotRepeatUnsupportedContentForSameChangeCount() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-monitor-nil-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let changedCount = pasteboard.changeCount + 1
        var normalizeCallCount = 0
        let monitor = ClipboardMonitor(
            pollInterval: 0.01,
            pasteboard: pasteboard,
            now: { Date(timeIntervalSince1970: 1) },
            normalize: { _, _ in
                normalizeCallCount += 1
                return nil
            }
        )

        monitor.process(changeCount: changedCount)
        monitor.process(changeCount: changedCount)

        XCTAssertEqual(normalizeCallCount, 1)
    }

    func testMonitorPassesSourceApplicationToNormalizer() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-monitor-source-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let changedCount = pasteboard.changeCount + 1
        let sourceApplication = ClipboardSourceApplication(
            name: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )
        var capturedSourceApplication: ClipboardSourceApplication?
        let monitor = ClipboardMonitor(
            pollInterval: 0.01,
            pasteboard: pasteboard,
            now: { Date(timeIntervalSince1970: 1) },
            sourceApplication: { sourceApplication },
            normalize: { _, _, sourceApplication in
                capturedSourceApplication = sourceApplication
                return .text(
                    plainText: "copy",
                    copiedAt: Date(timeIntervalSince1970: 1),
                    sourceApplication: sourceApplication
                )
            }
        )

        monitor.process(changeCount: changedCount)

        XCTAssertEqual(capturedSourceApplication, sourceApplication)
    }

    func testMonitorSuppressesIgnoredSourceApplicationAndAdvancesChangeCount() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-monitor-ignored-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let changedCount = pasteboard.changeCount + 1
        let sourceApplication = ClipboardSourceApplication(
            name: "Keychain Access",
            bundleIdentifier: "com.apple.keychainaccess"
        )
        var normalizeCallCount = 0
        let monitor = ClipboardMonitor(
            pollInterval: 0.01,
            pasteboard: pasteboard,
            now: { Date(timeIntervalSince1970: 1) },
            sourceApplication: { sourceApplication },
            isSourceApplicationIgnored: { application in
                IgnoredApplicationRule.defaultRules.contains { rule in
                    rule.matches(application)
                }
            },
            normalize: { _, _, _ in
                normalizeCallCount += 1
                return .text(
                    plainText: "secret",
                    copiedAt: Date(timeIntervalSince1970: 1)
                )
            }
        )
        var received: [ClipboardItem] = []
        monitor.onItem = { received.append($0) }

        monitor.process(changeCount: changedCount)
        monitor.process(changeCount: changedCount)

        XCTAssertEqual(normalizeCallCount, 0)
        XCTAssertTrue(received.isEmpty)
    }
}
