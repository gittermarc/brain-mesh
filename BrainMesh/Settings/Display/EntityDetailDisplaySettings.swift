//
//  EntityDetailDisplaySettings.swift
//  BrainMesh
//
//  PR 02: Display settings for Entity Detail.
//

import Foundation

enum EntityDetailHeroImageStyle: String, Codable, CaseIterable, Identifiable {
    case large
    case compact
    case hidden

    var id: String { rawValue }
}

enum EntityDetailSection: String, Codable, CaseIterable, Identifiable {
    case attributesPreview
    case detailsFields
    case notes
    case media
    case connections

    var id: String { rawValue }
}

struct EntityDetailDisplaySettings: Codable, Equatable {

    var heroImageStyle: EntityDetailHeroImageStyle
    var showHeroPills: Bool
    var heroPillLimit: Int

    /// Visual order of sections (even if some are hidden).
    var sectionOrder: [EntityDetailSection]

    /// Sections hidden entirely.
    var hiddenSections: [EntityDetailSection]

    /// Sections that should start collapsed.
    var collapsedSections: [EntityDetailSection]

    static func preset(_ preset: DisplayPreset) -> EntityDetailDisplaySettings {
        let baseOrder: [EntityDetailSection] = [.attributesPreview, .detailsFields, .notes, .media, .connections]

        switch preset {
        case .clean:
            return EntityDetailDisplaySettings(
                heroImageStyle: .compact,
                showHeroPills: false,
                heroPillLimit: 0,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: [.notes, .media]
            )

        case .dense:
            return EntityDetailDisplaySettings(
                heroImageStyle: .hidden,
                showHeroPills: false,
                heroPillLimit: 0,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: [.notes, .media, .connections]
            )

        case .visual:
            return EntityDetailDisplaySettings(
                heroImageStyle: .large,
                showHeroPills: true,
                heroPillLimit: 4,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: [.connections]
            )

        case .pro:
            return EntityDetailDisplaySettings(
                heroImageStyle: .large,
                showHeroPills: true,
                heroPillLimit: 6,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: []
            )
        }
    }

    static let `default` = EntityDetailDisplaySettings.preset(.clean)

    enum OptionKey: String, CaseIterable {
        case heroImageStyle
        case showHeroPills
        case heroPillLimit
        case sectionOrder
        case hiddenSections
        case collapsedSections
    }

    static let optionMeta: [OptionKey: DisplayOptionMeta] = [
        .heroImageStyle: DisplayOptionMeta(impact: .low, note: "Große Header können mehr Layout-Arbeit bedeuten."),
        .showHeroPills: DisplayOptionMeta(impact: .none),
        .heroPillLimit: DisplayOptionMeta(impact: .none),
        .sectionOrder: DisplayOptionMeta(impact: .none),
        .hiddenSections: DisplayOptionMeta(impact: .none),
        .collapsedSections: DisplayOptionMeta(impact: .none)
    ]

    private enum CodingKeys: String, CodingKey {
        case heroImageStyle
        case showHeroPills
        case heroPillLimit
        case sectionOrder
        case hiddenSections
        case collapsedSections
    }

    init(
        heroImageStyle: EntityDetailHeroImageStyle,
        showHeroPills: Bool,
        heroPillLimit: Int,
        sectionOrder: [EntityDetailSection],
        hiddenSections: [EntityDetailSection],
        collapsedSections: [EntityDetailSection]
    ) {
        self.heroImageStyle = heroImageStyle
        self.showHeroPills = showHeroPills
        self.heroPillLimit = heroPillLimit
        self.sectionOrder = sectionOrder
        self.hiddenSections = hiddenSections
        self.collapsedSections = collapsedSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = EntityDetailDisplaySettings.default

        self.heroImageStyle = try container.decodeIfPresent(EntityDetailHeroImageStyle.self, forKey: .heroImageStyle) ?? fallback.heroImageStyle
        self.showHeroPills = try container.decodeIfPresent(Bool.self, forKey: .showHeroPills) ?? fallback.showHeroPills
        self.heroPillLimit = try container.decodeIfPresent(Int.self, forKey: .heroPillLimit) ?? fallback.heroPillLimit

        self.sectionOrder = try container.decodeIfPresent([EntityDetailSection].self, forKey: .sectionOrder) ?? fallback.sectionOrder
        self.hiddenSections = try container.decodeIfPresent([EntityDetailSection].self, forKey: .hiddenSections) ?? fallback.hiddenSections
        self.collapsedSections = try container.decodeIfPresent([EntityDetailSection].self, forKey: .collapsedSections) ?? fallback.collapsedSections
    }
}
