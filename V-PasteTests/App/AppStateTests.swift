import Combine
import XCTest
@testable import V_Paste

@MainActor
final class AppStateTests: XCTestCase {
    func testInitialStateStartsVisibleFlagsAsFalse() {
        let state = AppState.preview()

        XCTAssertFalse(state.isPanelVisible)
        XCTAssertFalse(state.isMonitoringPaused)
        XCTAssertEqual(state.searchText, "")
        XCTAssertEqual(state.items.count, 0)
    }

    func testPreviewStartsWithoutGroupsOrSelection() {
        let state = AppState.preview()

        XCTAssertEqual(state.groups, [])
        XCTAssertNil(state.activeGroupID)
        XCTAssertNil(state.activeGroup)
        XCTAssertEqual(state.panelViewModel.groups, [])
        XCTAssertNil(state.panelViewModel.activeGroupID)
    }

    func testLoadGroupsKeepsNoSelectionAndPreservesUngroupedLoadedItems() {
        let state = AppState.preview()
        let work = makeGroup(name: "Work", sortOrder: 0)
        let personal = makeGroup(name: "Personal", sortOrder: 1)
        let ungrouped = makeItem(
            sourceHash: "ungrouped",
            displayTitle: "Ungrouped",
            plainText: "Ungrouped",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false
        )
        let grouped = makeItem(
            sourceHash: "grouped",
            displayTitle: "Grouped",
            plainText: "Grouped",
            createdAt: Date(timeIntervalSince1970: 2),
            lastCopiedAt: Date(timeIntervalSince1970: 2),
            isFavorited: false,
            groupID: personal.id
        )

        state.loadGroups([work, personal])
        state.loadItems([ungrouped, grouped])

        XCTAssertEqual(state.groups, [work, personal])
        XCTAssertNil(state.activeGroupID)
        XCTAssertEqual(state.items.map(\.groupID), [nil, personal.id])
        XCTAssertNil(state.panelViewModel.activeGroupID)
        XCTAssertEqual(state.panelViewModel.filteredItems.map(\.id), [ungrouped.id, grouped.id])
    }

    func testCreateGroupMakesNewGroupActive() throws {
        let state = AppState.preview()

        let group = state.createGroup(name: "Work", colorHex: "#4B8DFF")

        XCTAssertEqual(state.groups.last, group)
        XCTAssertEqual(group.name, "Work")
        XCTAssertEqual(group.colorHex, "#4B8DFF")
        XCTAssertEqual(state.activeGroupID, group.id)
        XCTAssertEqual(state.panelViewModel.activeGroupID, group.id)
    }

    func testCreateGroupWithoutExplicitColorUsesFirstUnusedPaletteColor() {
        let state = AppState.preview()

        let firstGroup = state.createGroup()
        let secondGroup = state.createGroup()

        XCTAssertEqual(firstGroup.colorHex, ClipboardGroupColorPalette.hexValues[0])
        XCTAssertEqual(secondGroup.colorHex, ClipboardGroupColorPalette.hexValues[1])
    }

    func testCreateGroupUsesCurrentLanguageForDefaultName() {
        let state = AppState.preview()

        state.setLanguage(.simplifiedChinese)
        let group = state.createGroup()

        XCTAssertEqual(group.name, "未命名")
        XCTAssertEqual(state.groups.last?.name, "未命名")
    }

    func testUpdateGroupReplacesExistingGroup() throws {
        let state = AppState.preview()
        let group = state.createGroup(name: "Work", colorHex: "#4B8DFF")
        let renamed = ClipboardGroup(
            id: group.id,
            name: "Clients",
            colorHex: "#8B65FF",
            createdAt: group.createdAt,
            sortOrder: group.sortOrder
        )

        state.updateGroup(renamed)

        XCTAssertEqual(state.groups.last, renamed)
        XCTAssertEqual(state.activeGroup, renamed)
    }

    func testDeleteGroupUngroupsItemsAndClearsDeletedSelection() {
        let state = AppState.preview()
        let work = state.createGroup(name: "Work", colorHex: "#4B8DFF")
        let code = state.createGroup(name: "Code", colorHex: "#26B36A")
        let workItem = makeItem(
            sourceHash: "work",
            displayTitle: "Work",
            plainText: "Work",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false,
            groupID: work.id
        )
        let codeItem = makeItem(
            sourceHash: "code",
            displayTitle: "Code",
            plainText: "Code",
            createdAt: Date(timeIntervalSince1970: 2),
            lastCopiedAt: Date(timeIntervalSince1970: 2),
            isFavorited: false,
            groupID: code.id
        )
        state.loadItems([workItem, codeItem])
        state.setActiveGroup(code.id)

        let deleted = state.deleteGroup(id: code.id)

        XCTAssertEqual(deleted, code)
        XCTAssertEqual(state.groups.map(\.id), [work.id])
        XCTAssertNil(state.activeGroupID)
        XCTAssertNil(state.items.first(where: { $0.id == codeItem.id })?.groupID)
        XCTAssertEqual(state.items.first(where: { $0.id == workItem.id })?.groupID, work.id)
        XCTAssertNil(state.panelViewModel.activeGroupID)
        XCTAssertEqual(state.panelViewModel.filteredItems.map(\.id), [workItem.id, codeItem.id])
    }

