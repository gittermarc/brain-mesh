//
//  GraphStatsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 18.12.25.
//

import SwiftUI
import SwiftData

struct GraphStatsView: View {
    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @Query private var entities: [MetaEntity]
    @Query private var attributes: [MetaAttribute]
    @Query private var links: [MetaLink]

    @State private var showSettings = false

    // ✅ Dedupe by UUID (falls Cloud/Bootstrap doppelt geliefert hat)
    private var uniqueGraphs: [MetaGraph] {
        var seen = Set<UUID>()
        return graphs.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSummary

                if hasLegacyData {
                    legacyCard
                }

                Section("Pro Graph") {
                    ForEach(uniqueGraphs) { g in
                        let c = counts(for: g.id)
                        GraphStatsCard(
                            title: g.name,
                            subtitle: (g.id == activeGraphID) ? "Aktiv" : nil,
                            counts: c
                        )
                    }
                }
            }
            .navigationTitle("Statistiken")
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
                }

                let total = totalCounts()
                StatsRow(icon: "square.grid.2x2", label: "Entitäten", value: total.entities)
                StatsRow(icon: "tag", label: "Attribute", value: total.attributes)
                StatsRow(icon: "link", label: "Links", value: total.links)
                StatsRow(icon: "note.text", label: "Notizen", value: total.notes)
                StatsRow(icon: "photo", label: "Bilder", value: total.images)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Legacy (graphID == nil)

    private var hasLegacyData: Bool {
        entities.contains(where: { $0.graphID == nil }) ||
        attributes.contains(where: { $0.graphID == nil }) ||
        links.contains(where: { $0.graphID == nil })
    }

    private var legacyCard: some View {
        let c = counts(for: nil)

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

    // MARK: - Counting

    private func counts(for gid: UUID?) -> GraphCounts {
        let ents = entities.filter { $0.graphID == gid }
        let attrs = attributes.filter { $0.graphID == gid }
        let lks = links.filter { $0.graphID == gid }

        let notes =
            ents.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count +
            attrs.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count +
            lks.filter { ($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count

        let images =
            ents.filter { hasImage($0.imageData, $0.imagePath) }.count +
            attrs.filter { hasImage($0.imageData, $0.imagePath) }.count

        return GraphCounts(
            entities: ents.count,
            attributes: attrs.count,
            links: lks.count,
            notes: notes,
            images: images
        )
    }

    private func totalCounts() -> GraphCounts {
        // total = sum pro UUID (und legacy separat), damit Dedupe bei Graphen keinen Quatsch macht
        // Hier zählen wir einfach über alle Records, egal welcher Graph – das ist die „Gesamt in App“-Zahl.
        let notes =
            entities.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count +
            attributes.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count +
            links.filter { ($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count

        let images =
            entities.filter { hasImage($0.imageData, $0.imagePath) }.count +
            attributes.filter { hasImage($0.imageData, $0.imagePath) }.count

        return GraphCounts(
            entities: entities.count,
            attributes: attributes.count,
            links: links.count,
            notes: notes,
            images: images
        )
    }

    private func hasImage(_ data: Data?, _ path: String?) -> Bool {
        if let data, !data.isEmpty { return true }
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
}

// MARK: - Small UI building blocks

private struct GraphCounts: Equatable {
    let entities: Int
    let attributes: Int
    let links: Int
    let notes: Int
    let images: Int
}

private struct GraphStatsCard: View {
    let title: String
    let subtitle: String?
    let counts: GraphCounts

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
    let counts: GraphCounts

    var body: some View {
        VStack(spacing: 8) {
            StatsRow(icon: "square.grid.2x2", label: "Entitäten", value: counts.entities)
            StatsRow(icon: "tag", label: "Attribute", value: counts.attributes)
            StatsRow(icon: "link", label: "Links", value: counts.links)
            StatsRow(icon: "note.text", label: "Notizen", value: counts.notes)
            StatsRow(icon: "photo", label: "Bilder", value: counts.images)
        }
    }
}

private struct StatsRow: View {
    let icon: String
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
