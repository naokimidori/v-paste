import AppKit
import Carbon
import XCTest
@testable import V_Paste

@MainActor
final class HistoryPanelViewModelTests: XCTestCase {
    func testCardLayoutContentHeightMatchesCardMinusHeader() {
        XCTAssertEqual(
            HistoryCardLayout.contentHeight,
            HistoryCardLayout.cardHeight - HistoryCardLayout.headerHeight
        )
    }

    func testCardLayoutUsesSquareAspectRatio() {
        XCTAssertEqual(HistoryCardLayout.cardHeight, HistoryCardLayout.cardWidth)
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

    func testSearchFiltersItemsAndMovesSelectionToFirstResult() {
        let titleMatch = makeItem(
            sourceHash: "title",
            displayTitle: "Project Needle",
            plainText: "ordinary text"
        )
        let plainTextMatch = makeItem(
            sourceHash: "plain",
            displayTitle: "Plain",
            plainText: "contains needle in body"
        )
        let fileNameMatch = makeItem(
            sourceHash: "file",
            displayTitle: "File",
            plainText: nil,
            fileName: "needle-notes.txt"
        )
        let urlMatch = makeItem(
            sourceHash: "url",
            displayTitle: "URL",
            plainText: nil,
            urlString: "https://example.com/needle"
        )
        let miss = makeItem(
            sourceHash: "miss",
            displayTitle: "Other",
            plainText: "not relevant"
        )
        let viewModel = HistoryPanelViewModel(items: [miss, titleMatch, plainTextMatch, fileNameMatch, urlMatch])
        viewModel.moveSelection(delta: 2)

        viewModel.updateSearchText("NEEDLE")

        XCTAssertEqual(viewModel.searchText, "NEEDLE")
        XCTAssertEqual(viewModel.filteredItems.map(\.sourceHash), ["title", "plain", "file", "url"])
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedItem, titleMatch)
    }