    func testDeleteOnlyGroupRemovesItAndLeavesNoGroups() {
        let state = AppState.preview()
        let group = state.createGroup(name: "Solo", colorHex: "#4B8DFF")

        let deleted = state.deleteGroup(id: group.id)

        XCTAssertEqual(deleted, group)
        XCTAssertEqual(state.groups, [])
        XCTAssertNil(state.activeGroupID)
        XCTAssertEqual(state.panelViewModel.groups, [])
    }

    func testAssignItemToGroupUpdatesItemsAndPanelViewModel() throws {
        let state = AppState.preview()
        let work = state.createGroup(name: "Work", colorHex: "#4B8DFF")
        let item = makeItem(
            sourceHash: "item",
            displayTitle: "Item",
            plainText: "Item",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false
        )
        state.loadItems([item])

        let updated = try XCTUnwrap(state.assignItem(id: item.id, to: work.id))

        XCTAssertEqual(updated.groupID, work.id)
        XCTAssertEqual(state.items.first?.groupID, work.id)
        XCTAssertEqual(state.panelViewModel.allItems.first?.groupID, work.id)
        XCTAssertEqual(state.panelViewModel.filteredItems, [updated])
    }

    func testDeleteItemUpdatesItemsAndRepairsPanelSelection() {
        let state = AppState.preview()
        let group = state.createGroup(name: "Work", colorHex: "#4B8DFF")
        let first = makeItem(
            sourceHash: "first",
            displayTitle: "First",
            plainText: "First",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false,
            groupID: group.id
        )
        let second = makeItem(
            sourceHash: "second",
            displayTitle: "Second",
            plainText: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            lastCopiedAt: Date(timeIntervalSince1970: 2),
            isFavorited: false,
            groupID: group.id
        )
        let third = makeItem(
            sourceHash: "third",
            displayTitle: "Third",
            plainText: "Third",
            createdAt: Date(timeIntervalSince1970: 3),
            lastCopiedAt: Date(timeIntervalSince1970: 3),
            isFavorited: false,
            groupID: group.id
        )
        state.loadItems([first, second, third])
        state.panelViewModel.selectItem(id: second.id)

        let deleted = state.deleteItem(id: second.id)

        XCTAssertEqual(deleted?.id, second.id)
        XCTAssertEqual(state.items.map(\.id), [first.id, third.id])
        XCTAssertEqual(state.panelViewModel.filteredItems.map(\.id), [first.id, third.id])
        XCTAssertEqual(state.panelViewModel.selectedItem?.id, third.id)
    }

    func testToggleMonitoringPausedFlipsPausedFlag() {
        let state = AppState.preview()

        state.toggleMonitoringPaused()

        XCTAssertTrue(state.isMonitoringPaused)

        state.toggleMonitoringPaused()

        XCTAssertFalse(state.isMonitoringPaused)
    }

    func testPauseAndResumeMonitoringSetPausedFlag() {
        let state = AppState.preview()

        state.pauseMonitoring()
        XCTAssertTrue(state.isMonitoringPaused)

        state.resumeMonitoring()
        XCTAssertFalse(state.isMonitoringPaused)
    }

    func testPauseAndResumeMonitoringDoNotPublishWhenStateIsUnchanged() {
        let state = AppState.preview()
        var changeCount = 0
        let cancellable = state.objectWillChange.sink {
            changeCount += 1
        }

        state.resumeMonitoring()
        XCTAssertEqual(changeCount, 0)

        state.pauseMonitoring()
        XCTAssertEqual(changeCount, 1)

        state.pauseMonitoring()
        XCTAssertEqual(changeCount, 1)

        _ = cancellable
    }

