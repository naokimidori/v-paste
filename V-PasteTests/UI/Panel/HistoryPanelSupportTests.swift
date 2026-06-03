import AppKit
import Carbon
import XCTest
@testable import V_Paste

@MainActor
final class HistoryPanelSupportTests: XCTestCase {
    func testCardLayoutContentHeightMatchesCardMinusHeader() {
        XCTAssertEqual(
            HistoryCardLayout.contentHeight,
            HistoryCardLayout.cardHeight - HistoryCardLayout.headerHeight
        )
    }

    func testCardLayoutUsesSquareAspectRatio() {
        XCTAssertEqual(HistoryCardLayout.cardHeight, HistoryCardLayout.cardWidth)
    }

    func testTypeFilterPillUsesUnifiedIconAndTextFontSize() {
        XCTAssertEqual(
            HistoryPanelTypeFilterLayout.iconFontSize,
            HistoryPanelTypeFilterLayout.titleFontSize
        )
    }

    func testTypeFilterChevronRotatesWhenMenuIsPresented() {
        XCTAssertEqual(
            HistoryPanelTypeFilterLayout.chevronRotationDegrees(isPresented: false),
            0
        )
        XCTAssertEqual(
            HistoryPanelTypeFilterLayout.chevronRotationDegrees(isPresented: true),
            180
        )
        XCTAssertGreaterThan(HistoryPanelTypeFilterLayout.chevronAnimationDuration, 0)
    }

