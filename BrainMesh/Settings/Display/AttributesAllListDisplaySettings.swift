//
//  AttributesAllListDisplaySettings.swift
//  BrainMesh
//
//  PR 02: Display settings for the "Alle Attribute" list.
//

import Foundation

enum AttributesAllRowDensity: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case comfortable

    var id: String { rawValue }
}

enum AttributesAllIconPolicy: String, Codable, CaseIterable, Identifiable {
    case always
    case onlyIfSet
    case never

    var id: String { rawValue }
}

enum AttributesAllPinnedDetailsStyle: String, Codable, CaseIterable, Identifiable {
    case chips
    case inline
    case twoColumns

    var id: String { rawValue }
}

enum AttributesAllGrouping: String, Codable, CaseIterable, Identifiable {
    case none
    case az
    case byIcon
    case hasDetails
    case hasMedia

    var id: String { rawValue }
}

struct AttributesAllListDisplaySettings: Codable, Equatable {

    var rowDensity: AttributesAllRowDensity
    var iconPolicy: AttributesAllIconPolicy

    /// 0 = off
    var notesPreviewLines: Int

    var showPinnedDetails: Bool
    var pinnedDetailsStyle: AttributesAllPinnedDetailsStyle

    var grouping: AttributesAllGrouping
    var stickyHeadersEnabled: Bool

    static func preset(_ preset: DisplayPreset) -> AttributesAllListDisplaySettings {
        switch preset {
        case .clean:
            return AttributesAllListDisplaySettings(
                rowDensity: .standard,
                iconPolicy: .onlyIfSet,
                notesPreviewLines: 0,
                showPinnedDetails: false,
                pinnedDetailsStyle: .chips,
                grouping: .none,
                stickyHeadersEnabled: false
            )

        case .dense:
            return AttributesAllListDisplaySettings(
                rowDensity: .compact,
                iconPolicy: .onlyIfSet,
                notesPreviewLines: 0,
                showPinnedDetails: false,
                pinnedDetailsStyle: .inline,
                grouping: .none,
                stickyHeadersEnabled: false
            )

        case .visual:
            return AttributesAllListDisplaySettings(
                rowDensity: .comfortable,
                iconPolicy: .always,
                notesPreviewLines: 2,
                showPinnedDetails: true,
                pinnedDetailsStyle: .chips,
                grouping: .none,
                stickyHeadersEnabled: false
            )

        case .pro:
            return AttributesAllListDisplaySettings(
                rowDensity: .standard,
                iconPolicy: .always,
                notesPreviewLines: 1,
                showPinnedDetails: true,
                pinnedDetailsStyle: .twoColumns,
                grouping: .az,
                stickyHeadersEnabled: true
            )
        }
    }

    static let `default` = AttributesAllListDisplaySettings.preset(.clean)

    enum OptionKey: String, CaseIterable {
        case rowDensity
        case iconPolicy
        case notesPreviewLines
        case showPinnedDetails
        case pinnedDetailsStyle
        case grouping
        case stickyHeadersEnabled
    }

    static let optionMeta: [OptionKey: DisplayOptionMeta] = [
        .rowDensity: DisplayOptionMeta(impact: .none),
        .iconPolicy: DisplayOptionMeta(impact: .none),
        .notesPreviewLines: DisplayOptionMeta(impact: .low, note: "Mehr Text kann das Rendering/Scrolling etwas belasten."),
        .showPinnedDetails: DisplayOptionMeta(impact: .low, note: "Pinned Details können die Zeilenhöhe erhöhen."),
        .pinnedDetailsStyle: DisplayOptionMeta(impact: .low, note: "Mehr Layout-Arbeit bei Inline/Spalten."),
        .grouping: DisplayOptionMeta(impact: .medium, note: "Gruppieren kann mehr Sort/Group-Arbeit auslösen."),
        .stickyHeadersEnabled: DisplayOptionMeta(impact: .low)
    ]

    private enum CodingKeys: String, CodingKey {
        case rowDensity
        case iconPolicy
        case notesPreviewLines
        case showPinnedDetails
        case pinnedDetailsStyle
        case grouping
        case stickyHeadersEnabled
    }

    init(
        rowDensity: AttributesAllRowDensity,
        iconPolicy: AttributesAllIconPolicy,
        notesPreviewLines: Int,
        showPinnedDetails: Bool,
        pinnedDetailsStyle: AttributesAllPinnedDetailsStyle,
        grouping: AttributesAllGrouping,
        stickyHeadersEnabled: Bool
    ) {
        self.rowDensity = rowDensity
        self.iconPolicy = iconPolicy
        self.notesPreviewLines = max(0, min(2, notesPreviewLines))
        self.showPinnedDetails = showPinnedDetails
        self.pinnedDetailsStyle = pinnedDetailsStyle
        self.grouping = grouping
        self.stickyHeadersEnabled = stickyHeadersEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AttributesAllListDisplaySettings.default

        self.rowDensity = try container.decodeIfPresent(AttributesAllRowDensity.self, forKey: .rowDensity) ?? fallback.rowDensity
        self.iconPolicy = try container.decodeIfPresent(AttributesAllIconPolicy.self, forKey: .iconPolicy) ?? fallback.iconPolicy

        let lines = try container.decodeIfPresent(Int.self, forKey: .notesPreviewLines) ?? fallback.notesPreviewLines
        self.notesPreviewLines = max(0, min(2, lines))

        self.showPinnedDetails = try container.decodeIfPresent(Bool.self, forKey: .showPinnedDetails) ?? fallback.showPinnedDetails
        self.pinnedDetailsStyle = try container.decodeIfPresent(AttributesAllPinnedDetailsStyle.self, forKey: .pinnedDetailsStyle) ?? fallback.pinnedDetailsStyle
        self.grouping = try container.decodeIfPresent(AttributesAllGrouping.self, forKey: .grouping) ?? fallback.grouping
        self.stickyHeadersEnabled = try container.decodeIfPresent(Bool.self, forKey: .stickyHeadersEnabled) ?? fallback.stickyHeadersEnabled
    }
}
