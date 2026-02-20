//
//  AttributeDetailDisplaySettings.swift
//  BrainMesh
//
//  PR 02: Display settings for Attribute Detail.
//

import Foundation

enum AttributeDetailFocusMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case writing
    case data
    case linking
    case media

    var id: String { rawValue }
}

enum AttributeDetailDetailsLayout: String, Codable, CaseIterable, Identifiable {
    case list
    case cards
    case twoColumns

    var id: String { rawValue }
}

enum AttributeDetailSection: String, Codable, CaseIterable, Identifiable {
    case detailsFields
    case notes
    case media
    case connections

    var id: String { rawValue }
}

struct AttributeDetailDisplaySettings: Codable, Equatable {

    var focusMode: AttributeDetailFocusMode
    var detailsLayout: AttributeDetailDetailsLayout
    var hideEmptyDetails: Bool

    var sectionOrder: [AttributeDetailSection]
    var hiddenSections: [AttributeDetailSection]
    var collapsedSections: [AttributeDetailSection]

    static func preset(_ preset: DisplayPreset) -> AttributeDetailDisplaySettings {
        let baseOrder: [AttributeDetailSection] = [.detailsFields, .notes, .media, .connections]

        switch preset {
        case .clean:
            return AttributeDetailDisplaySettings(
                focusMode: .auto,
                detailsLayout: .list,
                hideEmptyDetails: true,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: [.media, .connections]
            )

        case .dense:
            return AttributeDetailDisplaySettings(
                focusMode: .auto,
                detailsLayout: .list,
                hideEmptyDetails: true,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: [.notes, .media, .connections]
            )

        case .visual:
            return AttributeDetailDisplaySettings(
                focusMode: .auto,
                detailsLayout: .cards,
                hideEmptyDetails: true,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: [.connections]
            )

        case .pro:
            return AttributeDetailDisplaySettings(
                focusMode: .auto,
                detailsLayout: .twoColumns,
                hideEmptyDetails: false,
                sectionOrder: baseOrder,
                hiddenSections: [],
                collapsedSections: []
            )
        }
    }

    static let `default` = AttributeDetailDisplaySettings.preset(.clean)

    enum OptionKey: String, CaseIterable {
        case focusMode
        case detailsLayout
        case hideEmptyDetails
        case sectionOrder
        case hiddenSections
        case collapsedSections
    }

    static let optionMeta: [OptionKey: DisplayOptionMeta] = [
        .focusMode: DisplayOptionMeta(impact: .none),
        .detailsLayout: DisplayOptionMeta(impact: .low, note: "Karten/Spalten können mehr Layout-Arbeit bedeuten."),
        .hideEmptyDetails: DisplayOptionMeta(impact: .none),
        .sectionOrder: DisplayOptionMeta(impact: .none),
        .hiddenSections: DisplayOptionMeta(impact: .none),
        .collapsedSections: DisplayOptionMeta(impact: .none)
    ]

    private enum CodingKeys: String, CodingKey {
        case focusMode
        case detailsLayout
        case hideEmptyDetails
        case sectionOrder
        case hiddenSections
        case collapsedSections
    }

    init(
        focusMode: AttributeDetailFocusMode,
        detailsLayout: AttributeDetailDetailsLayout,
        hideEmptyDetails: Bool,
        sectionOrder: [AttributeDetailSection],
        hiddenSections: [AttributeDetailSection],
        collapsedSections: [AttributeDetailSection]
    ) {
        self.focusMode = focusMode
        self.detailsLayout = detailsLayout
        self.hideEmptyDetails = hideEmptyDetails
        self.sectionOrder = sectionOrder
        self.hiddenSections = hiddenSections
        self.collapsedSections = collapsedSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AttributeDetailDisplaySettings.default

        self.focusMode = try container.decodeIfPresent(AttributeDetailFocusMode.self, forKey: .focusMode) ?? fallback.focusMode
        self.detailsLayout = try container.decodeIfPresent(AttributeDetailDetailsLayout.self, forKey: .detailsLayout) ?? fallback.detailsLayout
        self.hideEmptyDetails = try container.decodeIfPresent(Bool.self, forKey: .hideEmptyDetails) ?? fallback.hideEmptyDetails

        self.sectionOrder = try container.decodeIfPresent([AttributeDetailSection].self, forKey: .sectionOrder) ?? fallback.sectionOrder
        self.hiddenSections = try container.decodeIfPresent([AttributeDetailSection].self, forKey: .hiddenSections) ?? fallback.hiddenSections
        self.collapsedSections = try container.decodeIfPresent([AttributeDetailSection].self, forKey: .collapsedSections) ?? fallback.collapsedSections
    }
}