    func testTypeFilterMenuPopupAnchorsToControlBottomEdge() {
        let point = HistoryPanelTypeFilterLayout.menuPopupPoint(anchorHeight: 30)

        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 0)
        XCTAssertLessThan(point.y, 30)
    }

    func testImageCardFooterUsesSharedBottomPadding() {
        XCTAssertEqual(
            HistoryCardLayout.imageFooterBottomPadding,
            HistoryCardLayout.contentBottomPadding
        )
    }

    func testImageHeaderPreviewUsesGenericSymbolInsteadOfAppIconOrThumbnail() {
        XCTAssertEqual(
            HistoryCardHeaderPreview.style(
                contentType: .image,
                urlString: nil,
                hasSourceAppIcon: true,
                hasPreviewImage: true
            ),
            .symbol(HistoryCardHeaderPreview.imageSymbolName)
        )
    }

    func testTextHeaderPreviewStillPrefersSourceApplicationIcon() {
        XCTAssertEqual(
            HistoryCardHeaderPreview.style(
                contentType: .text,
                urlString: nil,
                hasSourceAppIcon: true,
                hasPreviewImage: true
            ),
            .sourceApplicationIcon
        )
    }

    func testGroupedCardHeaderFillUsesGroupColorEvenWhenSelected() {
        let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000A111")!
        let group = ClipboardGroup(
            id: groupID,
            name: "Work",
            colorHex: "#4B8DFF",
            createdAt: Date(timeIntervalSince1970: 10),
            sortOrder: 0
        )
        let item = makeItem(
            sourceHash: "grouped",
            displayTitle: "Grouped",
            plainText: "Grouped",
            groupID: groupID
        )

        XCTAssertEqual(
            HistoryCardHeaderFill.style(
                item: item,
                isSelected: true,
                groups: [group]
            ),
            .groupColor("#4B8DFF")
        )
    }

    func testUngroupedSelectedCardStillUsesSelectionHeaderFill() {
        let item = makeItem(
            sourceHash: "selected",
            displayTitle: "Selected",
            plainText: "Selected"
        )

        XCTAssertEqual(
            HistoryCardHeaderFill.style(
                item: item,
                isSelected: true,
                groups: []
            ),
            .selected
        )
    }

    func testHoverCardShadowIncreasesWithoutMovingCardSurface() {
        let resting = HistoryCardHoverEffect.shadow(isSelected: false, isHovering: false)
        let hovering = HistoryCardHoverEffect.shadow(isSelected: false, isHovering: true)
        let selected = HistoryCardHoverEffect.shadow(isSelected: true, isHovering: true)

        XCTAssertGreaterThan(hovering.radius, resting.radius)
        XCTAssertGreaterThan(hovering.y, resting.y)
        XCTAssertGreaterThanOrEqual(hovering.opacity, 0.24)
        XCTAssertGreaterThanOrEqual(hovering.radius, 16)
        XCTAssertGreaterThanOrEqual(hovering.y, 9)
        XCTAssertEqual(selected, HistoryCardHoverEffect.selectedShadow)
        XCTAssertEqual(
            HistoryCardHoverEffect.verticalOffset(isSelected: false, isHovering: true),
            0
        )
    }

    func testHeaderPreviewImageUsesFullOpacityToAvoidHoverFlicker() {
        XCTAssertEqual(HistoryCardHeaderPreview.previewImageOpacity, 1)
    }

    func testCardMediaStoreCachesPreviewImagesByPreferredPath() {
        let expectedImage = NSImage(size: NSSize(width: 2, height: 2))
        var loadCount = 0
        let store = HistoryCardMediaStore(
            loadImage: { path in
                loadCount += 1
                return path == "/tmp/thumb.png" ? expectedImage : nil
            },
            applicationURLForBundleIdentifier: { _ in nil },
            iconForFile: { _ in NSImage(size: NSSize(width: 1, height: 1)) }
        )

        let firstImage = store.previewImage(
            thumbnailPath: "/tmp/thumb.png",
            assetPath: "/tmp/asset.png"
        )
        let secondImage = store.previewImage(
            thumbnailPath: "/tmp/thumb.png",
            assetPath: "/tmp/asset.png"
        )

        XCTAssertTrue(firstImage === expectedImage)
        XCTAssertTrue(secondImage === expectedImage)
        XCTAssertEqual(loadCount, 1)
    }

    func testCardMediaStoreCachesSourceApplicationIconsByBundleIdentifier() {
        let expectedIcon = NSImage(size: NSSize(width: 3, height: 3))
        var lookupCount = 0
        var iconLoadCount = 0
        let store = HistoryCardMediaStore(
            loadImage: { _ in nil },
            applicationURLForBundleIdentifier: { bundleIdentifier in
                lookupCount += 1
                return bundleIdentifier == "com.apple.Notes"
                    ? URL(fileURLWithPath: "/Applications/Notes.app")
                    : nil
            },
            iconForFile: { path in
                iconLoadCount += 1
                return path == "/Applications/Notes.app"
                    ? expectedIcon
                    : NSImage(size: NSSize(width: 1, height: 1))
            }
        )

        let firstIcon = store.sourceAppIcon(bundleIdentifier: "com.apple.Notes")
        let secondIcon = store.sourceAppIcon(bundleIdentifier: "com.apple.Notes")

        XCTAssertTrue(firstIcon === expectedIcon)
        XCTAssertTrue(secondIcon === expectedIcon)
        XCTAssertEqual(lookupCount, 1)
        XCTAssertEqual(iconLoadCount, 1)
    }

    func testImageDimensionLabelFormatsPixelSize() {
        XCTAssertEqual(
            HistoryImageDimensions.label(for: NSSize(width: 1024, height: 768)),
            "1024 x 768"
        )
    }

    func testCardMediaStoreReadsImageDimensionsFromOriginalAssetBeforeThumbnail() {
        let assetImage = NSImage(size: NSSize(width: 1600, height: 900))
        let thumbnailImage = NSImage(size: NSSize(width: 320, height: 180))
        var loadedPaths: [String] = []
        let store = HistoryCardMediaStore(
            loadImage: { path in
                loadedPaths.append(path)
                return path == "/tmp/original.png" ? assetImage : thumbnailImage
            },
            applicationURLForBundleIdentifier: { _ in nil },
            iconForFile: { _ in NSImage(size: NSSize(width: 1, height: 1)) }
        )

        XCTAssertEqual(
            store.imageSize(
                assetPath: "/tmp/original.png",
                thumbnailPath: "/tmp/thumb.png"
            ),
            NSSize(width: 1600, height: 900)
        )
        XCTAssertEqual(loadedPaths, ["/tmp/original.png"])
    }

    func testCardMediaStoreUsesBitmapPixelDimensionsWhenAvailable() throws {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 800,
            pixelsHigh: 600,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = NSSize(width: 400, height: 300)
        image.addRepresentation(bitmap)
        let store = HistoryCardMediaStore(
            loadImage: { _ in image },
            applicationURLForBundleIdentifier: { _ in nil },
            iconForFile: { _ in NSImage(size: NSSize(width: 1, height: 1)) }
        )

        XCTAssertEqual(
            store.imageSize(assetPath: "/tmp/retina.png", thumbnailPath: nil),
            NSSize(width: 800, height: 600)
        )
    }

    func testHeaderPreviewTreatsOnlyWebURLsAsLinks() {
        XCTAssertEqual(
            HistoryCardHeaderPreview.typeSymbolName(
                contentType: .text,
                urlString: "https://platform.minimaxi.com/user-center/payment/token-plan"
            ),
            "link"
        )
        XCTAssertEqual(
            HistoryCardHeaderPreview.typeSymbolName(
                contentType: .file,
                urlString: "file:///Users/longzhao/Desktop/report.png"
            ),
            "doc"
        )
    }

    func testFileMetadataFooterSplitsFileNameAndSize() {
        let footer = HistoryFileMetadata.footer(
            fileName: "MKDS25061.rar",
            displayTitle: "Fallback",
            contentSize: 1_048_576
        )

        XCTAssertEqual(footer.fileName, "MKDS25061.rar")
        XCTAssertEqual(footer.sizeLabel, "1 MB")
        XCTAssertEqual(footer.accessibilityLabel, "MKDS25061.rar, 1 MB")
    }

    func testFileMetadataFooterKeepsMissingSizeNil() {
        let footer = HistoryFileMetadata.footer(
            fileName: nil,
            displayTitle: "report.pdf",
            contentSize: nil
        )

        XCTAssertEqual(footer.fileName, "report.pdf")
        XCTAssertNil(footer.sizeLabel)
        XCTAssertEqual(footer.accessibilityLabel, "report.pdf")
    }

    func testImageFooterShowsDimensionsForInlineImages() {
        XCTAssertEqual(
            HistoryImageFooter.label(
                imageSize: NSSize(width: 1024, height: 768),
                secondaryLabel: "Image"
            ),
            "1024 x 768"
        )
    }

    func testPanelLayoutFramesWindowAtBottomOfScreenFrame() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1728, height: 1032)

        let frame = HistoryPanelLayout.frame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            hiddenOffset: 0
        )

        XCTAssertEqual(frame.origin.x, screenFrame.minX)
        XCTAssertEqual(frame.origin.y, screenFrame.minY)
        XCTAssertEqual(frame.width, screenFrame.width)
        XCTAssertEqual(frame.height, HistoryPanelLayout.panelHeight)
    }

    func testPanelLayoutAppliesHiddenOffsetBelowScreenFrame() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1728, height: 1032)

        let frame = HistoryPanelLayout.frame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            hiddenOffset: 24
        )

        XCTAssertEqual(frame.origin.y, screenFrame.minY - 24)
    }

    func testPanelPresentationHiddenOffsetMovesWholePanelBelowScreen() {
        XCTAssertEqual(
            HistoryPanelPresentationAnimation.hiddenOffset,
            HistoryPanelLayout.panelHeight + HistoryPanelPresentationAnimation.hiddenBottomInset
        )
    }

    func testPanelPresentationDoesNotAnimateWindowFrameAcrossDisplays() {
        XCTAssertFalse(HistoryPanelPresentationAnimation.animatesWindowFrame)
    }

    func testPanelPresentationSlidesContentByPanelHeightInsideClippedWindow() {
        XCTAssertEqual(
            HistoryPanelPresentationAnimation.contentHiddenOffset,
            HistoryPanelLayout.panelHeight
        )
    }

    func testPanelPresentationUsesLayerTransformForContentSlide() {
        XCTAssertTrue(HistoryPanelPresentationAnimation.usesLayerTransform)
    }

    func testPanelPresentationPrefersActiveScreenOverCurrentPanelScreen() {
        let mainScreen = HistoryPanelScreenSnapshot(
            frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: NSRect(x: 0, y: 40, width: 1728, height: 1032)
        )
        let secondaryScreen = HistoryPanelScreenSnapshot(
            frame: NSRect(x: -1512, y: -121, width: 1512, height: 982),
            visibleFrame: NSRect(x: -1512, y: -96, width: 1512, height: 921)
        )

        let frame = HistoryPanelPresentationTarget.frame(
            activeScreen: secondaryScreen,
            panelScreen: mainScreen,
            hiddenOffset: 0
        )

        XCTAssertEqual(frame?.origin.x, secondaryScreen.frame.minX)
        XCTAssertEqual(frame?.origin.y, secondaryScreen.frame.minY)
        XCTAssertEqual(frame?.width, secondaryScreen.frame.width)
    }

    func testPanelPresentationUsesSameDisplayForHiddenAndVisibleFrames() {
        let secondaryScreen = HistoryPanelScreenSnapshot(
            frame: NSRect(x: -1512, y: -121, width: 1512, height: 982),
            visibleFrame: NSRect(x: -1512, y: -96, width: 1512, height: 921)
        )

        let frames = HistoryPanelPresentationTarget.frames(
            activeScreen: secondaryScreen,
            panelScreen: nil,
            hiddenOffset: HistoryPanelPresentationAnimation.hiddenOffset
        )

        XCTAssertEqual(frames?.hidden.origin.x, secondaryScreen.frame.minX)
        XCTAssertEqual(frames?.visible.origin.x, secondaryScreen.frame.minX)
        XCTAssertEqual(frames?.hidden.width, secondaryScreen.frame.width)
        XCTAssertEqual(frames?.visible.width, secondaryScreen.frame.width)
        XCTAssertLessThan(frames?.hidden.origin.y ?? 0, frames?.visible.origin.y ?? 0)
    }

    func testPanelLayoutUsesWindowLevelAboveDock() {
        XCTAssertGreaterThan(
            HistoryPanelLayout.windowLevel.rawValue,
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow))).rawValue
        )
    }

    func testPanelLayoutKeepsBottomWhitespaceCompactAroundCards() {
        let bottomWhitespace = HistoryPanelLayout.panelHeight
            - HistoryPanelLayout.topPadding
            - HistoryPanelLayout.toolbarHeight
            - HistoryPanelLayout.toolbarToCardSpacing
            - HistoryPanelLayout.cardStripTopPadding
            - HistoryCardLayout.cardHeight

        XCTAssertGreaterThanOrEqual(bottomWhitespace, 8)
        XCTAssertLessThanOrEqual(bottomWhitespace, 16)
    }

    func testPanelLayoutKeepsToolbarCloseToCards() {
        let topWhitespace = HistoryPanelLayout.topPadding
            + HistoryPanelLayout.toolbarHeight
            + HistoryPanelLayout.toolbarToCardSpacing
            + HistoryPanelLayout.cardStripTopPadding

        XCTAssertLessThanOrEqual(topWhitespace, 58)
    }

    func testCopyToastFrameIsCenteredNearBottomOfScreen() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)

        let frame = CopyToastLayout.frame(screenFrame: screenFrame)

        XCTAssertEqual(frame.width, CopyToastLayout.size.width)
        XCTAssertEqual(frame.height, CopyToastLayout.size.height)
        XCTAssertEqual(frame.midX, screenFrame.midX)
        XCTAssertEqual(frame.minY, screenFrame.minY + CopyToastLayout.bottomInset)
    }

    func testCopyToastUsesLiftedCompactCapsuleMetrics() {
        XCTAssertEqual(CopyToastLayout.size, CGSize(width: 96, height: 32))
        XCTAssertEqual(CopyToastLayout.bottomInset, 88)
        XCTAssertEqual(CopyToastLayout.contentPadding, 8)
    }

    func testCopyToastContentUsesCheckmarkAndCopiedText() {
        XCTAssertEqual(CopyToastContent.iconSystemName, "checkmark")
        XCTAssertEqual(CopyToastContent.message, "Copied")
    }

    func testToolbarCopyUsesRequestedLanguage() {
        XCTAssertEqual(HistoryPanelToolbarCopy.title, "Clipboard History")
        XCTAssertEqual(HistoryPanelToolbarCopy.localizedTitle(language: .english), "Clipboard History")
        XCTAssertEqual(HistoryPanelToolbarCopy.localizedTitle(language: .simplifiedChinese), "剪贴板历史")
        XCTAssertEqual(HistoryPanelToolbarCopy.defaultGroupName, "Untitled")
        XCTAssertEqual(HistoryPanelToolbarCopy.noResultsTitle, "No Results")
        XCTAssertEqual(HistoryPanelToolbarCopy.noResultsTitle(language: .english), "No Results")
        XCTAssertEqual(HistoryPanelToolbarCopy.noResultsTitle(language: .simplifiedChinese), "无结果")
    }

    func testHistoryCardTypeLabelsUseRequestedLanguage() {
        XCTAssertEqual(
            HistoryCardTypeLabel.title(
                for: .text,
                urlString: nil,
                language: .simplifiedChinese
            ),
            "文本"
        )
        XCTAssertEqual(
            HistoryCardTypeLabel.title(
                for: .image,
                urlString: nil,
                language: .simplifiedChinese
            ),
            "图片"
        )
        XCTAssertEqual(
            HistoryCardTypeLabel.title(
                for: .file,
                urlString: nil,
                language: .simplifiedChinese
            ),
            "文件"
        )
        XCTAssertEqual(
            HistoryCardTypeLabel.title(
                for: .mixed,
                urlString: nil,
                language: .simplifiedChinese
            ),
            "混合"
        )
        XCTAssertEqual(
            HistoryCardTypeLabel.title(
                for: .text,
                urlString: "https://example.com",
                language: .simplifiedChinese
            ),
            "链接"
        )
        XCTAssertEqual(
            HistoryCardTypeLabel.title(
                for: .text,
                urlString: nil,
                language: .english
            ),
            "Text"
        )
    }

    func testHistoryCardMetadataLabelsUseRequestedLanguage() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            HistoryCardRelativeAgeLabel.label(
                copiedAt: now.addingTimeInterval(-20),
                now: now,
                language: .english
            ),
            "just now"
        )
        XCTAssertEqual(
            HistoryCardRelativeAgeLabel.label(
                copiedAt: now.addingTimeInterval(-20),
                now: now,
                language: .simplifiedChinese
            ),
            "刚刚"
        )
        XCTAssertEqual(
            HistoryCardRelativeAgeLabel.label(
                copiedAt: now.addingTimeInterval(-120),
                now: now,
                language: .simplifiedChinese
            ),
            "2 分钟前"
        )
        XCTAssertEqual(
            HistoryCardRelativeAgeLabel.label(
                copiedAt: now.addingTimeInterval(-10_800),
                now: now,
                language: .simplifiedChinese
            ),
            "3 小时前"
        )
        XCTAssertEqual(
            HistoryCardRelativeAgeLabel.label(
                copiedAt: now.addingTimeInterval(-345_600),
                now: now,
                language: .simplifiedChinese
            ),
            "4 天前"
        )
        XCTAssertEqual(
            HistoryCardCharacterCountLabel.label(count: 6816, language: .english),
            "6816 chars"
        )
        XCTAssertEqual(
            HistoryCardCharacterCountLabel.label(count: 6816, language: .simplifiedChinese),
            "6816 字符"
        )
    }

    func testHistoryCardActionCopyUsesRequestedLanguage() {
        XCTAssertEqual(HistoryCardActionCopy.addToGroupTitle(language: .english), "Add to Group")
        XCTAssertEqual(HistoryCardActionCopy.addToGroupTitle(language: .simplifiedChinese), "添加到分组")
        XCTAssertEqual(HistoryCardActionCopy.deleteTitle(language: .english), "Delete")
        XCTAssertEqual(HistoryCardActionCopy.deleteTitle(language: .simplifiedChinese), "删除")
        XCTAssertEqual(HistoryCardActionCopy.addFavoriteTitle(language: .english), "Add Favorite")
        XCTAssertEqual(HistoryCardActionCopy.addFavoriteTitle(language: .simplifiedChinese), "收藏")
        XCTAssertEqual(HistoryCardActionCopy.removeFavoriteTitle(language: .english), "Remove Favorite")
        XCTAssertEqual(HistoryCardActionCopy.removeFavoriteTitle(language: .simplifiedChinese), "取消收藏")
    }

    func testPanelEmptyStateCopyUsesRequestedLanguage() {
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.title(
                searchText: "missing",
                showsFavoritesOnly: false,
                hasActiveGroup: false,
                language: .simplifiedChinese
            ),
            "无结果"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.subtitle(
                searchText: "missing",
                showsFavoritesOnly: false,
                hasActiveGroup: false,
                language: .simplifiedChinese
            ),
            "试试更短的关键词。"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.title(
                searchText: "",
                showsFavoritesOnly: true,
                hasActiveGroup: false,
                language: .simplifiedChinese
            ),
            "暂无收藏"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.subtitle(
                searchText: "",
                showsFavoritesOnly: true,
                hasActiveGroup: false,
                language: .simplifiedChinese
            ),
            "为剪贴板卡片加星标后会显示在这里。"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.title(
                searchText: "",
                showsFavoritesOnly: true,
                hasActiveGroup: true,
                language: .simplifiedChinese
            ),
            "这个分组暂无收藏"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.subtitle(
                searchText: "",
                showsFavoritesOnly: true,
                hasActiveGroup: true,
                language: .simplifiedChinese
            ),
            "为这个分组里的卡片加星标后会显示在这里。"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.title(
                searchText: "",
                showsFavoritesOnly: false,
                hasActiveGroup: true,
                language: .simplifiedChinese
            ),
            "分组为空"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.subtitle(
                searchText: "",
                showsFavoritesOnly: false,
                hasActiveGroup: true,
                language: .simplifiedChinese
            ),
            "将卡片拖到这里，或通过“添加到分组”归类。"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.title(
                searchText: "",
                showsFavoritesOnly: false,
                hasActiveGroup: false,
                language: .simplifiedChinese
            ),
            "复制内容以开始"
        )
        XCTAssertEqual(
            HistoryPanelEmptyStateCopy.subtitle(
                searchText: "",
                showsFavoritesOnly: false,
                hasActiveGroup: false,
                language: .simplifiedChinese
            ),
            "文本、图片和文件引用会显示在这里。"
        )
    }

    func testPanelSearchAndScopeCopyUsesRequestedLanguage() {
        XCTAssertEqual(HistoryPanelSearchCopy.searchTitle(language: .english), "Search")
        XCTAssertEqual(HistoryPanelSearchCopy.searchTitle(language: .simplifiedChinese), "搜索")
        XCTAssertEqual(HistoryPanelSearchCopy.clearTitle(language: .english), "Clear Search")
        XCTAssertEqual(HistoryPanelSearchCopy.clearTitle(language: .simplifiedChinese), "清除搜索")
        XCTAssertEqual(HistoryPanelScopeCopy.allTitle(language: .english), "All")
        XCTAssertEqual(HistoryPanelScopeCopy.allTitle(language: .simplifiedChinese), "全部")
        XCTAssertEqual(HistoryPanelScopeCopy.favoritesTitle(language: .english), "Favorites")
        XCTAssertEqual(HistoryPanelScopeCopy.favoritesTitle(language: .simplifiedChinese), "收藏")
        XCTAssertEqual(HistoryPanelScopeCopy.clipboardScopeTitle(language: .english), "Clipboard scope")
        XCTAssertEqual(HistoryPanelScopeCopy.clipboardScopeTitle(language: .simplifiedChinese), "剪贴板范围")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.typeTitle(language: .english), "Type")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.typeTitle(language: .simplifiedChinese), "类型")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .all, language: .english), "All")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .images, language: .english), "Images")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .text, language: .english), "Text")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .links, language: .english), "Links")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .files, language: .english), "Files")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .all, language: .simplifiedChinese), "全部")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .images, language: .simplifiedChinese), "图片")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .text, language: .simplifiedChinese), "文本")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .links, language: .simplifiedChinese), "链接")
        XCTAssertEqual(HistoryPanelTypeFilterCopy.title(for: .files, language: .simplifiedChinese), "文件")
    }

    func testPanelGroupCopyUsesRequestedLanguage() {
        XCTAssertEqual(HistoryPanelGroupCopy.createTitle(language: .english), "Create Group")
        XCTAssertEqual(HistoryPanelGroupCopy.createTitle(language: .simplifiedChinese), "新建分组")
        XCTAssertEqual(HistoryPanelGroupCopy.groupListTitle(language: .english), "Groups")
        XCTAssertEqual(HistoryPanelGroupCopy.groupListTitle(language: .simplifiedChinese), "分组")
        XCTAssertEqual(HistoryPanelGroupCopy.editTitle(language: .english), "Edit")
        XCTAssertEqual(HistoryPanelGroupCopy.editTitle(language: .simplifiedChinese), "编辑")
        XCTAssertEqual(HistoryPanelGroupCopy.deleteTitle(language: .english), "Delete")
        XCTAssertEqual(HistoryPanelGroupCopy.deleteTitle(language: .simplifiedChinese), "删除")
        XCTAssertEqual(HistoryPanelGroupCopy.colorTitle(language: .english), "Group Color")
        XCTAssertEqual(HistoryPanelGroupCopy.colorTitle(language: .simplifiedChinese), "分组颜色")
    }

    func testGroupStripWidthShrinksToContentBeforeReachingMaxWidth() {
        let group = ClipboardGroup.defaultGroup(
            createdAt: Date(timeIntervalSince1970: 10)
        )

        let width = HistoryPanelGroupStripLayout.width(
            for: [group],
            editingGroupID: nil,
            maxWidth: 360
        )

        XCTAssertGreaterThan(width, 50)
        XCTAssertLessThan(width, 120)
    }

    func testGroupStripWidthCapsAtMaxWidthForManyGroups() {
        let groups = (0..<8).map { index in
            ClipboardGroup(
                name: "Long Project \(index)",
                colorHex: ClipboardGroupColorPalette.hexValues[
                    index % ClipboardGroupColorPalette.hexValues.count
                ],
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sortOrder: index
            )
        }

        let width = HistoryPanelGroupStripLayout.width(
            for: groups,
            editingGroupID: nil,
            maxWidth: 300
        )

        XCTAssertEqual(width, 300)
    }

    func testGroupAndCreateButtonSpacingStayCompactAndMatched() {
        XCTAssertEqual(
            HistoryPanelGroupStripLayout.createButtonSpacing,
            HistoryPanelGroupStripLayout.pillSpacing
        )
        XCTAssertEqual(HistoryPanelGroupStripLayout.stripHorizontalPadding, 0)
        XCTAssertLessThan(HistoryPanelGroupStripLayout.pillSpacing, 8)
    }

    func testDefaultGroupStripWidthDoesNotLeaveSlackBeforeCreateButton() {
        let groups = (0..<3).map { index in
            ClipboardGroup(
                name: ClipboardGroup.defaultName(language: .english),
                colorHex: ClipboardGroupColorPalette.hexValues[
                    index % ClipboardGroupColorPalette.hexValues.count
                ],
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sortOrder: index
            )
        }

        let width = HistoryPanelGroupStripLayout.width(
            for: groups,
            editingGroupID: nil,
            maxWidth: 360
        )

        XCTAssertLessThanOrEqual(width, 285)
    }

    func testLocalMouseRoutingKeepsPanelAndAuxiliaryAppWindowsOpen() {
        let panel = NSWindow()
        let colorPopoverWindow = NSWindow()
        let unrelatedWindow = NSWindow()

        XCTAssertTrue(
            HistoryPanelMouseEventRouting.shouldKeepEvent(
                eventWindow: panel,
                panel: panel,
                appWindows: [panel, colorPopoverWindow]
            )
        )
        XCTAssertTrue(
            HistoryPanelMouseEventRouting.shouldKeepEvent(
                eventWindow: colorPopoverWindow,
                panel: panel,
                appWindows: [panel, colorPopoverWindow]
            )
        )
        XCTAssertFalse(
            HistoryPanelMouseEventRouting.shouldKeepEvent(
                eventWindow: unrelatedWindow,
                panel: panel,
                appWindows: [panel, colorPopoverWindow]
            )
        )
        XCTAssertFalse(
            HistoryPanelMouseEventRouting.shouldKeepEvent(
                eventWindow: nil,
                panel: panel,
                appWindows: [panel]
            )
        )
        XCTAssertFalse(
            HistoryPanelMouseEventRouting.shouldHidePanelAfterResignKey(
                newKeyWindow: colorPopoverWindow,
                panel: panel,
                appWindows: [panel, colorPopoverWindow]
            )
        )
        XCTAssertTrue(
            HistoryPanelMouseEventRouting.shouldHidePanelAfterResignKey(
                newKeyWindow: unrelatedWindow,
                panel: panel,
                appWindows: [panel, colorPopoverWindow]
            )
        )
        XCTAssertTrue(
            HistoryPanelMouseEventRouting.shouldHidePanelAfterResignKey(
                newKeyWindow: nil,
                panel: panel,
                appWindows: [panel]
            )
        )
    }

    func testPanelKeyboardRoutingBypassesTextEditingResponders() {
        XCTAssertTrue(
            HistoryPanelKeyEventRouting.shouldBypassPanelHandling(
                firstResponder: NSTextView()
            )
        )
        XCTAssertTrue(
            HistoryPanelKeyEventRouting.shouldBypassPanelHandling(
                firstResponder: NSTextField()
            )
        )
        XCTAssertFalse(
            HistoryPanelKeyEventRouting.shouldBypassPanelHandling(
                firstResponder: NSView()
            )
        )
        XCTAssertFalse(
            HistoryPanelKeyEventRouting.shouldBypassPanelHandling(
                firstResponder: nil
            )
        )
    }

    func testPanelKeyboardRoutingHandlesSearchCopyShortcutBeforeTextEditingBypass() {
        XCTAssertTrue(
            HistoryPanelKeyEventRouting.shouldHandleSearchCopyShortcut(
                firstResponder: NSTextView(),
                charactersIgnoringModifiers: "c",
                modifierFlags: [.command],
                isSearchExpanded: true
            )
        )
        XCTAssertFalse(
            HistoryPanelKeyEventRouting.shouldHandleSearchCopyShortcut(
                firstResponder: NSTextView(),
                charactersIgnoringModifiers: "c",
                modifierFlags: [.command],
                isSearchExpanded: false
            )
        )
        XCTAssertFalse(
            HistoryPanelKeyEventRouting.shouldHandleSearchCopyShortcut(
                firstResponder: NSTextView(),
                charactersIgnoringModifiers: "c",
                modifierFlags: [.command, .option],
                isSearchExpanded: true
            )
        )
    }

    func testPrintableKeyDetectionOnlyAcceptsSingleUnmodifiedCharacters() {
        XCTAssertEqual(
            HistoryPanelPrintableKey.character(
                charactersIgnoringModifiers: "a",
                modifierFlags: []
            ),
            "a"
        )
        XCTAssertEqual(
            HistoryPanelPrintableKey.character(
                charactersIgnoringModifiers: "A",
                modifierFlags: [.shift]
            ),
            "A"
        )
        XCTAssertNil(
            HistoryPanelPrintableKey.character(
                charactersIgnoringModifiers: "c",
                modifierFlags: [.command]
            )
        )
        XCTAssertNil(
            HistoryPanelPrintableKey.character(
                charactersIgnoringModifiers: "\u{7F}",
                modifierFlags: []
            )
        )
    }

    func testScrollRevealKeepsFullyVisibleSelectionInPlace() {
        let cardFrame = CGRect(x: 28, y: 0, width: HistoryCardLayout.cardWidth, height: HistoryCardLayout.cardHeight)

        XCTAssertNil(
            HistoryPanelScrollReveal.anchor(
                forCardFrame: cardFrame,
                viewportWidth: 900
            )
        )
    }

    func testScrollRevealUsesTrailingAnchorWhenSelectionExtendsPastRightEdge() {
        let cardFrame = CGRect(x: 760, y: 0, width: HistoryCardLayout.cardWidth, height: HistoryCardLayout.cardHeight)

        XCTAssertEqual(
            HistoryPanelScrollReveal.anchor(
                forCardFrame: cardFrame,
                viewportWidth: 900
            ),
            .trailing
        )
    }

    func testScrollRevealTrailingUnitPointLeavesRightInset() {
        let viewportWidth: CGFloat = 900
        let cardWidth = HistoryCardLayout.cardWidth
        let unitPoint = HistoryPanelScrollReveal.unitPoint(
            for: .trailing,
            viewportWidth: viewportWidth,
            cardWidth: cardWidth
        )
        let revealedRightEdge = unitPoint.x * viewportWidth + (1 - unitPoint.x) * cardWidth

        XCTAssertEqual(
            revealedRightEdge,
            viewportWidth - HistoryPanelScrollReveal.trailingRevealInset,
            accuracy: 0.001
        )
    }

    func testScrollRevealUsesLeadingAnchorWhenSelectionExtendsPastLeftEdge() {
        let cardFrame = CGRect(x: -40, y: 0, width: HistoryCardLayout.cardWidth, height: HistoryCardLayout.cardHeight)

        XCTAssertEqual(
            HistoryPanelScrollReveal.anchor(
                forCardFrame: cardFrame,
                viewportWidth: 900
            ),
            .leading
        )
    }

    func testScrollRevealFallsBackToTrailingWhenSelectionMovesRightBeforeFrameIsMeasured() {
        XCTAssertEqual(
            HistoryPanelScrollReveal.fallbackAnchor(previousIndex: 2, selectedIndex: 3),
            .trailing
        )
    }

    func testScrollRevealFallsBackToLeadingWhenSelectionMovesLeftBeforeFrameIsMeasured() {
        XCTAssertEqual(
            HistoryPanelScrollReveal.fallbackAnchor(previousIndex: 4, selectedIndex: 3),
            .leading
        )
    }

    func testExpandedSearchWidthIsReducedByHalf() {
        XCTAssertEqual(HistoryPanelSearchLayout.expandedWidth, 180)
    }

    func testSearchInsertionPointRangeUsesEndWithoutSelection() {
        let range = HistoryPanelSearchSelection.insertionPointAtEnd(of: "ab")

        XCTAssertEqual(range.location, 2)
        XCTAssertEqual(range.length, 0)
    }

    func testGroupNameEditingSelectionUsesFullTextRange() {
        let range = HistoryPanelTextSelection.fullRange(of: "Untitled")

        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 8)
    }

    func testSearchCommandRoutingCollapsesEmptySearchOnBackspace() {
        XCTAssertTrue(
            HistoryPanelSearchCommandRouting.shouldCollapseEmptySearch(
                text: "",
                commandSelector: #selector(NSResponder.deleteBackward(_:))
            )
        )
        XCTAssertFalse(
            HistoryPanelSearchCommandRouting.shouldCollapseEmptySearch(
                text: "a",
                commandSelector: #selector(NSResponder.deleteBackward(_:))
            )
        )
    }

    func testPreviewTextNormalizesEscapedAndRealNewlinesForCards() {
        let item = makeItem(
            sourceHash: "escaped-newlines",
            displayTitle: "Escaped",
            plainText: "Release notes polish\\n- tighten card hierarchy\n- improve toolbar"
        )

        XCTAssertEqual(
            item.cardPreviewText,
            "Release notes polish\n- tighten card hierarchy\n- improve toolbar"
        )
    }
}
