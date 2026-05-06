import AppKit
import XCTest
@testable import V_Paste

final class ClipboardNormalizerTests: XCTestCase {
    func testLinkMetadataParserExtractsOpenGraphTitleAndShortcutIcon() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/pricing/pro-plan"))
        let html = """
        <html>
          <head>
            <meta property="og:title" content="Example Pricing Portal">
            <link rel="shortcut icon" href="https://example.com/logo.ico" type="image/x-icon">
          </head>
        </html>
        """

        let metadata = LinkMetadataParser.parse(html: html, pageURL: pageURL)

        XCTAssertEqual(metadata.title, "Example Pricing Portal")
        XCTAssertEqual(metadata.iconURL?.absoluteString, "https://example.com/logo.ico")
    }

    func testLinkMetadataParserResolvesRelativeIconAndFallsBackToTitleTag() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/docs/page"))
        let html = """
        <html>
          <head>
            <title>Example Docs</title>
            <link rel="apple-touch-icon" href="/touch-icon.png">
          </head>
        </html>
        """

        let metadata = LinkMetadataParser.parse(html: html, pageURL: pageURL)

        XCTAssertEqual(metadata.title, "Example Docs")
        XCTAssertEqual(metadata.iconURL?.absoluteString, "https://example.com/touch-icon.png")
    }

    func testNormalizePrefersFileURLOverStringPasteboardFlavor() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-normalizer-string"))
        pasteboard.clearContents()
        let fileURL = try makeTemporaryFile(named: "report.txt", contents: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        pasteboard.writeObjects([fileURL as NSURL])
        pasteboard.setString("hello", forType: .string)

        let item = try ClipboardNormalizer(assetCache: .inMemory()).normalize(
            pasteboard: pasteboard,
            copiedAt: Date(timeIntervalSince1970: 5),
            sourceApplication: ClipboardSourceApplication(
                name: "Safari",
                bundleIdentifier: "com.apple.Safari"
            )
        )

        XCTAssertEqual(item?.contentType, .file)
        XCTAssertNil(item?.plainText)
        XCTAssertEqual(item?.displayTitle, "report.txt")
        XCTAssertEqual(item?.fileName, "report.txt")
        XCTAssertEqual(item?.filePath, fileURL.path)
        XCTAssertEqual(item?.sourceHash, fileURL.absoluteString)
        XCTAssertEqual(item?.contentSize, 6)
        XCTAssertEqual(item?.lastCopiedAt, Date(timeIntervalSince1970: 5))
        XCTAssertEqual(item?.sourceAppName, "Safari")
        XCTAssertEqual(item?.sourceAppBundleIdentifier, "com.apple.Safari")
    }

    func testNormalizeFileURLPreservesFileFields() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-normalizer-file"))
        pasteboard.clearContents()
        let fileURL = try makeTemporaryFile(named: "report.txt", contents: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        pasteboard.writeObjects([fileURL as NSURL])

        let item = try ClipboardNormalizer(assetCache: .inMemory()).normalize(
            pasteboard: pasteboard,
            copiedAt: Date(timeIntervalSince1970: 10),
            sourceApplication: ClipboardSourceApplication(
                name: "Finder",
                bundleIdentifier: "com.apple.finder"
            )
        )

        XCTAssertEqual(item?.contentType, .file)
        XCTAssertEqual(item?.displayTitle, "report.txt")
        XCTAssertEqual(item?.fileName, "report.txt")
        XCTAssertEqual(item?.filePath, fileURL.path)
        XCTAssertEqual(item?.sourceHash, fileURL.absoluteString)
        XCTAssertEqual(item?.contentSize, 6)
        XCTAssertEqual(item?.sourceAppName, "Finder")
        XCTAssertEqual(item?.sourceAppBundleIdentifier, "com.apple.finder")
    }

    func testNormalizeImageFileURLUsesImageTypeWhilePreservingFileFields() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-normalizer-image-file"))
        pasteboard.clearContents()
        let fileURL = try makeTemporaryFile(named: "image.png", contents: makeTestPNGData())
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        pasteboard.writeObjects([fileURL as NSURL])

        let item = try ClipboardNormalizer(assetCache: .inMemory()).normalize(
            pasteboard: pasteboard,
            copiedAt: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(item?.contentType, .image)
        XCTAssertEqual(item?.displayTitle, "image.png")
        XCTAssertEqual(item?.fileName, "image.png")
        XCTAssertEqual(item?.filePath, fileURL.path)
        XCTAssertNil(item?.assetPath)
        XCTAssertNotNil(item?.contentSize)
        XCTAssertEqual(item?.sourceHash, fileURL.absoluteString)
    }

    func testNormalizeImageUsesStableSourceHashForIdenticalImageContent() throws {
        let firstPasteboard = NSPasteboard(name: NSPasteboard.Name("test-normalizer-stable-image-1"))
        firstPasteboard.clearContents()
        firstPasteboard.writeObjects([makeTestImage()])
        let secondPasteboard = NSPasteboard(name: NSPasteboard.Name("test-normalizer-stable-image-2"))
        secondPasteboard.clearContents()
        secondPasteboard.writeObjects([makeTestImage()])

        let normalizer = ClipboardNormalizer(assetCache: .inMemory())

        let firstItem = try normalizer.normalize(pasteboard: firstPasteboard)
        let secondItem = try normalizer.normalize(pasteboard: secondPasteboard)

        XCTAssertEqual(firstItem?.contentType, .image)
        XCTAssertEqual(secondItem?.contentType, .image)
        XCTAssertEqual(firstItem?.sourceHash, secondItem?.sourceHash)
    }

    func testNormalizeImageStoresAssetAndThumbnailWithRealCache() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V-PasteTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assetsDirectory = tempDirectory.appendingPathComponent("Assets", isDirectory: true)
        let thumbnailsDirectory = tempDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-normalizer-image"))
        pasteboard.clearContents()
        pasteboard.writeObjects([makeTestImage()])

        let item = try ClipboardNormalizer(
            assetCache: AssetCache(
                assetsDirectoryURL: assetsDirectory,
                thumbnailsDirectoryURL: thumbnailsDirectory
            )
        ).normalize(
            pasteboard: pasteboard,
            copiedAt: Date(timeIntervalSince1970: 15)
        )

        XCTAssertEqual(item?.contentType, .image)
        XCTAssertEqual(item?.displayTitle, "Image")
        XCTAssertNotNil(item?.assetPath)
        XCTAssertNotNil(item?.thumbnailPath)
        let assetPath = try XCTUnwrap(item?.assetPath)
        let thumbnailPath = try XCTUnwrap(item?.thumbnailPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailPath))
        XCTAssertGreaterThan(try Data(contentsOf: URL(fileURLWithPath: assetPath)).count, 0)
        XCTAssertGreaterThan(try Data(contentsOf: URL(fileURLWithPath: thumbnailPath)).count, 0)
    }

    func testStoreImageThrowsWithoutReturningUnwrittenPathsWhenPNGConversionFails() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V-PasteTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assetsDirectory = tempDirectory.appendingPathComponent("Assets", isDirectory: true)
        let thumbnailsDirectory = tempDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let cache = AssetCache(
            assetsDirectoryURL: assetsDirectory,
            thumbnailsDirectoryURL: thumbnailsDirectory
        )
        let unrepresentableImage = UnrepresentableImage(size: NSSize(width: 10, height: 10))

        XCTAssertThrowsError(try cache.storeImage(unrepresentableImage))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assetsDirectory.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: thumbnailsDirectory.path), [])
    }
}

private final class UnrepresentableImage: NSImage {
    override var tiffRepresentation: Data? {
        nil
    }
}

private func makeTestImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 40, height: 20))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 40, height: 20).fill()
    image.unlockFocus()
    return image
}

private func makeTestPNGData() throws -> Data {
    let image = makeTestImage()
    let bitmap = try XCTUnwrap(image.tiffRepresentation).flatMap { NSBitmapImageRep(data: $0) }
    return try XCTUnwrap(bitmap?.representation(using: .png, properties: [:]))
}

private func makeTemporaryFile(named fileName: String, contents: Data) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("V-PasteTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
    try contents.write(to: fileURL)
    return fileURL
}
