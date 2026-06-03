import AppKit
import Carbon
import XCTest
@testable import V_Paste

func makeItem(
    contentType: ClipboardContentType = .text,
    sourceHash: String,
    displayTitle: String,
    plainText: String?,
    fileName: String? = nil,
    urlString: String? = nil,
    isFavorited: Bool = false,
    groupID: UUID? = nil
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        contentType: contentType,
        sourceHash: sourceHash,
        displayTitle: displayTitle,
        plainText: plainText,
        urlString: urlString,
        fileName: fileName,
        filePath: nil,
        assetPath: nil,
        thumbnailPath: nil,
        createdAt: Date(timeIntervalSince1970: 1),
        lastCopiedAt: Date(timeIntervalSince1970: 1),
        contentSize: plainText?.utf8.count,
        utiTypes: [],
        isFavorited: isFavorited,
        groupID: groupID
    )
}
