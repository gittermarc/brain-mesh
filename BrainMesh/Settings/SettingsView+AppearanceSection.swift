//
//  SettingsView+AppearanceSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var displayCard: some View {
        NavigationLink {
            DisplaySettingsView()
        } label: {
            SettingsHubCardRow(
                systemImage: "paintpalette",
                title: "Darstellung",
                subtitle: "Look, Presets & Performance"
            )
        }
        .settingsHubCardStyle(showsAccessoryChevron: false)
    }
}
