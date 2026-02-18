//
//  SettingsView+HelpSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var helpSection: some View {
        Section("Hilfe") {
            Button {
                onboarding.isPresented = true
            } label: {
                Label("Onboarding anzeigen", systemImage: "questionmark.circle")
            }
        }
    }
}
