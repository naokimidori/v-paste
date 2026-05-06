import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

enum HistoryCardLayout {
    static let cardWidth: CGFloat = 270
    static let cardHeight: CGFloat = cardWidth
    static let headerHeight: CGFloat = 56
    static let contentHeight: CGFloat = cardHeight - headerHeight
    static let cornerRadius: CGFloat = 9
    static let contentHorizontalPadding: CGFloat = 16
    static let contentTopPadding: CGFloat = 14
    static let contentBottomPadding: CGFloat = 12
    static let imageContentHorizontalPadding: CGFloat = 14
    static let imageContentTopPadding: CGFloat = 14
    static let imageFooterBottomPadding: CGFloat = contentBottomPadding
    static let imagePreviewHeight: CGFloat = 144
}

enum HistoryCardHeaderPreview {
    enum Style: Equatable {
        case sourceApplicationIcon
        case previewImage
        case symbol(String)
    }

    static let imageSymbolName = "photo.on.rectangle.angled"
    static let previewImageOpacity: Double = 1

    static func style(
        contentType: ClipboardContentType,
        urlString: String?,
        hasSourceAppIcon: Bool,
        hasPreviewImage: Bool
    ) -> Style {
        if contentType == .image {
            return .symbol(imageSymbolName)
        }

        if hasSourceAppIcon {
            return .sourceApplicationIcon
        }

        if hasPreviewImage {
            return .previewImage
        }

        return .symbol(typeSymbolName(contentType: contentType, urlString: urlString))
    }

    static func typeSymbolName(contentType: ClipboardContentType, urlString: String?) -> String {
        if HistoryLinkPreview.isWebURL(urlString) {
            return "link"
        }

        switch contentType {
        case .text:
            return "text.alignleft"
        case .image:
            return imageSymbolName
        case .file:
            return "doc"
        case .mixed:
            return "square.grid.2x2"
        }
    }
}

enum HistoryCardHeaderFill {
    enum Style: Equatable {
        case groupColor(String)
        case selected
        case link
        case standard
    }

    static func style(
        item: ClipboardItem,
        isSelected: Bool,
        groups: [ClipboardGroup]
    ) -> Style {
        if let groupID = item.groupID,
           let group = groups.first(where: { $0.id == groupID }) {
            return .groupColor(group.colorHex)
        }

        if isSelected {
            return .selected
        }

        if HistoryLinkPreview.isWebURL(item.urlString) {
            return .link
        }

        return .standard
    }
}

struct HistoryCardShadowStyle: Equatable {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat
}

enum HistoryCardHoverEffect {
    static let restingShadow = HistoryCardShadowStyle(opacity: 0.08, radius: 7, y: 3)
    static let hoveringShadow = HistoryCardShadowStyle(opacity: 0.26, radius: 18, y: 10)
    static let selectedShadow = HistoryCardShadowStyle(opacity: 0.18, radius: 12, y: 7)

    static func shadow(isSelected: Bool, isHovering: Bool) -> HistoryCardShadowStyle {
        if isSelected {
            return selectedShadow
        }

        return isHovering ? hoveringShadow : restingShadow
    }

    static func verticalOffset(isSelected: Bool, isHovering: Bool) -> CGFloat {
        0
    }
}

enum HistoryImageDimensions {
    static func pixelSize(for image: NSImage) -> NSSize {
        let representationSizes = image.representations.compactMap { representation -> NSSize? in
            let width = representation.pixelsWide
            let height = representation.pixelsHigh
            guard width > 0, height > 0 else {
                return nil
            }

            return NSSize(width: CGFloat(width), height: CGFloat(height))
        }

        if let representationSize = representationSizes.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }) {
            return representationSize
        }

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSSize(width: cgImage.width, height: cgImage.height)
        }

        return image.size
    }

    static func label(for size: NSSize?) -> String? {
        guard let size else {
            return nil
        }

        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else {
            return nil
        }

        return "\(width) x \(height)"
    }
}

struct HistoryFileMetadataFooter: Equatable {
    let fileName: String
    let sizeLabel: String?

    var accessibilityLabel: String {
        guard let sizeLabel else {
            return fileName
        }

        return "\(fileName), \(sizeLabel)"
    }
}

enum HistoryFileMetadata {
    static func footer(
        fileName: String?,
        displayTitle: String,
        contentSize: Int?
    ) -> HistoryFileMetadataFooter {
        HistoryFileMetadataFooter(
            fileName: preferredName(fileName: fileName, displayTitle: displayTitle),
            sizeLabel: contentSize.map(sizeLabel)
        )
    }

    private static func preferredName(fileName: String?, displayTitle: String) -> String {
        let trimmedFileName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedFileName, !trimmedFileName.isEmpty {
            return trimmedFileName
        }

        let trimmedTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "File" : trimmedTitle
    }

    private static func sizeLabel(for contentSize: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(contentSize),
            countStyle: .file
        )
    }
}

enum HistoryImageFooter {
    static func label(
        imageSize: NSSize?,
        secondaryLabel: String
    ) -> String {
        return HistoryImageDimensions.label(for: imageSize) ?? secondaryLabel
    }
}

