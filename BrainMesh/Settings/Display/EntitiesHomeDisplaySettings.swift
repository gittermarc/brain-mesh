//
//  EntitiesHomeDisplaySettings.swift
//  BrainMesh
//
//  PR 02: Display settings for Entities Home.
//

import Foundation

enum EntitiesHomeListStyle: String, Codable, CaseIterable, Identifiable {
    case plain
    case insetGrouped
    case cards

    var id: String { rawValue }
}

enum EntitiesHomeRowStyle: String, Codable, CaseIterable, Identifiable {
    case titleOnly
    case titleWithSubtitle
    case titleWithBadges

    var id: String { rawValue }
}

enum EntitiesHomeRowDensity: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case comfortable

    var id: String { rawValue }
}

enum EntitiesHomeBadgeStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case smallCounter
    case pills

    var id: String { rawValue }
}

enum EntitiesHomeMetaLine: String, Codable, CaseIterable, Identifiable {
    case none
    case notesPreview
    case counts

    var id: String { rawValue }
}

struct EntitiesHomeDisplaySettings: Codable, Equatable {

    // MARK: - New visual knobs (PRs 04/05 will start using these)

    var listStyle: EntitiesHomeListStyle
    var rowStyle: EntitiesHomeRowStyle
    var density: EntitiesHomeRowDensity
    var showSeparators: Bool
    var badgeStyle: EntitiesHomeBadgeStyle
    var metaLine: EntitiesHomeMetaLine

    // MARK: - Existing knobs (currently still sourced from Appearance; included here as foundation)

    var showAttributeCount: Bool
    var showLinkCount: Bool
    var showNotesPreview: Bool
    var preferThumbnailOverIcon: Bool

    // MARK: - Defaults

    static func preset(_ preset: DisplayPreset) -> EntitiesHomeDisplaySettings {
        switch preset {
        case .clean:
            return EntitiesHomeDisplaySettings(
                listStyle: .plain,
                rowStyle: .titleOnly,
                density: .standard,
                showSeparators: true,
                badgeStyle: .none,
                metaLine: .none,
                showAttributeCount: false,
                showLinkCount: false,
                showNotesPreview: false,
                preferThumbnailOverIcon: false
            )
        case .dense:
            return EntitiesHomeDisplaySettings(
                listStyle: .plain,
                rowStyle: .titleWithBadges,
                density: .compact,
                showSeparators: false,
                badgeStyle: .smallCounter,
                metaLine: .none,
                showAttributeCount: true,
                showLinkCount: true,
                showNotesPreview: false,
                preferThumbnailOverIcon: false
            )
        case .visual:
            return EntitiesHomeDisplaySettings(
                listStyle: .cards,
                rowStyle: .titleWithSubtitle,
                density: .comfortable,
                showSeparators: false,
                badgeStyle: .pills,
                metaLine: .notesPreview,
                showAttributeCount: false,
                showLinkCount: false,
                showNotesPreview: true,
                preferThumbnailOverIcon: true
            )
        case .pro:
            return EntitiesHomeDisplaySettings(
                listStyle: .insetGrouped,
                rowStyle: .titleWithSubtitle,
                density: .standard,
                showSeparators: true,
                badgeStyle: .pills,
                metaLine: .counts,
                showAttributeCount: true,
                showLinkCount: true,
                showNotesPreview: true,
                preferThumbnailOverIcon: true
            )
        }
    }

    static let `default` = EntitiesHomeDisplaySettings.preset(.clean)

    // MARK: - Performance metadata (labeling only; UI comes later)

    enum OptionKey: String, CaseIterable {
        case listStyle
        case rowStyle
        case density
        case showSeparators
        case badgeStyle
        case metaLine
        case showAttributeCount
        case showLinkCount
        case showNotesPreview
        case preferThumbnailOverIcon
    }

    static let optionMeta: [OptionKey: DisplayOptionMeta] = [
        .listStyle: DisplayOptionMeta(impact: .none),
        .rowStyle: DisplayOptionMeta(impact: .none),
        .density: DisplayOptionMeta(impact: .none),
        .showSeparators: DisplayOptionMeta(impact: .none),
        .badgeStyle: DisplayOptionMeta(impact: .none),
        .metaLine: DisplayOptionMeta(impact: .low),
        .showAttributeCount: DisplayOptionMeta(impact: .high, note: "Kann zusätzliche Zähl-Queries auslösen."),
        .showLinkCount: DisplayOptionMeta(impact: .medium, note: "Kann zusätzliche Zähl-Queries auslösen."),
        .showNotesPreview: DisplayOptionMeta(impact: .low, note: "Mehr Text kann das Rendering/Scrolling etwas belasten."),
        .preferThumbnailOverIcon: DisplayOptionMeta(impact: .medium, note: "Thumbnails können zusätzliche Loads/Hydration triggern.")
    ]

    // MARK: - Codable (forward compatible)

    private enum CodingKeys: String, CodingKey {
        case listStyle
        case rowStyle
        case density
        case showSeparators
        case badgeStyle
        case metaLine
        case showAttributeCount
        case showLinkCount
        case showNotesPreview
        case preferThumbnailOverIcon
    }

    init(
        listStyle: EntitiesHomeListStyle,
        rowStyle: EntitiesHomeRowStyle,
        density: EntitiesHomeRowDensity,
        showSeparators: Bool,
        badgeStyle: EntitiesHomeBadgeStyle,
        metaLine: EntitiesHomeMetaLine,
        showAttributeCount: Bool,
        showLinkCount: Bool,
        showNotesPreview: Bool,
        preferThumbnailOverIcon: Bool
    ) {
        self.listStyle = listStyle
        self.rowStyle = rowStyle
        self.density = density
        self.showSeparators = showSeparators
        self.badgeStyle = badgeStyle
        self.metaLine = metaLine
        self.showAttributeCount = showAttributeCount
        self.showLinkCount = showLinkCount
        self.showNotesPreview = showNotesPreview
        self.preferThumbnailOverIcon = preferThumbnailOverIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let fallback = EntitiesHomeDisplaySettings.default

        self.listStyle = try container.decodeIfPresent(EntitiesHomeListStyle.self, forKey: .listStyle) ?? fallback.listStyle
        self.rowStyle = try container.decodeIfPresent(EntitiesHomeRowStyle.self, forKey: .rowStyle) ?? fallback.rowStyle
        self.density = try container.decodeIfPresent(EntitiesHomeRowDensity.self, forKey: .density) ?? fallback.density
        self.showSeparators = try container.decodeIfPresent(Bool.self, forKey: .showSeparators) ?? fallback.showSeparators
        self.badgeStyle = try container.decodeIfPresent(EntitiesHomeBadgeStyle.self, forKey: .badgeStyle) ?? fallback.badgeStyle
        self.metaLine = try container.decodeIfPresent(EntitiesHomeMetaLine.self, forKey: .metaLine) ?? fallback.metaLine

        self.showAttributeCount = try container.decodeIfPresent(Bool.self, forKey: .showAttributeCount) ?? fallback.showAttributeCount
        self.showLinkCount = try container.decodeIfPresent(Bool.self, forKey: .showLinkCount) ?? fallback.showLinkCount
        self.showNotesPreview = try container.decodeIfPresent(Bool.self, forKey: .showNotesPreview) ?? fallback.showNotesPreview
        self.preferThumbnailOverIcon = try container.decodeIfPresent(Bool.self, forKey: .preferThumbnailOverIcon) ?? fallback.preferThumbnailOverIcon
    }
}
