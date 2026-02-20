//
//  OnboardingMiniExplainerView.swift
//  BrainMesh
//

import SwiftUI

/// Mini explainer used in empty states and in the onboarding sheet.
struct OnboardingMiniExplainerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Was ist was?", systemImage: "sparkles")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cube")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Entität** = Kategorie/Sammlung: Bücher, Projekte, Personen …")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Attribut (Eintrag)** = ein konkretes Ding in der Entität: Dune, Claudia, Apollo 11 …")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Details** = frei definierbare Felder pro Entität (z.B. Jahr, Status) + Werte pro Eintrag")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Link** = Beziehung zwischen zwei Nodes: *arbeitet an*, *liegt in*, *gehört zu* …")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }
}
