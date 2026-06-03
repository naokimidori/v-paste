import SwiftUI

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

struct HistoryCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ClipboardItem.ID: CGRect] = [:]

    static func reduce(value: inout [ClipboardItem.ID: CGRect], nextValue: () -> [ClipboardItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
