import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum HistoryPanelToolbarCopy {
    static let title = "Clipboard History"
    static let defaultGroupName = ClipboardGroup.defaultName
    static let noResultsTitle = "No Results"
}

enum HistoryPanelSearchTransition {
    static let duration: Double = 0.18
    static let scale: CGFloat = 0.98

    static var animation: Animation {
        .snappy(duration: duration)
    }
}

enum HistoryPanelSearchLayout {
    static let expandedWidth: CGFloat = 180
}

enum HistoryPanelSearchSelection {
    static func insertionPointAtEnd(of text: String) -> NSRange {
        NSRange(location: (text as NSString).length, length: 0)
    }
}

enum HistoryPanelTextSelection {
    static func fullRange(of text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }
}

enum HistoryPanelSearchCommandRouting {
    static func shouldCollapseEmptySearch(
        text: String,
        commandSelector: Selector
    ) -> Bool {
        text.isEmpty && (
            commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:))
        )
    }
}

struct HistoryPanelSearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String
    let onSubmit: () -> Void
    let onEmptyBackspace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(
            ofSize: NSFont.systemFontSize(for: .regular)
        )
        textField.placeholderString = placeholder
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }
        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }
        if isFocused {
            context.coordinator.focus(textField)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HistoryPanelSearchTextField

        init(parent: HistoryPanelSearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            parent.isFocused = true
            moveInsertionPointToEnd(textField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if HistoryPanelSearchCommandRouting.shouldCollapseEmptySearch(
                text: textView.string,
                commandSelector: commandSelector
            ) {
                parent.onEmptyBackspace()
                return true
            }

            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            parent.onSubmit()
            return true
        }

        func focus(_ textField: NSTextField) {
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self,
                      let textField,
                      let window = textField.window else {
                    return
                }

                if !self.isEditing(textField) {
                    window.makeFirstResponder(textField)
                }
                self.moveInsertionPointToEnd(textField)
            }
        }

        private func isEditing(_ textField: NSTextField) -> Bool {
            guard let editor = textField.currentEditor() else { return false }

            return textField.window?.firstResponder === editor
        }

        private func moveInsertionPointToEnd(_ textField: NSTextField) {
            guard let editor = textField.currentEditor() as? NSTextView else { return }

            editor.setSelectedRange(
                HistoryPanelSearchSelection.insertionPointAtEnd(of: editor.string)
            )
        }
    }
}

struct HistoryPanelGroupNameTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(
            ofSize: NSFont.systemFontSize(for: .regular),
            weight: .medium
        )
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }
        if isFocused {
            context.coordinator.focus(textField)
        } else {
            context.coordinator.resetSelectionState()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HistoryPanelGroupNameTextField
        private var didSelectAllForCurrentFocus = false

        init(parent: HistoryPanelGroupNameTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            parent.isFocused = true
            selectAllIfNeeded(in: textField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
            resetSelectionState()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            parent.onSubmit()
            return true
        }

        func focus(_ textField: NSTextField) {
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self,
                      let textField,
                      let window = textField.window else {
                    return
                }

                if !self.isEditing(textField) {
                    window.makeFirstResponder(textField)
                    textField.selectText(nil)
                }
                self.selectAllIfNeeded(in: textField)
            }
        }

        func resetSelectionState() {
            didSelectAllForCurrentFocus = false
        }

        private func isEditing(_ textField: NSTextField) -> Bool {
            guard let editor = textField.currentEditor() else { return false }

            return textField.window?.firstResponder === editor
        }

        private func selectAllIfNeeded(in textField: NSTextField) {
            guard !didSelectAllForCurrentFocus,
                  let editor = textField.currentEditor() as? NSTextView else {
                return
            }

            editor.setSelectedRange(HistoryPanelTextSelection.fullRange(of: editor.string))
            didSelectAllForCurrentFocus = true
        }
    }
}

