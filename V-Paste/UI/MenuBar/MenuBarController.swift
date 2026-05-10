import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: 28
    )
    private let onTogglePanel: () -> Void
    private let onOpenPreferences: () -> Void
    private let onOpenAbout: () -> Void

    private var menu = NSMenu()

    init(
        onTogglePanel: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void
    ) {
        self.onTogglePanel = onTogglePanel
        self.onOpenPreferences = onOpenPreferences
        self.onOpenAbout = onOpenAbout
        super.init()

        configureStatusItem()
        rebuildMenu(isMonitoringPaused: false)
    }

    func rebuildMenu(
        isMonitoringPaused: Bool,
        language: AppLanguage = .english,
        shortcut: HotKeyPreference = .defaultShowPanel
    ) {
        let menu = NSMenu()
        MenuBarMenuDescriptor.items(
            appName: "V-Paste",
            language: language,
            shortcut: shortcut
        ).forEach { descriptor in
            menu.addItem(menuItem(for: descriptor))
        }

        self.menu = menu
    }

    private func menuItem(for descriptor: MenuBarMenuItemDescriptor) -> NSMenuItem {
        guard let title = descriptor.title else {
            return .separator()
        }

        let item = NSMenuItem(
            title: title,
            action: selector(for: descriptor.action),
            keyEquivalent: descriptor.keyEquivalent
        )
        item.keyEquivalentModifierMask = descriptor.keyEquivalentModifierMask
        item.target = self
        item.isEnabled = descriptor.action != nil || !descriptor.children.isEmpty

        if let iconAssetName = descriptor.iconAssetName,
           let image = NSImage(named: NSImage.Name(iconAssetName))?.copy() as? NSImage {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }

        if !descriptor.children.isEmpty {
            let submenu = NSMenu(title: title)
            descriptor.children.forEach { child in
                submenu.addItem(menuItem(for: child))
            }
            item.submenu = submenu
        }

        return item
    }

    private func selector(for action: MenuBarMenuAction?) -> Selector? {
        action.map { NSSelectorFromString($0.selectorName) }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        if let menuBarImage = NSImage(named: "MenuBarIcon")?.copy() as? NSImage {
            menuBarImage.isTemplate = true
            menuBarImage.size = NSSize(width: 22, height: 22)
            button.image = menuBarImage
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.title = ""
        } else {
            button.title = "VP"
        }
        button.toolTip = "V-Paste Clipboard History"
        button.setAccessibilityLabel("V-Paste Clipboard History")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true {
            statusItem.popUpMenu(menu)
            return
        }

        onTogglePanel()
    }

    @objc private func openClipboardHistory() {
        onTogglePanel()
    }

    @objc private func openPreferences() {
        onOpenPreferences()
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(MenuBarAboutDescriptor.repositoryURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
