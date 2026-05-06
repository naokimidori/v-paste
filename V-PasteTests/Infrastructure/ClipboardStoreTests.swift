import XCTest
import SQLite3
@testable import V_Paste

final class ClipboardStoreTests: XCTestCase {
    func testUpsertInsertsTextItemAndFetchRecentRoundTripsFields() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let copiedAt = Date(timeIntervalSince1970: 100)
        let item = ClipboardItem.text(
            plainText: "https://pasteapp.io",
            copiedAt: copiedAt
        )

        let store = try ClipboardStore(paths: paths)
        try store.upsert(item)

        let recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(recent, [item])
        XCTAssertEqual(try store.fetchGroups(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.databaseURL.path))
    }

    func testUpsertUpdatesExistingSourceHashAndFetchesByRecency() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        let original = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceHash: "same-source",
            displayTitle: "Original",
            plainText: "Original body",
            createdAt: Date(timeIntervalSince1970: 100),
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        )
        let updated = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sourceHash: "same-source",
            displayTitle: "Updated",
            plainText: "Updated body",
            createdAt: Date(timeIntervalSince1970: 200),
            lastCopiedAt: Date(timeIntervalSince1970: 300)
        )
        let newerDifferentItem = ClipboardItem.text(
            plainText: "Newest item",
            copiedAt: Date(timeIntervalSince1970: 400)
        )

        try store.upsert(original)
        try store.upsert(newerDifferentItem)
        try store.upsert(updated)

        let recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(recent.map(\.displayTitle), ["Newest item", "Updated"])
        XCTAssertEqual(recent[1].id, original.id)
        XCTAssertEqual(recent[1].createdAt, original.createdAt)
        XCTAssertEqual(recent[1].plainText, "Updated body")
        XCTAssertEqual(recent[1].lastCopiedAt, updated.lastCopiedAt)
    }

    func testSearchMatchesSearchableFieldsCaseInsensitivelyByRecency() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        try store.upsert(makeItem(
            sourceHash: "title-match",
            displayTitle: "Alpha Launch Notes",
            plainText: nil,
            urlString: nil,
            fileName: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        ))
        try store.upsert(makeItem(
            sourceHash: "plain-match",
            displayTitle: "Body",
            plainText: "contains ALPHA text",
            urlString: nil,
            fileName: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 400)
        ))
        try store.upsert(makeItem(
            sourceHash: "url-match",
            displayTitle: "Site",
            plainText: nil,
            urlString: "https://example.com/alpha",
            fileName: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 300)
        ))
        try store.upsert(makeItem(
            sourceHash: "file-match",
            displayTitle: "File",
            plainText: nil,
            urlString: nil,
            fileName: "alpha-report.txt",
            lastCopiedAt: Date(timeIntervalSince1970: 200)
        ))
        try store.upsert(ClipboardItem.text(
            plainText: "unrelated",
            copiedAt: Date(timeIntervalSince1970: 500)
        ))

        let results = try store.search(query: "alpha", limit: 10)

        XCTAssertEqual(results.map(\.sourceHash), [
            "plain-match",
            "url-match",
            "file-match",
            "title-match"
        ])
    }

    func testSearchTreatsPercentAsLiteralCharacter() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        try store.upsert(makeItem(
            sourceHash: "literal-percent",
            displayTitle: "Battery 100%",
            plainText: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        ))
        try store.upsert(makeItem(
            sourceHash: "word-percent",
            displayTitle: "Battery 100 percent",
            plainText: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 200)
        ))
        try store.upsert(makeItem(
            sourceHash: "unrelated",
            displayTitle: "Battery full",
            plainText: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 300)
        ))

        let results = try store.search(query: "%", limit: 10)

        XCTAssertEqual(results.map(\.sourceHash), ["literal-percent"])
    }

    func testSearchTreatsUnderscoreAsLiteralCharacter() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        try store.upsert(makeItem(
            sourceHash: "literal-underscore",
            displayTitle: "build_artifact",
            plainText: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        ))
        try store.upsert(makeItem(
            sourceHash: "hyphenated",
            displayTitle: "build-artifact",
            plainText: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 200)
        ))
        try store.upsert(makeItem(
            sourceHash: "spaced",
            displayTitle: "build artifact",
            plainText: nil,
            lastCopiedAt: Date(timeIntervalSince1970: 300)
        ))

        let results = try store.search(query: "_", limit: 10)

        XCTAssertEqual(results.map(\.sourceHash), ["literal-underscore"])
    }

    func testBootstrapSetsSchemaUserVersionToThreeAndStartsWithoutGroups() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }

        let store = try ClipboardStore(paths: paths)
        let groups = try store.fetchGroups()

        XCTAssertEqual(try userVersion(at: paths.databaseURL), 3)
        XCTAssertEqual(groups, [])
    }

    func testMigratesVersionOneDatabaseAndRoundTripsSourceApplication() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        try makeVersionOneDatabase(at: paths.databaseURL)
        let store = try ClipboardStore(paths: paths)
        let item = makeItem(
            sourceHash: "source-app",
            displayTitle: "Copied from Chrome",
            plainText: "Copied from Chrome",
            lastCopiedAt: Date(timeIntervalSince1970: 100),
            sourceAppName: "Google Chrome",
            sourceAppBundleIdentifier: "com.google.Chrome"
        )

        try store.upsert(item)

        let recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(try userVersion(at: paths.databaseURL), 3)
        XCTAssertEqual(recent.first?.sourceAppName, "Google Chrome")
        XCTAssertEqual(recent.first?.sourceAppBundleIdentifier, "com.google.Chrome")
        XCTAssertNil(recent.first?.groupID)
    }

    func testMigratesVersionTwoDatabaseLeavesExistingItemsUngrouped() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        try makeVersionTwoDatabaseWithItem(at: paths.databaseURL)

        let store = try ClipboardStore(paths: paths)

        let groups = try store.fetchGroups()
        let recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(try userVersion(at: paths.databaseURL), 3)
        XCTAssertEqual(groups, [])
        XCTAssertEqual(recent.map(\.sourceHash), ["v2-source"])
        XCTAssertNil(recent.first?.groupID)
    }

    func testCreatesUpdatesAndFetchesGroupsBySortOrder() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)

        let work = try store.createGroup(name: "Work", colorHex: "#4B8DFF")
        let code = try store.createGroup(name: "Code", colorHex: "#26B36A")
        let renamed = ClipboardGroup(
            id: work.id,
            name: "Clients",
            colorHex: "#8B65FF",
            createdAt: work.createdAt,
            sortOrder: work.sortOrder
        )
        try store.updateGroup(renamed)

        let groups = try store.fetchGroups()
        XCTAssertEqual(groups.map(\.name), ["Clients", "Code"])
        XCTAssertEqual(groups.map(\.sortOrder), [0, 1])
        XCTAssertEqual(groups[0].id, work.id)
        XCTAssertEqual(groups[0].colorHex, "#8B65FF")
        XCTAssertEqual(groups[1].id, code.id)
    }

    func testAssignItemToGroupReplacesPersistedMembership() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        let work = try store.createGroup(name: "Work", colorHex: "#4B8DFF")
        let code = try store.createGroup(name: "Code", colorHex: "#26B36A")
        let item = ClipboardItem.text(
            plainText: "group me",
            copiedAt: Date(timeIntervalSince1970: 100)
        )

        try store.upsert(item)
        try store.assignItem(id: item.id, to: work.id)
        XCTAssertEqual(try store.fetchRecent(limit: 10).first?.groupID, work.id)

        try store.assignItem(id: item.id, to: code.id)
        XCTAssertEqual(try store.fetchRecent(limit: 10).first?.groupID, code.id)
    }

    func testDeleteGroupRemovesGroupAndUngroupsItems() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        let work = try store.createGroup(name: "Work", colorHex: "#4B8DFF")
        let workItem = ClipboardItem.text(
            plainText: "work item",
            copiedAt: Date(timeIntervalSince1970: 100)
        ).withGroup(work.id)
        let ungroupedItem = ClipboardItem.text(
            plainText: "ungrouped item",
            copiedAt: Date(timeIntervalSince1970: 200)
        )

        try store.upsert(workItem)
        try store.upsert(ungroupedItem)

        try store.deleteGroup(id: work.id)

        let groups = try store.fetchGroups()
        let recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(groups, [])
        XCTAssertEqual(recent.map(\.groupID), [nil, nil])
    }

    func testAssetPathsForItemAndDeleteItemRemoveSingleRecord() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        let firstAsset = paths.assetsDirectoryURL.appendingPathComponent("first.png").path
        let firstThumbnail = paths.thumbnailsDirectoryURL.appendingPathComponent("first.png").path
        let first = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            contentType: .image,
            sourceHash: "first-image",
            displayTitle: "First Image",
            plainText: nil,
            assetPath: firstAsset,
            thumbnailPath: firstThumbnail,
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        )
        let second = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            sourceHash: "second",
            displayTitle: "Second",
            plainText: "Second",
            lastCopiedAt: Date(timeIntervalSince1970: 200)
        )
        try store.upsert(first)
        try store.upsert(second)

        XCTAssertEqual(Set(try store.assetPaths(for: first.id)), [firstAsset, firstThumbnail])

        try store.deleteItem(id: first.id)

        XCTAssertEqual(try store.fetchRecent(limit: 10).map(\.id), [second.id])
    }

    func testDeleteItemsOlderThanCutoffUsesLastCopiedAt() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        try store.upsert(ClipboardItem.text(
            plainText: "old",
            copiedAt: Date(timeIntervalSince1970: 100)
        ))
        try store.upsert(ClipboardItem.text(
            plainText: "boundary",
            copiedAt: Date(timeIntervalSince1970: 200)
        ))
        try store.upsert(ClipboardItem.text(
            plainText: "new",
            copiedAt: Date(timeIntervalSince1970: 300)
        ))

        try store.deleteItems(olderThan: Date(timeIntervalSince1970: 200))

        let recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(recent.map(\.displayTitle), ["new", "boundary"])
    }

    func testAssetPathsForItemsOlderThanCutoffReturnsOnlyExpiredCacheReferences() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        try store.upsert(makeItem(
            contentType: .image,
            sourceHash: "old-image",
            displayTitle: "Old Image",
            plainText: nil,
            assetPath: paths.assetsDirectoryURL.appendingPathComponent("old.png").path,
            thumbnailPath: paths.thumbnailsDirectoryURL.appendingPathComponent("old.png").path,
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        ))
        try store.upsert(makeItem(
            contentType: .image,
            sourceHash: "new-image",
            displayTitle: "New Image",
            plainText: nil,
            assetPath: paths.assetsDirectoryURL.appendingPathComponent("new.png").path,
            thumbnailPath: paths.thumbnailsDirectoryURL.appendingPathComponent("new.png").path,
            lastCopiedAt: Date(timeIntervalSince1970: 300)
        ))

        let pathsForDeletion = try store.assetPathsForItems(
            olderThan: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(Set(pathsForDeletion), [
            paths.assetsDirectoryURL.appendingPathComponent("old.png").path,
            paths.thumbnailsDirectoryURL.appendingPathComponent("old.png").path
        ])
    }

    func testDeleteAllRemovesStoredHistory() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        try store.upsert(ClipboardItem.text(
            plainText: "first",
            copiedAt: Date(timeIntervalSince1970: 100)
        ))
        try store.upsert(ClipboardItem.text(
            plainText: "second",
            copiedAt: Date(timeIntervalSince1970: 200)
        ))

        try store.deleteAll()

        XCTAssertEqual(try store.fetchRecent(limit: 10), [])
    }

    func testSetFavoritePersistsFlagWithoutChangingRecency() throws {
        let paths = try makeTemporaryPaths()
        defer { removeTemporaryPaths(paths) }
        let store = try ClipboardStore(paths: paths)
        let older = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            sourceHash: "older",
            displayTitle: "Older",
            plainText: "Older",
            lastCopiedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            sourceHash: "newer",
            displayTitle: "Newer",
            plainText: "Newer",
            lastCopiedAt: Date(timeIntervalSince1970: 200)
        )

        try store.upsert(older)
        try store.upsert(newer)
        try store.setFavorite(id: older.id, isFavorited: true)

        var recent = try store.fetchRecent(limit: 10)
        XCTAssertEqual(recent.map(\.id), [newer.id, older.id])
        XCTAssertFalse(recent[0].isFavorited)
        XCTAssertTrue(recent[1].isFavorited)

        try store.setFavorite(id: older.id, isFavorited: false)

        recent = try store.fetchRecent(limit: 10)
        XCTAssertFalse(recent[1].isFavorited)
    }
}

