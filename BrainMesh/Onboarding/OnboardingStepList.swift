//
//  OnboardingStepList.swift
//  BrainMesh
//

import SwiftUI

struct OnboardingStepListView: View {
    let progress: OnboardingProgress
    let onAddEntity: () -> Void
    let onPickEntityForAttribute: () -> Void
    let onPickEntityForLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Die 3 Schritte")
                .font(.headline)

            OnboardingStepCardView(
                number: 1,
                title: "Erste Entität anlegen",
                subtitle: "Zum Beispiel: \"Bücher\", \"Projekte\" oder \"Personen\"",
                systemImage: "plus.circle",
                isDone: progress.hasEntity,
                actionTitle: "Entität anlegen",
                actionEnabled: true,
                disabledHint: "",
                isOptional: false,
                action: onAddEntity
            )

            OnboardingStepCardView(
                number: 2,
                title: "Ersten Eintrag hinzufügen",
                subtitle: "Zum Beispiel: \"Dune\", \"Apollo 11\" oder \"Claudia\"",
                systemImage: "tag.circle",
                isDone: progress.hasAttribute,
                actionTitle: "Eintrag hinzufügen",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: false,
                action: onPickEntityForAttribute
            )

            OnboardingStepCardView(
                number: 3,
                title: "Link erstellen",
                subtitle: "Verbinde zwei Nodes (optional mit Notiz)",
                systemImage: "arrow.triangle.branch.circle",
                isDone: progress.hasLink,
                actionTitle: "Link erstellen",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: false,
                action: onPickEntityForLink
            )

            if !progress.hasEntity {
                Text("Tipp: Leg zuerst 2 Entitäten an, dann kannst du direkt einen Link zwischen ihnen bauen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct OnboardingDetailsTurboView: View {
    let progress: OnboardingProgress
    let hasAnyDetailFields: Bool
    let hasAnyDetailValues: Bool
    let onPickEntityForSchema: () -> Void
    let onPickAttributeForValue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turbo: Details")
                .font(.headline)

            Text("Details sind frei definierbare Felder pro Entität (z.B. Jahr, Status). Du kannst sie später für Sortierung, Filter und Überblick nutzen.")
                .font(.callout)
                .foregroundStyle(.secondary)

            OnboardingStepCardView(
                number: nil,
                title: "Details-Felder definieren",
                subtitle: "Pro Entität, z.B. Jahr, Status, Rolle",
                systemImage: "list.bullet.rectangle",
                isDone: hasAnyDetailFields,
                actionTitle: "Felder konfigurieren",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: true,
                action: onPickEntityForSchema
            )

            OnboardingStepCardView(
                number: nil,
                title: "Ersten Wert setzen",
                subtitle: "Zum Beispiel: Jahr=1965 bei \"Dune\"",
                systemImage: "pencil.and.list.clipboard",
                isDone: hasAnyDetailValues,
                actionTitle: "Wert setzen",
                actionEnabled: progress.hasAttribute && hasAnyDetailFields,
                disabledHint: progress.hasAttribute ? "Lege zuerst Details-Felder an." : "Dafür brauchst du zuerst einen Eintrag (Attribut).",
                isOptional: true,
                action: onPickAttributeForValue
            )
        }
    }
}

struct OnboardingRecipesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rezepte")
                .font(.headline)

            OnboardingRecipeCard(
                title: "Rezept: Bücher",
                lines: [
                    "Entität: **Bücher**",
                    "Eintrag: **Dune**",
                    "Details: Jahr=1965, Status=Gelesen (optional)",
                    "Link: Dune —(Autor)—> Frank Herbert"
                ]
            )

            OnboardingRecipeCard(
                title: "Rezept: Projekte",
                lines: [
                    "Entität: **Projekte**",
                    "Eintrag: **BrainMesh Onboarding**",
                    "Details: Status=In Arbeit, Deadline=… (optional)",
                    "Link: BrainMesh Onboarding —(gehört zu)—> BrainMesh"
                ]
            )
        }
    }
}

private struct OnboardingRecipeCard: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tint)
                            .padding(.top, 1)
                        Text(.init(line))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }
}

// MARK: - Simple Flow Chips

private struct FlowChipsView: View {
    let chips: [(systemImage: String, title: String)]

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.title)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.quaternary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
