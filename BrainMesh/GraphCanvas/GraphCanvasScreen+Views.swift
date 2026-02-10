//
//  GraphCanvasScreen+Views.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Views

    func errorView(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Fehler").font(.headline)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await loadGraph() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    var emptyView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("Dein Graph ist noch leer", systemImage: "circle.grid.cross")
                } description: {
                    Text("Starte mit 1–2 Entitäten, gib ihnen Attribute und verknüpfe sie. Danach macht der Graph richtig Spaß.")
                }

                HStack(spacing: 12) {
                    Button {
                        onboarding.isPresented = true
                    } label: {
                        Label(onboardingCompleted ? "Onboarding ansehen" : "Onboarding starten", systemImage: onboardingCompleted ? "questionmark.circle" : "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(onboardingHidden)
                }

                if !onboardingHidden {
                    OnboardingMiniExplainerView()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
        }
    }


}
