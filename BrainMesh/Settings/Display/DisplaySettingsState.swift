//
//  DisplaySettingsState.swift
//  BrainMesh
//
//  PR 02: Root container for display settings.
//  This introduces an override layer at *screen* granularity:
//  - Preset defines defaults per screen.
//  - An optional override replaces those defaults for that screen.
//

import Foundation

struct DisplaySettingsState: Codable, Equatable {

    var preset: DisplayPreset

    var entitiesHomeOverride: EntitiesHomeDisplaySettings?
    var entityDetailOverride: EntityDetailDisplaySettings?
    var attributeDetailOverride: AttributeDetailDisplaySettings?
    var attributesAllListOverride: AttributesAllListDisplaySettings?

    static let `default` = DisplaySettingsState(
        preset: .clean,
        entitiesHomeOverride: nil,
        entityDetailOverride: nil,
        attributeDetailOverride: nil,
        attributesAllListOverride: nil
    )

    // MARK: - Resolved values (preset defaults + overrides)

    var entitiesHome: EntitiesHomeDisplaySettings {
        entitiesHomeOverride ?? EntitiesHomeDisplaySettings.preset(preset)
    }

    var entityDetail: EntityDetailDisplaySettings {
        entityDetailOverride ?? EntityDetailDisplaySettings.preset(preset)
    }

    var attributeDetail: AttributeDetailDisplaySettings {
        attributeDetailOverride ?? AttributeDetailDisplaySettings.preset(preset)
    }

    var attributesAllList: AttributesAllListDisplaySettings {
        attributesAllListOverride ?? AttributesAllListDisplaySettings.preset(preset)
    }

    // MARK: - Resets

    mutating func resetEntitiesHome() {
        entitiesHomeOverride = nil
    }

    mutating func resetEntityDetail() {
        entityDetailOverride = nil
    }

    mutating func resetAttributeDetail() {
        attributeDetailOverride = nil
    }

    mutating func resetAttributesAllList() {
        attributesAllListOverride = nil
    }

    mutating func resetAll() {
        resetEntitiesHome()
        resetEntityDetail()
        resetAttributeDetail()
        resetAttributesAllList()
    }

    // MARK: - Codable (forward compatible)

    private enum CodingKeys: String, CodingKey {
        case preset
        case entitiesHomeOverride
        case entityDetailOverride
        case attributeDetailOverride
        case attributesAllListOverride
    }

    init(
        preset: DisplayPreset,
        entitiesHomeOverride: EntitiesHomeDisplaySettings?,
        entityDetailOverride: EntityDetailDisplaySettings?,
        attributeDetailOverride: AttributeDetailDisplaySettings?,
        attributesAllListOverride: AttributesAllListDisplaySettings?
    ) {
        self.preset = preset
        self.entitiesHomeOverride = entitiesHomeOverride
        self.entityDetailOverride = entityDetailOverride
        self.attributeDetailOverride = attributeDetailOverride
        self.attributesAllListOverride = attributesAllListOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DisplaySettingsState.default

        self.preset = try container.decodeIfPresent(DisplayPreset.self, forKey: .preset) ?? fallback.preset

        self.entitiesHomeOverride = try container.decodeIfPresent(EntitiesHomeDisplaySettings.self, forKey: .entitiesHomeOverride)
        self.entityDetailOverride = try container.decodeIfPresent(EntityDetailDisplaySettings.self, forKey: .entityDetailOverride)
        self.attributeDetailOverride = try container.decodeIfPresent(AttributeDetailDisplaySettings.self, forKey: .attributeDetailOverride)
        self.attributesAllListOverride = try container.decodeIfPresent(AttributesAllListDisplaySettings.self, forKey: .attributesAllListOverride)
    }
}
