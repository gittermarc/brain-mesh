//
//  AppearanceStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppearanceStore: ObservableObject {

    static let sharedKey = "BMAppearanceSettingsV1"

    @Published private(set) var settings: AppearanceSettings

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = AppearanceStore.load(from: userDefaults)
    }

    // MARK: - Public derived values

    var appTintColor: Color {
        settings.app.tint.color
    }

    var preferredColorScheme: ColorScheme? {
        settings.app.colorScheme.preferredColorScheme
    }

    // MARK: - Mutations

    func setTint(_ color: Color) {
        settings.app.tint = ColorRef(color)
        persist()
    }

    func setColorScheme(_ scheme: AppColorSchemePreference) {
        settings.app.colorScheme = scheme
        persist()
    }

    func setGraphBackgroundStyle(_ style: GraphBackgroundStyle) {
        settings.graph.backgroundStyle = style
        persist()
    }

    func setGraphBackgroundPrimary(_ color: Color) {
        settings.graph.backgroundPrimary = ColorRef(color)
        persist()
    }

    func setGraphBackgroundSecondary(_ color: Color) {
        settings.graph.backgroundSecondary = ColorRef(color)
        persist()
    }

    func setEntityColor(_ color: Color) {
        settings.graph.entityColor = ColorRef(color)
        persist()
    }

    func setAttributeColor(_ color: Color) {
        settings.graph.attributeColor = ColorRef(color)
        persist()
    }

    func setLinkColor(_ color: Color) {
        settings.graph.linkColor = ColorRef(color)
        persist()
    }

    func setContainmentColor(_ color: Color) {
        settings.graph.containmentColor = ColorRef(color)
        persist()
    }

    func setHighlightColor(_ color: Color) {
        settings.graph.highlightColor = ColorRef(color)
        persist()
    }

    func setLabelHaloEnabled(_ enabled: Bool) {
        settings.graph.labelHaloEnabled = enabled
        persist()
    }

    func applyPreset(_ preset: AppearancePreset) {
        settings = preset.makeSettings()
        persist()
    }

    func resetToDefaults() {
        settings = .default
        persist()
    }

    // MARK: - Private

    private let userDefaults: UserDefaults

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: AppearanceStore.sharedKey)
        } catch {
            print("⚠️ AppearanceStore: Could not encode settings: \(error)")
        }
    }

    private static func load(from userDefaults: UserDefaults) -> AppearanceSettings {
        guard let data = userDefaults.data(forKey: AppearanceStore.sharedKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(AppearanceSettings.self, from: data)
        } catch {
            print("⚠️ AppearanceStore: Could not decode settings, using defaults: \(error)")
            return .default
        }
    }
}
