import AppKit
import QuartzCore
import SwiftUI

enum HistoryPanelPrintableKey {
    static func character(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        let blockedModifiers = modifierFlags.intersection([.command, .option, .control])
        guard blockedModifiers.isEmpty,
              let charactersIgnoringModifiers,
              charactersIgnoringModifiers.count == 1,
              let scalar = charactersIgnoringModifiers.unicodeScalars.first,
              scalar.value >= 32,
              scalar.value != 127
        else {
            return nil
        }

        return charactersIgnoringModifiers
    }
}

enum HistoryPanelMouseEventRouting {
    static func shouldKeepEvent(
        eventWindow: NSWindow?,
        panel: NSWindow?,
        appWindows: [NSWindow] = NSApp.windows
    ) -> Bool {
        guard let eventWindow else { return false }

        if let panel, eventWindow === panel {
            return true
        }

        return appWindows.contains { $0 === eventWindow }
    }

    static func shouldHidePanelAfterResignKey(
        newKeyWindow: NSWindow?,
        panel: NSWindow?,
        appWindows: [NSWindow] = NSApp.windows
    ) -> Bool {
        !shouldKeepEvent(
            eventWindow: newKeyWindow,
            panel: panel,
            appWindows: appWindows
        )
    }
}

enum HistoryPanelKeyEventRouting {
    static func shouldBypassPanelHandling(firstResponder: NSResponder?) -> Bool {
        firstResponder is NSTextView || firstResponder is NSTextField
    }

    static func isPanelCopyCommand(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let meaningfulModifiers = modifierFlags.intersection([.command, .option, .control])

        return meaningfulModifiers == .command
            && charactersIgnoringModifiers?.lowercased() == "c"
    }

    static func shouldHandleSearchCopyShortcut(
        firstResponder: NSResponder?,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        isSearchExpanded: Bool
    ) -> Bool {
        guard isSearchExpanded,
              shouldBypassPanelHandling(firstResponder: firstResponder)
        else {
            return false
        }

        return isPanelCopyCommand(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        )
    }
}

enum HistoryPanelLayout {
    static let topPadding: CGFloat = 10
    static let rootBottomPadding: CGFloat = 8
    static let toolbarHeight: CGFloat = 38
    static let toolbarToCardSpacing: CGFloat = 8
    static let cardStripTopPadding: CGFloat = 0
    static let cardStripBottomPadding: CGFloat = 4
    static let horizontalPadding: CGFloat = 28
    static let panelHeight: CGFloat = topPadding
        + toolbarHeight
        + toolbarToCardSpacing
        + cardStripTopPadding
        + HistoryCardLayout.cardHeight
        + cardStripBottomPadding
        + rootBottomPadding
    static let windowLevel: NSWindow.Level = .statusBar

    static func frame(screenFrame: NSRect, visibleFrame: NSRect, hiddenOffset: CGFloat) -> NSRect {
        NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY - hiddenOffset,
            width: screenFrame.width,
            height: panelHeight
        )
    }
}

enum HistoryPanelPresentationAnimation {
    static let hiddenBottomInset: CGFloat = 8
    static var hiddenOffset: CGFloat {
        HistoryPanelLayout.panelHeight + hiddenBottomInset
    }
    static let showDuration: TimeInterval = 0.24
    static let hideDuration: TimeInterval = 0.18

