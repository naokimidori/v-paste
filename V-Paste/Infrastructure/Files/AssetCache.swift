import AppKit
import Foundation

enum AssetCacheError: Error {
    case imagePNGConversionFailed
    case thumbnailPNGConversionFailed
}

final class AssetCache {
    private let fileManager: FileManager
    private let assetsDirectoryURL: URL?
    private let thumbnailsDirectoryURL: URL?

    init(
        fileManager: FileManager = .default,
        assetsDirectoryURL: URL,
        thumbnailsDirectoryURL: URL
    ) {
        self.fileManager = fileManager
        self.assetsDirectoryURL = assetsDirectoryURL
        self.thumbnailsDirectoryURL = thumbnailsDirectoryURL
    }

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        assetsDirectoryURL = nil
        thumbnailsDirectoryURL = nil
    }

    static func inMemory() -> AssetCache {
        AssetCache()
    }

    func storeImage(
        _ image: NSImage,
        id: UUID = UUID()
    ) throws -> (assetPath: String?, thumbnailPath: String?) {
        guard let assetsDirectoryURL, let thumbnailsDirectoryURL else {
            return (nil, nil)
        }

        try fileManager.createDirectory(
            at: assetsDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: thumbnailsDirectoryURL,
            withIntermediateDirectories: true
        )

        let assetURL = assetsDirectoryURL.appendingPathComponent(
            "\(id.uuidString).png",
            isDirectory: false
        )
        let thumbnailURL = thumbnailsDirectoryURL.appendingPathComponent(
            "\(id.uuidString).png",
            isDirectory: false
        )

        guard let assetData = image.vPastePNGData() else {
            throw AssetCacheError.imagePNGConversionFailed
        }

        guard let thumbnailData = image.thumbnail(maxPixelSize: 320).vPastePNGData() else {
            throw AssetCacheError.thumbnailPNGConversionFailed
        }

        try assetData.write(to: assetURL, options: .atomic)
        try thumbnailData.write(to: thumbnailURL, options: .atomic)

        return (assetURL.path, thumbnailURL.path)
    }

    func deleteAllAssets() throws {
        try deleteContents(of: assetsDirectoryURL)
        try deleteContents(of: thumbnailsDirectoryURL)
    }

    func deleteCachedFiles(at paths: [String]) throws {
        for path in paths where isCachedFilePath(path) {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func deleteContents(of directoryURL: URL?) throws {
        guard let directoryURL,
              fileManager.fileExists(atPath: directoryURL.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }

    private func isCachedFilePath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return isDescendant(url, of: assetsDirectoryURL)
            || isDescendant(url, of: thumbnailsDirectoryURL)
    }

    private func isDescendant(_ url: URL, of directoryURL: URL?) -> Bool {
        guard let directoryURL else { return false }

        let directoryPath = directoryURL.standardizedFileURL.path
        let filePath = url.path
        return filePath.hasPrefix(directoryPath + "/")
    }
}

extension NSImage {
    func vPastePNGData() -> Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    func thumbnail(maxPixelSize: CGFloat) -> NSImage {
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: NSSize(width: maxPixelSize, height: maxPixelSize))
        }

        let scale = min(maxPixelSize / size.width, maxPixelSize / size.height, 1)
        let thumbnailSize = NSSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        draw(in: NSRect(origin: .zero, size: thumbnailSize))
        thumbnail.unlockFocus()
        return thumbnail
    }
}
