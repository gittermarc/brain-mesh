//
//  SettingsView+AppearanceSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var displayTile: some View {
        NavigationLink {
            DisplaySettingsView()
        } label: {
            SettingsHubTile(
                systemImage: "paintpalette",
                title: "Darstellung",
                subtitle: "Look, Presets & Performance",
                showsAccessoryIndicator: false
            )
        }
        .buttonStyle(SettingsHubTileButtonStyle())
    }
}
