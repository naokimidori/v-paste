import Foundation

enum HistoryPanelToolbarCopy {
    static let title = "Clipboard History"
    static let defaultGroupName = ClipboardGroup.defaultName(language: .english)
    static let noResultsTitle = "No Results"

    static func localizedTitle(language: AppLanguage) -> String {
        language == .english ? title : "剪贴板历史"
    }

    static func noResultsTitle(language: AppLanguage) -> String {
        language == .english ? noResultsTitle : "无结果"
    }
}

enum HistoryPanelSearchCopy {
    static func searchTitle(language: AppLanguage) -> String {
        language == .english ? "Search" : "搜索"
    }

    static func clearTitle(language: AppLanguage) -> String {
        language == .english ? "Clear Search" : "清除搜索"
    }
}

enum HistoryPanelScopeCopy {
    static func allTitle(language: AppLanguage) -> String {
        language == .english ? "All" : "全部"
    }

    static func favoritesTitle(language: AppLanguage) -> String {
        language == .english ? "Favorites" : "收藏"
    }

    static func clipboardScopeTitle(language: AppLanguage) -> String {
        language == .english ? "Clipboard scope" : "剪贴板范围"
    }
}

enum HistoryPanelTypeFilterCopy {
    static func typeTitle(language: AppLanguage) -> String {
        language == .english ? "Type" : "类型"
    }

    static func title(for filter: ClipboardContentFilter, language: AppLanguage) -> String {
        switch filter {
        case .all:
            return language == .english ? "All" : "全部"
        case .images:
            return language == .english ? "Images" : "图片"
        case .text:
            return language == .english ? "Text" : "文本"
        case .links:
            return language == .english ? "Links" : "链接"
        case .files:
            return language == .english ? "Files" : "文件"
        }
    }
}

enum HistoryPanelEmptyStateCopy {
    static func title(
        searchText: String,
        showsFavoritesOnly: Bool,
        hasActiveGroup: Bool,
        language: AppLanguage
    ) -> String {
        if !searchText.isEmpty {
            return HistoryPanelToolbarCopy.noResultsTitle(language: language)
        }

        if showsFavoritesOnly {
            if hasActiveGroup {
                return language == .english ? "No favorites in this group" : "这个分组暂无收藏"
            }

            return language == .english ? "No favorite clips" : "暂无收藏"
        }

        if hasActiveGroup {
            return language == .english ? "Group is empty" : "分组为空"
        }

        return language == .english ? "Copy something to begin" : "复制内容以开始"
    }

    static func subtitle(
        searchText: String,
        showsFavoritesOnly: Bool,
        hasActiveGroup: Bool,
        language: AppLanguage
    ) -> String {
        if !searchText.isEmpty {
            return language == .english ? "Try a shorter search term." : "试试更短的关键词。"
        }

        if showsFavoritesOnly {
            if hasActiveGroup {
                return language == .english
                    ? "Star a clip in this group to keep it here."
                    : "为这个分组里的卡片加星标后会显示在这里。"
            }

            return language == .english
                ? "Star a clip to keep it here."
                : "为剪贴板卡片加星标后会显示在这里。"
        }

        if hasActiveGroup {
            return language == .english
                ? "Drag a card here or use Add to Group."
                : "将卡片拖到这里，或通过“添加到分组”归类。"
        }

        return language == .english
            ? "Text, images, and file references will appear here."
            : "文本、图片和文件引用会显示在这里。"
    }
}

enum HistoryPanelGroupCopy {
    static func createTitle(language: AppLanguage) -> String {
        language == .english ? "Create Group" : "新建分组"
    }

    static func groupListTitle(language: AppLanguage) -> String {
        language == .english ? "Groups" : "分组"
    }

    static func editTitle(language: AppLanguage) -> String {
        language == .english ? "Edit" : "编辑"
    }

    static func deleteTitle(language: AppLanguage) -> String {
        language == .english ? "Delete" : "删除"
    }

    static func colorTitle(language: AppLanguage) -> String {
        language == .english ? "Group Color" : "分组颜色"
    }
}
