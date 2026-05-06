import Foundation

struct AppPaths: Equatable {
    let appSupportDirectoryURL: URL
    let databaseURL: URL
    let assetsDirectoryURL: URL
    let thumbnailsDirectoryURL: URL

    static func make(
        fileManager: FileManager = .default,
        bundleID: String
    ) throws -> AppPaths {
        guard let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let appSupportDirectoryURL = baseURL
            .appendingPathComponent(bundleID, isDirectory: true)
        let assetsDirectoryURL = appSupportDirectoryURL
            .appendingPathComponent("Assets", isDirectory: true)
        let thumbnailsDirectoryURL = appSupportDirectoryURL
            .appendingPathComponent("Thumbnails", isDirectory: true)

        try fileManager.createDirectory(
            at: assetsDirectoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: thumbnailsDirectoryURL,
            withIntermediateDirectories: true
        )

        return AppPaths(
            appSupportDirectoryURL: appSupportDirectoryURL,
            databaseURL: appSupportDirectoryURL.appendingPathComponent("history.sqlite3"),
            assetsDirectoryURL: assetsDirectoryURL,
            thumbnailsDirectoryURL: thumbnailsDirectoryURL
        )
    }
}
