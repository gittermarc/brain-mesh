//
//  GraphStatsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 18.12.25.
//

import Foundation
import SwiftUI
import SwiftData

struct GraphStatsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showSettings = false

    @State private var total: GraphCounts? = nil
    @State private var perGraph: [UUID?: GraphCounts] = [:]
    @State private var loadError: String? = nil
    @State private var loadTask: Task<Void, Never>? = nil

    // ✅ Dedupe by UUID (falls Cloud/Bootstrap doppelt geliefert hat)
    private var uniqueGraphs: [MetaGraph] {
        var seen = Set<UUID>()
        return graphs.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSummary

                if let loadError {
                    Section("Fehler") {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasLegacyData {
                    legacyCard
                }

                Section("Pro Graph") {
                    ForEach(uniqueGraphs) { g in
                        GraphStatsCard(
                            title: g.name,
                            subtitle: (g.id == activeGraphID) ? "Aktiv" : nil,
                            counts: perGraph[g.id]
                        )
                    }
                }
            }
            .navigationTitle("Statistiken")
            .task {
                startReload(graphIDs: uniqueGraphs.map(\.id))
            }
            .onChange(of: uniqueGraphs.map(\.id)) { _, newValue in
                startReload(graphIDs: newValue)
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

    // MARK: - Header

    private var headerSummary: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Graphen gesamt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(uniqueGraphs.count)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    Spacer()

                    if total == nil && loadError == nil {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                StatsRow(icon: "square.grid.2x2", label: "Entitäten", value: total?.entities)
                StatsRow(icon: "tag", label: "Attribute", value: total?.attributes)
                StatsRow(icon: "link", label: "Links", value: total?.links)
                StatsRow(icon: "note.text", label: "Notizen", value: total?.notes)
                StatsRow(icon: "photo", label: "Bilder", value: total?.images)
                StatsRow(icon: "paperclip", label: "Anhänge", value: total?.attachments)
                StatsRowText(icon: "externaldrive", label: "Anhänge Größe", value: formatBytes(total?.attachmentBytes))
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Legacy (graphID == nil)

    private var hasLegacyData: Bool {
        guard let legacy = perGraph[nil] else { return false }
        return legacy.isEmpty == false
    }

    private var legacyCard: some View {
        let c = perGraph[nil]

        return Section("Hinweis") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Unzugeordnet (Legacy)")
                        .font(.headline)
                    Spacer()
                }

                Text("Hier landet alles, was noch keine graphID hat. Normalerweise sollte das nach dem Bootstrap/Migration 0 sein.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                GraphStatsCompact(counts: c)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Loading

    @MainActor
    private func startReload(graphIDs: [UUID]) {
        loadTask?.cancel()
        total = nil
        perGraph = [:]
        loadError = nil

        let context = modelContext
        loadTask = Task { @MainActor in
            let service = GraphStatsService(context: context)
            do {
                total = try service.totalCounts()
                perGraph[nil] = try service.counts(for: nil)

                for gid in graphIDs {
                    try Task.checkCancellation()
                    perGraph[gid] = try service.counts(for: gid)
                    await Task.yield()
                }
            } catch {
                if Task.isCancelled { return }
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Small UI building blocks

private struct GraphStatsCard: View {
    let title: String
    let subtitle: String?
    let counts: GraphCounts?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chart.bar")
                    .foregroundStyle(.secondary)
            }

            GraphStatsCompact(counts: counts)
        }
        .padding(.vertical, 6)
    }
}

private struct GraphStatsCompact: View {
    let counts: GraphCounts?

    var body: some View {
        VStack(spacing: 8) {
            StatsRow(icon: "square.grid.2x2", label: "Entitäten", value: counts?.entities)
            StatsRow(icon: "tag", label: "Attribute", value: counts?.attributes)
            StatsRow(icon: "link", label: "Links", value: counts?.links)
            StatsRow(icon: "note.text", label: "Notizen", value: counts?.notes)
            StatsRow(icon: "photo", label: "Bilder", value: counts?.images)
            StatsRow(icon: "paperclip", label: "Anhänge", value: counts?.attachments)
            StatsRowText(icon: "externaldrive", label: "Anhänge Größe", value: formatBytes(counts?.attachmentBytes))
        }
    }
}

private func formatBytes(_ bytes: Int64?) -> String? {
    guard let bytes else { return nil }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private struct StatsRow: View {
    let icon: String
    let label: String
    let value: Int?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            if let value {
                Text("\(value)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } else {
                Text("—")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatsRowText: View {
    let icon: String
    let label: String
    let value: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            if let value {
                Text(value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } else {
                Text("—")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
