import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

final class ClipboardNormalizer {
    private let assetCache: AssetCache

    init(assetCache: AssetCache) {
        self.assetCache = assetCache
    }

    func normalize(
        pasteboard: NSPasteboard,
        copiedAt: Date = Date(),
        sourceApplication: ClipboardSourceApplication? = nil
    ) throws -> ClipboardItem? {
        if let fileURL = fileURL(from: pasteboard) {
            return makeFileItem(
                from: fileURL,
                copiedAt: copiedAt,
                sourceApplication: sourceApplication
            )
        }

        if let string = pasteboard.string(forType: .string) {
            return .text(
                plainText: string,
                copiedAt: copiedAt,
                sourceApplication: sourceApplication
            )
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return try makeImageItem(
                from: image,
                copiedAt: copiedAt,
                sourceApplication: sourceApplication
            )
        }

        return nil
    }

    private func makeImageItem(
        from image: NSImage,
        copiedAt: Date,
        sourceApplication: ClipboardSourceApplication?
    ) throws -> ClipboardItem {
        let id = UUID()
        let imageData = try pngData(from: image)
        let paths = try assetCache.storeImage(image, id: id)

        return ClipboardItem(
            id: id,
            contentType: .image,
            sourceHash: stableSourceHash(from: imageData),
            displayTitle: "Image",
            plainText: nil,
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: paths.assetPath,
            thumbnailPath: paths.thumbnailPath,
            createdAt: copiedAt,
            lastCopiedAt: copiedAt,
            contentSize: nil,
            utiTypes: [],
            isFavorited: false,
            sourceAppName: sourceApplication?.name,
            sourceAppBundleIdentifier: sourceApplication?.bundleIdentifier
        )
    }

    private func makeFileItem(
        from fileURL: URL,
        copiedAt: Date,
        sourceApplication: ClipboardSourceApplication?
    ) -> ClipboardItem {
        let metadata = fileMetadata(for: fileURL)
        let contentType: ClipboardContentType = metadata.contentType?.conforms(to: .image) == true
            ? .image
            : .file

        return ClipboardItem(
            id: UUID(),
            contentType: contentType,
            sourceHash: fileURL.absoluteString,
            displayTitle: fileURL.lastPathComponent,
            plainText: nil,
            urlString: fileURL.absoluteString,
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: copiedAt,
            lastCopiedAt: copiedAt,
            contentSize: metadata.fileSize,
            utiTypes: metadata.contentType.map { [$0.identifier] } ?? [],
            isFavorited: false,
            sourceAppName: sourceApplication?.name,
            sourceAppBundleIdentifier: sourceApplication?.bundleIdentifier
        )
    }

    private func fileMetadata(for fileURL: URL) -> (fileSize: Int?, contentType: UTType?) {
        let resourceValues = try? fileURL.resourceValues(
            forKeys: [.fileSizeKey, .totalFileSizeKey, .contentTypeKey]
        )
        let contentType = resourceValues?.contentType
            ?? UTType(filenameExtension: fileURL.pathExtension)

        return (
            fileSize: resourceValues?.fileSize ?? resourceValues?.totalFileSize,
            contentType: contentType
        )
    }

    private func fileURL(from pasteboard: NSPasteboard) -> URL? {
        pasteboard
            .readObjects(forClasses: [NSURL.self], options: nil)?
            .compactMap { $0 as? URL }
            .first
    }

    private func pngData(from image: NSImage) throws -> Data {
        guard let data = image.vPastePNGData() else {
            throw AssetCacheError.imagePNGConversionFailed
        }

        return data
    }

    private func stableSourceHash(from imageData: Data) -> String {
        let digest = SHA256.hash(data: imageData)
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return "image-\(hexDigest)"
    }
}
