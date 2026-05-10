import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isPanelVisible = false
    @Published var isMonitoringPaused = false
    @Published var searchText = ""
    @Published var items: [ClipboardItem] = []
    @Published private(set) var language: AppLanguage = .english
    @Published private(set) var groups: [ClipboardGroup]
    @Published private(set) var activeGroupID: ClipboardGroup.ID?
    @Published private(set) var panelViewModel: HistoryPanelViewModel

    var activeGroup: ClipboardGroup? {
        groups.first { $0.id == activeGroupID }
    }

    init() {
        groups = []
        activeGroupID = nil
        panelViewModel = HistoryPanelViewModel(
            items: [],
            groups: [],
            activeGroupID: nil
        )
    }

    func toggleMonitoringPaused() {
        isMonitoringPaused.toggle()
    }

    func pauseMonitoring() {
        guard !isMonitoringPaused else { return }
        isMonitoringPaused = true
    }

    func resumeMonitoring() {
        guard isMonitoringPaused else { return }
        isMonitoringPaused = false
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }

        self.language = language
        panelViewModel.setLanguage(language)
    }

    @discardableResult
    func ingest(_ item: ClipboardItem) -> Bool {
        guard !isMonitoringPaused else { return false }

        let existingItem = items.first { $0.sourceHash == item.sourceHash }
        items.removeAll { $0.sourceHash == item.sourceHash }
        items.insert(assignActiveGroupIfNeeded(merged(item, preservingStateFrom: existingItem)), at: 0)
        refreshPanelItems(resetSelection: true)
        return true
    }

    func refreshPanelItems(resetSelection: Bool = false) {
        panelViewModel.updateItems(items, resetSelection: resetSelection)
    }

    func loadItems(_ loadedItems: [ClipboardItem]) {
        items = loadedItems
        refreshPanelItems(resetSelection: true)
    }

    func loadGroups(_ loadedGroups: [ClipboardGroup]) {
        let previousActiveGroupID = activeGroupID
        groups = loadedGroups
        activeGroupID = previousActiveGroupID.flatMap { previousID in
            groups.contains { $0.id == previousID } ? previousID : nil
        }
        refreshPanelGroups()
        refreshPanelItems(resetSelection: true)
    }

    @discardableResult
    func createGroup(
        name: String? = nil,
        colorHex: String? = nil
    ) -> ClipboardGroup {
        let colorHex = colorHex ?? ClipboardGroupColorPalette.firstUnusedColor(
            usedColorHexes: groups.map(\.colorHex)
        )
        let group = ClipboardGroup(
            name: name ?? ClipboardGroup.defaultName(language: language),
            colorHex: colorHex,
            createdAt: Date(),
            sortOrder: (groups.map(\.sortOrder).max() ?? -1) + 1
        )

        groups.append(group)
        activeGroupID = group.id
        refreshPanelGroups()
        return group
    }

    func setActiveGroup(_ groupID: ClipboardGroup.ID?) {
        guard groupID == nil || groups.contains(where: { $0.id == groupID }) else { return }

        activeGroupID = activeGroupID == groupID ? nil : groupID
        refreshPanelGroups()
    }

    func updateGroup(_ group: ClipboardGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
        refreshPanelGroups()
    }

    @discardableResult
    func deleteGroup(id groupID: ClipboardGroup.ID) -> ClipboardGroup? {
        guard let deletedIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            return nil
        }

        let deletedGroup = groups.remove(at: deletedIndex)
        if activeGroupID == groupID {
            activeGroupID = nil
        }

        items = items.map { item in
            item.groupID == groupID ? item.withGroup(nil) : item
        }
        refreshPanelGroups()
        refreshPanelItems(resetSelection: true)
        return deletedGroup
    }

    @discardableResult
    func assignItem(
        id itemID: ClipboardItem.ID,
        to groupID: ClipboardGroup.ID
    ) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let updatedItem = items[index].withGroup(groupID)
        items[index] = updatedItem
        refreshPanelItems()
        return updatedItem
    }

    @discardableResult
    func deleteItem(id itemID: ClipboardItem.ID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let deletedItem = items.remove(at: index)
        refreshPanelItems()
        return deletedItem
    }

    func clearHistory() {
        items = []
        searchText = ""
        panelViewModel.updateSearchText("")
        refreshPanelItems(resetSelection: true)
    }

    @discardableResult
    func toggleFavorite(for itemID: ClipboardItem.ID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let updatedItem = items[index].withFavorite(!items[index].isFavorited)
        items[index] = updatedItem
        refreshPanelItems()
        return updatedItem
    }

    @discardableResult
    func updateLinkPreview(
        sourceHash: String,
        title: String?,
        assetPath: String?,
        thumbnailPath: String?
    ) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.sourceHash == sourceHash }) else {
            return nil
        }

        let updatedItem = items[index].withLinkPreview(
            title: title,
            assetPath: assetPath,
            thumbnailPath: thumbnailPath
        )
        items[index] = updatedItem
        refreshPanelItems()
        return updatedItem
    }

    static func preview() -> AppState {
        AppState()
    }

    private func merged(
        _ newItem: ClipboardItem,
        preservingStateFrom existingItem: ClipboardItem?
    ) -> ClipboardItem {
        guard let existingItem else { return newItem }

        return ClipboardItem(
            id: existingItem.id,
            contentType: newItem.contentType,
            sourceHash: newItem.sourceHash,
            displayTitle: newItem.displayTitle,
            plainText: newItem.plainText,
            urlString: newItem.urlString,
            fileName: newItem.fileName,
            filePath: newItem.filePath,
            assetPath: newItem.assetPath,
            thumbnailPath: newItem.thumbnailPath,
            createdAt: existingItem.createdAt,
            lastCopiedAt: newItem.lastCopiedAt,
            contentSize: newItem.contentSize,
            utiTypes: newItem.utiTypes,
            isFavorited: existingItem.isFavorited,
            sourceAppName: newItem.sourceAppName,
            sourceAppBundleIdentifier: newItem.sourceAppBundleIdentifier,
            groupID: existingItem.groupID
        )
    }

    private func refreshPanelGroups() {
        panelViewModel.updateGroups(groups, activeGroupID: activeGroupID)
    }

    private func assignActiveGroupIfNeeded(_ item: ClipboardItem) -> ClipboardItem {
        guard item.groupID == nil,
              let groupID = activeGroupID
        else {
            return item
        }

        return item.withGroup(groupID)
    }
}
