import Foundation

struct ClipboardGroup: Identifiable, Equatable {
    private static let englishDefaultName = "Untitled"
    private static let simplifiedChineseDefaultName = "未命名"
    static let defaultColorHex = "#FF5B57"

    let id: UUID
    let name: String
    let colorHex: String
    let createdAt: Date
    let sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        createdAt: Date,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    static func defaultName(language: AppLanguage) -> String {
        language == .english ? englishDefaultName : simplifiedChineseDefaultName
    }

    static func defaultGroup(
        createdAt: Date = Date(),
        language: AppLanguage = .english
    ) -> ClipboardGroup {
        ClipboardGroup(
            name: defaultName(language: language),
            colorHex: defaultColorHex,
            createdAt: createdAt,
            sortOrder: 0
        )
    }
}

enum ClipboardGroupColorPalette {
    static let hexValues = [
        "#FF5B57",
        "#4B8DFF",
        "#26B36A",
        "#F4B400",
        "#8B65FF",
        "#FF8A3D",
        "#00A3A3"
    ]

    static func firstUnusedColor<S: Sequence>(
        usedColorHexes: S
    ) -> String where S.Element == String {
        let usedColorHexes = Set(usedColorHexes.map { $0.uppercased() })

        return hexValues.first { colorHex in
            !usedColorHexes.contains(colorHex.uppercased())
        } ?? ClipboardGroup.defaultColorHex
    }
}
