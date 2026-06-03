import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isTypeFilterMenuPresented = false

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
                Array(MenuBarMenuDescriptor.panelOverflowItems(
                    appName: "V-Paste",
                    language: viewModel.language
                ).enumerated()),
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
        .help(overflowMenuAccessibilityLabel)
        .accessibilityLabel(overflowMenuAccessibilityLabel)
    }

    private var overflowMenuAccessibilityLabel: String {
        viewModel.language == .english ? "Menu" : "菜单"
    }

    private func overflowMenuContent(for descriptor: MenuBarMenuItemDescriptor) -> AnyView {
        guard let title = descriptor.title else {
            return AnyView(Divider())
        }

        if !descriptor.children.isEmpty {
            return AnyView(
                Menu(title) {
                    ForEach(Array(descriptor.children.enumerated()), id: \.offset) { _, child in
                        overflowMenuContent(for: child)
                    }
                }
            )
        }

        switch descriptor.action {
        case .openPreferences:
            return AnyView(
                Button(action: performOpenPreferences) {
                    overflowMenuLabel(title: title, descriptor: descriptor)
                }
                .keyboardShortcut(",", modifiers: .command)
            )
        case .openAbout:
            return AnyView(
                Button(action: performOpenAbout) {
                    overflowMenuLabel(title: title, descriptor: descriptor)
                }
            )
        case .openGitHub:
            return AnyView(
                Button(action: performOpenGitHub) {
                    overflowMenuLabel(title: title, descriptor: descriptor)
                }
            )
        case .quit:
            return AnyView(
                Button(action: onQuit) {
                    overflowMenuLabel(title: title, descriptor: descriptor)
                }
                .keyboardShortcut("q", modifiers: .command)
            )
        case .showPanel, nil:
            return AnyView(
                Button(action: {}) {
                    overflowMenuLabel(title: title, descriptor: descriptor)
                }
                .disabled(true)
            )
        }
    }

    @ViewBuilder
    private func overflowMenuLabel(
        title: String,
        descriptor: MenuBarMenuItemDescriptor
    ) -> some View {
        if let shortcutDisplay = descriptor.shortcutDisplay,
           descriptor.keyEquivalent.isEmpty {
            HStack(spacing: 12) {
                overflowMenuPrimaryLabel(title: title, descriptor: descriptor)
                Spacer(minLength: 18)
                Text(shortcutDisplay)
                    .foregroundStyle(.secondary)
            }
        } else {
            overflowMenuPrimaryLabel(title: title, descriptor: descriptor)
        }
    }

    @ViewBuilder
    private func overflowMenuPrimaryLabel(
        title: String,
        descriptor: MenuBarMenuItemDescriptor
    ) -> some View {
        if let iconAssetName = descriptor.iconAssetName {
            Label {
                Text(title)
            } icon: {
                Image(iconAssetName)
                    .renderingMode(.template)
            }
        } else {
            Text(title)
        }
    }

    private func performOpenPreferences() {
        onOpenPreferences()
    }

    private func performOpenAbout() {
        onOpenAbout()
    }

    private func performOpenGitHub() {
        NSWorkspace.shared.open(MenuBarAboutDescriptor.repositoryURL)
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
            .help(HistoryPanelSearchCopy.searchTitle(language: viewModel.language))
            .accessibilityLabel(HistoryPanelSearchCopy.searchTitle(language: viewModel.language))

            Label(
                HistoryPanelToolbarCopy.localizedTitle(language: viewModel.language),
                systemImage: "clock.arrow.circlepath"
            )
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(nsColor: .separatorColor).opacity(0.22), in: Capsule())

            groupStrip(maxWidth: 360)

            createGroupButton

            typeFilterMenu

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
                .accessibilityLabel(HistoryPanelToolbarCopy.localizedTitle(language: viewModel.language))

            groupStrip(maxWidth: 300)

            createGroupButton

            typeFilterMenu
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
                                language: viewModel.language,
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
                title: HistoryPanelScopeCopy.allTitle(language: viewModel.language),
                systemImage: "tray.full",
                isActive: !viewModel.showsFavoritesOnly
            ) {
                viewModel.setShowsFavoritesOnly(false)
            }

            scopeButton(
                title: HistoryPanelScopeCopy.favoritesTitle(language: viewModel.language),
                systemImage: "star.fill",
                isActive: viewModel.showsFavoritesOnly
            ) {
                viewModel.setShowsFavoritesOnly(true)
            }
        }
        .padding(3)
        .background(Color(nsColor: .separatorColor).opacity(0.18), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HistoryPanelScopeCopy.clipboardScopeTitle(language: viewModel.language))
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

    private var typeFilterMenu: some View {
        Button {
            withAnimation(HistoryPanelTypeFilterLayout.chevronAnimation) {
                isTypeFilterMenuPresented = true
            }
        } label: {
            HStack(spacing: HistoryPanelTypeFilterLayout.labelSpacing) {
                Image(systemName: typeFilterSystemImage(for: viewModel.activeContentFilter))

                Text(
                    HistoryPanelTypeFilterCopy.title(
                        for: viewModel.activeContentFilter,
                        language: viewModel.language
                    )
                )
                .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(
                        size: HistoryPanelTypeFilterLayout.chevronFontSize,
                        weight: .bold
                    ))
                    .rotationEffect(.degrees(
                        HistoryPanelTypeFilterLayout.chevronRotationDegrees(
                            isPresented: isTypeFilterMenuPresented
                        )
                    ))
                    .animation(
                        HistoryPanelTypeFilterLayout.chevronAnimation,
                        value: isTypeFilterMenuPresented
                    )
            }
            .font(HistoryPanelTypeFilterLayout.labelFont)
            .foregroundStyle(viewModel.activeContentFilter == .all ? .secondary : .primary)
            .padding(.horizontal, HistoryPanelTypeFilterLayout.horizontalPadding)
            .frame(height: HistoryPanelTypeFilterLayout.controlHeight)
            .background {
                Capsule()
                    .fill(
                        viewModel.activeContentFilter == .all
                            ? Color(nsColor: .separatorColor).opacity(0.16)
                            : Color(nsColor: .controlAccentColor).opacity(0.16)
                    )
            }
            .contentShape(Capsule())
            .background {
                HistoryPanelTypeFilterMenuAnchor(
                    isPresented: $isTypeFilterMenuPresented,
                    activeFilter: viewModel.activeContentFilter,
                    language: viewModel.language,
                    imageName: typeFilterSystemImage(for:),
                    onSelect: { filter in
                        viewModel.setActiveContentFilter(filter)
                    }
                )
            }
        }
        .buttonStyle(.plain)
        .help(HistoryPanelTypeFilterCopy.typeTitle(language: viewModel.language))
        .accessibilityLabel(HistoryPanelTypeFilterCopy.typeTitle(language: viewModel.language))
        .accessibilityValue(
            HistoryPanelTypeFilterCopy.title(
                for: viewModel.activeContentFilter,
                language: viewModel.language
            )
        )
    }

    private func typeFilterSystemImage(for filter: ClipboardContentFilter) -> String {
        switch filter {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .images:
            return "photo"
        case .text:
            return "text.alignleft"
        case .links:
            return "link"
        case .files:
            return "doc"
        }
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
                placeholder: HistoryPanelSearchCopy.searchTitle(language: viewModel.language),
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
                .accessibilityLabel(HistoryPanelSearchCopy.clearTitle(language: viewModel.language))
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
        HistoryPanelEmptyStateCopy.title(
            searchText: viewModel.searchText,
            showsFavoritesOnly: viewModel.showsFavoritesOnly,
            hasActiveGroup: viewModel.activeGroupID != nil,
            language: viewModel.language
        )
    }

    private var emptyStateSubtitle: String {
        HistoryPanelEmptyStateCopy.subtitle(
            searchText: viewModel.searchText,
            showsFavoritesOnly: viewModel.showsFavoritesOnly,
            hasActiveGroup: viewModel.activeGroupID != nil,
            language: viewModel.language
        )
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
        .help(HistoryPanelGroupCopy.createTitle(language: viewModel.language))
        .accessibilityLabel(HistoryPanelGroupCopy.createTitle(language: viewModel.language))
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
        .accessibilityLabel(HistoryPanelGroupCopy.groupListTitle(language: viewModel.language))
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
                Button(HistoryPanelGroupCopy.editTitle(language: viewModel.language)) {
                    beginEditing(group: group)
                }

                Button(HistoryPanelGroupCopy.deleteTitle(language: viewModel.language), role: .destructive) {
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
            Button(HistoryPanelGroupCopy.deleteTitle(language: viewModel.language), role: .destructive) {
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
        .accessibilityLabel(HistoryPanelGroupCopy.colorTitle(language: viewModel.language))
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
            name: trimmedName.isEmpty
                ? ClipboardGroup.defaultName(language: viewModel.language)
                : trimmedName,
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