    func testSearchStartsCollapsedAndEmpty() {
        let viewModel = HistoryPanelViewModel(items: [])

        XCTAssertFalse(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "")
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

    func testExpandSearchWithCharacterExpandsAndInsertsCharacter() {
        let viewModel = HistoryPanelViewModel(items: [])

        viewModel.expandSearch(with: "a")

        XCTAssertTrue(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "a")
    }

    func testExpandSearchCanRequestFocusForDirectTyping() {
        let viewModel = HistoryPanelViewModel(items: [])

        viewModel.expandSearch(with: "a", requestFocus: true)

        XCTAssertTrue(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "a")
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
    }

    func testDeleteLastSearchCharacterUpdatesQueryAndRequestsFocus() {
        let shorterMatch = makeItem(
            sourceHash: "short",
            displayTitle: "Short",
            plainText: "a"
        )
        let longerMatch = makeItem(
            sourceHash: "long",
            displayTitle: "Long",
            plainText: "ab"
        )
        let viewModel = HistoryPanelViewModel(items: [shorterMatch, longerMatch])
        viewModel.expandSearch(with: "ab")

        viewModel.deleteLastSearchCharacter(requestFocus: true)

        XCTAssertTrue(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "a")
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
        XCTAssertEqual(viewModel.filteredItems.map(\.sourceHash), ["short", "long"])
    }

    func testDeleteLastSearchCharacterKeepsSearchExpandedAfterClearingLastCharacter() {
        let viewModel = HistoryPanelViewModel(items: [])
        viewModel.expandSearch(with: "a")

        viewModel.deleteLastSearchCharacter(requestFocus: true)

        XCTAssertTrue(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
    }

    func testDeleteLastSearchCharacterCollapsesWhenSearchIsAlreadyEmpty() {
        let viewModel = HistoryPanelViewModel(items: [])
        viewModel.expandSearch(requestFocus: true)

        viewModel.deleteLastSearchCharacter(requestFocus: true)

        XCTAssertFalse(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
    }

    func testResetSearchForPresentationClearsQueryAndCollapsesSearch() {
        let matchingItem = makeItem(
            sourceHash: "matching",
            displayTitle: "Needle",
            plainText: "Needle"
        )
        let hiddenItem = makeItem(
            sourceHash: "hidden",
            displayTitle: "Haystack",
            plainText: "Haystack"
        )
        let viewModel = HistoryPanelViewModel(items: [matchingItem, hiddenItem])
        viewModel.expandSearch(with: "needle", requestFocus: true)

        viewModel.resetSearchForPresentation()

        XCTAssertFalse(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
        XCTAssertEqual(viewModel.filteredItems.map(\.sourceHash), ["matching", "hidden"])
    }

    func testClearSearchEmptiesQueryAndCollapsesSearch() {
        let viewModel = HistoryPanelViewModel(items: [])
        viewModel.expandSearch(with: "needle")

        viewModel.clearSearch()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertFalse(viewModel.isSearchExpanded)
    }

    func testCollapseSearchIfEmptyKeepsNonEmptySearchExpanded() {
        let viewModel = HistoryPanelViewModel(items: [])
        viewModel.expandSearch(with: "a")

        viewModel.collapseSearchIfEmpty()

        XCTAssertTrue(viewModel.isSearchExpanded)
        XCTAssertEqual(viewModel.searchText, "a")
    }

    func testSetActiveGroupFiltersItemsToGroupScope() {
        let workID = UUID()
        let personalID = UUID()
        let work = makeItem(
            sourceHash: "work",
            displayTitle: "Work",
            plainText: "Work",
            groupID: workID
        )
        let personal = makeItem(
            sourceHash: "personal",
            displayTitle: "Personal",
            plainText: "Personal",
            groupID: personalID
        )
        let viewModel = HistoryPanelViewModel(items: [work, personal])

        viewModel.setActiveGroup(workID)

        XCTAssertEqual(viewModel.activeGroupID, workID)
        XCTAssertEqual(viewModel.filteredItems, [work])
        XCTAssertEqual(viewModel.selectedItem, work)
    }

    func testSetActiveGroupTogglesOffWhenSelectingCurrentGroup() {
        let workID = UUID()
        let work = makeItem(
            sourceHash: "work",
            displayTitle: "Work",
            plainText: "Work",
            groupID: workID
        )
        let ungrouped = makeItem(
            sourceHash: "ungrouped",
            displayTitle: "Ungrouped",
            plainText: "Ungrouped"
        )
        let viewModel = HistoryPanelViewModel(items: [work, ungrouped])

        viewModel.setActiveGroup(workID)
        viewModel.setActiveGroup(workID)

        XCTAssertNil(viewModel.activeGroupID)
        XCTAssertEqual(viewModel.filteredItems, [work, ungrouped])
        XCTAssertEqual(viewModel.selectedItem, work)
    }

    func testSearchFiltersInsideActiveGroupScope() {
        let workID = UUID()
        let personalID = UUID()
        let workMatch = makeItem(
            sourceHash: "work-match",
            displayTitle: "Needle Work",
            plainText: "Work",
            groupID: workID
        )
        let workMiss = makeItem(
            sourceHash: "work-miss",
            displayTitle: "Other Work",
            plainText: "Work",
            groupID: workID
        )
        let personalMatch = makeItem(
            sourceHash: "personal-match",
            displayTitle: "Needle Personal",
            plainText: "Personal",
            groupID: personalID
        )
        let viewModel = HistoryPanelViewModel(items: [workMatch, workMiss, personalMatch])

        viewModel.setActiveGroup(workID)
        viewModel.updateSearchText("needle")

        XCTAssertEqual(viewModel.filteredItems, [workMatch])
    }

    func testUpdateItemsRepairsSelectionToNearestRemainingVisibleItem() {
        let groupID = UUID()
        let first = makeItem(
            sourceHash: "first",
            displayTitle: "First",
            plainText: "First",
            groupID: groupID
        )
        let second = makeItem(
            sourceHash: "second",
            displayTitle: "Second",
            plainText: "Second",
            groupID: groupID
        )
        let third = makeItem(
            sourceHash: "third",
            displayTitle: "Third",
            plainText: "Third",
            groupID: groupID
        )
        let viewModel = HistoryPanelViewModel(items: [first, second, third])
        viewModel.setActiveGroup(groupID)
        viewModel.selectItem(id: second.id)

        viewModel.updateItems([first, third])

        XCTAssertEqual(viewModel.filteredItems, [first, third])
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.selectedItem, third)
    }

    func testSelectionMovesRightAndClampsAtEnd() {
        let items = [
            makeItem(sourceHash: "first", displayTitle: "First", plainText: "First"),
            makeItem(sourceHash: "second", displayTitle: "Second", plainText: "Second"),
            makeItem(sourceHash: "third", displayTitle: "Third", plainText: "Third")
        ]
        let viewModel = HistoryPanelViewModel(items: items)

        viewModel.moveSelection(delta: 1)
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.selectedItem, items[1])

        viewModel.moveSelection(delta: 10)
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertEqual(viewModel.selectedItem, items[2])
    }

    func testSelectItemUpdatesSelectionWhenItemIsVisible() {
        let first = makeItem(sourceHash: "first", displayTitle: "First", plainText: "First")
        let second = makeItem(sourceHash: "second", displayTitle: "Needle Two", plainText: "Second")
        let hidden = makeItem(sourceHash: "hidden", displayTitle: "Hidden", plainText: "Hidden")
        let viewModel = HistoryPanelViewModel(items: [first, second, hidden])

        viewModel.updateSearchText("needle")
        viewModel.selectItem(id: hidden.id)
        XCTAssertEqual(viewModel.selectedItem, second)

        viewModel.selectItem(id: second.id)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedItem, second)
    }

    func testEmptyResultsSelectedIndexIsMinusOneAndSelectedItemIsNil() {
        let viewModel = HistoryPanelViewModel(items: [
            makeItem(sourceHash: "first", displayTitle: "First", plainText: "First")
        ])

        viewModel.updateSearchText("missing")

        XCTAssertEqual(viewModel.filteredItems, [])
        XCTAssertEqual(viewModel.selectedIndex, -1)
        XCTAssertNil(viewModel.selectedItem)
    }

    func testAppStateRefreshesPanelViewModelAfterIngest() throws {
        let state = AppState.preview()
        let originalViewModel = state.panelViewModel
        let first = makeItem(sourceHash: "first", displayTitle: "First", plainText: "First")
        let second = makeItem(sourceHash: "second", displayTitle: "Second", plainText: "Second")

        XCTAssertTrue(state.ingest(first))
        XCTAssertEqual(state.panelViewModel.filteredItems, [first])

        XCTAssertTrue(state.ingest(second))

        XCTAssertTrue(state.panelViewModel === originalViewModel)
        XCTAssertEqual(state.panelViewModel.allItems, [second, first])
        XCTAssertEqual(state.panelViewModel.filteredItems, [second, first])
        XCTAssertEqual(state.panelViewModel.selectedIndex, 0)
        XCTAssertEqual(state.panelViewModel.selectedItem, second)
    }

    func testUpdateItemsRefiltersUsingCurrentSearchTextAndKeepsSelectionWhenPossible() {
        let first = makeItem(sourceHash: "first", displayTitle: "Needle One", plainText: "First")
        let second = makeItem(sourceHash: "second", displayTitle: "Needle Two", plainText: "Second")
        let third = makeItem(sourceHash: "third", displayTitle: "Other", plainText: "Third")
        let viewModel = HistoryPanelViewModel(items: [first, second])
        viewModel.updateSearchText("needle")
        viewModel.moveSelection(delta: 1)

        viewModel.updateItems([third, second, first])

        XCTAssertEqual(viewModel.searchText, "needle")
        XCTAssertEqual(viewModel.filteredItems, [second, first])
        XCTAssertEqual(viewModel.selectedItem, second)
    }

    func testFavoritesFilterCombinesWithSearchAndCanReturnToAllResults() {
        let favoriteMatch = makeItem(
            sourceHash: "favorite-match",
            displayTitle: "Needle Favorite",
            plainText: "First",
            isFavorited: true
        )
        let favoriteMiss = makeItem(
            sourceHash: "favorite-miss",
            displayTitle: "Saved Clip",
            plainText: "Second",
            isFavorited: true
        )
        let ordinaryMatch = makeItem(
            sourceHash: "ordinary-match",
            displayTitle: "Needle Ordinary",
            plainText: "Third"
        )
        let viewModel = HistoryPanelViewModel(items: [favoriteMatch, favoriteMiss, ordinaryMatch])

        viewModel.updateSearchText("needle")
        XCTAssertEqual(viewModel.filteredItems, [favoriteMatch, ordinaryMatch])

        viewModel.toggleFavoritesOnly()

        XCTAssertTrue(viewModel.showsFavoritesOnly)
        XCTAssertEqual(viewModel.filteredItems, [favoriteMatch])
        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.toggleFavoritesOnly()

        XCTAssertFalse(viewModel.showsFavoritesOnly)
        XCTAssertEqual(viewModel.filteredItems, [favoriteMatch, ordinaryMatch])
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

    func testMenuBarDescriptorUsesRequestedSettingsMenu() {
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            shortcut: .defaultShowPanel
        )

        XCTAssertEqual(items.map(\.title), [
            "Show V-Paste",
            nil,
            "Preferences...",
            "About V-Paste",
            nil,
            "Quit"
        ])
        XCTAssertEqual(items[0].keyEquivalent, "~")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.option])
        XCTAssertEqual(items[0].shortcutDisplay, "⌥~")
        XCTAssertEqual(items[2].keyEquivalent, ",")
        XCTAssertEqual(items[2].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(items[5].keyEquivalent, "q")
        XCTAssertEqual(items[5].keyEquivalentModifierMask, [.command])
    }

