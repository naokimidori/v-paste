import XCTest
@testable import V_Paste

final class ClipboardItemTests: XCTestCase {
    func testTextFactoryBuildsSearchableFields() {
        let copiedAt = Date(timeIntervalSince1970: 10)
        let sourceApplication = ClipboardSourceApplication(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )

        let item = ClipboardItem.text(
            plainText: "https://pasteapp.io",
            copiedAt: copiedAt,
            sourceApplication: sourceApplication
        )

        XCTAssertEqual(item.contentType, .text)
        XCTAssertEqual(item.sourceHash, "https://pasteapp.io")
        XCTAssertEqual(item.displayTitle, "https://pasteapp.io")
        XCTAssertEqual(item.plainText, "https://pasteapp.io")
        XCTAssertEqual(item.urlString, "https://pasteapp.io")
        XCTAssertNil(item.fileName)
        XCTAssertNil(item.filePath)
        XCTAssertNil(item.assetPath)
        XCTAssertNil(item.thumbnailPath)
        XCTAssertEqual(item.createdAt, copiedAt)
        XCTAssertEqual(item.lastCopiedAt, copiedAt)
        XCTAssertEqual(item.contentSize, "https://pasteapp.io".utf8.count)
        XCTAssertEqual(item.utiTypes, [])
        XCTAssertFalse(item.isFavorited)
        XCTAssertEqual(item.sourceAppName, "Google Chrome")
        XCTAssertEqual(item.sourceAppBundleIdentifier, "com.google.Chrome")
    }

    func testTextFactoryDoesNotTreatOrdinaryTextAsURL() {
        let item = ClipboardItem.text(
            plainText: "hello",
            copiedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertNil(item.urlString)
    }

    func testTextFactoryUsesFirstNonEmptyTrimmedLineAsDisplayTitle() {
        let item = ClipboardItem.text(
            plainText: "\n\n  First useful line  \nSecond line",
            copiedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(item.displayTitle, "First useful line")
    }

    func testTextFactoryCapsLongFirstLineDisplayTitle() {
        let longLine = String(repeating: "A", count: 121)

        let item = ClipboardItem.text(
            plainText: longLine,
            copiedAt: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(item.displayTitle.count, 120)
        XCTAssertEqual(item.displayTitle, String(repeating: "A", count: 120))
    }

    func testDefaultClipboardGroupUsesEnglishUntitledAndRedColor() {
        let createdAt = Date(timeIntervalSince1970: 50)

        let group = ClipboardGroup.defaultGroup(createdAt: createdAt)

        XCTAssertEqual(group.name, "Untitled")
        XCTAssertEqual(group.colorHex, "#FF5B57")
        XCTAssertEqual(group.createdAt, createdAt)
        XCTAssertEqual(group.sortOrder, 0)
    }

    func testClipboardGroupDefaultNameUsesRequestedLanguage() {
        XCTAssertEqual(ClipboardGroup.defaultName(language: .english), "Untitled")
        XCTAssertEqual(ClipboardGroup.defaultName(language: .simplifiedChinese), "未命名")
    }

    func testClipboardGroupColorPaletteHasSevenColorsAndPicksFirstUnusedColor() {
        XCTAssertEqual(ClipboardGroupColorPalette.hexValues.count, 7)
        XCTAssertEqual(
            ClipboardGroupColorPalette.firstUnusedColor(
                usedColorHexes: [ClipboardGroup.defaultColorHex]
            ),
            ClipboardGroupColorPalette.hexValues[1]
        )
        XCTAssertEqual(
            ClipboardGroupColorPalette.firstUnusedColor(
                usedColorHexes: Set(ClipboardGroupColorPalette.hexValues)
            ),
            ClipboardGroup.defaultColorHex
        )
    }

    func testWithGroupReplacesMembershipWithoutChangingContent() {
        let originalGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let newGroupID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000333")!,
            contentType: .text,
            sourceHash: "source",
            displayTitle: "Title",
            plainText: "Body",
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(timeIntervalSince1970: 60),
            lastCopiedAt: Date(timeIntervalSince1970: 70),
            contentSize: 4,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: true,
            sourceAppName: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            groupID: originalGroupID
        )

        let updated = item.withGroup(newGroupID)

        XCTAssertEqual(updated.groupID, newGroupID)
        XCTAssertEqual(updated.id, item.id)
        XCTAssertEqual(updated.contentType, item.contentType)
        XCTAssertEqual(updated.sourceHash, item.sourceHash)
        XCTAssertEqual(updated.displayTitle, item.displayTitle)
        XCTAssertEqual(updated.plainText, item.plainText)
        XCTAssertEqual(updated.createdAt, item.createdAt)
        XCTAssertEqual(updated.lastCopiedAt, item.lastCopiedAt)
        XCTAssertEqual(updated.isFavorited, item.isFavorited)
        XCTAssertEqual(updated.sourceAppName, item.sourceAppName)
        XCTAssertEqual(updated.sourceAppBundleIdentifier, item.sourceAppBundleIdentifier)
    }

    func testAppPathsCreatesExpectedAppSupportFolders() throws {
        let fileManager = FileManager.default
        let bundleID = "io.vpaste.tests.\(UUID().uuidString)"

        let paths = try AppPaths.make(
            fileManager: fileManager,
            bundleID: bundleID
        )
        defer { try? fileManager.removeItem(at: paths.appSupportDirectoryURL) }

        XCTAssertEqual(paths.databaseURL.lastPathComponent, "history.sqlite3")
        XCTAssertEqual(paths.assetsDirectoryURL.lastPathComponent, "Assets")
        XCTAssertEqual(paths.thumbnailsDirectoryURL.lastPathComponent, "Thumbnails")
        XCTAssertTrue(fileManager.fileExists(atPath: paths.appSupportDirectoryURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.assetsDirectoryURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.thumbnailsDirectoryURL.path))
    }
}