private func makeTemporaryPaths() throws -> AppPaths {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("V-PasteTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let assetsDirectory = tempDirectory.appendingPathComponent(
        "Assets",
        isDirectory: true
    )
    let thumbnailsDirectory = tempDirectory.appendingPathComponent(
        "Thumbnails",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: assetsDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: thumbnailsDirectory,
        withIntermediateDirectories: true
    )

    return AppPaths(
        appSupportDirectoryURL: tempDirectory,
        databaseURL: tempDirectory.appendingPathComponent("history.sqlite3"),
        assetsDirectoryURL: assetsDirectory,
        thumbnailsDirectoryURL: thumbnailsDirectory
    )
}

private func removeTemporaryPaths(_ paths: AppPaths) {
    try? FileManager.default.removeItem(at: paths.appSupportDirectoryURL)
}

private func userVersion(at databaseURL: URL) throws -> Int {
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
    defer {
        if let database {
            sqlite3_close(database)
        }
    }

    var statement: OpaquePointer?
    XCTAssertEqual(
        sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil),
        SQLITE_OK
    )
    defer {
        if let statement {
            sqlite3_finalize(statement)
        }
    }

    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    return Int(sqlite3_column_int(statement, 0))
}

private func makeVersionOneDatabase(at databaseURL: URL) throws {
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
    defer {
        if let database {
            sqlite3_close(database)
        }
    }

    let sql = """
    CREATE TABLE clipboard_items (
        id TEXT PRIMARY KEY NOT NULL,
        content_type TEXT NOT NULL,
        source_hash TEXT NOT NULL UNIQUE,
        display_title TEXT NOT NULL,
        plain_text TEXT,
        url_string TEXT,
        file_name TEXT,
        file_path TEXT,
        asset_path TEXT,
        thumbnail_path TEXT,
        created_at REAL NOT NULL,
        last_copied_at REAL NOT NULL,
        content_size INTEGER,
        uti_types TEXT NOT NULL,
        is_favorited INTEGER NOT NULL DEFAULT 0
    );
    PRAGMA user_version = 1;
    """
    XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
}

