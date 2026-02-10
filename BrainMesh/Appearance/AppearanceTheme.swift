//
//  AppearanceTheme.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct GraphTheme: Hashable {
    let backgroundStyle: GraphBackgroundStyle
    let backgroundPrimary: Color
    let backgroundSecondary: Color

    let entityColor: Color
    let attributeColor: Color

    let linkColor: Color
    let containmentColor: Color

    let highlightColor: Color

    let labelHaloEnabled: Bool

    init(settings: GraphAppearanceSettings) {
        self.backgroundStyle = settings.backgroundStyle
        self.backgroundPrimary = settings.backgroundPrimary.color
        self.backgroundSecondary = settings.backgroundSecondary.color
        self.entityColor = settings.entityColor.color
        self.attributeColor = settings.attributeColor.color
        self.linkColor = settings.linkColor.color
        self.containmentColor = settings.containmentColor.color
        self.highlightColor = settings.highlightColor.color
        self.labelHaloEnabled = settings.labelHaloEnabled
    }
}

extension GraphBackgroundStyle {
    var needsPrimaryColor: Bool {
        switch self {
        case .system: return false
        case .solid: return true
        case .gradient: return true
        case .grid: return true
        }
    }

    var needsSecondaryColor: Bool {
        switch self {
        case .gradient: return true
        default: return false
        }
    }
}
