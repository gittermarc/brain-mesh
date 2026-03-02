//
//  HelpSupportView+HelpSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension HelpSupportView {
    var helpSection: some View {
        Section("Hilfe") {
            Button {
                onboarding.isPresented = true
            } label: {
                Label("Onboarding anzeigen", systemImage: "questionmark.circle")
            }

            Button {
                sheet = .detailsIntro
            } label: {
                Label("Neu: Details-Felder", systemImage: "sparkles")
            }
        }
    }
}
