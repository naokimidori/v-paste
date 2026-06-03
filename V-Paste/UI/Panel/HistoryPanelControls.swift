import AppKit
import SwiftUI

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

enum HistoryPanelTypeFilterLayout {
    static let labelSpacing: CGFloat = 6
    static let iconFontSize: CGFloat = 13
    static let titleFontSize: CGFloat = iconFontSize
    static let chevronFontSize: CGFloat = 10
    static let chevronAnimationDuration: Double = 0.16
    static let horizontalPadding: CGFloat = 10
    static let controlHeight: CGFloat = 30

    static var labelFont: Font {
        .system(size: titleFontSize, weight: .semibold, design: .rounded)
    }

    static var chevronAnimation: Animation {
        .easeInOut(duration: chevronAnimationDuration)
    }

    static func chevronRotationDegrees(isPresented: Bool) -> Double {
        isPresented ? 180 : 0
    }

    static func menuPopupPoint(anchorHeight _: CGFloat) -> NSPoint {
        NSPoint(x: 0, y: 0)
    }
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

struct HistoryPanelTypeFilterMenuAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool

    let activeFilter: ClipboardContentFilter
    let language: AppLanguage
    let imageName: (ClipboardContentFilter) -> String
    let onSelect: (ClipboardContentFilter) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self

        guard isPresented, !context.coordinator.isMenuOpen else { return }

        DispatchQueue.main.async { [weak nsView, weak coordinator = context.coordinator] in
            guard let nsView,
                  let coordinator,
                  coordinator.parent.isPresented,
                  !coordinator.isMenuOpen else {
                return
            }

            coordinator.showMenu(from: nsView)
        }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: HistoryPanelTypeFilterMenuAnchor
        var isMenuOpen = false

        init(parent: HistoryPanelTypeFilterMenuAnchor) {
            self.parent = parent
        }

        func showMenu(from nsView: NSView) {
            isMenuOpen = true

            let menu = NSMenu()
            menu.delegate = self
            for (index, filter) in ClipboardContentFilter.allCases.enumerated() {
                let item = NSMenuItem(
                    title: HistoryPanelTypeFilterCopy.title(
                        for: filter,
                        language: parent.language
                    ),
                    action: #selector(selectFilter(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.image = NSImage(
                    systemSymbolName: parent.imageName(filter),
                    accessibilityDescription: nil
                )
                menu.addItem(item)
            }

            menu.popUp(
                positioning: nil,
                at: HistoryPanelTypeFilterLayout.menuPopupPoint(
                    anchorHeight: nsView.bounds.height
                ),
                in: nsView
            )
            closeMenuIfNeeded()
        }

        @objc private func selectFilter(_ sender: NSMenuItem) {
            guard ClipboardContentFilter.allCases.indices.contains(sender.tag) else { return }

            parent.onSelect(ClipboardContentFilter.allCases[sender.tag])
        }

        func menuDidClose(_ menu: NSMenu) {
            closeMenuIfNeeded()
        }

        private func closeMenuIfNeeded() {
            guard isMenuOpen else { return }

            isMenuOpen = false
            DispatchQueue.main.async { [parent] in
                withAnimation(HistoryPanelTypeFilterLayout.chevronAnimation) {
                    parent.isPresented = false
                }
            }
        }
    }
}
