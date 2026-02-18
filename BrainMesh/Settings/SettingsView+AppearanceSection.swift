//
//  SettingsView+AppearanceSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var appearanceSection: some View {
        Section("Darstellung") {
            NavigationLink {
                DisplaySettingsView()
            } label: {
                Label("Darstellung", systemImage: "paintpalette")
            }
        }
    }
}
