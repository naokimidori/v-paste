import Foundation
import SQLite3

enum ClipboardStoreError: Error, Equatable {
    case invalidLimit
    case invalidStoredItem(String)
    case unsupportedSchemaVersion(Int)
}

final class ClipboardStore {
    private static let schemaVersion = 3
    private static let likeEscapeCharacter: Character = "\\"

    private let database: SQLiteDatabase
    private let transientDestructor = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    init(paths: AppPaths) throws {
        try FileManager.default.createDirectory(
            at: paths.appSupportDirectoryURL,
            withIntermediateDirectories: true
        )
        database = try SQLiteDatabase(url: paths.databaseURL)
        try bootstrapSchema()
    }

    func upsert(_ item: ClipboardItem) throws {
        let sql = """
        INSERT INTO clipboard_items (
            id,
            content_type,
            source_hash,
            display_title,
            plain_text,
            url_string,
            file_name,
            file_path,
            asset_path,
            thumbnail_path,
            created_at,
            last_copied_at,
            content_size,
            uti_types,
            is_favorited,
            source_app_name,
            source_app_bundle_identifier,
            group_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_hash) DO UPDATE SET
            content_type = excluded.content_type,
            display_title = excluded.display_title,
            plain_text = excluded.plain_text,
            url_string = excluded.url_string,
            file_name = excluded.file_name,
            file_path = excluded.file_path,
            asset_path = excluded.asset_path,
            thumbnail_path = excluded.thumbnail_path,
            last_copied_at = excluded.last_copied_at,
            content_size = excluded.content_size,
            uti_types = excluded.uti_types,
            source_app_name = excluded.source_app_name,
            source_app_bundle_identifier = excluded.source_app_bundle_identifier;
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(item.id.uuidString, to: 1, in: statement)
        try bind(item.contentType.rawValue, to: 2, in: statement)
        try bind(item.sourceHash, to: 3, in: statement)
        try bind(item.displayTitle, to: 4, in: statement)
        try bind(item.plainText, to: 5, in: statement)
        try bind(item.urlString, to: 6, in: statement)
        try bind(item.fileName, to: 7, in: statement)
        try bind(item.filePath, to: 8, in: statement)
        try bind(item.assetPath, to: 9, in: statement)
        try bind(item.thumbnailPath, to: 10, in: statement)
        try bind(item.createdAt, to: 11, in: statement)
        try bind(item.lastCopiedAt, to: 12, in: statement)
        try bind(item.contentSize, to: 13, in: statement)
        try bind(encodeUTITypes(item.utiTypes), to: 14, in: statement)
        try bind(item.isFavorited, to: 15, in: statement)
        try bind(item.sourceAppName, to: 16, in: statement)
        try bind(item.sourceAppBundleIdentifier, to: 17, in: statement)
        try bind(item.groupID?.uuidString, to: 18, in: statement)
        try stepDone(statement)
    }

    func fetchRecent(limit: Int) throws -> [ClipboardItem] {
        try validate(limit: limit)
        let statement = try database.prepare("""
        SELECT
            id,
            content_type,
            source_hash,
            display_title,
            plain_text,
            url_string,
            file_name,
            file_path,
            asset_path,
            thumbnail_path,
            created_at,
            last_copied_at,
            content_size,
            uti_types,
            is_favorited,
            source_app_name,
            source_app_bundle_identifier,
            group_id
        FROM clipboard_items
        ORDER BY last_copied_at DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(limit, to: 1, in: statement)
        return try fetchItems(from: statement)
    }

    func search(query: String, limit: Int) throws -> [ClipboardItem] {
        try validate(limit: limit)
        let statement = try database.prepare("""
        SELECT
            id,
            content_type,
            source_hash,
            display_title,
            plain_text,
            url_string,
            file_name,
            file_path,
            asset_path,
            thumbnail_path,
            created_at,
            last_copied_at,
            content_size,
            uti_types,
            is_favorited,
            source_app_name,
            source_app_bundle_identifier,
            group_id
        FROM clipboard_items
        WHERE display_title COLLATE NOCASE LIKE ? ESCAPE '\\'
           OR plain_text COLLATE NOCASE LIKE ? ESCAPE '\\'
           OR url_string COLLATE NOCASE LIKE ? ESCAPE '\\'
           OR file_name COLLATE NOCASE LIKE ? ESCAPE '\\'
           OR source_app_name COLLATE NOCASE LIKE ? ESCAPE '\\'
        ORDER BY last_copied_at DESC
        LIMIT ?;
        """)
        defer { sqlite3_finalize(statement) }

        let pattern = escapedLikePattern(for: query)
        try bind(pattern, to: 1, in: statement)
        try bind(pattern, to: 2, in: statement)
        try bind(pattern, to: 3, in: statement)
        try bind(pattern, to: 4, in: statement)
        try bind(pattern, to: 5, in: statement)
        try bind(limit, to: 6, in: statement)
        return try fetchItems(from: statement)
    }