    func testIngestDeduplicatesBySourceHashAndMovesLatestItemToFront() {
        let state = AppState.preview()
        let original = ClipboardItem.text(
            plainText: "duplicate",
            copiedAt: Date(timeIntervalSince1970: 1)
        )
        let other = ClipboardItem.text(
            plainText: "other",
            copiedAt: Date(timeIntervalSince1970: 2)
        )
        let latestDuplicate = ClipboardItem.text(
            plainText: "duplicate",
            copiedAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertTrue(state.ingest(original))
        XCTAssertTrue(state.ingest(other))
        XCTAssertTrue(state.ingest(latestDuplicate))

        XCTAssertEqual(state.items.map(\.sourceHash), ["duplicate", "other"])
        XCTAssertEqual(state.items.first?.lastCopiedAt, Date(timeIntervalSince1970: 3))
    }

    func testIngestKeepsItemUngroupedWhenNoGroupIsSelected() {
        let state = AppState.preview()
        let item = makeItem(
            sourceHash: "ungrouped",
            displayTitle: "Ungrouped",
            plainText: "Ungrouped",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false
        )

        XCTAssertTrue(state.ingest(item))

        XCTAssertNil(state.activeGroupID)
        XCTAssertNil(state.items.first?.groupID)
        XCTAssertNil(state.panelViewModel.filteredItems.first?.groupID)
    }

    func testIngestAssignsActiveGroupWhenGroupIsSelected() {
        let state = AppState.preview()
        let group = state.createGroup(name: "Work", colorHex: "#4B8DFF")
        let item = makeItem(
            sourceHash: "ungrouped",
            displayTitle: "Ungrouped",
            plainText: "Ungrouped",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false
        )

        XCTAssertTrue(state.ingest(item))

        XCTAssertEqual(state.activeGroupID, group.id)
        XCTAssertEqual(state.items.first?.groupID, group.id)
        XCTAssertEqual(state.panelViewModel.filteredItems.first?.groupID, group.id)
    }

    func testSelectingActiveGroupAgainClearsSelection() {
        let state = AppState.preview()
        let group = state.createGroup(name: "Work", colorHex: "#4B8DFF")

        state.setActiveGroup(group.id)

        XCTAssertNil(state.activeGroupID)
        XCTAssertNil(state.panelViewModel.activeGroupID)
    }

    func testIngestRejectsItemsWhileMonitoringIsPaused() {
        let state = AppState.preview()
        state.pauseMonitoring()

        let didIngest = state.ingest(ClipboardItem.text(
            plainText: "paused",
            copiedAt: Date(timeIntervalSince1970: 1)
        ))

        XCTAssertFalse(didIngest)
        XCTAssertEqual(state.items, [])
    }

    func testClearHistoryRemovesItemsAndResetsSearch() {
        let state = AppState.preview()
        let item = ClipboardItem.text(
            plainText: "one",
            copiedAt: Date(timeIntervalSince1970: 1)
        )
        state.ingest(item)
        state.searchText = "one"
        state.panelViewModel.updateSearchText("one")

        state.clearHistory()

        XCTAssertEqual(state.items, [])
        XCTAssertEqual(state.searchText, "")
        XCTAssertEqual(state.panelViewModel.searchText, "")
        XCTAssertEqual(state.panelViewModel.filteredItems, [])
        XCTAssertNil(state.panelViewModel.selectedItem)
    }

    func testIngestPreservesOriginalCreatedAtAndFavoriteStateForDuplicate() {
        let state = AppState.preview()
        let originalCreatedAt = Date(timeIntervalSince1970: 1)
        let updatedCopiedAt = Date(timeIntervalSince1970: 5)
        let original = makeItem(
            sourceHash: "duplicate",
            displayTitle: "Original",
            plainText: "Original",
            createdAt: originalCreatedAt,
            lastCopiedAt: originalCreatedAt,
            isFavorited: true
        )
        let updated = makeItem(
            sourceHash: "duplicate",
            displayTitle: "Updated",
            plainText: "Updated",
            createdAt: updatedCopiedAt,
            lastCopiedAt: updatedCopiedAt,
            isFavorited: false
        )

        XCTAssertTrue(state.ingest(original))
        XCTAssertTrue(state.ingest(updated))

        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[0].displayTitle, "Updated")
        XCTAssertEqual(state.items[0].plainText, "Updated")
        XCTAssertEqual(state.items[0].createdAt, originalCreatedAt)
        XCTAssertEqual(state.items[0].lastCopiedAt, updatedCopiedAt)
        XCTAssertTrue(state.items[0].isFavorited)
    }

