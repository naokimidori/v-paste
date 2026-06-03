import AppKit
import Carbon
import XCTest
@testable import V_Paste

@MainActor
final class HistoryPanelViewModelTests: XCTestCase {
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

    func testContentFilterDefaultsToAll() {
        let text = makeItem(
            sourceHash: "text",
            displayTitle: "Text",
            plainText: "Plain"
        )
        let viewModel = HistoryPanelViewModel(items: [text])

        XCTAssertEqual(viewModel.activeContentFilter, .all)
        XCTAssertEqual(viewModel.filteredItems, [text])
    }

    func testContentFilterSeparatesImagesTextLinksAndFiles() {
        let image = makeItem(
            contentType: .image,
            sourceHash: "image",
            displayTitle: "Image",
            plainText: nil
        )
        let text = makeItem(
            contentType: .text,
            sourceHash: "text",
            displayTitle: "Text",
            plainText: "Plain text"
        )
        let link = makeItem(
            contentType: .text,
            sourceHash: "link",
            displayTitle: "Link",
            plainText: "https://example.com",
            urlString: "https://example.com"
        )
        let file = makeItem(
            contentType: .file,
            sourceHash: "file",
            displayTitle: "File",
            plainText: nil,
            fileName: "report.pdf"
        )
        let viewModel = HistoryPanelViewModel(items: [image, text, link, file])

        viewModel.setActiveContentFilter(.images)
        XCTAssertEqual(viewModel.filteredItems, [image])

        viewModel.setActiveContentFilter(.text)
        XCTAssertEqual(viewModel.filteredItems, [text])

        viewModel.setActiveContentFilter(.links)
        XCTAssertEqual(viewModel.filteredItems, [link])

        viewModel.setActiveContentFilter(.files)
        XCTAssertEqual(viewModel.filteredItems, [file])
    }

    func testContentFilterCombinesWithSearchText() {
        let imageMatch = makeItem(
            contentType: .image,
            sourceHash: "image-match",
            displayTitle: "Needle Image",
            plainText: nil
        )
        let textMatch = makeItem(
            contentType: .text,
            sourceHash: "text-match",
            displayTitle: "Needle Text",
            plainText: "Needle"
        )
        let imageMiss = makeItem(
            contentType: .image,
            sourceHash: "image-miss",
            displayTitle: "Other Image",
            plainText: nil
        )
        let viewModel = HistoryPanelViewModel(items: [imageMatch, textMatch, imageMiss])

        viewModel.setActiveContentFilter(.images)
        viewModel.updateSearchText("needle")

        XCTAssertEqual(viewModel.filteredItems, [imageMatch])
    }

    func testContentFilterCombinesWithActiveGroup() {
        let workID = UUID()
        let personalID = UUID()
        let workImage = makeItem(
            contentType: .image,
            sourceHash: "work-image",
            displayTitle: "Work Image",
            plainText: nil,
            groupID: workID
        )
        let personalImage = makeItem(
            contentType: .image,
            sourceHash: "personal-image",
            displayTitle: "Personal Image",
            plainText: nil,
            groupID: personalID
        )
        let workText = makeItem(
            contentType: .text,
            sourceHash: "work-text",
            displayTitle: "Work Text",
            plainText: "Work",
            groupID: workID
        )
        let viewModel = HistoryPanelViewModel(items: [workImage, personalImage, workText])

        viewModel.setActiveGroup(workID)
        viewModel.setActiveContentFilter(.images)

        XCTAssertEqual(viewModel.filteredItems, [workImage])
    }

    func testChangingContentFilterResetsSelectionToFirstVisibleItem() {
        let firstImage = makeItem(
            contentType: .image,
            sourceHash: "first-image",
            displayTitle: "First Image",
            plainText: nil
        )
        let text = makeItem(
            contentType: .text,
            sourceHash: "text",
            displayTitle: "Text",
            plainText: "Text"
        )
        let secondImage = makeItem(
            contentType: .image,
            sourceHash: "second-image",
            displayTitle: "Second Image",
            plainText: nil
        )
        let viewModel = HistoryPanelViewModel(items: [firstImage, text, secondImage])
        viewModel.moveSelection(delta: 2)

        viewModel.setActiveContentFilter(.images)

        XCTAssertEqual(viewModel.filteredItems, [firstImage, secondImage])
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.selectedItem, firstImage)
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
                "关于",
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
}