enum HistoryFilePreviewLayout {
    static let thumbnailSize = CGSize(width: 190, height: 128)
    static let fallbackIconSize: CGFloat = 72
    static let cornerRadius: CGFloat = 6
}

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

struct HistoryCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let groups: [ClipboardGroup]
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onToggleFavorite: () -> Void
    let onAssignToGroup: (ClipboardGroup.ID) -> Void
    let onDelete: () -> Void

    @StateObject private var mediaStore = HistoryCardMediaStore()
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            header

            content
                .frame(
                    width: HistoryCardLayout.cardWidth,
                    height: HistoryCardLayout.contentHeight,
                    alignment: .top
                )
        }
        .frame(width: HistoryCardLayout.cardWidth, height: HistoryCardLayout.cardHeight)
        .background(Color(nsColor: .textBackgroundColor), in: cardShape)
        .overlay(cardBorder)
        .clipShape(cardShape)
        .shadow(
            color: .black.opacity(cardShadow.opacity),
            radius: cardShadow.radius,
            y: cardShadow.y
        )
        .contentShape(cardShape)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onCopy)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .animation(.snappy(duration: 0.16), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects or copies this clipboard item")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Select", onSelect)
        .accessibilityAction(named: "Copy", onCopy)
        .contextMenu {
            Menu("Add to Group") {
                ForEach(groups) { group in
                    Button(group.name) {
                        onAssignToGroup(group.id)
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive, action: onDelete)
        }
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabel)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(relativeAgeLabel)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            Button(action: onToggleFavorite) {
                Image(systemName: item.isFavorited ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(item.isFavorited ? .yellow : .white.opacity(0.86))
                    .frame(width: 30, height: HistoryCardLayout.headerHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isFavorited ? "Remove Favorite" : "Add Favorite")

            headerPreview
                .frame(width: 58, height: HistoryCardLayout.headerHeight)
        }
        .frame(width: HistoryCardLayout.cardWidth, height: HistoryCardLayout.headerHeight)
        .background(headerFill)
    }

    @ViewBuilder
    private var content: some View {
        switch item.contentType {
        case .image:
            imageContent
        case .file:
            fileContent
        case .text, .mixed:
            if HistoryLinkPreview.isWebURL(item.urlString) {
                linkContent
            } else {
                textContent
            }
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.cardPreviewText)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            metadataFooter
        }
        .padding(.horizontal, HistoryCardLayout.contentHorizontalPadding)
        .padding(.top, HistoryCardLayout.contentTopPadding)
        .padding(.bottom, HistoryCardLayout.contentBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var linkContent: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.88),
                        Color.black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 66, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 146)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(linkURLDisplay)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, HistoryCardLayout.contentHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var imageContent: some View {
        VStack(spacing: 10) {
            Group {
                if item.filePath != nil {
                    HistoryFilePreviewView(
                        filePath: item.filePath,
                        fallbackImage: fileIcon
                    )
                } else if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderPreview(systemName: "photo", title: "Image")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: HistoryCardLayout.imagePreviewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Spacer(minLength: 0)

            if isFileBackedContent {
                fileMetadataFooter
            } else {
                Text(imageFooterLabel)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, HistoryCardLayout.imageContentHorizontalPadding)
        .padding(.top, HistoryCardLayout.imageContentTopPadding)
        .padding(.bottom, HistoryCardLayout.imageFooterBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var fileContent: some View {
        VStack(spacing: 10) {
            HistoryFilePreviewView(
                filePath: item.filePath,
                fallbackImage: fileIcon
            )
            .frame(maxWidth: .infinity)
            .frame(height: HistoryCardLayout.imagePreviewHeight)

            Spacer(minLength: 0)

            fileMetadataFooter
        }
        .padding(.horizontal, HistoryCardLayout.imageContentHorizontalPadding)
        .padding(.top, HistoryCardLayout.imageContentTopPadding)
        .padding(.bottom, HistoryCardLayout.imageFooterBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var fileMetadataFooter: some View {
        let footer = fileFooter

        return VStack(spacing: 2) {
            Text(footer.fileName)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)

            if let sizeLabel = footer.sizeLabel {
                Text(sizeLabel)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(footer.accessibilityLabel)
    }

    private var metadataFooter: some View {
        HStack(spacing: 8) {
            Text(sourceAppLabel)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(sourceAppForeground)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(characterCountLabel)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var headerPreview: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 18, bottomLeading: 18),
                style: .continuous
            )
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))

            headerPreviewContent
        }
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 18, bottomLeading: 18),
                style: .continuous
            )
        )
        .padding(.leading, 3)
    }

    @ViewBuilder
    private var headerPreviewContent: some View {
        let cachedSourceAppIcon = sourceAppIcon
        let cachedPreviewImage = previewImage

        switch HistoryCardHeaderPreview.style(
            contentType: item.contentType,
            urlString: item.urlString,
            hasSourceAppIcon: cachedSourceAppIcon != nil,
            hasPreviewImage: cachedPreviewImage != nil
        ) {
        case .sourceApplicationIcon:
            if let cachedSourceAppIcon {
                Image(nsImage: cachedSourceAppIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else {
                headerSymbol(typeIcon)
            }
        case .previewImage:
            if let image = cachedPreviewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(HistoryCardHeaderPreview.previewImageOpacity)
            } else {
                headerSymbol(typeIcon)
            }
        case let .symbol(symbolName):
            headerSymbol(symbolName)
        }
    }

    private func headerSymbol(_ symbolName: String) -> some View {
        ZStack {
            DecorativeGrid()
                .stroke(Color(nsColor: .controlAccentColor).opacity(0.18), lineWidth: 1)
                .padding(5)

            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor).opacity(0.35))
        }
    }

    private var cardBorder: some View {
        cardShape
            .strokeBorder(
                isSelected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor).opacity(0.28),
                lineWidth: isSelected ? 3 : 1
            )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HistoryCardLayout.cornerRadius, style: .continuous)
    }

    private var headerFill: Color {
        switch HistoryCardHeaderFill.style(
            item: item,
            isSelected: isSelected,
            groups: groups
        ) {
        case let .groupColor(colorHex):
            return Color(hex: colorHex) ?? Color(nsColor: .controlAccentColor)
        case .selected:
            return Color(nsColor: .controlAccentColor)
        case .link:
            return Color(nsColor: .systemOrange)
        case .standard:
            return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var cardShadow: HistoryCardShadowStyle {
        HistoryCardHoverEffect.shadow(
            isSelected: isSelected,
            isHovering: isHovering
        )
    }

    private var typeLabel: String {
        if HistoryLinkPreview.isWebURL(item.urlString) {
            return "Link"
        }

        switch item.contentType {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .mixed:
            return "Mixed"
        }
    }

    private var typeIcon: String {
        HistoryCardHeaderPreview.typeSymbolName(
            contentType: item.contentType,
            urlString: item.urlString
        )
    }

    private var relativeAgeLabel: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(item.lastCopiedAt)))

        if elapsed < 60 {
            return "just now"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "\(minutes) min ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr ago"
        }

        let days = hours / 24
        if days < 7 {
            return "\(days) d ago"
        }

        return Self.dateFormatter.string(from: item.lastCopiedAt)
    }

    private var characterCountLabel: String {
        guard let plainText = item.plainText, !plainText.isEmpty else {
            return secondaryLabel
        }

        return "\(plainText.count) chars"
    }

    private var sourceAppLabel: String {
        item.sourceAppName ?? secondaryLabel
    }

    private var sourceAppForeground: Color {
        item.sourceAppName == nil ? Color.secondary : Color.primary.opacity(0.72)
    }

    private var secondaryLabel: String {
        if let urlString = item.urlString, let host = URL(string: urlString)?.host {
            return host
        }

        if isFileBackedContent {
            return fileFooter.accessibilityLabel
        }

        if let contentSize = item.contentSize {
            return ByteCountFormatter.string(fromByteCount: Int64(contentSize), countStyle: .file)
        }

        return item.contentType.rawValue.capitalized
    }

    private var imageFooterLabel: String {
        HistoryImageFooter.label(
            imageSize: imageSize,
            secondaryLabel: secondaryLabel
        )
    }

    private var fileFooter: HistoryFileMetadataFooter {
        HistoryFileMetadata.footer(
            fileName: item.fileName,
            displayTitle: item.displayTitle,
            contentSize: item.contentSize
        )
    }

    private var isFileBackedContent: Bool {
        item.contentType == .file || item.fileName != nil || item.filePath != nil
    }

    private var imageSize: NSSize? {
        mediaStore.imageSize(
            assetPath: item.assetPath,
            thumbnailPath: item.thumbnailPath
        )
    }

    private var linkURLDisplay: String {
        guard let urlString = item.urlString,
              let url = URL(string: urlString)
        else {
            return item.displayTitle
        }

        let host = url.host ?? urlString
        let path = url.path.isEmpty ? "" : url.path
        return host + path
    }

    private var accessibilityLabel: Text {
        Text("\(typeLabel), \(item.displayTitle), \(secondaryLabel)")
    }

    private var previewImage: NSImage? {
        mediaStore.previewImage(
            thumbnailPath: item.thumbnailPath,
            assetPath: item.assetPath
        )
    }

    private var fileIcon: NSImage {
        if let filePath = item.filePath {
            return NSWorkspace.shared.icon(forFile: filePath)
        }

        return NSWorkspace.shared.icon(for: .data)
    }

    private var sourceAppIcon: NSImage? {
        mediaStore.sourceAppIcon(bundleIdentifier: item.sourceAppBundleIdentifier)
    }

    private func placeholderPreview(systemName: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct DecorativeGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(rect.width, rect.height) / 3

        stride(from: rect.minX, through: rect.maxX, by: step).forEach { x in
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        stride(from: rect.minY, through: rect.maxY, by: step).forEach { y in
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18))
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.34, dy: rect.height * 0.34))
        return path
    }
}

enum HistoryLinkPreview {
    static func isWebURL(_ urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }
}
