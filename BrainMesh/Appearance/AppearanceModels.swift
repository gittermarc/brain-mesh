//
//  AppearanceModels.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import UIKit

// MARK: - ColorRef

/// Persistable color representation (sRGB RGBA, 0...1).
struct ColorRef: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = ColorRef.clamp01(red)
        self.green = ColorRef.clamp01(green)
        self.blue = ColorRef.clamp01(blue)
        self.alpha = ColorRef.clamp01(alpha)
    }

    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        } else {
            // Fallback: try CGColor components (can be grayscale).
            let comps = ui.cgColor.components ?? [0, 0, 0, 1]
            if comps.count >= 4 {
                self.init(red: Double(comps[0]), green: Double(comps[1]), blue: Double(comps[2]), alpha: Double(comps[3]))
            } else if comps.count == 2 {
                self.init(red: Double(comps[0]), green: Double(comps[0]), blue: Double(comps[0]), alpha: Double(comps[1]))
            } else {
                self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            }
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexRGBA: String {
        let r = Int((red * 255.0).rounded())
        let g = Int((green * 255.0).rounded())
        let b = Int((blue * 255.0).rounded())
        let a = Int((alpha * 255.0).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    private static func clamp01(_ v: Double) -> Double {
        min(1.0, max(0.0, v))
    }
}

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

// MARK: - Graph appearance

enum GraphBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case system
    case solid
    case gradient
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .solid: return "Einfarbig"
        case .gradient: return "Verlauf"
        case .grid: return "Grid"
        }
    }
}

struct GraphAppearanceSettings: Codable, Hashable {
    var backgroundStyle: GraphBackgroundStyle
    var backgroundPrimary: ColorRef
    var backgroundSecondary: ColorRef

    var entityColor: ColorRef
    var attributeColor: ColorRef

    var linkColor: ColorRef
    var containmentColor: ColorRef

    var highlightColor: ColorRef

    var labelHaloEnabled: Bool

    static let `default` = GraphAppearanceSettings(
        backgroundStyle: .system,
        backgroundPrimary: ColorRef(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0),
        backgroundSecondary: ColorRef(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0),
        entityColor: ColorRef(red: 0.22, green: 0.52, blue: 0.96, alpha: 1.0),
        attributeColor: ColorRef(red: 0.15, green: 0.75, blue: 0.56, alpha: 1.0),
        linkColor: ColorRef(red: 0.75, green: 0.78, blue: 0.82, alpha: 1.0),
        containmentColor: ColorRef(red: 0.75, green: 0.78, blue: 0.82, alpha: 0.55),
        highlightColor: ColorRef(red: 1.00, green: 0.80, blue: 0.20, alpha: 1.0),
        labelHaloEnabled: true
    )
}

// MARK: - Combined settings

struct AppearanceSettings: Codable, Hashable {
    var app: AppAppearanceSettings
    var graph: GraphAppearanceSettings

    static let `default` = AppearanceSettings(app: .default, graph: .default)
}

// MARK: - Presets

