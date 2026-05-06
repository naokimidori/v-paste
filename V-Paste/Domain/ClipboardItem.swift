import Foundation

struct ClipboardSourceApplication: Equatable {
    let name: String
    let bundleIdentifier: String?
}

struct ClipboardItem: Identifiable, Equatable {
    private static let maxDisplayTitleLength = 120

    let id: UUID
    let contentType: ClipboardContentType
    let sourceHash: String
    let displayTitle: String
    let plainText: String?
    let urlString: String?
    let fileName: String?
    let filePath: String?
    let assetPath: String?
    let thumbnailPath: String?
    let createdAt: Date
    let lastCopiedAt: Date
    let contentSize: Int?
    let utiTypes: [String]
    let isFavorited: Bool
    let sourceAppName: String?
    let sourceAppBundleIdentifier: String?
    let groupID: UUID?

    init(
        id: UUID,
        contentType: ClipboardContentType,
        sourceHash: String,
        displayTitle: String,
        plainText: String?,
        urlString: String?,
        fileName: String?,
        filePath: String?,
        assetPath: String?,
        thumbnailPath: String?,
        createdAt: Date,
        lastCopiedAt: Date,
        contentSize: Int?,
        utiTypes: [String],
        isFavorited: Bool,
        sourceAppName: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.sourceHash = sourceHash
        self.displayTitle = displayTitle
        self.plainText = plainText
        self.urlString = urlString
        self.fileName = fileName
        self.filePath = filePath
        self.assetPath = assetPath
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.contentSize = contentSize
        self.utiTypes = utiTypes
        self.isFavorited = isFavorited
        self.sourceAppName = sourceAppName
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.groupID = groupID
    }

    var cardPreviewText: String {
        let rawText = plainText ?? displayTitle

        return rawText
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func text(
        plainText: String,
        copiedAt: Date,
        sourceApplication: ClipboardSourceApplication? = nil
    ) -> ClipboardItem {
        let displayTitle = makeDisplayTitle(from: plainText)

        return ClipboardItem(
            id: UUID(),
            contentType: .text,
            sourceHash: plainText,
            displayTitle: displayTitle,
            plainText: plainText,
            urlString: makeURLString(from: plainText),
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: copiedAt,
            lastCopiedAt: copiedAt,
            contentSize: plainText.utf8.count,
            utiTypes: [],
            isFavorited: false,
            sourceAppName: sourceApplication?.name,
            sourceAppBundleIdentifier: sourceApplication?.bundleIdentifier
        )
    }

    func withFavorite(_ isFavorited: Bool) -> ClipboardItem {
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
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            groupID: groupID
        )
    }

    func withGroup(_ groupID: UUID?) -> ClipboardItem {
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
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            groupID: groupID
        )
    }

    func withLinkPreview(
        title: String?,
        assetPath: String?,
        thumbnailPath: String?
    ) -> ClipboardItem {
        let cleanTitle = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let previewTitle: String
        if let cleanTitle, !cleanTitle.isEmpty {
            previewTitle = String(cleanTitle.prefix(Self.maxDisplayTitleLength))
        } else {
            previewTitle = displayTitle
        }

        return ClipboardItem(
            id: id,
            contentType: contentType,
            sourceHash: sourceHash,
            displayTitle: previewTitle,
            plainText: plainText,
            urlString: urlString,
            fileName: fileName,
            filePath: filePath,
            assetPath: assetPath ?? self.assetPath,
            thumbnailPath: thumbnailPath ?? self.thumbnailPath,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            contentSize: contentSize,
            utiTypes: utiTypes,
            isFavorited: isFavorited,
            sourceAppName: sourceAppName,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            groupID: groupID
        )
    }

    private static func makeDisplayTitle(from plainText: String) -> String {
        let title = plainText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Untitled Text"

        return String(title.prefix(maxDisplayTitleLength))
    }

    private static func makeURLString(from plainText: String) -> String? {
        let trimmedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let url = URL(string: trimmedText),
            url.scheme?.isEmpty == false,
            url.host?.isEmpty == false
        else {
            return nil
        }

        return url.absoluteString
    }
}
