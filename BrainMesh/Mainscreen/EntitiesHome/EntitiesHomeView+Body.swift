//
//  EntitiesHomeView+Body.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI

extension EntitiesHomeView {
    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Fehler").font(.headline)
                        Text(loadError)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Erneut versuchen") {
                            Task { await reload(forFolded: BMSearch.fold(searchText)) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if isLoading && rows.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Lade Entitäten…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else if rows.isEmpty {
                    if searchText.isEmpty {
                        ScrollView {
                            VStack(spacing: 16) {
                                ContentUnavailableView {
                                    Label("Noch keine Entitäten", systemImage: "cube.transparent")
                                } description: {
                                    Text("Lege deine ersten Entitäten an und gib ihnen Attribute. Danach wird dein Graph lebendig.")
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        showAddEntity = true
                                    } label: {
                                        Label("Entität anlegen", systemImage: "plus")
                                    }
                                    .buttonStyle(.borderedProminent)

                                    if !onboardingHidden {
                                        Button {
                                            onboarding.isPresented = true
                                        } label: {
                                            Label(onboardingCompleted ? "Onboarding" : "Onboarding starten", systemImage: onboardingCompleted ? "questionmark.circle" : "sparkles")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.top, 4)

                                if !onboardingHidden {
                                    OnboardingMiniExplainerView()
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 20)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Keine Treffer", systemImage: "magnifyingglass")
                        } description: {
                            Text("Deine Suche hat keine Entität oder kein Attribut gefunden.")
                        }
                    }
                } else {
                    if resolvedEntitiesHomeAppearance.layout == .grid {
                        EntitiesHomeGrid(
                            rows: rows,
                            isLoading: isLoading,
                            settings: resolvedEntitiesHomeAppearance,
                            display: displaySettings.entitiesHome,
                            onDelete: { id in
                                deleteEntityIDs([id])
                            }
                        )
                    } else {
                        EntitiesHomeList(
                            rows: rows,
                            isLoading: isLoading,
                            settings: resolvedEntitiesHomeAppearance,
                            display: displaySettings.entitiesHome,
                            onDelete: deleteEntities,
                            onDeleteID: { id in
                                deleteEntityIDs([id])
                            }
                        )
                    }
                }
            }
            .navigationTitle("Entitäten")
            .searchable(text: $searchText, prompt: "Entität, Attribut, Notiz suchen…")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            // On iPad mini in Portrait, toolbar space is tight and SwiftUI may drop trailing
                            // icon-only items. We switch to a compact, menu-based toolbar when the available
                            // width is below a safe threshold.
                            preferExpandedToolbarActions = proxy.size.width >= 820
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            preferExpandedToolbarActions = newSize.width >= 820
                        }
                }
            )
            .toolbar {
                EntitiesHomeToolbar(
                    activeGraphName: activeGraphName,
                    showGraphPicker: $showGraphPicker,
                    showViewOptions: $showViewOptions,
                    sortSelection: sortBinding,
                    showAddEntity: $showAddEntity,
                    preferExpandedActions: preferExpandedToolbarActions
                )
            }
            .sheet(isPresented: $showViewOptions) {
                EntitiesHomeDisplaySheet(isPresented: $showViewOptions)
            }
            .sheet(isPresented: $showAddEntity) {
                AddEntityView()
            }
            .sheet(isPresented: $showGraphPicker) {
                GraphPickerSheet()
            }
            .task(id: taskToken) {
                let folded = BMSearch.fold(searchText)
                isLoading = true
                loadError = nil

                // Debounce typing + fast graph switching
                try? await Task.sleep(nanoseconds: debounceNanos)
                if Task.isCancelled { return }

                await reload(forFolded: folded)
            }
            .onChange(of: entitiesHomeSortRaw) { _, _ in
                // Apply sorting instantly without waiting for a reload.
                rows = sortOption.apply(to: rows)
            }
            .onChange(of: showAddEntity) { _, newValue in
                // Ensure newly created entities show up even without @Query driving this list.
                if newValue == false {
                    Task {
                        await EntitiesHomeLoader.shared.invalidateCache(for: activeGraphID)
                        await reload(forFolded: BMSearch.fold(searchText))
                    }
                }
            }
        }
    }
}