enum AppearancePreset: String, CaseIterable, Identifiable {
    case classic
    case midnight
    case paper
    case neon
    case ocean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .paper: return "Paper"
        case .neon: return "Neon"
        case .ocean: return "Ocean"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Neutral & klar"
        case .midnight: return "Dunkel & kontrastreich"
        case .paper: return "Hell & ruhig"
        case .neon: return "Cyber & knallig"
        case .ocean: return "Kühl & modern"
        }
    }

    func makeSettings() -> AppearanceSettings {
        switch self {
        case .classic:
            return .default

        case .midnight:
            return AppearanceSettings(
                app: AppAppearanceSettings(
                    tint: ColorRef(red: 0.62, green: 0.72, blue: 1.00, alpha: 1.0),
                    colorScheme: .dark
                ),
                graph: GraphAppearanceSettings(
                    backgroundStyle: .gradient,
                    backgroundPrimary: ColorRef(red: 0.05, green: 0.06, blue: 0.09, alpha: 1.0),
                    backgroundSecondary: ColorRef(red: 0.12, green: 0.08, blue: 0.18, alpha: 1.0),
                    entityColor: ColorRef(red: 0.35, green: 0.70, blue: 1.00, alpha: 1.0),
                    attributeColor: ColorRef(red: 0.38, green: 0.95, blue: 0.70, alpha: 1.0),
                    linkColor: ColorRef(red: 0.78, green: 0.80, blue: 0.86, alpha: 0.90),
                    containmentColor: ColorRef(red: 0.78, green: 0.80, blue: 0.86, alpha: 0.55),
                    highlightColor: ColorRef(red: 1.00, green: 0.77, blue: 0.22, alpha: 1.0),
                    labelHaloEnabled: true
                )
            )

        case .paper:
            return AppearanceSettings(
                app: AppAppearanceSettings(
                    tint: ColorRef(red: 0.20, green: 0.48, blue: 0.95, alpha: 1.0),
                    colorScheme: .light
                ),
                graph: GraphAppearanceSettings(
                    backgroundStyle: .grid,
                    backgroundPrimary: ColorRef(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0),
                    backgroundSecondary: ColorRef(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0),
                    entityColor: ColorRef(red: 0.18, green: 0.45, blue: 0.90, alpha: 1.0),
                    attributeColor: ColorRef(red: 0.10, green: 0.65, blue: 0.48, alpha: 1.0),
                    linkColor: ColorRef(red: 0.25, green: 0.26, blue: 0.30, alpha: 0.35),
                    containmentColor: ColorRef(red: 0.25, green: 0.26, blue: 0.30, alpha: 0.18),
                    highlightColor: ColorRef(red: 0.95, green: 0.55, blue: 0.18, alpha: 1.0),
                    labelHaloEnabled: false
                )
            )

        case .neon:
            return AppearanceSettings(
                app: AppAppearanceSettings(
                    tint: ColorRef(red: 0.98, green: 0.22, blue: 0.74, alpha: 1.0),
                    colorScheme: .dark
                ),
                graph: GraphAppearanceSettings(
                    backgroundStyle: .gradient,
                    backgroundPrimary: ColorRef(red: 0.03, green: 0.03, blue: 0.06, alpha: 1.0),
                    backgroundSecondary: ColorRef(red: 0.02, green: 0.08, blue: 0.14, alpha: 1.0),
                    entityColor: ColorRef(red: 0.20, green: 0.95, blue: 0.95, alpha: 1.0),
                    attributeColor: ColorRef(red: 0.98, green: 0.22, blue: 0.74, alpha: 1.0),
                    linkColor: ColorRef(red: 0.74, green: 0.80, blue: 0.98, alpha: 0.65),
                    containmentColor: ColorRef(red: 0.74, green: 0.80, blue: 0.98, alpha: 0.35),
                    highlightColor: ColorRef(red: 1.00, green: 0.93, blue: 0.25, alpha: 1.0),
                    labelHaloEnabled: true
                )
            )

        case .ocean:
            return AppearanceSettings(
                app: AppAppearanceSettings(
                    tint: ColorRef(red: 0.10, green: 0.72, blue: 0.85, alpha: 1.0),
                    colorScheme: .system
                ),
                graph: GraphAppearanceSettings(
                    backgroundStyle: .gradient,
                    backgroundPrimary: ColorRef(red: 0.02, green: 0.08, blue: 0.10, alpha: 1.0),
                    backgroundSecondary: ColorRef(red: 0.05, green: 0.18, blue: 0.24, alpha: 1.0),
                    entityColor: ColorRef(red: 0.10, green: 0.72, blue: 0.85, alpha: 1.0),
                    attributeColor: ColorRef(red: 0.18, green: 0.88, blue: 0.65, alpha: 1.0),
                    linkColor: ColorRef(red: 0.82, green: 0.90, blue: 0.96, alpha: 0.55),
                    containmentColor: ColorRef(red: 0.82, green: 0.90, blue: 0.96, alpha: 0.28),
                    highlightColor: ColorRef(red: 1.00, green: 0.80, blue: 0.22, alpha: 1.0),
                    labelHaloEnabled: true
                )
            )
        }
    }
}
