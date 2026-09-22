import XCTest
@testable import V_Paste

@MainActor
final class HistoryPanelViewModelRecommendationTests: XCTestCase {

    private func makeItem(
        id: UUID = UUID(),
        text: String = "Test Item",
        isFavorited: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: .text,
            sourceHash: "h-\(id)",
            displayTitle: text,
            plainText: text,
            urlString: nil,
            fileName: nil,
            filePath: nil,
            assetPath: nil,
            thumbnailPath: nil,
            createdAt: Date(),
            lastCopiedAt: Date(),
            contentSize: 10,
            utiTypes: ["public.utf8-plain-text"],
            isFavorited: isFavorited
        )
    }

    func testPresentedItemsProjectsRecommendedItemToFirstSlot() {
        let item1 = makeItem(text: "Item 1")
        let item2 = makeItem(text: "Item 2")
        let item3 = makeItem(text: "Item 3")
        let viewModel = HistoryPanelViewModel(items: [item1, item2, item3])

        XCTAssertEqual(viewModel.presentedItems.map(\.id), [item1.id, item2.id, item3.id])

        // 接收到对 item3 的推荐
        viewModel.setRecommendationState(.ready(itemID: item3.id))

        XCTAssertEqual(viewModel.presentedItems.count, 3)
        XCTAssertEqual(viewModel.presentedItems.first?.id, item3.id, "推荐项必须投影置顶为第 1 卡")
        XCTAssertEqual(viewModel.presentedItems.map(\.id), [item3.id, item1.id, item2.id])
        XCTAssertEqual(viewModel.allItems.map(\.id), [item1.id, item2.id, item3.id], "原始 allItems 顺序严禁被修改")
    }

    func testSelectionPreservesByItemIDWhenRecommendationArrives() {
        let item1 = makeItem(text: "Item 1")
        let item2 = makeItem(text: "Item 2")
        let item3 = makeItem(text: "Item 3")
        let viewModel = HistoryPanelViewModel(items: [item1, item2, item3])

        // 用户当前选中了 item2 (原 index 1)
        viewModel.selectItem(id: item2.id)
        XCTAssertEqual(viewModel.selectedItemID, item2.id)
        XCTAssertEqual(viewModel.selectedIndex, 1)

        // 推荐 item3 置顶
        viewModel.setRecommendationState(.ready(itemID: item3.id))

        // 投影后顺序为 [item3, item1, item2]，item2 的位置变成了 index 2
        XCTAssertEqual(viewModel.selectedItemID, item2.id, "以 ID 为真值，选中项绝不发生跳选")
        XCTAssertEqual(viewModel.selectedIndex, 2, "selectedIndex 应自适应更新为新投影列表中的下标")
        XCTAssertEqual(viewModel.selectedItem?.id, item2.id)
    }

    func testSearchClearsRecommendationStateAndRestoresNormalOrder() {
        let item1 = makeItem(text: "Apple")
        let item2 = makeItem(text: "Banana")
        let viewModel = HistoryPanelViewModel(items: [item1, item2])

        viewModel.setRecommendationState(.ready(itemID: item2.id))
        XCTAssertEqual(viewModel.presentedItems.first?.id, item2.id)

        // 开始搜索
        viewModel.updateSearchText("App")

        XCTAssertEqual(viewModel.recommendationState, .inactive, "搜索开始后必须清除推荐状态")
        XCTAssertEqual(viewModel.presentedItems.map(\.id), [item1.id])
    }

    func testDeletingRecommendedItemClearsRecommendationState() {
        let item1 = makeItem(text: "Alpha")
        let item2 = makeItem(text: "Beta")
        let viewModel = HistoryPanelViewModel(items: [item1, item2])

        viewModel.setRecommendationState(.ready(itemID: item2.id))
        XCTAssertEqual(viewModel.presentedItems.first?.id, item2.id)

        // 删除 item2
        viewModel.updateItems([item1])

        XCTAssertEqual(viewModel.recommendationState, .inactive, "推荐项在历史中被删除后应自动重置推荐")
        XCTAssertEqual(viewModel.presentedItems.map(\.id), [item1.id])
    }

    func testUserInteractionCallbackTriggeredOnActions() {
        let item1 = makeItem(text: "Alpha")
        let item2 = makeItem(text: "Beta")
        let viewModel = HistoryPanelViewModel(items: [item1, item2])

        var interactionCount = 0
        viewModel.onUserInteraction = {
            interactionCount += 1
        }

        viewModel.moveSelection(delta: 1)
        XCTAssertEqual(interactionCount, 1)

        viewModel.selectItem(id: item1.id)
        XCTAssertEqual(interactionCount, 2)

        viewModel.setActiveContentFilter(.images)
        XCTAssertEqual(interactionCount, 3)

        viewModel.toggleFavoritesOnly()
        XCTAssertEqual(interactionCount, 4)
    }
}
