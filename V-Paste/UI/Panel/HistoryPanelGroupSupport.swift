import AppKit
import SwiftUI

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

struct GroupColorPickerPopover: View {
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
