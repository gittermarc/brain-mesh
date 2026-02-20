//
//  AppearanceModels+App.swift
//  BrainMesh
//
//  Split out from AppearanceModels.swift (PR 01).
//

import SwiftUI

// MARK: - App appearance

enum AppColorSchemePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppAppearanceSettings: Codable, Hashable {
    var tint: ColorRef
    var colorScheme: AppColorSchemePreference

    static let `default` = AppAppearanceSettings(
        tint: ColorRef(red: 0.00, green: 0.48, blue: 1.00, alpha: 1.0),
        colorScheme: .system
    )
}
