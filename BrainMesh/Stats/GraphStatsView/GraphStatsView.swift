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

    /// Lazy per-graph counts state ("Pro Graph").
    @State var isLoadingPerGraphCounts: Bool = false
    @State var perGraphLoadError: String? = nil
    @State var perGraphLoadTask: Task<Void, Never>? = nil

    /// Soft refresh state: keep the last snapshot on screen while recomputing.
    @State var isRefreshing: Bool = false

    /// Token to guard against late-arriving tasks updating state after a newer reload was started.
    @State private var currentLoadToken: UUID = UUID()

    /// Last load input used by `.task(id:)` to compute/dedupe reloads.
    @State private var lastLoadKey: StatsLoadKey? = nil

    /// Token to guard against late-arriving per-graph count loads.
    @State private var currentPerGraphLoadToken: UUID = UUID()

    /// Last per-graph input used to compute/dedupe "Pro Graph" loads.
    @State private var lastPerGraphKey: PerGraphCountsLoadKey? = nil

    @State var showPerGraph = false

    private struct StatsLoadKey: Hashable {
        let graphIDs: [UUID]
        let activeGraphID: UUID?
        let days: Int
    }

    private struct PerGraphCountsLoadKey: Hashable {
        let graphIDs: [UUID]
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
            .onChange(of: showPerGraph) { _, newValue in
                if newValue {
                    _ = triggerPerGraphCountsReload(for: perGraphCountsLoadKey, force: false)
                }
            }
            .refreshable {
                let task = await triggerReload(for: statsLoadKey, force: true)
                await task?.value

                if showPerGraph {
                    await perGraphLoadTask?.value
                }
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

    private var perGraphCountsLoadKey: PerGraphCountsLoadKey {
        PerGraphCountsLoadKey(
            graphIDs: uniqueGraphs.map(\.id)
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

        // If the graph list changed, prune stale per-graph entries.
        prunePerGraphCounts(allowedGraphIDs: Set(key.graphIDs))

        let task = Task { @MainActor [key] in
            do {
                // In case the loader is configured in a detached task during app startup,
                // yield once before the first attempt to reduce race likelihood.
                await Task.yield()

                let snapshot = try await GraphStatsLoader.shared.loadDashboardSnapshot(
                    graphIDs: key.graphIDs,
                    activeGraphID: key.activeGraphID,
                    days: key.days
                )

                try Task.checkCancellation()

                guard currentLoadToken == token else { return }

                total = snapshot.total
                // Merge partial dashboard counts into existing map (keep already-lazy-loaded per-graph counts).
                for (k, v) in snapshot.perGraph {
                    perGraph[k] = v
                }
                prunePerGraphCounts(allowedGraphIDs: Set(key.graphIDs))
                dashboardGraphID = snapshot.dashboardGraphID
                activeMedia = snapshot.activeMedia
                activeStructure = snapshot.activeStructure
                activeTrends = snapshot.activeTrends
                isRefreshing = false

                // If "Pro Graph" is currently expanded, ensure per-graph counts exist.
                if showPerGraph {
                    _ = triggerPerGraphCountsReload(for: perGraphCountsLoadKey, force: force)
                }
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

    @MainActor
    private func triggerPerGraphCountsReload(for key: PerGraphCountsLoadKey, force: Bool) -> Task<Void, Never>? {
        guard key.graphIDs.isEmpty == false else { return nil }

        let alreadyHaveAllCounts = key.graphIDs.allSatisfy { perGraph[$0] != nil }
        if !force, alreadyHaveAllCounts {
            return perGraphLoadTask
        }

        // Dedupe: don't restart a running per-graph load for the same key unless forced.
        if !force, lastPerGraphKey == key, isLoadingPerGraphCounts {
            return perGraphLoadTask
        }

        lastPerGraphKey = key

        perGraphLoadTask?.cancel()
        perGraphLoadError = nil
        isLoadingPerGraphCounts = true

        let token = UUID()
        currentPerGraphLoadToken = token

        let task = Task { @MainActor [key] in
            do {
                await Task.yield()

                let counts = try await GraphStatsLoader.shared.loadPerGraphCounts(graphIDs: key.graphIDs)
                try Task.checkCancellation()

                guard currentPerGraphLoadToken == token else { return }

                for (k, v) in counts {
                    perGraph[k] = v
                }
                prunePerGraphCounts(allowedGraphIDs: Set(key.graphIDs))
                isLoadingPerGraphCounts = false
            } catch {
                if Task.isCancelled {
                    if currentPerGraphLoadToken == token {
                        isLoadingPerGraphCounts = false
                    }
                    return
                }
                guard currentPerGraphLoadToken == token else { return }
                perGraphLoadError = error.localizedDescription
                isLoadingPerGraphCounts = false
            }
        }

        perGraphLoadTask = task
        return task
    }

    @MainActor
    private func prunePerGraphCounts(allowedGraphIDs: Set<UUID>) {
        var pruned: [UUID?: GraphCounts] = [:]

        if let legacy = perGraph[nil] {
            pruned[nil] = legacy
        }

        for (k, v) in perGraph {
            guard let id = k else { continue }
            if allowedGraphIDs.contains(id) {
                pruned[id] = v
            }
        }

        perGraph = pruned
    }
}
