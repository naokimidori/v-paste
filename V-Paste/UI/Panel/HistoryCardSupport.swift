import AppKit
import SwiftUI

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

enum HistoryCardTypeLabel {
    static func title(
        for contentType: ClipboardContentType,
        urlString: String?,
        language: AppLanguage
    ) -> String {
        if HistoryLinkPreview.isWebURL(urlString) {
            return language == .english ? "Link" : "链接"
        }

        switch contentType {
        case .text:
            return language == .english ? "Text" : "文本"
        case .image:
            return language == .english ? "Image" : "图片"
        case .file:
            return language == .english ? "File" : "文件"
        case .mixed:
            return language == .english ? "Mixed" : "混合"
        }
    }
}

enum HistoryCardRelativeAgeLabel {
    static func label(
        copiedAt: Date,
        now: Date = Date(),
        language: AppLanguage
    ) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(copiedAt)))

        if elapsed < 60 {
            return language == .english ? "just now" : "刚刚"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return language == .english ? "\(minutes) min ago" : "\(minutes) 分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return language == .english ? "\(hours) hr ago" : "\(hours) 小时前"
        }

        let days = hours / 24
        if days < 7 {
            return language == .english ? "\(days) d ago" : "\(days) 天前"
        }

        return dateFormatter.string(from: copiedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

enum HistoryCardCharacterCountLabel {
    static func label(count: Int, language: AppLanguage) -> String {
        language == .english ? "\(count) chars" : "\(count) 字符"
    }
}

enum HistoryCardActionCopy {
    static func selectedValue(isSelected: Bool, language: AppLanguage) -> String {
        if isSelected {
            return language == .english ? "Selected" : "已选中"
        }

        return language == .english ? "Not selected" : "未选中"
    }

    static func hint(language: AppLanguage) -> String {
        language == .english ? "Selects or copies this clipboard item" : "选择或复制这条剪贴板内容"
    }

    static func selectTitle(language: AppLanguage) -> String {
        language == .english ? "Select" : "选择"
    }

    static func copyTitle(language: AppLanguage) -> String {
        language == .english ? "Copy" : "复制"
    }

    static func addToGroupTitle(language: AppLanguage) -> String {
        language == .english ? "Add to Group" : "添加到分组"
    }

    static func deleteTitle(language: AppLanguage) -> String {
        language == .english ? "Delete" : "删除"
    }

    static func addFavoriteTitle(language: AppLanguage) -> String {
        language == .english ? "Add Favorite" : "收藏"
    }

    static func removeFavoriteTitle(language: AppLanguage) -> String {
        language == .english ? "Remove Favorite" : "取消收藏"
    }
}

enum HistoryFilePreviewLayout {
    static let thumbnailSize = CGSize(width: 190, height: 128)
    static let fallbackIconSize: CGFloat = 72
    static let cornerRadius: CGFloat = 6
}

struct DecorativeGrid: Shape {
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