    static let showTimingFunction = CAMediaTimingFunction(name: .easeOut)
    static let hideTimingFunction = CAMediaTimingFunction(name: .easeIn)
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var panel: FloatingHistoryPanel?
    private var hostingController: NSHostingController<HistoryPanelView>?
    private var globalOutsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var onCopy: ((ClipboardItem) -> Void)?
    private var onToggleFavorite: ((ClipboardItem) -> Void)?
    private var onCreateGroup: (() -> ClipboardGroup?)?
    private var onSelectGroup: ((ClipboardGroup.ID?) -> Void)?
    private var onUpdateGroup: ((ClipboardGroup) -> Void)?
    private var onAssignItemToGroup: ((ClipboardItem.ID, ClipboardGroup.ID) -> Void)?
    private var onDeleteGroup: ((ClipboardGroup.ID) -> Void)?
    private var onDeleteItem: ((ClipboardItem) -> Void)?
    private var onOpenPreferences: (() -> Void)?
    private var onOpenAbout: (() -> Void)?
    private var onQuit: (() -> Void)?
    private var presentationGeneration = 0

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func toggle(
        onCopy: @escaping (ClipboardItem) -> Void,
        onToggleFavorite: @escaping (ClipboardItem) -> Void,
        onCreateGroup: @escaping () -> ClipboardGroup?,
        onSelectGroup: @escaping (ClipboardGroup.ID?) -> Void,
        onUpdateGroup: @escaping (ClipboardGroup) -> Void,
        onAssignItemToGroup: @escaping (ClipboardItem.ID, ClipboardGroup.ID) -> Void,
        onDeleteGroup: @escaping (ClipboardGroup.ID) -> Void,
        onDeleteItem: @escaping (ClipboardItem) -> Void,
        onOpenPreferences: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        if appState.isPanelVisible {
            hide()
        } else {
            show(
                onCopy: onCopy,
                onToggleFavorite: onToggleFavorite,
                onCreateGroup: onCreateGroup,
                onSelectGroup: onSelectGroup,
                onUpdateGroup: onUpdateGroup,
                onAssignItemToGroup: onAssignItemToGroup,
                onDeleteGroup: onDeleteGroup,
                onDeleteItem: onDeleteItem,
                onOpenPreferences: onOpenPreferences,
                onOpenAbout: onOpenAbout,
                onQuit: onQuit
            )
        }
    }

