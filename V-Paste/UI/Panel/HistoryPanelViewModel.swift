import Combine
import Foundation

enum ClipboardContentFilter: CaseIterable, Equatable {
    case all
    case images
    case text
    case links
    case files
}

@MainActor
final class HistoryPanelViewModel: ObservableObject {
    @Published private(set) var allItems: [ClipboardItem]
    @Published private(set) var filteredItems: [ClipboardItem]
    @Published private(set) var selectedIndex: Int
    @Published private(set) var selectedItemID: ClipboardItem.ID?
    @Published private(set) var searchText: String
    @Published private(set) var showsFavoritesOnly: Bool
    @Published private(set) var activeContentFilter: ClipboardContentFilter
    @Published private(set) var groups: [ClipboardGroup]
    @Published private(set) var activeGroupID: ClipboardGroup.ID?
    @Published private(set) var isSearchExpanded: Bool
    @Published private(set) var searchFocusRequestID: Int
    @Published private(set) var language: AppLanguage

    // MARK: - Jev 推荐相关状态与展示投影

    /// Jev 推荐展示状态
    @Published private(set) var recommendationState: JevRecommendationPresentationState

    /// 用户发生交互时的通知回调（用于通知服务锁定防抢占）
    var onUserInteraction: (() -> Void)?

    /// 只读展示投影列表：若有 Jev 推荐且未处于搜索中，则将推荐项投影置顶为第 1 卡；否则保持原始筛选顺序
    var presentedItems: [ClipboardItem] {
        guard searchText.isEmpty else {
            return filteredItems
        }
        if case .ready(let recID) = recommendationState,
           let recommendedItem = filteredItems.first(where: { $0.id == recID }) {
            return [recommendedItem] + filteredItems.filter { $0.id != recID }
        }
        return filteredItems
    }

    /// 当前选中的剪贴板条目（以 ID 真值为第一依据，结合展示投影列表）
    var selectedItem: ClipboardItem? {
        if let selectedItemID, let item = presentedItems.first(where: { $0.id == selectedItemID }) {
            return item
        }
        guard presentedItems.indices.contains(selectedIndex) else { return nil }
        return presentedItems[selectedIndex]
    }

    init(
        items: [ClipboardItem],
        groups: [ClipboardGroup] = [],
        activeGroupID: ClipboardGroup.ID? = nil,
        language: AppLanguage = .english
    ) {
        allItems = items
        filteredItems = []
        selectedIndex = items.isEmpty ? -1 : 0
        selectedItemID = items.first?.id
        searchText = ""
        showsFavoritesOnly = false
        activeContentFilter = .all
        self.groups = groups
        self.activeGroupID = activeGroupID
        isSearchExpanded = false
        searchFocusRequestID = 0
        self.language = language
        self.recommendationState = .inactive
        applyFilter(resetSelection: true)
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
    }

    // MARK: - Jev 推荐状态管理

    func setRecommendationState(_ state: JevRecommendationPresentationState) {
        // 搜索时不展示推荐卡
        guard searchText.isEmpty else {
            recommendationState = .inactive
            return
        }

        // 记录状态变更前的选中 ID
        let previousSelectedID = selectedItemID

        recommendationState = state

        // 状态变更后（如产生推荐卡置顶），根据 ID 重新同步更新 selectedIndex
        if let previousSelectedID, let newIdx = presentedItems.firstIndex(where: { $0.id == previousSelectedID }) {
            selectedIndex = newIdx
        } else {
            selectedIndex = presentedItems.isEmpty ? -1 : 0
            selectedItemID = presentedItems.first?.id
        }
    }

    func applyRecommendation(recommendedItemID: UUID) {
        setRecommendationState(.ready(itemID: recommendedItemID))
    }

    func clearRecommendation() {
        guard recommendationState != .inactive else { return }
        let previousSelectedID = selectedItemID
        recommendationState = .inactive

        if let previousSelectedID, let newIdx = presentedItems.firstIndex(where: { $0.id == previousSelectedID }) {
            selectedIndex = newIdx
        } else {
            selectedIndex = presentedItems.isEmpty ? -1 : 0
            selectedItemID = presentedItems.first?.id
        }
    }

    // MARK: - 搜索处理

    func updateSearchText(_ text: String) {
        onUserInteraction?()
        clearRecommendation()

        searchText = text
        if !text.isEmpty {
            isSearchExpanded = true
        }
        applyFilter(resetSelection: true)
    }

    func expandSearch(with text: String = "", requestFocus: Bool = false) {
        onUserInteraction?()
        clearRecommendation()

        isSearchExpanded = true
        if !text.isEmpty {
            searchText += text
            applyFilter(resetSelection: true)
        }
        if requestFocus {
            searchFocusRequestID += 1
        }
    }

