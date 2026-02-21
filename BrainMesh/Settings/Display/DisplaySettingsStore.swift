//
//  DisplaySettingsStore.swift
//  BrainMesh
//
//  PR 02: Persistence + mutation API for DisplaySettingsState.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class DisplaySettingsStore: ObservableObject {

    static let sharedKey = BMAppStorageKeys.displaySettingsV1

    @Published private(set) var state: DisplaySettingsState

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.state = DisplaySettingsStore.load(from: userDefaults)

        migrateLegacyAttributesAllAppStorageIfNeeded()
        migrateLegacyEntitiesHomeAppearanceIfNeeded()
    }

    // MARK: - Resolved values

    var preset: DisplayPreset { state.preset }

    var entitiesHome: EntitiesHomeDisplaySettings { state.entitiesHome }
    var entityDetail: EntityDetailDisplaySettings { state.entityDetail }
    var attributeDetail: AttributeDetailDisplaySettings { state.attributeDetail }
    var attributesAllList: AttributesAllListDisplaySettings { state.attributesAllList }

    // MARK: - Preset

    func setPreset(_ preset: DisplayPreset) {
        state.preset = preset
        persist()
    }

    // MARK: - Updates (create/replace overrides)

    func updateEntitiesHome(_ mutate: (inout EntitiesHomeDisplaySettings) -> Void) {
        var next = state.entitiesHome
        mutate(&next)
        state.entitiesHomeOverride = next
        persist()
    }

    func updateEntityDetail(_ mutate: (inout EntityDetailDisplaySettings) -> Void) {
        var next = state.entityDetail
        mutate(&next)
        state.entityDetailOverride = next
        persist()
    }

    func updateAttributeDetail(_ mutate: (inout AttributeDetailDisplaySettings) -> Void) {
        var next = state.attributeDetail
        mutate(&next)
        state.attributeDetailOverride = next
        persist()
    }

    func updateAttributesAllList(_ mutate: (inout AttributesAllListDisplaySettings) -> Void) {
        var next = state.attributesAllList
        mutate(&next)
        state.attributesAllListOverride = next
        persist()
    }

    // MARK: - Resets

    func resetEntitiesHome() {
        state.resetEntitiesHome()
        persist()
    }

    func resetEntityDetail() {
        state.resetEntityDetail()
        persist()
    }

    func resetAttributeDetail() {
        state.resetAttributeDetail()
        persist()
    }

    func resetAttributesAllList() {
        state.resetAttributesAllList()
        persist()
    }

    func resetAll() {
        state.resetAll()
        persist()
    }

    // MARK: - Binding helpers (used by Settings UI in PR 03+)

    var presetBinding: Binding<DisplayPreset> {
        Binding(
            get: { [weak self] in self?.state.preset ?? .clean },
            set: { [weak self] newValue in self?.setPreset(newValue) }
        )
    }

    func entitiesHomeBinding<T>(_ keyPath: WritableKeyPath<EntitiesHomeDisplaySettings, T>) -> Binding<T> {
        Binding(
            get: { [weak self] in
                guard let self else { return EntitiesHomeDisplaySettings.default[keyPath: keyPath] }
                return self.entitiesHome[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.updateEntitiesHome { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    func entityDetailBinding<T>(_ keyPath: WritableKeyPath<EntityDetailDisplaySettings, T>) -> Binding<T> {
        Binding(
            get: { [weak self] in
                guard let self else { return EntityDetailDisplaySettings.default[keyPath: keyPath] }
                return self.entityDetail[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.updateEntityDetail { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    func attributeDetailBinding<T>(_ keyPath: WritableKeyPath<AttributeDetailDisplaySettings, T>) -> Binding<T> {
        Binding(
            get: { [weak self] in
                guard let self else { return AttributeDetailDisplaySettings.default[keyPath: keyPath] }
                return self.attributeDetail[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.updateAttributeDetail { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    func attributesAllListBinding<T>(_ keyPath: WritableKeyPath<AttributesAllListDisplaySettings, T>) -> Binding<T> {
        Binding(
            get: { [weak self] in
                guard let self else { return AttributesAllListDisplaySettings.default[keyPath: keyPath] }
                return self.attributesAllList[keyPath: keyPath]
            },
            set: { [weak self] newValue in
                self?.updateAttributesAllList { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    // MARK: - Private

    private let userDefaults: UserDefaults

    private func migrateLegacyAttributesAllAppStorageIfNeeded() {
        let migratedKey = BMAppStorageKeys.displaySettingsMigratedAttributesAllV1
        guard userDefaults.bool(forKey: migratedKey) == false else { return }

        // If the user already customized this screen via DisplaySettings, do not override.
        guard state.attributesAllListOverride == nil else {
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        let legacyPinnedObject = userDefaults.object(forKey: BMAppStorageKeys.entityAttributesAllShowPinnedDetails)
        let legacyNotesObject = userDefaults.object(forKey: BMAppStorageKeys.entityAttributesAllShowNotesPreview)

        guard legacyPinnedObject != nil || legacyNotesObject != nil else {
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        let legacyShowPinned = userDefaults.bool(forKey: BMAppStorageKeys.entityAttributesAllShowPinnedDetails)
        let legacyShowNotes = userDefaults.bool(forKey: BMAppStorageKeys.entityAttributesAllShowNotesPreview)

        var next = state.attributesAllList
        next.showPinnedDetails = legacyShowPinned
        if legacyShowNotes {
            // Old setting was boolean. Map to a sensible default.
            next.notesPreviewLines = max(next.notesPreviewLines, 1)
        } else {
            next.notesPreviewLines = 0
        }

        state.attributesAllListOverride = next
        persist()
        userDefaults.set(true, forKey: migratedKey)
    }


    private func migrateLegacyEntitiesHomeAppearanceIfNeeded() {
        let migratedKey = BMAppStorageKeys.displaySettingsMigratedEntitiesHomeFromAppearanceV1
        guard userDefaults.bool(forKey: migratedKey) == false else { return }

        // If the user already customized this screen via DisplaySettings, do not override.
        guard state.entitiesHomeOverride == nil else {
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        guard let data = userDefaults.data(forKey: BMAppStorageKeys.appearanceSettingsV1) else {
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        let appearance: AppearanceSettings
        do {
            appearance = try JSONDecoder().decode(AppearanceSettings.self, from: data)
        } catch {
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        let legacy = appearance.entitiesHome
        let def = EntitiesHomeAppearanceSettings.default

        let hasAnyCustomizations =
            legacy.layout != def.layout ||
            legacy.density != def.density ||
            legacy.showAttributeCount != def.showAttributeCount ||
            legacy.showLinkCount != def.showLinkCount ||
            legacy.showNotesPreview != def.showNotesPreview ||
            legacy.preferThumbnailOverIcon != def.preferThumbnailOverIcon

        guard hasAnyCustomizations else {
            userDefaults.set(true, forKey: migratedKey)
            return
        }

        var next = state.entitiesHome
        next.layout = (legacy.layout == .grid) ? .grid : .list
        next.density = mapLegacyEntitiesHomeDensity(legacy.density)
        next.showAttributeCount = legacy.showAttributeCount
        next.showLinkCount = legacy.showLinkCount
        next.showNotesPreview = legacy.showNotesPreview
        next.preferThumbnailOverIcon = legacy.preferThumbnailOverIcon

        state.entitiesHomeOverride = next
        persist()
        userDefaults.set(true, forKey: migratedKey)
    }

    private func mapLegacyEntitiesHomeDensity(_ density: EntitiesHomeDensity) -> EntitiesHomeRowDensity {
        switch density {
        case .compact:
            return .compact
        case .normal:
            return .standard
        case .cozy:
            return .comfortable
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: DisplaySettingsStore.sharedKey)
        } catch {
            print("⚠️ DisplaySettingsStore: Could not encode settings: \(error)")
        }
    }

    private static func load(from userDefaults: UserDefaults) -> DisplaySettingsState {
        guard let data = userDefaults.data(forKey: DisplaySettingsStore.sharedKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(DisplaySettingsState.self, from: data)
        } catch {
            print("⚠️ DisplaySettingsStore: Could not decode settings, using defaults: \(error)")
            return .default
        }
    }
}