private func makeVersionTwoDatabaseWithItem(at databaseURL: URL) throws {
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
    defer {
        if let database {
            sqlite3_close(database)
        }
    }

    let sql = """
    CREATE TABLE clipboard_items (
        id TEXT PRIMARY KEY NOT NULL,
        content_type TEXT NOT NULL,
        source_hash TEXT NOT NULL UNIQUE,
        display_title TEXT NOT NULL,
        plain_text TEXT,
        url_string TEXT,
        file_name TEXT,
        file_path TEXT,
        asset_path TEXT,
        thumbnail_path TEXT,
        created_at REAL NOT NULL,
        last_copied_at REAL NOT NULL,
        content_size INTEGER,
        uti_types TEXT NOT NULL,
        is_favorited INTEGER NOT NULL DEFAULT 0,
        source_app_name TEXT,
        source_app_bundle_identifier TEXT
    );
    INSERT INTO clipboard_items (
        id,
        content_type,
        source_hash,
        display_title,
        plain_text,
        created_at,
        last_copied_at,
        uti_types,
        is_favorited
    ) VALUES (
        '00000000-0000-0000-0000-000000000301',
        'text',
        'v2-source',
        'Migrated Item',
        'Migrated Item',
        100,
        100,
        '[]',
        0
    );
    PRAGMA user_version = 2;
    """
    XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
}

private func makeItem(
    id: UUID = UUID(),
    contentType: ClipboardContentType = .text,
    sourceHash: String,
    displayTitle: String,
    plainText: String?,
    urlString: String? = nil,
    fileName: String? = nil,
    filePath: String? = nil,
    assetPath: String? = nil,
    thumbnailPath: String? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date,
    contentSize: Int? = nil,
    utiTypes: [String] = [],
    isFavorited: Bool = false,
    sourceAppName: String? = nil,
    sourceAppBundleIdentifier: String? = nil
) -> ClipboardItem {
    ClipboardItem(
        id: id,
        contentType: contentType,
        sourceHash: sourceHash,
        displayTitle: displayTitle,
        plainText: plainText,
        urlString: urlString,
        fileName: fileName,
        filePath: filePath,
        assetPath: assetPath,
        thumbnailPath: thumbnailPath,
        createdAt: createdAt,
        lastCopiedAt: lastCopiedAt,
        contentSize: contentSize,
        utiTypes: utiTypes,
        isFavorited: isFavorited,
        sourceAppName: sourceAppName,
        sourceAppBundleIdentifier: sourceAppBundleIdentifier
    )
}
