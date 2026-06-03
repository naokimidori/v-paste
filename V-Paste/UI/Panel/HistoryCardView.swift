import AppKit
import SwiftUI

struct HistoryCardView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let groups: [ClipboardGroup]
    let language: AppLanguage
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
        .accessibilityValue(HistoryCardActionCopy.selectedValue(isSelected: isSelected, language: language))
        .accessibilityHint(HistoryCardActionCopy.hint(language: language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: HistoryCardActionCopy.selectTitle(language: language), onSelect)
        .accessibilityAction(named: HistoryCardActionCopy.copyTitle(language: language), onCopy)
        .contextMenu {
            Menu(HistoryCardActionCopy.addToGroupTitle(language: language)) {
                ForEach(groups) { group in
                    Button(group.name) {
                        onAssignToGroup(group.id)
                    }
                }
            }

            Divider()

            Button(HistoryCardActionCopy.deleteTitle(language: language), role: .destructive, action: onDelete)
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
            .accessibilityLabel(
                item.isFavorited
                    ? HistoryCardActionCopy.removeFavoriteTitle(language: language)
                    : HistoryCardActionCopy.addFavoriteTitle(language: language)
            )

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
                    placeholderPreview(
                        systemName: "photo",
                        title: HistoryCardTypeLabel.title(
                            for: .image,
                            urlString: nil,
                            language: language
                        )
                    )
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
        HistoryCardTypeLabel.title(
            for: item.contentType,
            urlString: item.urlString,
            language: language
        )
    }

    private var typeIcon: String {
        HistoryCardHeaderPreview.typeSymbolName(
            contentType: item.contentType,
            urlString: item.urlString
        )
    }

    private var relativeAgeLabel: String {
        HistoryCardRelativeAgeLabel.label(
            copiedAt: item.lastCopiedAt,
            language: language
        )
    }

    private var characterCountLabel: String {
        guard let plainText = item.plainText, !plainText.isEmpty else {
            return secondaryLabel
        }

        return HistoryCardCharacterCountLabel.label(
            count: plainText.count,
            language: language
        )
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

        return HistoryCardTypeLabel.title(
            for: item.contentType,
            urlString: item.urlString,
            language: language
        )
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

}
