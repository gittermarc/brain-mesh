//
//  OnboardingActions.swift
//  BrainMesh
//

import SwiftUI

struct OnboardingActionsView: View {
    let isComplete: Bool
    @Binding var onboardingHidden: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isComplete {
                Label("Nice! Dein Graph lebt.", systemImage: "checkmark.seal")
                    .font(.headline)
            }

            Button {
                onboardingHidden = true
                onClose()
            } label: {
                Label("Onboarding nicht mehr automatisch anzeigen", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered)

            Text("Du findest das Onboarding jederzeit in Einstellungen → Hilfe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
