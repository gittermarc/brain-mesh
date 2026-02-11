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
                    Text("**Entität** = ein Ding in deinem Wissen: Person, Projekt, Begriff, Ort, Buch …")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Attribut** = ein Detail dazu: Rolle, Status, Datum, Tag, Kategorie …")
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
