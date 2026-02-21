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
    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

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

        loadTask = Task {
            do {
                // In case the loader is configured in a detached task during app startup,
                // yield once before the first attempt to reduce race likelihood.
                await Task.yield()

                let snapshot = try await GraphStatsLoader.shared.loadSnapshot(
                    graphIDs: graphIDs,
                    activeGraphID: activeGraphID,
                    days: 7
                )

                try Task.checkCancellation()

                total = snapshot.total
                perGraph = snapshot.perGraph
                dashboardGraphID = snapshot.dashboardGraphID
                activeMedia = snapshot.activeMedia
                activeStructure = snapshot.activeStructure
                activeTrends = snapshot.activeTrends
            } catch {
                if Task.isCancelled { return }
                loadError = error.localizedDescription
            }
        }
    }
}