enum HistoryPanelGroupStripLayout {
    static let pillSpacing: CGFloat = 7
    static let createButtonSpacing: CGFloat = pillSpacing
    static let stripHorizontalPadding: CGFloat = 0
    static let colorDotSize: CGFloat = 8
    static let dotToNameSpacing: CGFloat = 7
    static let pillHorizontalPadding: CGFloat = 20
    static let minimumPillWidth: CGFloat = 54
    static let maximumPillWidth: CGFloat = 160
    static let editablePillWidth: CGFloat = 161
    static let pillTextFont = NSFont.systemFont(
        ofSize: NSFont.systemFontSize(for: .regular),
        weight: .medium
    )

    static var nameMaxWidth: CGFloat {
        maximumPillWidth - pillHorizontalPadding - colorDotSize - dotToNameSpacing
    }

    static func width(
        for groups: [ClipboardGroup],
        editingGroupID: ClipboardGroup.ID?,
        maxWidth: CGFloat
    ) -> CGFloat {
        guard !groups.isEmpty else { return 0 }

        let pillWidths = groups.reduce(CGFloat(0)) { width, group in
            width + pillWidth(
                for: group,
                isEditing: group.id == editingGroupID
            )
        }
        let spacing = CGFloat(max(groups.count - 1, 0)) * pillSpacing
        let estimatedWidth = pillWidths + spacing + stripHorizontalPadding

        return min(maxWidth, ceil(estimatedWidth))
    }

    static func pillWidth(for group: ClipboardGroup, isEditing: Bool) -> CGFloat {
        guard !isEditing else { return editablePillWidth }

        let estimatedWidth = measuredNameWidth(for: group.name)
            + pillHorizontalPadding
            + colorDotSize
            + dotToNameSpacing

        return min(maximumPillWidth, max(minimumPillWidth, estimatedWidth))
    }

    static func measuredNameWidth(for name: String) -> CGFloat {
        let width = (name as NSString).size(
            withAttributes: [.font: pillTextFont]
        ).width

        return ceil(width)
    }
}

struct HistoryPanelView: View {
    @ObservedObject var viewModel: HistoryPanelViewModel

    let onClose: () -> Void
    let onCopy: (ClipboardItem) -> Void
    let onToggleFavorite: (ClipboardItem) -> Void
    let onCreateGroup: () -> ClipboardGroup?
    let onSelectGroup: (ClipboardGroup.ID?) -> Void
    let onUpdateGroup: (ClipboardGroup) -> Void
    let onAssignItemToGroup: (ClipboardItem.ID, ClipboardGroup.ID) -> Void
    let onDeleteGroup: (ClipboardGroup.ID) -> Void
    let onDeleteItem: (ClipboardItem) -> Void
    let onOpenPreferences: () -> Void
    let onOpenAbout: () -> Void
    let onQuit: () -> Void

    @State private var isSearchFocused = false
    @State private var focusedEditingGroupID: ClipboardGroup.ID?
    @State private var cardFrames: [ClipboardItem.ID: CGRect] = [:]
    @State private var pendingRevealItemID: ClipboardItem.ID?
    @State private var isSearchExpandedFallback = false
    @State private var editingGroupID: ClipboardGroup.ID?
    @State private var colorPickerGroupID: ClipboardGroup.ID?
    @State private var editingGroupName = ""
    @State private var editingGroupColorHex = ClipboardGroup.defaultColorHex

