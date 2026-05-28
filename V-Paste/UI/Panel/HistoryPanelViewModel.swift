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
    @Published private(set) var searchText: String
    @Published private(set) var showsFavoritesOnly: Bool
    @Published private(set) var activeContentFilter: ClipboardContentFilter
    @Published private(set) var groups: [ClipboardGroup]
    @Published private(set) var activeGroupID: ClipboardGroup.ID?
    @Published private(set) var isSearchExpanded: Bool
    @Published private(set) var searchFocusRequestID: Int
    @Published private(set) var language: AppLanguage

    var selectedItem: ClipboardItem? {
        guard filteredItems.indices.contains(selectedIndex) else { return nil }

        return filteredItems[selectedIndex]
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
        searchText = ""
        showsFavoritesOnly = false
        activeContentFilter = .all
        self.groups = groups
        self.activeGroupID = activeGroupID
        isSearchExpanded = false
        searchFocusRequestID = 0
        self.language = language
        applyFilter(resetSelection: true)
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }

        self.language = language
    }

    func updateSearchText(_ text: String) {
        searchText = text
        if !text.isEmpty {
            isSearchExpanded = true
        }
        applyFilter(resetSelection: true)
    }

    func expandSearch(with text: String = "", requestFocus: Bool = false) {
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
        activeGroupID = activeGroupID == groupID ? nil : groupID
        applyFilter(resetSelection: true)
    }

    func toggleFavoritesOnly() {
        setShowsFavoritesOnly(!showsFavoritesOnly)
    }

    func setShowsFavoritesOnly(_ showsFavoritesOnly: Bool) {
        guard self.showsFavoritesOnly != showsFavoritesOnly else { return }

        self.showsFavoritesOnly = showsFavoritesOnly
        applyFilter(resetSelection: true)
    }

    func setActiveContentFilter(_ filter: ClipboardContentFilter) {
        guard activeContentFilter != filter else { return }

        activeContentFilter = filter
        applyFilter(resetSelection: true)
    }

    private func applyFilter(resetSelection: Bool) {
        let previousItem = selectedItem
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

        if resetSelection {
            selectedIndex = filteredItems.isEmpty ? -1 : 0
            return
        }

        if let previousItem,
           let newIndex = filteredItems.firstIndex(where: { $0.id == previousItem.id }) {
            selectedIndex = newIndex
        } else {
            selectedIndex = filteredItems.isEmpty ? -1 : min(max(selectedIndex, 0), filteredItems.count - 1)
        }
    }

    func moveSelection(delta: Int) {
        guard !filteredItems.isEmpty else {
            selectedIndex = -1
            return
        }

        selectedIndex = min(max(selectedIndex + delta, 0), filteredItems.count - 1)
    }

    func selectItem(id: ClipboardItem.ID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == id }) else { return }

        selectedIndex = index
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
