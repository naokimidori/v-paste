import AppKit
import QuickLookThumbnailing
import SwiftUI

final class HistoryCardMediaStore: ObservableObject {
    private let loadImage: (String) -> NSImage?
    private let applicationURLForBundleIdentifier: (String) -> URL?
    private let iconForFile: (String) -> NSImage
    private var previewImagesByPath: [String: NSImage] = [:]
    private var sourceAppIconsByBundleIdentifier: [String: NSImage] = [:]

    init(
        loadImage: @escaping (String) -> NSImage? = { NSImage(contentsOfFile: $0) },
        applicationURLForBundleIdentifier: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        iconForFile: @escaping (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }
    ) {
        self.loadImage = loadImage
        self.applicationURLForBundleIdentifier = applicationURLForBundleIdentifier
        self.iconForFile = iconForFile
    }

    func previewImage(thumbnailPath: String?, assetPath: String?) -> NSImage? {
        guard let imagePath = thumbnailPath ?? assetPath else {
            return nil
        }

        return cachedImage(at: imagePath)
    }

    func imageSize(assetPath: String?, thumbnailPath: String?) -> NSSize? {
        guard let imagePath = assetPath ?? thumbnailPath else {
            return nil
        }

        guard let image = cachedImage(at: imagePath) else {
            return nil
        }

        return HistoryImageDimensions.pixelSize(for: image)
    }

    private func cachedImage(at imagePath: String) -> NSImage? {
        if let cachedImage = previewImagesByPath[imagePath] {
            return cachedImage
        }

        guard let loadedImage = loadImage(imagePath) else {
            return nil
        }

        previewImagesByPath[imagePath] = loadedImage
        return loadedImage
    }

    func sourceAppIcon(bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else {
            return nil
        }

        if let cachedIcon = sourceAppIconsByBundleIdentifier[bundleIdentifier] {
            return cachedIcon
        }

        guard let applicationURL = applicationURLForBundleIdentifier(bundleIdentifier) else {
            return nil
        }

        let loadedIcon = iconForFile(applicationURL.path)
        sourceAppIconsByBundleIdentifier[bundleIdentifier] = loadedIcon
        return loadedIcon
    }
}

struct HistoryFilePreviewView: View {
    let filePath: String?
    let fallbackImage: NSImage

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
            } else {
                Image(nsImage: fallbackImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: HistoryFilePreviewLayout.fallbackIconSize,
                        height: HistoryFilePreviewLayout.fallbackIconSize
                    )
            }
        }
        .clipShape(RoundedRectangle(
            cornerRadius: HistoryFilePreviewLayout.cornerRadius,
            style: .continuous
        ))
        .task(id: filePath) {
            await loadThumbnail(for: filePath)
        }
    }

    @MainActor
    private func loadThumbnail(for filePath: String?) async {
        thumbnail = nil

        guard let filePath else {
            return
        }

        let loadedThumbnail = await Self.quickLookThumbnail(for: filePath)
        guard !Task.isCancelled else {
            return
        }

        thumbnail = loadedThumbnail
    }

    private static func quickLookThumbnail(for filePath: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let fileURL = URL(fileURLWithPath: filePath)
            let request = QLThumbnailGenerator.Request(
                fileAt: fileURL,
                size: HistoryFilePreviewLayout.thumbnailSize,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: [.thumbnail, .icon]
            )

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }
}