    func deleteItems(olderThan cutoff: Date) throws {
        let statement = try database.prepare("""
        DELETE FROM clipboard_items
        WHERE last_copied_at < ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(cutoff, to: 1, in: statement)
        try stepDone(statement)
    }

    func assetPathsForItems(olderThan cutoff: Date) throws -> [String] {
        let statement = try database.prepare("""
        SELECT asset_path, thumbnail_path
        FROM clipboard_items
        WHERE last_copied_at < ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(cutoff, to: 1, in: statement)

        var paths: [String] = []
        while true {
            let result = sqlite3_step(statement)

            switch result {
            case SQLITE_ROW:
                if let assetPath = optionalText(at: 0, in: statement) {
                    paths.append(assetPath)
                }
                if let thumbnailPath = optionalText(at: 1, in: statement) {
                    paths.append(thumbnailPath)
                }
            case SQLITE_DONE:
                return paths
            default:
                throw SQLiteDatabaseError.stepFailed(
                    String(cString: sqlite3_errmsg(database.handle))
                )
            }
        }
    }

    func assetPaths(for id: UUID) throws -> [String] {
        let statement = try database.prepare("""
        SELECT asset_path, thumbnail_path
        FROM clipboard_items
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, to: 1, in: statement)

        var paths: [String] = []
        while true {
            let result = sqlite3_step(statement)

            switch result {
            case SQLITE_ROW:
                if let assetPath = optionalText(at: 0, in: statement) {
                    paths.append(assetPath)
                }
                if let thumbnailPath = optionalText(at: 1, in: statement) {
                    paths.append(thumbnailPath)
                }
            case SQLITE_DONE:
                return paths
            default:
                throw SQLiteDatabaseError.stepFailed(
                    String(cString: sqlite3_errmsg(database.handle))
                )
            }
        }
    }

    func deleteAll() throws {
        try database.execute("DELETE FROM clipboard_items;")
    }

    func deleteItem(id: UUID) throws {
        let statement = try database.prepare("""
        DELETE FROM clipboard_items
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, to: 1, in: statement)
        try stepDone(statement)
    }

    func setFavorite(id: UUID, isFavorited: Bool) throws {
        let statement = try database.prepare("""
        UPDATE clipboard_items
        SET is_favorited = ?
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(isFavorited, to: 1, in: statement)
        try bind(id.uuidString, to: 2, in: statement)
        try stepDone(statement)
    }

    func fetchGroups() throws -> [ClipboardGroup] {
        let statement = try database.prepare("""
        SELECT id, name, color_hex, created_at, sort_order
        FROM clipboard_groups
        ORDER BY sort_order ASC, created_at ASC;
        """)
        defer { sqlite3_finalize(statement) }

        var groups: [ClipboardGroup] = []
        while true {
            let result = sqlite3_step(statement)

            switch result {
            case SQLITE_ROW:
                groups.append(try group(from: statement))
            case SQLITE_DONE:
                return groups
            default:
                throw SQLiteDatabaseError.stepFailed(
                    String(cString: sqlite3_errmsg(database.handle))
                )
            }
        }
    }

    func createGroup(name: String, colorHex: String) throws -> ClipboardGroup {
        let group = ClipboardGroup(
            name: name,
            colorHex: colorHex,
            createdAt: Date(),
            sortOrder: try nextGroupSortOrder()
        )

        try insert(group)
        return group
    }

    func updateGroup(_ group: ClipboardGroup) throws {
        let statement = try database.prepare("""
        UPDATE clipboard_groups
        SET name = ?,
            color_hex = ?,
            sort_order = ?
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(group.name, to: 1, in: statement)
        try bind(group.colorHex, to: 2, in: statement)
        try bind(group.sortOrder, to: 3, in: statement)
        try bind(group.id.uuidString, to: 4, in: statement)
        try stepDone(statement)
    }

    func deleteGroup(id groupID: UUID) throws {
        try database.execute("BEGIN IMMEDIATE;")

        do {
            try clearGroupMembership(for: groupID)
            try deleteGroupRow(id: groupID)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    func assignItem(id: UUID, to groupID: UUID) throws {
        let statement = try database.prepare("""
        UPDATE clipboard_items
        SET group_id = ?
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(groupID.uuidString, to: 1, in: statement)
        try bind(id.uuidString, to: 2, in: statement)
        try stepDone(statement)
    }

    private func clearGroupMembership(for groupID: UUID) throws {
        let statement = try database.prepare("""
        UPDATE clipboard_items
        SET group_id = NULL
        WHERE group_id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(groupID.uuidString, to: 1, in: statement)
        try stepDone(statement)
    }

    private func deleteGroupRow(id groupID: UUID) throws {
        let statement = try database.prepare("""
        DELETE FROM clipboard_groups
        WHERE id = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bind(groupID.uuidString, to: 1, in: statement)
        try stepDone(statement)
    }

    private func bootstrapSchema() throws {
        var currentVersion = try schemaVersion()
        guard currentVersion <= Self.schemaVersion else {
            throw ClipboardStoreError.unsupportedSchemaVersion(currentVersion)
        }

        guard currentVersion > 0 else {
            try createSchema()
            return
        }

        if currentVersion == 1 {
            try migrateSchemaFromOneToTwo()
            currentVersion = 2
        }

        if currentVersion == 2 {
            try migrateSchemaFromTwoToThree()
        }
    }

    private func createSchema() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS clipboard_groups (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            color_hex TEXT NOT NULL,
            created_at REAL NOT NULL,
            sort_order INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS clipboard_items (
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
            source_app_bundle_identifier TEXT,
            group_id TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_clipboard_groups_sort_order
        ON clipboard_groups(sort_order ASC);

        CREATE INDEX IF NOT EXISTS idx_clipboard_items_last_copied_at
        ON clipboard_items(last_copied_at DESC);

        CREATE INDEX IF NOT EXISTS idx_clipboard_items_display_title
        ON clipboard_items(display_title COLLATE NOCASE);

        CREATE INDEX IF NOT EXISTS idx_clipboard_items_plain_text
        ON clipboard_items(plain_text COLLATE NOCASE);

        PRAGMA user_version = 3;
        """)
    }

    private func migrateSchemaFromOneToTwo() throws {
        try database.execute("""
        ALTER TABLE clipboard_items ADD COLUMN source_app_name TEXT;
        ALTER TABLE clipboard_items ADD COLUMN source_app_bundle_identifier TEXT;
        PRAGMA user_version = 2;
        """)
    }

    private func migrateSchemaFromTwoToThree() throws {
        try createGroupsTableIfNeeded()
        try database.execute("""
        ALTER TABLE clipboard_items ADD COLUMN group_id TEXT;
        PRAGMA user_version = 3;
        """)
    }

    private func createGroupsTableIfNeeded() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS clipboard_groups (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            color_hex TEXT NOT NULL,
            created_at REAL NOT NULL,
            sort_order INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_clipboard_groups_sort_order
        ON clipboard_groups(sort_order ASC);
        """)
    }

    private func schemaVersion() throws -> Int {
        let statement = try database.prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(
                String(cString: sqlite3_errmsg(database.handle))
            )
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private func escapedLikePattern(for query: String) -> String {
        var escaped = "%"

        for character in query {
            if character == Self.likeEscapeCharacter
                || character == "%"
                || character == "_" {
                escaped.append(Self.likeEscapeCharacter)
            }
            escaped.append(character)
        }

        escaped.append("%")
        return escaped
    }

    private func fetchItems(from statement: OpaquePointer) throws -> [ClipboardItem] {
        var items: [ClipboardItem] = []

        while true {
            let result = sqlite3_step(statement)

            switch result {
            case SQLITE_ROW:
                items.append(try item(from: statement))
            case SQLITE_DONE:
                return items
            default:
                throw SQLiteDatabaseError.stepFailed(
                    String(cString: sqlite3_errmsg(database.handle))
                )
            }
        }
    }

    private func item(from statement: OpaquePointer) throws -> ClipboardItem {
        guard
            let id = UUID(uuidString: try requiredText(at: 0, in: statement)),
            let contentType = ClipboardContentType(
                rawValue: try requiredText(at: 1, in: statement)
            )
        else {
            throw ClipboardStoreError.invalidStoredItem("Invalid id or content type")
        }

        return ClipboardItem(
            id: id,
            contentType: contentType,
            sourceHash: try requiredText(at: 2, in: statement),
            displayTitle: try requiredText(at: 3, in: statement),
            plainText: optionalText(at: 4, in: statement),
            urlString: optionalText(at: 5, in: statement),
            fileName: optionalText(at: 6, in: statement),
            filePath: optionalText(at: 7, in: statement),
            assetPath: optionalText(at: 8, in: statement),
            thumbnailPath: optionalText(at: 9, in: statement),
            createdAt: date(at: 10, in: statement),
            lastCopiedAt: date(at: 11, in: statement),
            contentSize: optionalInt(at: 12, in: statement),
            utiTypes: try decodeUTITypes(try requiredText(at: 13, in: statement)),
            isFavorited: sqlite3_column_int(statement, 14) != 0,
            sourceAppName: optionalText(at: 15, in: statement),
            sourceAppBundleIdentifier: optionalText(at: 16, in: statement),
            groupID: try optionalUUID(at: 17, in: statement)
        )
    }

    private func group(from statement: OpaquePointer) throws -> ClipboardGroup {
        guard let id = UUID(uuidString: try requiredText(at: 0, in: statement)) else {
            throw ClipboardStoreError.invalidStoredItem("Invalid group id")
        }

        return ClipboardGroup(
            id: id,
            name: try requiredText(at: 1, in: statement),
            colorHex: try requiredText(at: 2, in: statement),
            createdAt: date(at: 3, in: statement),
            sortOrder: Int(sqlite3_column_int64(statement, 4))
        )
    }

    private func requiredText(
        at index: Int32,
        in statement: OpaquePointer
    ) throws -> String {
        guard let value = optionalText(at: index, in: statement) else {
            throw ClipboardStoreError.invalidStoredItem(
                "Missing text at column \(index)"
            )
        }

        return value
    }

    private func optionalText(
        at index: Int32,
        in statement: OpaquePointer
    ) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: text)
    }

    private func optionalInt(
        at index: Int32,
        in statement: OpaquePointer
    ) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return Int(sqlite3_column_int64(statement, index))
    }

    private func optionalUUID(
        at index: Int32,
        in statement: OpaquePointer
    ) throws -> UUID? {
        guard let text = optionalText(at: index, in: statement) else { return nil }

        guard let uuid = UUID(uuidString: text) else {
            throw ClipboardStoreError.invalidStoredItem("Invalid UUID at column \(index)")
        }

        return uuid
    }

    private func date(at index: Int32, in statement: OpaquePointer) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func bind(
        _ value: String?,
        to index: Int32,
        in statement: OpaquePointer
    ) throws {
        let result: Int32

        if let value {
            result = sqlite3_bind_text(
                statement,
                index,
                value,
                -1,
                transientDestructor
            )
        } else {
            result = sqlite3_bind_null(statement, index)
        }

        try validateBind(result)
    }

    private func bind(
        _ value: Date,
        to index: Int32,
        in statement: OpaquePointer
    ) throws {
        try validateBind(
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        )
    }

    private func bind(
        _ value: Int?,
        to index: Int32,
        in statement: OpaquePointer
    ) throws {
        let result: Int32

        if let value {
            result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            result = sqlite3_bind_null(statement, index)
        }

        try validateBind(result)
    }

    private func nextGroupSortOrder() throws -> Int {
        let statement = try database.prepare("""
        SELECT COALESCE(MAX(sort_order), -1) + 1
        FROM clipboard_groups;
        """)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(
                String(cString: sqlite3_errmsg(database.handle))
            )
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func insert(_ group: ClipboardGroup) throws {
        let statement = try database.prepare("""
        INSERT INTO clipboard_groups (
            id,
            name,
            color_hex,
            created_at,
            sort_order
        ) VALUES (?, ?, ?, ?, ?);
        """)
        defer { sqlite3_finalize(statement) }

        try bind(group.id.uuidString, to: 1, in: statement)
        try bind(group.name, to: 2, in: statement)
        try bind(group.colorHex, to: 3, in: statement)
        try bind(group.createdAt, to: 4, in: statement)
        try bind(group.sortOrder, to: 5, in: statement)
        try stepDone(statement)
    }

    private func bind(
        _ value: Bool,
        to index: Int32,
        in statement: OpaquePointer
    ) throws {
        try validateBind(sqlite3_bind_int(statement, index, value ? 1 : 0))
    }

    private func validateBind(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SQLiteDatabaseError.stepFailed(
                String(cString: sqlite3_errmsg(database.handle))
            )
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteDatabaseError.stepFailed(
                String(cString: sqlite3_errmsg(database.handle))
            )
        }
    }

    private func validate(limit: Int) throws {
        guard limit >= 0 else {
            throw ClipboardStoreError.invalidLimit
        }
    }

    private func encodeUTITypes(_ utiTypes: [String]) throws -> String {
        let data = try JSONEncoder().encode(utiTypes)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeUTITypes(_ text: String) throws -> [String] {
        guard let data = text.data(using: .utf8) else {
            throw ClipboardStoreError.invalidStoredItem("Invalid UTI JSON")
        }

        return try JSONDecoder().decode([String].self, from: data)
    }
}
