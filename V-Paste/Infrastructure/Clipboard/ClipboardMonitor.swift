import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pollInterval: TimeInterval
    private let pasteboard: NSPasteboard
    private let now: () -> Date
    private let sourceApplication: () -> ClipboardSourceApplication?
    private let normalize: (NSPasteboard, Date, ClipboardSourceApplication?) throws -> ClipboardItem?
    private var timer: Timer?
    private var lastChangeCount: Int

    var onItem: ((ClipboardItem) -> Void)?
    var onError: ((Error) -> Void)?

    init(
        pollInterval: TimeInterval = 0.3,
        pasteboard: NSPasteboard,
        now: @escaping () -> Date,
        sourceApplication: @escaping () -> ClipboardSourceApplication? = ClipboardSourceApplication.frontmost,
        normalize: @escaping (NSPasteboard, Date, ClipboardSourceApplication?) throws -> ClipboardItem?
    ) {
        self.pollInterval = pollInterval
        self.pasteboard = pasteboard
        self.now = now
        self.sourceApplication = sourceApplication
        self.normalize = normalize
        self.lastChangeCount = pasteboard.changeCount
    }

    convenience init(
        pollInterval: TimeInterval = 0.3,
        pasteboard: NSPasteboard,
        now: @escaping () -> Date,
        normalize: @escaping (NSPasteboard, Date) throws -> ClipboardItem?
    ) {
        self.init(
            pollInterval: pollInterval,
            pasteboard: pasteboard,
            now: now,
            sourceApplication: ClipboardSourceApplication.frontmost
        ) { pasteboard, copiedAt, _ in
            try normalize(pasteboard, copiedAt)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process(changeCount: self.pasteboard.changeCount)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func process(changeCount: Int) {
        guard changeCount != lastChangeCount else { return }

        do {
            if let item = try normalize(pasteboard, now(), sourceApplication()) {
                lastChangeCount = changeCount
                onItem?(item)
            } else {
                lastChangeCount = changeCount
            }
        } catch {
            onError?(error)
        }
    }
}

extension ClipboardSourceApplication {
    static func frontmost() -> ClipboardSourceApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return ClipboardSourceApplication(
            name: application.localizedName ?? "Unknown App",
            bundleIdentifier: application.bundleIdentifier
        )
    }
}