    private static let cardStripCoordinateSpace = "HistoryPanelCardStrip"

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryPanelLayout.toolbarToCardSpacing) {
            toolbar

            if viewModel.filteredItems.isEmpty {
                emptyState
            } else {
                cardStrip
            }
        }
        .padding(.top, HistoryPanelLayout.topPadding)
        .padding(.bottom, HistoryPanelLayout.rootBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            panelBackground
                .contentShape(Rectangle())
                .onTapGesture {
                    handleBlankPanelClick()
                }
        )
        .onAppear {
            focusSearchFieldIfNeeded()
        }
        .onChange(of: isSearchExpanded) { _, expanded in
            if expanded {
                focusSearchFieldIfNeeded()
            } else {
                isSearchFocused = false
            }
        }
        .onChange(of: viewModel.isSearchExpanded) { _, expanded in
            guard !expanded else { return }

            isSearchExpandedFallback = false
            isSearchFocused = false
        }
        .onChange(of: viewModel.searchFocusRequestID) { _, _ in
            focusSearchFieldIfNeeded()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                viewModel.moveSelection(delta: -1)
            case .right:
                viewModel.moveSelection(delta: 1)
            default:
                break
            }
        }
        .onExitCommand(perform: onClose)
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)

            if isSearchExpanded {
                expandedSearchToolbar
                    .transition(searchToolbarTransition)
            } else {
                collapsedToolbar
                    .transition(searchToolbarTransition)
            }

            Spacer(minLength: 0)

            overflowMenuButton
        }
        .padding(.horizontal, HistoryPanelLayout.horizontalPadding)
        .frame(height: HistoryPanelLayout.toolbarHeight)
        .animation(HistoryPanelSearchTransition.animation, value: isSearchExpanded)
    }

    private var overflowMenuButton: some View {
        Menu {
            ForEach(
                Array(MenuBarMenuDescriptor.panelOverflowItems(appName: "V-Paste").enumerated()),
                id: \.offset
            ) { _, descriptor in
                overflowMenuContent(for: descriptor)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Menu")
        .accessibilityLabel("Menu")
    }

    @ViewBuilder
    private func overflowMenuContent(for descriptor: MenuBarMenuItemDescriptor) -> some View {
        if let title = descriptor.title {
            switch descriptor.action {
            case .openPreferences:
                Button(title, action: performOpenPreferences)
                    .keyboardShortcut(",", modifiers: .command)
            case .openAbout:
                Button(title, action: performOpenAbout)
            case .quit:
                Button(title, action: onQuit)
                    .keyboardShortcut("q", modifiers: .command)
            case .showPanel, nil:
                Button(title) {}
                    .disabled(true)
            }
        } else {
            Divider()
        }
    }

    private func performOpenPreferences() {
        onOpenPreferences()
    }

    private func performOpenAbout() {
        onOpenAbout()
    }

    private var collapsedToolbar: some View {
        HStack(spacing: HistoryPanelGroupStripLayout.createButtonSpacing) {
            Button {
                expandSearch(with: "")
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Search")
            .accessibilityLabel("Search")

            Label(HistoryPanelToolbarCopy.title, systemImage: "clock.arrow.circlepath")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(nsColor: .separatorColor).opacity(0.22), in: Capsule())

            groupStrip(maxWidth: 360)

            createGroupButton

            favoriteScopeControl
        }
    }

    private var expandedSearchToolbar: some View {
        HStack(spacing: HistoryPanelGroupStripLayout.createButtonSpacing) {
            searchField

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityLabel(HistoryPanelToolbarCopy.title)

            groupStrip(maxWidth: 300)

            createGroupButton
        }
    }

    private var cardStrip: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 24) {
                        ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                            HistoryCardView(
                                item: item,
                                isSelected: index == viewModel.selectedIndex,
                                groups: groups,
                                onSelect: {
                                    viewModel.selectItem(id: item.id)
                                },
                                onCopy: {
                                    viewModel.selectItem(id: item.id)
                                    onCopy(item)
                                },
                                onToggleFavorite: {
                                    onToggleFavorite(item)
                                },
                                onAssignToGroup: { groupID in
                                    onAssignItemToGroup(item.id, groupID)
                                },
                                onDelete: {
                                    onDeleteItem(item)
                                }
                            )
                            .id(item.id)
                            .background {
                                GeometryReader { card in
                                    Color.clear.preference(
                                        key: HistoryCardFramePreferenceKey.self,
                                        value: [
                                            item.id: card.frame(in: .named(Self.cardStripCoordinateSpace))
                                        ]
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, HistoryPanelLayout.cardStripTopPadding)
                    .padding(.bottom, HistoryPanelLayout.cardStripBottomPadding)
                    .padding(.horizontal, HistoryPanelLayout.horizontalPadding)
                }
                .coordinateSpace(name: Self.cardStripCoordinateSpace)
                .scrollIndicators(.hidden)
                .onPreferenceChange(HistoryCardFramePreferenceKey.self) { frames in
                    cardFrames = frames

                    if pendingRevealItemID != nil,
                       revealSelectedItemIfNeeded(
                        itemID: pendingRevealItemID,
                        cardFrames: frames,
                        viewportWidth: viewport.size.width,
                        proxy: proxy
                       ) {
                        pendingRevealItemID = nil
                    }
                }
                .onChange(of: viewModel.selectedItem?.id) { oldID, id in
                    let fallbackAnchor = revealFallbackAnchor(from: oldID, to: id)
                    pendingRevealItemID = id

                    if revealSelectedItemIfNeeded(
                        itemID: id,
                        cardFrames: cardFrames,
                        viewportWidth: viewport.size.width,
                        proxy: proxy,
                        fallbackAnchor: fallbackAnchor
                    ) {
                        pendingRevealItemID = nil
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleBlankPanelClick()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text(emptyStateTitle)
                .font(.system(.headline, design: .rounded))

            Text(emptyStateSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, HistoryPanelLayout.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            handleBlankPanelClick()
        }
    }

    private var panelBackground: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 1)

            ZStack {
                Rectangle()
                    .fill(.regularMaterial)

                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0.64),
                        Color(nsColor: .controlAccentColor).opacity(0.14),
                        Color(nsColor: .windowBackgroundColor).opacity(0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private var favoriteScopeControl: some View {
        HStack(spacing: 2) {
            scopeButton(
                title: "All",
                systemImage: "tray.full",
                isActive: !viewModel.showsFavoritesOnly
            ) {
                viewModel.setShowsFavoritesOnly(false)
            }

            scopeButton(
                title: "Favorites",
                systemImage: "star.fill",
                isActive: viewModel.showsFavoritesOnly
            ) {
                viewModel.setShowsFavoritesOnly(true)
            }
        }
        .padding(3)
        .background(Color(nsColor: .separatorColor).opacity(0.18), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard scope")
    }

    private func scopeButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 30, height: 24)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.78))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            HistoryPanelSearchTextField(
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.updateSearchText($0) }
                ),
                isFocused: $isSearchFocused,
                placeholder: "Search",
                onSubmit: copySelectedItem,
                onEmptyBackspace: collapseSearchIfEmpty
            )
            .frame(height: 18)

            if !viewModel.searchText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(width: HistoryPanelSearchLayout.expandedWidth)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.66), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .controlAccentColor).opacity(0.85), lineWidth: 1.5)
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused {
                collapseSearchIfEmpty()
            }
        }
        .onAppear {
            focusSearchFieldIfNeeded()
        }
    }

    private var emptyStateTitle: String {
        if !viewModel.searchText.isEmpty {
            return HistoryPanelToolbarCopy.noResultsTitle
        }

        return viewModel.showsFavoritesOnly ? "No favorite clips" : "Copy something to begin"
    }

    private var emptyStateSubtitle: String {
        if !viewModel.searchText.isEmpty {
            return "Try a shorter search term."
        }

        return viewModel.showsFavoritesOnly ? "Star a clip to keep it here." : "Text, images, and file references will appear here."
    }

    private func copySelectedItem() {
        guard let selectedItem = viewModel.selectedItem else { return }

        onCopy(selectedItem)
    }

    private var isSearchExpanded: Bool {
        viewModel.isSearchExpanded || isSearchExpandedFallback
    }

    private var groups: [ClipboardGroup] {
        viewModel.groups
    }

    private var searchToolbarTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: HistoryPanelSearchTransition.scale))
    }

    private func expandSearch(with text: String) {
        withAnimation(HistoryPanelSearchTransition.animation) {
            isSearchExpandedFallback = true
            viewModel.expandSearch(with: text, requestFocus: true)
            focusSearchFieldIfNeeded()
        }
    }

    private func focusSearchFieldIfNeeded() {
        guard isSearchExpanded else { return }

        isSearchFocused = true
        DispatchQueue.main.async {
            guard isSearchExpanded else { return }

            isSearchFocused = true
        }
    }

    private func clearSearch() {
        withAnimation(HistoryPanelSearchTransition.animation) {
            viewModel.clearSearch()
            isSearchExpandedFallback = false
            isSearchFocused = false
        }
    }

    private func collapseSearchIfEmpty() {
        guard viewModel.searchText.isEmpty else {
            viewModel.collapseSearchIfEmpty()
            return
        }

        withAnimation(HistoryPanelSearchTransition.animation) {
            viewModel.collapseSearchIfEmpty()
            isSearchExpandedFallback = false
            isSearchFocused = false
        }
    }

    private var createGroupButton: some View {
        Button {
            createAndEditGroup()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Create Group")
        .accessibilityLabel("Create Group")
    }

    private func groupStrip(maxWidth: CGFloat) -> some View {
        let width = HistoryPanelGroupStripLayout.width(
            for: groups,
            editingGroupID: editingGroupID,
            maxWidth: maxWidth
        )

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HistoryPanelGroupStripLayout.pillSpacing) {
                ForEach(groups) { group in
                    groupPill(group)
                }
            }
            .padding(.horizontal, HistoryPanelGroupStripLayout.stripHorizontalPadding / 2)
        }
        .scrollIndicators(.hidden)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Groups")
    }

    @ViewBuilder
    private func groupPill(_ group: ClipboardGroup) -> some View {
        let isActive = viewModel.activeGroupID == group.id

        if editingGroupID == group.id {
            editableGroupPill(group, isActive: isActive)
        } else {
            Button {
                commitEditingGroupIfNeeded()
                let nextGroupID = isActive ? nil : group.id
                setActiveGroup(id: nextGroupID)
                onSelectGroup(nextGroupID)
            } label: {
                HStack(spacing: HistoryPanelGroupStripLayout.dotToNameSpacing) {
                    groupColorDot(
                        colorHex: group.colorHex,
                        size: HistoryPanelGroupStripLayout.colorDotSize
                    )

                    Text(group.name)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: HistoryPanelGroupStripLayout.nameMaxWidth, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(groupPillBackground(isActive: isActive), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                handleDrop(providers: providers, groupID: group.id)
            }
            .contextMenu {
                Button("Edit") {
                    beginEditing(group: group)
                }

                Button("Delete", role: .destructive) {
                    deleteGroup(group)
                }
            }
            .accessibilityLabel(group.name)
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
    }

    private func editableGroupPill(_ group: ClipboardGroup, isActive: Bool) -> some View {
        HStack(spacing: HistoryPanelGroupStripLayout.dotToNameSpacing) {
            editingColorButton(groupID: group.id)

            HistoryPanelGroupNameTextField(
                text: $editingGroupName,
                isFocused: Binding(
                    get: { focusedEditingGroupID == group.id },
                    set: { isFocused in
                        focusedEditingGroupID = isFocused ? group.id : nil
                    }
                ),
                onSubmit: commitEditingGroupIfNeeded
            )
            .frame(width: 118, height: 18)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(groupPillBackground(isActive: isActive), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .controlAccentColor).opacity(0.74), lineWidth: 1.5)
        }
        .contentShape(Capsule())
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handleDrop(providers: providers, groupID: group.id)
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                deleteGroup(group)
            }
        }
        .onAppear {
            focusedEditingGroupID = group.id
        }
    }

    private func editingColorButton(groupID: ClipboardGroup.ID) -> some View {
        Button {
            colorPickerGroupID = groupID
        } label: {
            groupColorDot(colorHex: editingGroupColorHex, size: 9)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: colorPickerBinding(for: groupID), arrowEdge: .top) {
            GroupColorPickerPopover(
                selectedColorHex: $editingGroupColorHex,
                onSelect: { colorHex in
                    editingGroupColorHex = colorHex
                    colorPickerGroupID = nil
                }
            )
        }
        .accessibilityLabel("Group Color")
    }

    private func colorPickerBinding(for groupID: ClipboardGroup.ID) -> Binding<Bool> {
        Binding(
            get: {
                colorPickerGroupID == groupID
            },
            set: { isPresented in
                colorPickerGroupID = isPresented ? groupID : nil
            }
        )
    }

    private func groupColorDot(colorHex: String, size: CGFloat) -> some View {
        Circle()
            .fill(Color(hex: colorHex) ?? Color(nsColor: .systemRed))
            .frame(width: size, height: size)
    }

    private func groupPillBackground(isActive: Bool) -> Color {
        isActive
            ? Color(nsColor: .controlAccentColor).opacity(0.18)
            : Color(nsColor: .separatorColor).opacity(0.16)
    }

    private func setActiveGroup(id: ClipboardGroup.ID?) {
        viewModel.setActiveGroup(id)
    }

    private func createAndEditGroup() {
        commitEditingGroupIfNeeded()

        guard let group = onCreateGroup() else { return }

        beginEditing(group: group)
    }

    private func beginEditing(group: ClipboardGroup) {
        editingGroupID = group.id
        editingGroupName = group.name
        editingGroupColorHex = group.colorHex
        focusedEditingGroupID = group.id
    }

    private func commitEditingGroupIfNeeded() {
        guard let editingGroupID else { return }
        guard let originalGroup = groups.first(where: { $0.id == editingGroupID }) else {
            self.editingGroupID = nil
            colorPickerGroupID = nil
            focusedEditingGroupID = nil
            return
        }

        let trimmedName = editingGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedGroup = ClipboardGroup(
            id: originalGroup.id,
            name: trimmedName.isEmpty ? ClipboardGroup.defaultName : trimmedName,
            colorHex: editingGroupColorHex,
            createdAt: originalGroup.createdAt,
            sortOrder: originalGroup.sortOrder
        )

        viewModel.updateGroups(
            groups.map { $0.id == updatedGroup.id ? updatedGroup : $0 },
            activeGroupID: viewModel.activeGroupID
        )
        onUpdateGroup(updatedGroup)
        self.editingGroupID = nil
        colorPickerGroupID = nil
        focusedEditingGroupID = nil
    }

    private func deleteGroup(_ group: ClipboardGroup) {
        if editingGroupID == group.id {
            editingGroupID = nil
            colorPickerGroupID = nil
            focusedEditingGroupID = nil
        }

        onDeleteGroup(group.id)
    }

    private func handleBlankPanelClick() {
        commitEditingGroupIfNeeded()

        if isSearchExpanded, viewModel.searchText.isEmpty {
            collapseSearchIfEmpty()
        }
    }

    private func handleDrop(providers: [NSItemProvider], groupID: ClipboardGroup.ID) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let itemID = UUID(uuidString: string)
            else {
                return
            }

            Task { @MainActor in
                onAssignItemToGroup(itemID, groupID)
            }
        }

        return true
    }

    private func revealSelectedItemIfNeeded(
        itemID: ClipboardItem.ID?,
        cardFrames: [ClipboardItem.ID: CGRect],
        viewportWidth: CGFloat,
        proxy: ScrollViewProxy,
        fallbackAnchor: HistoryPanelScrollReveal.Anchor? = nil
    ) -> Bool {
        guard let id = itemID else {
            return true
        }

        guard let frame = cardFrames[id] else {
            guard let fallbackAnchor else { return false }

            withAnimation(.snappy(duration: 0.18)) {
                proxy.scrollTo(
                    id,
                    anchor: HistoryPanelScrollReveal.unitPoint(
                        for: fallbackAnchor,
                        viewportWidth: viewportWidth,
                        cardWidth: HistoryCardLayout.cardWidth
                    )
                )
            }

            return true
        }

        guard let anchor = HistoryPanelScrollReveal.anchor(
            forCardFrame: frame,
            viewportWidth: viewportWidth
        )
        else {
            return true
        }

        withAnimation(.snappy(duration: 0.18)) {
            proxy.scrollTo(
                id,
                anchor: HistoryPanelScrollReveal.unitPoint(
                    for: anchor,
                    viewportWidth: viewportWidth,
                    cardWidth: frame.width
                )
            )
        }

        return true
    }

    private func revealFallbackAnchor(
        from oldID: ClipboardItem.ID?,
        to newID: ClipboardItem.ID?
    ) -> HistoryPanelScrollReveal.Anchor? {
        guard let newID,
              let selectedIndex = viewModel.filteredItems.firstIndex(where: { $0.id == newID })
        else {
            return nil
        }

        let previousIndex = oldID.flatMap { id in
            viewModel.filteredItems.firstIndex(where: { $0.id == id })
        }

        return HistoryPanelScrollReveal.fallbackAnchor(
            previousIndex: previousIndex,
            selectedIndex: selectedIndex
        )
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16)
        else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum HistoryPanelScrollReveal {
    static let trailingRevealInset: CGFloat = 36

    enum Anchor: Equatable {
        case leading
        case trailing

        fileprivate var defaultUnitPoint: UnitPoint {
            switch self {
            case .leading:
                return .leading
            case .trailing:
                return .trailing
            }
        }
    }

    static func anchor(
        forCardFrame frame: CGRect,
        viewportWidth: CGFloat,
        tolerance: CGFloat = 1
    ) -> Anchor? {
        guard viewportWidth > 0 else { return nil }

        if frame.minX < -tolerance {
            return .leading
        }

        if frame.maxX > viewportWidth + tolerance {
            return .trailing
        }

        return nil
    }

    static func fallbackAnchor(previousIndex: Int?, selectedIndex: Int) -> Anchor {
        guard let previousIndex else {
            return .trailing
        }

        return selectedIndex < previousIndex ? .leading : .trailing
    }

    static func unitPoint(for anchor: Anchor, viewportWidth: CGFloat, cardWidth: CGFloat) -> UnitPoint {
        guard anchor == .trailing else {
            return anchor.defaultUnitPoint
        }

        let availableWidth = viewportWidth - cardWidth
        guard availableWidth > 0 else {
            return anchor.defaultUnitPoint
        }

        let inset = min(trailingRevealInset, availableWidth)
        let x = (viewportWidth - cardWidth - inset) / availableWidth
        return UnitPoint(x: x, y: 0.5)
    }
}

private struct HistoryCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ClipboardItem.ID: CGRect] = [:]

    static func reduce(value: inout [ClipboardItem.ID: CGRect], nextValue: () -> [ClipboardItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct GroupColorPickerPopover: View {
    @Binding var selectedColorHex: String

    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ClipboardGroupColorPalette.hexValues, id: \.self) { colorHex in
                Button {
                    onSelect(colorHex)
                } label: {
                    Circle()
                        .fill(Color(hex: colorHex) ?? Color(nsColor: .systemRed))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedColorHex == colorHex ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colorHex)
                .accessibilityAddTraits(selectedColorHex == colorHex ? [.isSelected] : [])
            }
        }
        .padding(12)
    }
}
