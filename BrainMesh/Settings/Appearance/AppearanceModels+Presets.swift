//
//  AppearanceModels+Presets.swift
//  BrainMesh
//
//  Split out from AppearanceModels.swift (PR 01).
//

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