    func testMenuBarDescriptorUsesChineseLanguage() {
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            language: .simplifiedChinese,
            shortcut: .defaultShowPanel
        )

        XCTAssertEqual(items.map(\.title), [
            "显示 V-Paste",
            nil,
            "偏好设置...",
            "关于 V-Paste",
            nil,
            "退出"
        ])
        XCTAssertEqual(items[0].keyEquivalent, "~")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.option])
        XCTAssertEqual(items[0].shortcutDisplay, "⌥~")
        XCTAssertEqual(items[2].keyEquivalent, ",")
        XCTAssertEqual(items[2].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(items[5].keyEquivalent, "q")
        XCTAssertEqual(items[5].keyEquivalentModifierMask, [.command])
    }

    func testMenuBarDescriptorUsesCustomShowPanelShortcut() {
        let shortcut = HotKeyPreference(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(shiftKey | cmdKey),
            keyEquivalent: "k",
            displayKey: "K"
        )
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            shortcut: shortcut
        )

        XCTAssertEqual(items[0].keyEquivalent, "k")
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(items[0].shortcutDisplay, "⇧⌘K")
    }

    func testMenuBarDescriptorRemovesDangerActionsFromStatusMenu() {
        let titles = MenuBarMenuDescriptor.items(appName: "V-Paste", shortcut: .defaultShowPanel)
            .compactMap(\.title)

        XCTAssertFalse(titles.contains("Pause Monitoring"))
        XCTAssertFalse(titles.contains("Resume Monitoring"))
        XCTAssertFalse(titles.contains("Clear History"))
    }

    func testPanelOverflowMenuDescriptorOmitsShowPanelAction() {
        let items = MenuBarMenuDescriptor.panelOverflowItems(
            appName: "V-Paste",
            shortcut: .defaultShowPanel
        )

        XCTAssertEqual(items.map(\.title), [
            "Preferences...",
            "About V-Paste",
            nil,
            "Quit"
        ])
        XCTAssertEqual(items.map(\.action), [
            .openPreferences,
            .openAbout,
            nil,
            .quit
        ])
        XCTAssertFalse(items.contains { $0.action == .showPanel })
    }

    func testPanelOverflowMenuDescriptorUsesRequestedLanguage() {
        let items = MenuBarMenuDescriptor.panelOverflowItems(
            appName: "V-Paste",
            language: .simplifiedChinese,
            shortcut: .defaultShowPanel,
            appVersion: "1.0.1"
        )

        XCTAssertEqual(items.map(\.title), [
            "偏好设置...",
            "关于 V-Paste",
            nil,
            "退出"
        ])
        XCTAssertEqual(items[1].children.map(\.title), [
            "版本 1.0.1",
            "GitHub 仓库"
        ])
        XCTAssertEqual(items[1].children.map(\.action), [
            nil,
            .openGitHub
        ])
        XCTAssertEqual(
            items[1].children[1].iconAssetName,
            MenuBarAboutDescriptor.githubIconAssetName
        )
        XCTAssertEqual(
            MenuBarAboutDescriptor.repositoryURL.absoluteString,
            "https://github.com/naokimidori/v-paste"
        )
    }

    func testMenuBarAboutDescriptorUsesVersionAndGitHubAction() throws {
        let items = MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            language: .english,
            shortcut: .defaultShowPanel,
            appVersion: "1.0.1"
        )

        let aboutItem = try XCTUnwrap(items.first { $0.action == .openAbout })
        XCTAssertEqual(aboutItem.title, "About V-Paste")
        XCTAssertEqual(aboutItem.children.map(\.title), [
            "Version 1.0.1",
            "GitHub Repository"
        ])
        XCTAssertEqual(aboutItem.children.map(\.action), [
            nil,
            .openGitHub
        ])
        XCTAssertEqual(
            aboutItem.children[1].iconAssetName,
            MenuBarAboutDescriptor.githubIconAssetName
        )
    }

    func testHistoryPanelViewModelKeepsCurrentLanguageForOverflowMenu() {
        let viewModel = HistoryPanelViewModel(items: [])

        XCTAssertEqual(viewModel.language, .english)

        viewModel.setLanguage(.simplifiedChinese)

        XCTAssertEqual(viewModel.language, .simplifiedChinese)
        XCTAssertEqual(
            MenuBarMenuDescriptor.panelOverflowItems(
                appName: "V-Paste",
                language: viewModel.language,
                shortcut: .defaultShowPanel
            ).map(\.title),
            [
                "偏好设置...",
                "关于 V-Paste",
                nil,
                "退出"
            ]
        )
    }

    func testAppStatePropagatesLanguageToPanelViewModel() {
        let state = AppState.preview()

        state.setLanguage(.simplifiedChinese)

        XCTAssertEqual(state.panelViewModel.language, .simplifiedChinese)
    }

    func testSettingsPreferencesUseSingleGroupOrder() {
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .english).map(\.title), [
            "Status",
            "Launch at Login",
            "Monitor Clipboard",
            "Show V-Paste",
            "History Retention",
            "Language",
            "About V-Paste"
        ])
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .english).map(\.detail), [
            nil,
            nil,
            nil,
            "⌥~",
            "30 days",
            "English",
            "Debug"
        ])
    }

    func testSettingsPreferencesUseChineseLanguage() {
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .simplifiedChinese).map(\.title), [
            "运行状态",
            "开机自启",
            "监听剪贴板",
            "显示 V-Paste",
            "历史记录有效期",
            "语言",
            "关于 V-Paste"
        ])
        XCTAssertEqual(SettingsPreferenceDescriptor.singleGroup(language: .simplifiedChinese).map(\.detail), [
            nil,
            nil,
            nil,
            "⌥~",
            "30 天",
            "简体中文",
            "Debug"
        ])
    }

    func testSettingsTabsSeparateApplicationIgnoreGroup() {
        XCTAssertEqual(SettingsTabDescriptor.all(language: .english).map(\.title), [
            "General",
            "App Ignore"
        ])
        XCTAssertEqual(SettingsTabDescriptor.all(language: .simplifiedChinese).map(\.title), [
            "通用",
            "应用忽略"
        ])
    }

    func testIgnoredApplicationsUseVerticalListMetrics() {
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppIconSize, 24)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppListRowHeight, 34)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsListHeight, 144)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsPickerWidth, 0)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsDescriptionHeight, 46)
        XCTAssertEqual(SettingsViewLayoutMetrics.ignoredAppsToggleRowHeight, 28)
    }

    func testIgnoredApplicationsDescriptorLocalizesListActions() {
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.title(language: .english), "App Ignore")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.title(language: .simplifiedChinese), "应用忽略")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.enabledTitle(language: .english), "Enable App Ignore")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.enabledTitle(language: .simplifiedChinese), "启用应用忽略")
        XCTAssertEqual(
            SettingsIgnoredAppsDescriptor.explanation(language: .english),
            "When enabled, V-Paste will not save clipboard content copied from the apps below. Use it for Keychain Access, password managers, or other sensitive apps."
        )
        XCTAssertEqual(
            SettingsIgnoredAppsDescriptor.explanation(language: .simplifiedChinese),
            "开启后，V-Paste 不会保存下列应用产生的剪贴板内容。适合钥匙串、密码管理器等敏感应用。"
        )
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.addTitle(language: .english), "Add...")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.addTitle(language: .simplifiedChinese), "添加...")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.removeTitle(language: .english), "Remove")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.removeTitle(language: .simplifiedChinese), "移除")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.resetTitle(language: .english), "Defaults")
        XCTAssertEqual(SettingsIgnoredAppsDescriptor.resetTitle(language: .simplifiedChinese), "恢复默认")
    }

    func testShortcutSettingsDescriptorShowsCurrentShortcut() {
        XCTAssertEqual(SettingsShortcutDescriptor.showPanelTitle(language: .english), "Show V-Paste")
        XCTAssertEqual(SettingsShortcutDescriptor.showPanelTitle(language: .simplifiedChinese), "显示 V-Paste")
        XCTAssertEqual(SettingsShortcutDescriptor.currentShortcutLabel, "⌥~")
    }

    func testShortcutRecordingCopyLocalizes() {
        XCTAssertEqual(SettingsShortcutDescriptor.recordingPrompt(language: .english), "Press shortcut")
        XCTAssertEqual(SettingsShortcutDescriptor.recordingPrompt(language: .simplifiedChinese), "按下快捷键")
        XCTAssertEqual(SettingsShortcutDescriptor.invalidShortcutMessage(language: .english), "Shortcut requires a modifier key")
        XCTAssertEqual(SettingsShortcutDescriptor.invalidShortcutMessage(language: .simplifiedChinese), "快捷键需要包含修饰键")
    }

    func testHotKeyPreferenceCapturesModifiedKeyboardShortcut() {
        let shortcut = HotKeyPreference.capture(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: [.command, .shift],
            charactersIgnoringModifiers: "k"
        )

        XCTAssertEqual(shortcut?.displayLabel, "⇧⌘K")
        XCTAssertEqual(shortcut?.keyEquivalent, "k")
        XCTAssertEqual(shortcut?.keyEquivalentModifierMask, [.command, .shift])
    }

    func testHotKeyPreferenceRejectsShortcutWithoutModifier() {
        XCTAssertNil(HotKeyPreference.capture(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: [],
            charactersIgnoringModifiers: "k"
        ))
    }

    func testClipboardRetentionPolicyUsesRequestedOptions() {
        XCTAssertEqual(ClipboardRetentionPolicy.allCases.map { $0.title(language: .english) }, [
            "7 days",
            "30 days",
            "Unlimited"
        ])
        XCTAssertEqual(ClipboardRetentionPolicy.allCases.map { $0.title(language: .simplifiedChinese) }, [
            "7 天",
            "30 天",
            "不限制"
        ])
        XCTAssertEqual(ClipboardRetentionPolicy.sevenDays.dayCount, 7)
        XCTAssertEqual(ClipboardRetentionPolicy.thirtyDays.dayCount, 30)
        XCTAssertNil(ClipboardRetentionPolicy.unlimited.dayCount)
    }

    func testAppPreferencesRoundTripsLanguageRetentionAndShortcut() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferences(userDefaults: defaults)
        let shortcut = HotKeyPreference(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey),
            keyEquivalent: "k",
            displayKey: "K"
        )

        XCTAssertEqual(preferences.language, .english)
        preferences.language = .simplifiedChinese
        preferences.clipboardRetentionPolicy = .sevenDays
        preferences.showPanelHotKey = shortcut

        let loadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(loadedPreferences.language, .simplifiedChinese)
        XCTAssertEqual(loadedPreferences.clipboardRetentionPolicy, .sevenDays)
        XCTAssertEqual(loadedPreferences.showPanelHotKey, shortcut)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testIgnoredApplicationDefaultsIncludeSecureApps() {
        XCTAssertTrue(IgnoredApplicationRule.defaultRules.contains {
            $0.bundleIdentifier == "com.apple.keychainaccess"
        })
        XCTAssertTrue(IgnoredApplicationRule.defaultRules.contains {
            $0.bundleIdentifier == "com.apple.SecurityAgent"
        })
    }

    func testIgnoredApplicationRuleMatchesBundleIdentifierCaseInsensitively() {
        let rule = IgnoredApplicationRule(
            name: "Keychain Access",
            bundleIdentifier: "com.apple.keychainaccess"
        )
        let sourceApplication = ClipboardSourceApplication(
            name: "Keychain Access",
            bundleIdentifier: "COM.APPLE.KEYCHAINACCESS"
        )

        XCTAssertTrue(rule.matches(sourceApplication))
    }

    func testIgnoredApplicationMatchingCanBeDisabled() {
        let sourceApplication = ClipboardSourceApplication(
            name: "Keychain Access",
            bundleIdentifier: "com.apple.keychainaccess"
        )

        XCTAssertTrue(IgnoredApplicationRule.isIgnored(
            sourceApplication,
            rules: IgnoredApplicationRule.defaultRules,
            isEnabled: true
        ))
        XCTAssertFalse(IgnoredApplicationRule.isIgnored(
            sourceApplication,
            rules: IgnoredApplicationRule.defaultRules,
            isEnabled: false
        ))
    }

    func testApplicationIgnorePreferenceDefaultsOnAndCanBeDisabled() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferences(userDefaults: defaults)

        XCTAssertTrue(preferences.isApplicationIgnoreEnabled)

        preferences.isApplicationIgnoreEnabled = false

        let loadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertFalse(loadedPreferences.isApplicationIgnoreEnabled)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAppPreferencesRoundTripsIgnoredApplications() throws {
        let suiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = AppPreferences(userDefaults: defaults)
        let customRules = [
            IgnoredApplicationRule(
                name: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        ]

        XCTAssertGreaterThanOrEqual(preferences.ignoredApplications.count, 2)

        preferences.ignoredApplications = customRules

        let loadedPreferences = AppPreferences(userDefaults: defaults)
        XCTAssertEqual(loadedPreferences.ignoredApplications, customRules)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSettingsPanelDescriptorUsesPopupContentMetrics() {
        XCTAssertEqual(SettingsPanelDescriptor.title(language: .english), "Preferences")
        XCTAssertEqual(SettingsPanelDescriptor.title(language: .simplifiedChinese), "偏好设置")
        XCTAssertEqual(SettingsPanelDescriptor.contentSize, CGSize(width: 580, height: 380))
    }

    func testSettingsPanelPlacementKeepsHorizontalCenterAndUsesUpperThirdVerticalPosition() {
        let frame = SettingsPanelPlacement.preferredFrame(
            contentSize: CGSize(width: 580, height: 420),
            screenFrame: NSRect(x: 100, y: 60, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, NSRect(x: 530, y: 450, width: 580, height: 420))
    }

    func testSettingsViewUsesCompactBorderlessContentLayout() {
        XCTAssertEqual(SettingsViewLayoutMetrics.horizontalPadding, 22)
        XCTAssertEqual(SettingsViewLayoutMetrics.topPadding, 8)
        XCTAssertEqual(SettingsViewLayoutMetrics.bottomPadding, 8)
        XCTAssertEqual(SettingsViewLayoutMetrics.topPadding, SettingsViewLayoutMetrics.bottomPadding)
        XCTAssertEqual(SettingsViewLayoutMetrics.groupTopPadding, 10)
        XCTAssertEqual(SettingsViewLayoutMetrics.groupBottomPadding, 10)
        XCTAssertFalse(SettingsViewLayoutMetrics.drawsGroupBorder)
    }

    func testSettingsViewUsesManualTabSwitcherToAvoidNativeTabContainerCycle() {
        XCTAssertTrue(SettingsViewLayoutMetrics.usesManualTabSwitcher)
    }

    func testSettingsPanelHeightKeepsClearHistoryButtonVisible() {
        XCTAssertEqual(SettingsViewLayoutMetrics.clearHistoryButtonRowHeight, 28)
        XCTAssertGreaterThanOrEqual(
            SettingsPanelDescriptor.contentSize.height,
            SettingsViewLayoutMetrics.minimumHeightForClearHistoryButton
        )
    }

    func testSettingsPanelHeightFitsIgnoredApplicationsTab() {
        XCTAssertGreaterThanOrEqual(
            SettingsPanelDescriptor.contentSize.height,
            SettingsViewLayoutMetrics.minimumHeightForIgnoredApplicationsTab
        )
    }

    func testClearHistoryUsesDestructiveConfirmationCopy() {
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.title(language: .english), "Clear history?")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.title(language: .simplifiedChinese), "确认清空历史？")
        XCTAssertEqual(
            SettingsClearHistoryConfirmationDescriptor.message(language: .simplifiedChinese),
            "此操作会删除所有剪贴板记录，无法撤销。"
        )
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.confirmTitle(language: .english), "Clear History")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.confirmTitle(language: .simplifiedChinese), "清空历史")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.cancelTitle(language: .english), "Cancel")
        XCTAssertEqual(SettingsClearHistoryConfirmationDescriptor.cancelTitle(language: .simplifiedChinese), "取消")
    }

    func testMenuBarDescriptorMapsItemsToActions() {
        XCTAssertEqual(MenuBarMenuAction.showPanel.selectorName, "openClipboardHistory")
        XCTAssertEqual(MenuBarMenuAction.openPreferences.selectorName, "openPreferences")
        XCTAssertEqual(MenuBarMenuAction.openAbout.selectorName, "openAbout")
        XCTAssertEqual(MenuBarMenuAction.openGitHub.selectorName, "openGitHub")
        XCTAssertEqual(MenuBarMenuAction.quit.selectorName, "quit")
    }
}

private func makeItem(
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
        contentType: .text,
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