    func testDuplicateIngestPreservesPreviousGroupMembership() {
        let state = AppState.preview()
        let group = state.createGroup(name: "Work", colorHex: "#4B8DFF")
        let originalCreatedAt = Date(timeIntervalSince1970: 1)
        let updatedCopiedAt = Date(timeIntervalSince1970: 5)
        let original = makeItem(
            sourceHash: "duplicate",
            displayTitle: "Original",
            plainText: "Original",
            createdAt: originalCreatedAt,
            lastCopiedAt: originalCreatedAt,
            isFavorited: false,
            groupID: group.id
        )
        let updated = makeItem(
            sourceHash: "duplicate",
            displayTitle: "Updated",
            plainText: "Updated",
            createdAt: updatedCopiedAt,
            lastCopiedAt: updatedCopiedAt,
            isFavorited: false
        )

        XCTAssertTrue(state.ingest(original))
        XCTAssertTrue(state.ingest(updated))

        XCTAssertEqual(state.items.count, 1)
        XCTAssertEqual(state.items[0].displayTitle, "Updated")
        XCTAssertEqual(state.items[0].groupID, group.id)
        XCTAssertEqual(state.panelViewModel.filteredItems.first?.groupID, group.id)
    }

    func testUpdateLinkPreviewUpdatesTitleAndThumbnailWithoutChangingItemState() {
        let state = AppState.preview()
        let copiedAt = Date(timeIntervalSince1970: 3)
        let item = ClipboardItem.text(
            plainText: "https://platform.minimaxi.com/user-center/payment/token-plan",
            copiedAt: copiedAt,
            sourceApplication: ClipboardSourceApplication(
                name: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            )
        )
        state.ingest(item)
        _ = state.toggleFavorite(for: item.id)

        let updated = state.updateLinkPreview(
            sourceHash: item.sourceHash,
            title: "MiniMax-与用户共创智能",
            assetPath: "/tmp/minimax-logo.png",
            thumbnailPath: "/tmp/minimax-thumb.png"
        )

        XCTAssertEqual(updated?.id, item.id)
        XCTAssertEqual(updated?.displayTitle, "MiniMax-与用户共创智能")
        XCTAssertEqual(updated?.plainText, item.plainText)
        XCTAssertEqual(updated?.urlString, item.urlString)
        XCTAssertEqual(updated?.assetPath, "/tmp/minimax-logo.png")
        XCTAssertEqual(updated?.thumbnailPath, "/tmp/minimax-thumb.png")
        XCTAssertEqual(updated?.createdAt, copiedAt)
        XCTAssertEqual(updated?.lastCopiedAt, copiedAt)
        XCTAssertTrue(updated?.isFavorited == true)
        XCTAssertEqual(updated?.sourceAppName, "Google Chrome")
        XCTAssertEqual(state.panelViewModel.filteredItems.first?.displayTitle, "MiniMax-与用户共创智能")
    }

    func testToggleFavoriteUpdatesItemsAndPanelViewModel() {
        let state = AppState.preview()
        let first = makeItem(
            sourceHash: "first",
            displayTitle: "First",
            plainText: "First",
            createdAt: Date(timeIntervalSince1970: 1),
            lastCopiedAt: Date(timeIntervalSince1970: 1),
            isFavorited: false
        )
        let second = makeItem(
            sourceHash: "second",
            displayTitle: "Second",
            plainText: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            lastCopiedAt: Date(timeIntervalSince1970: 2),
            isFavorited: false
        )
        state.loadItems([first, second])

        let updated = state.toggleFavorite(for: first.id)

        XCTAssertEqual(updated?.id, first.id)
        XCTAssertTrue(updated?.isFavorited == true)
        XCTAssertTrue(state.items[0].isFavorited)
        XCTAssertEqual(state.items[1], second)
        XCTAssertTrue(state.panelViewModel.allItems[0].isFavorited)
        XCTAssertTrue(state.panelViewModel.filteredItems[0].isFavorited)
    }

    func testToggleFavoriteReturnsNilForMissingItem() {
        let state = AppState.preview()

        XCTAssertNil(state.toggleFavorite(for: UUID()))
    }
}

private func makeItem(
    sourceHash: String,
    displayTitle: String,
    plainText: String,
    createdAt: Date,
    lastCopiedAt: Date,
    isFavorited: Bool,
    groupID: UUID? = nil
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        contentType: .text,
        sourceHash: sourceHash,
        displayTitle: displayTitle,
        plainText: plainText,
        urlString: nil,
        fileName: nil,
        filePath: nil,
        assetPath: nil,
        thumbnailPath: nil,
        createdAt: createdAt,
        lastCopiedAt: lastCopiedAt,
        contentSize: plainText.utf8.count,
        utiTypes: [],
        isFavorited: isFavorited,
        groupID: groupID
    )
}

private func makeGroup(
    name: String,
    colorHex: String = ClipboardGroup.defaultColorHex,
    sortOrder: Int
) -> ClipboardGroup {
    ClipboardGroup(
        id: UUID(),
        name: name,
        colorHex: colorHex,
        createdAt: Date(timeIntervalSince1970: TimeInterval(sortOrder)),
        sortOrder: sortOrder
    )
}