    func deleteLastSearchCharacter(requestFocus: Bool = false) {
        onUserInteraction?()
        clearRecommendation()

        guard isSearchExpanded else { return }

        guard !searchText.isEmpty else {
            isSearchExpanded = false
            return
        }

        searchText.removeLast()
        applyFilter(resetSelection: true)
        if requestFocus {
            searchFocusRequestID += 1
        }
    }

    func resetSearchForPresentation() {
        searchText = ""
        isSearchExpanded = false
        applyFilter(resetSelection: true)
    }

    func clearSearch() {
        onUserInteraction?()
        searchText = ""
        isSearchExpanded = false
        applyFilter(resetSelection: true)
    }

    func collapseSearchIfEmpty() {
        guard searchText.isEmpty else { return }
        isSearchExpanded = false
    }

    func updateItems(_ items: [ClipboardItem], resetSelection: Bool = false) {
        allItems = items

        // 检查当前推荐项是否在新的 items 列表中仍然存在；若已被删除，则重置推荐状态
        if case .ready(let recID) = recommendationState {
            if !items.contains(where: { $0.id == recID }) {
                recommendationState = .inactive
            }
        }

        applyFilter(resetSelection: resetSelection)
    }

    func updateGroups(
        _ groups: [ClipboardGroup],
        activeGroupID: ClipboardGroup.ID?
    ) {
        self.groups = groups
        self.activeGroupID = activeGroupID
        applyFilter(resetSelection: true)
    }

    func setActiveGroup(_ groupID: ClipboardGroup.ID?) {
        onUserInteraction?()
        clearRecommendation()

        activeGroupID = activeGroupID == groupID ? nil : groupID
        applyFilter(resetSelection: true)
    }

    func toggleFavoritesOnly() {
        setShowsFavoritesOnly(!showsFavoritesOnly)
    }

    func setShowsFavoritesOnly(_ showsFavoritesOnly: Bool) {
        onUserInteraction?()
        clearRecommendation()

        guard self.showsFavoritesOnly != showsFavoritesOnly else { return }

        self.showsFavoritesOnly = showsFavoritesOnly
        applyFilter(resetSelection: true)
    }

    func setActiveContentFilter(_ filter: ClipboardContentFilter) {
        onUserInteraction?()
        clearRecommendation()

        guard activeContentFilter != filter else { return }

        activeContentFilter = filter
        applyFilter(resetSelection: true)
    }

    private func applyFilter(resetSelection: Bool) {
        let previousSelectedID = selectedItemID
        var candidateItems = allItems

        if let activeGroupID {
            candidateItems = candidateItems.filter { $0.groupID == activeGroupID }
        }

        if showsFavoritesOnly {
            candidateItems = candidateItems.filter(\.isFavorited)
        }

        candidateItems = candidateItems.filter { item in
            activeContentFilter.includes(item)
        }

        if searchText.isEmpty {
            filteredItems = candidateItems
        } else {
            filteredItems = candidateItems.filter { item in
                item.matchesSearchQuery(searchText)
            }
        }

        let currentPresented = presentedItems
        if resetSelection {
            selectedIndex = currentPresented.isEmpty ? -1 : 0
            selectedItemID = currentPresented.first?.id
            return
        }

        if let previousSelectedID,
           let newIndex = currentPresented.firstIndex(where: { $0.id == previousSelectedID }) {
            selectedIndex = newIndex
            selectedItemID = previousSelectedID
        } else {
            selectedIndex = currentPresented.isEmpty ? -1 : min(max(selectedIndex, 0), currentPresented.count - 1)
            selectedItemID = (selectedIndex >= 0 && selectedIndex < currentPresented.count) ? currentPresented[selectedIndex].id : nil
        }
    }

    func moveSelection(delta: Int) {
        onUserInteraction?()

        let items = presentedItems
        guard !items.isEmpty else {
            selectedIndex = -1
            selectedItemID = nil
            return
        }

        let targetIndex = min(max(selectedIndex + delta, 0), items.count - 1)
        selectedIndex = targetIndex
        selectedItemID = items[targetIndex].id
    }

    func selectItem(id: ClipboardItem.ID) {
        onUserInteraction?()

        let items = presentedItems
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        selectedIndex = index
        selectedItemID = id
    }
}

private extension ClipboardContentFilter {
    func includes(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            return true
        case .images:
            return item.contentType == .image
        case .text:
            return item.contentType == .text && !isWebURL(item.urlString)
        case .links:
            return isWebURL(item.urlString)
        case .files:
            return item.contentType == .file
        }
    }

    private func isWebURL(_ urlString: String?) -> Bool {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false
        else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }
}

private extension ClipboardItem {
    func matchesSearchQuery(_ query: String) -> Bool {
        [displayTitle, plainText, fileName, urlString, sourceAppName]
            .compactMap { $0 }
            .contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