    func show(
        onCopy: @escaping (ClipboardItem) -> Void,
        onToggleFavorite: @escaping (ClipboardItem) -> Void,
        onCreateGroup: @escaping () -> ClipboardGroup?,
        onSelectGroup: @escaping (ClipboardGroup.ID?) -> Void,
        onUpdateGroup: @escaping (ClipboardGroup) -> Void,
        onAssignItemToGroup: @escaping (ClipboardItem.ID, ClipboardGroup.ID) -> Void,
        onDeleteGroup: @escaping (ClipboardGroup.ID) -> Void,
        onDeleteItem: @escaping (ClipboardItem) -> Void,
        onOpenPreferences: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onToggleFavorite = onToggleFavorite
        self.onCreateGroup = onCreateGroup
        self.onSelectGroup = onSelectGroup
        self.onUpdateGroup = onUpdateGroup
        self.onAssignItemToGroup = onAssignItemToGroup
        self.onDeleteGroup = onDeleteGroup
        self.onDeleteItem = onDeleteItem
        self.onOpenPreferences = onOpenPreferences
        self.onOpenAbout = onOpenAbout
        self.onQuit = onQuit
        presentationGeneration += 1
        appState.panelViewModel.resetSearchForPresentation()
        appState.refreshPanelItems(resetSelection: true)

        let panel = makePanelIfNeeded()
        position(panel: panel, hiddenOffset: HistoryPanelPresentationAnimation.hiddenOffset)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.isPanelVisible = true
        installEventMonitors()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = HistoryPanelPresentationAnimation.showDuration
            context.timingFunction = HistoryPanelPresentationAnimation.showTimingFunction
            animatePosition(panel: panel, hiddenOffset: 0)
        }
    }

    func hide() {
        guard let panel else {
            appState.isPanelVisible = false
            return
        }

        presentationGeneration += 1
        let hideGeneration = presentationGeneration
        removeEventMonitors()
        appState.isPanelVisible = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = HistoryPanelPresentationAnimation.hideDuration
            context.timingFunction = HistoryPanelPresentationAnimation.hideTimingFunction
            animatePosition(
                panel: panel,
                hiddenOffset: HistoryPanelPresentationAnimation.hiddenOffset
            )
        } completionHandler: {
            Task { @MainActor in
                guard self.presentationGeneration == hideGeneration else { return }

                panel.orderOut(nil)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appState.isPanelVisible else { return }
            guard HistoryPanelMouseEventRouting.shouldHidePanelAfterResignKey(
                newKeyWindow: NSApp.keyWindow,
                panel: self.panel
            ) else {
                return
            }

            self.hide()
        }
    }

    private func makePanelIfNeeded() -> FloatingHistoryPanel {
        if let panel {
            return panel
        }

        let view = HistoryPanelView(
            viewModel: appState.panelViewModel,
            onClose: { [weak self] in
                self?.hide()
            },
            onCopy: { [weak self] item in
                self?.onCopy?(item)
                self?.hide()
            },
            onToggleFavorite: { [weak self] item in
                self?.onToggleFavorite?(item)
            },
            onCreateGroup: { [weak self] in
                guard let self else { return nil }

                return self.onCreateGroup?()
            },
            onSelectGroup: { [weak self] groupID in
                self?.onSelectGroup?(groupID)
            },
            onUpdateGroup: { [weak self] group in
                self?.onUpdateGroup?(group)
            },
            onAssignItemToGroup: { [weak self] itemID, groupID in
                self?.onAssignItemToGroup?(itemID, groupID)
            },
            onDeleteGroup: { [weak self] groupID in
                self?.onDeleteGroup?(groupID)
            },
            onDeleteItem: { [weak self] item in
                self?.onDeleteItem?(item)
            },
            onOpenPreferences: { [weak self] in
                self?.onOpenPreferences?()
            },
            onOpenAbout: { [weak self] in
                self?.onOpenAbout?()
            },
            onQuit: { [weak self] in
                self?.onQuit?()
            }
        )
        let hostingController = NSHostingController(rootView: view)
        let panel = FloatingHistoryPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.delegate = self
        panel.level = HistoryPanelLayout.windowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]

        self.hostingController = hostingController
        self.panel = panel
        return panel
    }

    private func position(panel: NSWindow, hiddenOffset: CGFloat) {
        guard let frame = frame(for: panel, hiddenOffset: hiddenOffset) else { return }

        panel.setFrame(frame, display: true)
    }

    private func animatePosition(panel: NSWindow, hiddenOffset: CGFloat) {
        guard let frame = frame(for: panel, hiddenOffset: hiddenOffset) else { return }

        panel.animator().setFrame(frame, display: true)
    }

    private func frame(for panel: NSWindow, hiddenOffset: CGFloat) -> NSRect? {
        guard let screen = panel.screen ?? activeScreen() else { return nil }

        return HistoryPanelLayout.frame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            hiddenOffset: hiddenOffset
        )
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func installEventMonitors() {
        removeEventMonitors()

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }

            return self.handleLocalEvent(event)
        }
    }

    private func removeEventMonitors() {
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard appState.isPanelVisible else { return event }

        switch event.type {
        case .keyDown:
            if HistoryPanelKeyEventRouting.shouldHandleSearchCopyShortcut(
                firstResponder: panel?.firstResponder,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags,
                isSearchExpanded: appState.panelViewModel.isSearchExpanded
            ) {
                copySelectedItem()
                return nil
            }

            guard !HistoryPanelKeyEventRouting.shouldBypassPanelHandling(
                firstResponder: panel?.firstResponder
            ) else {
                return event
            }

            return handleKeyDown(event)
        case .leftMouseDown, .rightMouseDown:
            guard HistoryPanelMouseEventRouting.shouldKeepEvent(
                eventWindow: event.window,
                panel: panel
            ) else {
                hide()
                return nil
            }

            return event
        default:
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if HistoryPanelKeyEventRouting.isPanelCopyCommand(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) {
            copySelectedItem()
            return nil
        }

        let meaningfulModifiers = event.modifierFlags.intersection([.command, .option, .control])

        guard meaningfulModifiers.isEmpty else { return event }

        switch event.keyCode {
        case 123:
            appState.panelViewModel.moveSelection(delta: -1)
            return nil
        case 124:
            appState.panelViewModel.moveSelection(delta: 1)
            return nil
        case 36, 76:
            copySelectedItem()
            return nil
        case 53:
            hide()
            return nil
        case 51, 117:
            guard appState.panelViewModel.isSearchExpanded else { return event }

            appState.panelViewModel.deleteLastSearchCharacter(requestFocus: true)
            return nil
        default:
            if let character = HistoryPanelPrintableKey.character(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags
            ) {
                appState.panelViewModel.expandSearch(with: character, requestFocus: true)
                return nil
            }

            return event
        }
    }

    private func copySelectedItem() {
        guard let selectedItem = appState.panelViewModel.selectedItem else { return }

        onCopy?(selectedItem)
        hide()
    }
}

private final class FloatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
