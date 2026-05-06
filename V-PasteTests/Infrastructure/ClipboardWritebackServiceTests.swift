import AppKit
import XCTest
@testable import V_Paste

final class ClipboardWritebackServiceTests: XCTestCase {
    func testWritebackRestoresStringToPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-writeback-string"))
        let item = ClipboardItem.text(plainText: "round trip", copiedAt: Date())

        try ClipboardWritebackService().write(item: item, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "round trip")
    }

    func testWritebackRestoresFileURLToPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-writeback-file"))
        let fileURL = try makeTemporaryWritebackFile(named: "report.txt")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let item = ClipboardItem(
            id: UUID(),
            contentType: .file,
            sourceHash: fileURL.absoluteString,
            displayTitle: "report.txt",
            plainText: nil,
            urlString: nil,
            fileName: "report.txt",
            filePath: fileURL.path,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            lastCopiedAt: Date(timeIntervalSince1970: 0),
            contentSize: nil,
            utiTypes: [],
            isFavorited: false
        )

        try ClipboardWritebackService().write(item: item, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.first?.path, fileURL.path)
    }

    func testWritebackImageFileItemRestoresFileURLToPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-writeback-image-file"))
        let fileURL = try makeTemporaryWritebackFile(named: "preview.png")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let item = ClipboardItem(
            id: UUID(),
            contentType: .image,
            sourceHash: fileURL.absoluteString,
            displayTitle: "preview.png",
            plainText: nil,
            urlString: fileURL.absoluteString,
            fileName: "preview.png",
            filePath: fileURL.path,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            lastCopiedAt: Date(timeIntervalSince1970: 0),
            contentSize: nil,
            utiTypes: [],
            isFavorited: false
        )

        try ClipboardWritebackService().write(item: item, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.first?.path, fileURL.path)
    }

    func testWritebackMissingImageAssetThrowsAndPreservesPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-writeback-missing-image"))
        pasteboard.clearContents()
        pasteboard.setString("stale", forType: .string)
        XCTAssertEqual(pasteboard.string(forType: .string), "stale")
        let item = ClipboardItem(
            id: UUID(),
            contentType: .image,
            sourceHash: "image-missing",
            displayTitle: "Image",
            plainText: nil,
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: "/tmp/does-not-exist-v-paste-image.png",
            thumbnailPath: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            lastCopiedAt: Date(timeIntervalSince1970: 0),
            contentSize: nil,
            utiTypes: [],
            isFavorited: false
        )

        XCTAssertThrowsError(try ClipboardWritebackService().write(item: item, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "stale")
    }
}

private func makeTemporaryWritebackFile(named fileName: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("V-PasteTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
    try Data("report".utf8).write(to: fileURL)
    return fileURL
}
