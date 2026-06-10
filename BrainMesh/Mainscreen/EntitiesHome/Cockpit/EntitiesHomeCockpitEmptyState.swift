//
//  EntitiesHomeCockpitEmptyState.swift
//  BrainMesh
//
//  Empty states used by the Entities Home Cockpit integration.
//

import SwiftUI

struct EntitiesHomeCockpitEmptyState: View {
    let hasGraphs: Bool
    let showsOnboardingAction: Bool
    let onboardingTitle: String
    let onAddEntity: () -> Void
    let onOpenGraphPicker: () -> Void
    let onOpenOnboarding: () -> Void
    let onOpenCommandCenter: () -> Void
    let onOpenGuide: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label(hasGraphs ? "Noch keine Entitäten" : "Noch kein Graph", systemImage: hasGraphs ? "cube.transparent" : "square.stack.3d.up")
                } description: {
                    Text(hasGraphs ? "Lege deine ersten Entitäten an und gib ihnen Attribute. Danach wird dein Graph lebendig." : "Wähle oder erstelle zuerst einen Graph. Danach kannst du Entitäten, Attribute und Links aufbauen.")
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    if hasGraphs {
                        Button {
                            onAddEntity()
                        } label: {
                            Label("Entität anlegen", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            onOpenGraphPicker()
                        } label: {
                            Label("Graph auswählen", systemImage: "square.stack.3d.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        onOpenCommandCenter()
                    } label: {
                        Label("Command Center", systemImage: "command.circle")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    if showsOnboardingAction {
                        Button {
                            onOpenOnboarding()
                        } label: {
                            Label(onboardingTitle, systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        onOpenGuide()
                    } label: {
                        Label("Anleitung", systemImage: "book")
                    }
                    .buttonStyle(.bordered)
                }

                if hasGraphs && showsOnboardingAction {
                    OnboardingMiniExplainerView()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
        }
    }
}

struct EntitiesHomeQuickFilterEmptyStateView: View {
    let filter: EntitiesHomeQuickFilter
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label("Keine Treffer", systemImage: filter.systemImage)
            } description: {
                Text("Der aktive Quick Filter „\(filter.title)“ findet in der aktuellen Entitätenliste keine passenden Einträge.")
                    .multilineTextAlignment(.center)
            }

            Button {
                onReset()
            } label: {
                Label("Filter zurücksetzen", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
