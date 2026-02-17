//
//  GraphStatsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 18.12.25.
//

import Foundation
import SwiftUI
import SwiftData

/// Dashboard-style stats screen for graphs.
///
/// NOTE: This file intentionally only contains the host/state + loading orchestration.
/// UI sections are split into separate files (GraphStatsView+*.swift) to keep compile
/// times stable and responsibilities small.
struct GraphStatsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showSettings = false

    // These states are read by section extensions in other files, therefore they cannot be `private`.
    @State var total: GraphCounts? = nil
    @State var perGraph: [UUID?: GraphCounts] = [:]
    @State var activeMedia: GraphMediaSnapshot? = nil
    @State var activeStructure: GraphStructureSnapshot? = nil
    @State var activeTrends: GraphTrendsSnapshot? = nil
    @State var dashboardGraphID: UUID? = nil
    @State var loadError: String? = nil
    @State var loadTask: Task<Void, Never>? = nil

    @State var showPerGraph = false

    // ✅ Dedupe by UUID (falls Cloud/Bootstrap doppelt geliefert hat)
    var uniqueGraphs: [MetaGraph] {
        var seen = Set<UUID>()
        return graphs.filter { seen.insert($0.id).inserted }
    }

    var dashboardGraph: MetaGraph? {
        if let gid = dashboardGraphID {
            return uniqueGraphs.first(where: { $0.id == gid })
        }
        if let gid = activeGraphID {
            return uniqueGraphs.first(where: { $0.id == gid })
        }
        return uniqueGraphs.first
    }

    var dashboardCounts: GraphCounts? {
        guard let gid = dashboardGraph?.id else { return nil }
        return perGraph[gid]
    }

    var isLoading: Bool {
        total == nil && loadError == nil
    }

    var isLoadingDetails: Bool {
        (activeMedia == nil || activeStructure == nil || activeTrends == nil) && loadError == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    dashboardHeader

                    if let loadError {
                        StatsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.secondary)
                                    Text("Fehler")
                                        .font(.headline)
                                    Spacer()
                                }
                                Text(loadError)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    dashboardKPIGrid
                    trendsBreakdown
                    mediaBreakdown
                    structureBreakdown

                    if hasLegacyData {
                        legacyCard
                    }

                    perGraphDisclosure
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Statistiken")
            .task {
                startReload(graphIDs: uniqueGraphs.map(\.id))
            }
            .onChange(of: uniqueGraphs.map(\.id)) { _, newValue in
                startReload(graphIDs: newValue)
            }
            .onChange(of: activeGraphIDString) { _, _ in
                startReload(graphIDs: uniqueGraphs.map(\.id))
            }
            .refreshable {
                startReload(graphIDs: uniqueGraphs.map(\.id))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    // MARK: - Loading

    @MainActor
    private func startReload(graphIDs: [UUID]) {
        loadTask?.cancel()

        total = nil
        perGraph = [:]
        activeMedia = nil
        activeStructure = nil
        activeTrends = nil
        loadError = nil

        let pickedGraphID = graphIDs.first(where: { $0 == activeGraphID }) ?? graphIDs.first
        dashboardGraphID = pickedGraphID

        let context = modelContext

        loadTask = Task { @MainActor in
            let service = GraphStatsService(context: context)

            do {
                total = try service.totalCounts()
                perGraph[nil] = try service.counts(for: nil)

                for gid in graphIDs {
                    try Task.checkCancellation()
                    perGraph[gid] = try service.counts(for: gid)

                    if gid == pickedGraphID {
                        activeMedia = try service.mediaSnapshot(for: gid)
                        activeStructure = try service.structureSnapshot(for: gid)
                        activeTrends = try service.trendsSnapshot(for: gid, days: 7)
                    }

                    await Task.yield()
                }

                if pickedGraphID != nil && activeMedia == nil {
                    if let gid = pickedGraphID {
                        activeMedia = try service.mediaSnapshot(for: gid)
                        activeStructure = try service.structureSnapshot(for: gid)
                        activeTrends = try service.trendsSnapshot(for: gid, days: 7)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                loadError = error.localizedDescription
            }
        }
    }
}
