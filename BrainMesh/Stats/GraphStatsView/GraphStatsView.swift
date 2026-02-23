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

    /// Soft refresh state: keep the last snapshot on screen while recomputing.
    @State var isRefreshing: Bool = false

    /// Token to guard against late-arriving tasks updating state after a newer reload was started.
    @State private var currentLoadToken: UUID = UUID()

    /// Last load input used by `.task(id:)` to compute/dedupe reloads.
    @State private var lastLoadKey: StatsLoadKey? = nil

    @State var showPerGraph = false

    private struct StatsLoadKey: Hashable {
        let graphIDs: [UUID]
        let activeGraphID: UUID?
        let days: Int
    }

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
            .task(id: statsLoadKey) {
                _ = await triggerReload(for: statsLoadKey, force: false)
            }
            .refreshable {
                let task = await triggerReload(for: statsLoadKey, force: true)
                await task?.value
            }
        }
    }

    // MARK: - Loading

    private var statsLoadKey: StatsLoadKey {
        StatsLoadKey(
            graphIDs: uniqueGraphs.map(\.id),
            activeGraphID: activeGraphID,
            days: 7
        )
    }

    @MainActor
    private func triggerReload(for key: StatsLoadKey, force: Bool) -> Task<Void, Never>? {
        // Dedupe: when the same inputs arrive multiple times in quick succession (e.g. Query jitter),
        // don't restart a running load unless forced.
        if !force, lastLoadKey == key, isRefreshing {
            return loadTask
        }

        lastLoadKey = key

        loadTask?.cancel()
        loadError = nil
        isRefreshing = true

        let token = UUID()
        currentLoadToken = token

        // If the dashboard graph changes, don't keep old graph-specific details on screen.
        let pickedGraphID = key.graphIDs.first(where: { $0 == key.activeGraphID }) ?? key.graphIDs.first
        if pickedGraphID != dashboardGraphID {
            dashboardGraphID = pickedGraphID
            activeMedia = nil
            activeStructure = nil
            activeTrends = nil
        }

        let task = Task { @MainActor [key] in
            do {
                // In case the loader is configured in a detached task during app startup,
                // yield once before the first attempt to reduce race likelihood.
                await Task.yield()

                let snapshot = try await GraphStatsLoader.shared.loadSnapshot(
                    graphIDs: key.graphIDs,
                    activeGraphID: key.activeGraphID,
                    days: key.days
                )

                try Task.checkCancellation()

                guard currentLoadToken == token else { return }

                total = snapshot.total
                perGraph = snapshot.perGraph
                dashboardGraphID = snapshot.dashboardGraphID
                activeMedia = snapshot.activeMedia
                activeStructure = snapshot.activeStructure
                activeTrends = snapshot.activeTrends
                isRefreshing = false
            } catch {
                if Task.isCancelled {
                    if currentLoadToken == token {
                        isRefreshing = false
                    }
                    return
                }
                guard currentLoadToken == token else { return }
                loadError = error.localizedDescription
                isRefreshing = false
            }
        }

        loadTask = task
        return task
    }
}
