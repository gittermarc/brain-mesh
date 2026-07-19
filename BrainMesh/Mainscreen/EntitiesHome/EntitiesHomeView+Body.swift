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
            content
                .navigationTitle("Entitäten")
                .searchable(text: $searchText, prompt: "Entität, Attribut, Notiz suchen")
                .background(toolbarWidthProbe)
                .toolbar {
                    EntitiesHomeToolbar(
                        activeGraphName: activeGraphName,
                        showGraphPicker: $showGraphPicker,
                        showViewOptions: $showViewOptions,
                        sortSelection: sortBinding,
                        showAddEntity: $showAddEntity,
                        preferExpandedActions: preferExpandedToolbarActions,
                        openCommandCenter: { commandCenter.present() }
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
                .task(id: cockpitTaskToken) {
                    await loadCockpitIfNeeded()
                }
                .onChange(of: entitiesHomeSortRaw) { _, _ in
                    // Apply sorting instantly without waiting for a reload.
                    rows = sortOption.apply(to: rows)
                }
                .onChange(of: searchText) { _, newValue in
                    if BMSearch.fold(newValue).isEmpty == false {
                        selectedQuickFilter = .all
                    }
                }
                .onChange(of: activeGraphIDString) { _, _ in
                    if entitiesHomeRouting.pendingQuickFilterRoute == nil {
                        selectedQuickFilter = .all
                    }
                }
                .onChange(of: entitiesHomeRouting.pendingQuickFilterRoute?.id) { _, _ in
                    applyPendingQuickFilterRoute()
                }
                .onAppear {
                    applyPendingQuickFilterRoute()
                }
                .onChange(of: showAddEntity) { _, newValue in
                    // Ensure newly created entities show up even without @Query driving this list.
                    if newValue == false {
                        Task {
                            await EntitiesHomeLoader.shared.invalidateCache(for: activeGraphID)
                            await reload(forFolded: BMSearch.fold(searchText))
                            await loadCockpitIfNeeded()
                        }
                    }
                }
                .alert("BrainMesh", isPresented: Binding(
                    get: { deletionErrorMessage != nil },
                    set: { if !$0 { deletionErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deletionErrorMessage ?? "")
                }
        }
    }

    @ViewBuilder private var content: some View {
        if let loadError {
            loadErrorView(loadError)
        } else if isLoading && rows.isEmpty {
            loadingView
        } else if rows.isEmpty {
            emptyRowsView
        } else if shouldShowQuickFilterEmptyState {
            quickFilterEmptyContent
        } else {
            rowsContent
        }
    }

    private var toolbarWidthProbe: some View {
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
    }

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Fehler").font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") {
                Task { await reload(forFolded: BMSearch.fold(searchText)) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Lade Entitäten")
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder private var emptyRowsView: some View {
        if searchText.isEmpty {
            EntitiesHomeCockpitEmptyState(
                hasGraphs: graphs.isEmpty == false,
                showsOnboardingAction: !onboardingHidden,
                onboardingTitle: onboardingCompleted ? "Onboarding" : "Onboarding starten",
                onAddEntity: { showAddEntity = true },
                onOpenGraphPicker: { showGraphPicker = true },
                onOpenOnboarding: { onboarding.isPresented = true },
                onOpenCommandCenter: { commandCenter.present() },
                onOpenGuide: {
                    Task { @MainActor in
                        commandCenter.presentDestination(.guide)
                    }
                }
            )
        } else {
            EntitiesHomeSearchEmptyStateView(
                searchText: searchText,
                onOpenCommandCenter: { query in
                    commandCenter.present(initialQuery: query)
                }
            )
        }
    }

    private var quickFilterEmptyContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let cockpitHeader {
                    cockpitHeader
                }

                EntitiesHomeQuickFilterEmptyStateView(
                    filter: effectiveQuickFilter,
                    onReset: { selectedQuickFilter = .all }
                )
            }
        }
    }

    @ViewBuilder private var rowsContent: some View {
        if resolvedEntitiesHomeAppearance.layout == .grid {
            EntitiesHomeGrid(
                rows: visibleRows,
                isLoading: isLoading,
                settings: resolvedEntitiesHomeAppearance,
                display: displaySettings.entitiesHome,
                header: cockpitHeader,
                onDelete: { id in
                    deleteEntityIDs([id])
                }
            )
        } else {
            EntitiesHomeList(
                rows: visibleRows,
                isLoading: isLoading,
                settings: resolvedEntitiesHomeAppearance,
                display: displaySettings.entitiesHome,
                header: cockpitHeader,
                onDelete: { offsets in
                    deleteEntities(at: offsets, from: visibleRows)
                },
                onDeleteID: { id in
                    deleteEntityIDs([id])
                }
            )
        }
    }

    private var cockpitHeader: AnyView? {
        guard shouldShowCockpit else { return nil }
        return AnyView(
            EntitiesHomeCockpitView(
                activeGraphName: activeGraphName,
                snapshot: cockpitSnapshot,
                isLoading: isCockpitLoading,
                errorMessage: cockpitErrorMessage,
                selectedFilter: effectiveQuickFilter,
                onSelectFilter: { filter in
                    selectedQuickFilter = filter
                },
                onOpenRecent: openRecentNode,
                onJumpRecentToGraph: jumpRecentNodeToGraph,
                onOpenStats: {
                    Task { @MainActor in
                        tabRouter.select(.stats)
                    }
                }
            )
        )
    }



    @MainActor
    private func applyPendingQuickFilterRoute() {
        guard let route = entitiesHomeRouting.pendingQuickFilterRoute else { return }

        if let graphID = route.graphID, activeGraphIDString != graphID.uuidString {
            activeGraphIDString = graphID.uuidString
        }

        searchText = ""
        selectedQuickFilter = route.filter
        _ = entitiesHomeRouting.consumeQuickFilterRoute(id: route.id)
    }

    private func openRecentNode(_ item: EntitiesHomeCockpitRecentNode) {
        guard let nodeKind = item.nodeKind else { return }
        Task { @MainActor in
            commandCenter.presentDestination(.nodeDetail(kind: nodeKind, id: item.nodeID))
        }
    }

    private func jumpRecentNodeToGraph(_ item: EntitiesHomeCockpitRecentNode) {
        guard let graphID = item.graphID, let nodeKey = item.nodeKey else { return }
        Task { @MainActor in
            graphJump.requestJump(to: nodeKey, in: graphID, centerOnArrival: true)
            tabRouter.select(.graph)
        }
    }
}
