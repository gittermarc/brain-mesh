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
    @State private var activeMedia: GraphMediaSnapshot? = nil
    @State private var activeStructure: GraphStructureSnapshot? = nil
    @State private var dashboardGraphID: UUID? = nil
    @State private var loadError: String? = nil
    @State private var loadTask: Task<Void, Never>? = nil

    @State private var showPerGraph = false

    // ✅ Dedupe by UUID (falls Cloud/Bootstrap doppelt geliefert hat)
    private var uniqueGraphs: [MetaGraph] {
        var seen = Set<UUID>()
        return graphs.filter { seen.insert($0.id).inserted }
    }

    private var dashboardGraph: MetaGraph? {
        if let gid = dashboardGraphID {
            return uniqueGraphs.first(where: { $0.id == gid })
        }
        if let gid = activeGraphID {
            return uniqueGraphs.first(where: { $0.id == gid })
        }
        return uniqueGraphs.first
    }

    private var dashboardCounts: GraphCounts? {
        guard let gid = dashboardGraph?.id else { return nil }
        return perGraph[gid]
    }

    private var isLoading: Bool {
        total == nil && loadError == nil
    }

    private var isLoadingDetails: Bool {
        (activeMedia == nil || activeStructure == nil) && loadError == nil
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

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dashboard")
                            .font(.headline)

                        if let g = dashboardGraph {
                            HStack(spacing: 8) {
                                Text(g.name)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)

                                if g.id == activeGraphID {
                                    Text("Aktiv")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(.thinMaterial)
                                        )
                                }
                            }
                        } else {
                            Text("Kein Graph")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 14) {
                    InfoPill(icon: "square.stack.3d.up", text: "Graphen: \(uniqueGraphs.count)")
                    InfoPill(icon: "square.grid.2x2", text: "Knoten: \(formatInt(dashboardCounts?.entities, plus: dashboardCounts?.attributes))")
                    InfoPill(icon: "paperclip", text: "Anhänge: \(formatInt(dashboardCounts?.attachments))")
                }
            }
        }
    }

    // MARK: - KPI Grid

    private var dashboardKPIGrid: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Übersicht")
                        .font(.headline)
                    Spacer()
                    if isLoadingDetails {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    KPICard(
                        icon: "square.grid.2x2",
                        title: "Knoten",
                        value: formatInt(dashboardCounts?.entities, plus: dashboardCounts?.attributes),
                        detail: detailNodes
                    )

                    KPICard(
                        icon: "link",
                        title: "Links",
                        value: formatInt(dashboardCounts?.links),
                        detail: detailLinks
                    )

                    KPICard(
                        icon: "photo.on.rectangle",
                        title: "Medien",
                        value: mediaTotalString,
                        detail: mediaDetail
                    )

                    KPICard(
                        icon: "externaldrive",
                        title: "Speicher",
                        value: formatBytes(dashboardCounts?.attachmentBytes) ?? "—",
                        detail: "Nur Anhänge" 
                    )
                }
            }
        }
    }

    private var detailNodes: String? {
        guard let c = dashboardCounts else { return nil }
        return "Entitäten: \(c.entities) • Attribute: \(c.attributes)"
    }

    private var detailLinks: String? {
        guard let c = dashboardCounts else { return nil }
        if c.links == 0 { return "Noch keine Verknüpfungen" }
        return "Linkdichte: \(formatRatio(numerator: c.links, denominator: max(1, c.entities + c.attributes)))"
    }

    private var mediaTotalString: String {
        guard let c = dashboardCounts else { return "—" }
        return "\(c.images + c.attachments)"
    }

    private var mediaDetail: String? {
        guard let c = dashboardCounts else { return nil }
        return "Header: \(c.images) • Anhänge: \(c.attachments)"
    }

    // MARK: - Media Breakdown

    private var mediaBreakdown: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Medien")
                        .font(.headline)
                    Spacer()
                }

                if let m = activeMedia {
                    VStack(alignment: .leading, spacing: 10) {
                        StatLine(icon: "photo", label: "Header-Bilder", value: "\(m.headerImages)")
                        StatLine(icon: "paperclip", label: "Anhänge", value: "\(m.attachmentsTotal)")

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Anhänge nach Typ")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            BreakdownRow(
                                icon: "doc",
                                label: "Dateien",
                                count: m.attachmentsFile,
                                total: m.attachmentsTotal
                            )
                            BreakdownRow(
                                icon: "video",
                                label: "Videos",
                                count: m.attachmentsVideo,
                                total: m.attachmentsTotal
                            )
                            BreakdownRow(
                                icon: "photo.on.rectangle",
                                label: "Galerie-Bilder",
                                count: m.attachmentsGalleryImages,
                                total: m.attachmentsTotal
                            )
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Dateitypen")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if m.topFileExtensions.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(m.topFileExtensions, id: \.label) { item in
                                            TagChip(text: "\(item.label.uppercased())  \(item.count)")
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Größte Anhänge")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if m.largestAttachments.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(m.largestAttachments, id: \.id) { a in
                                        LargestAttachmentRow(item: a)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    PlaceholderBlock(text: "Medien werden geladen…")
                }
            }
        }
    }

    // MARK: - Structure Breakdown

    private var structureBreakdown: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Graph-Struktur")
                        .font(.headline)
                    Spacer()
                }

                if let s = activeStructure {
                    VStack(alignment: .leading, spacing: 10) {
                        StatLine(icon: "square.grid.2x2", label: "Knoten", value: "\(s.nodeCount)")
                        StatLine(icon: "link", label: "Links", value: "\(s.linkCount)")

                        Divider()

                        let isolated = s.isolatedNodeCount
                        let nodes = max(1, s.nodeCount)
                        let connected = max(0, nodes - isolated)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Isolierte Knoten")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(isolated)")
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            ProgressView(value: Double(connected), total: Double(nodes))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Hubs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if s.topHubs.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(s.topHubs.enumerated()), id: \.element.id) { index, hub in
                                        HubRow(rank: index + 1, hub: hub)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    PlaceholderBlock(text: "Struktur wird berechnet…")
                }
            }
        }
    }

    // MARK: - Legacy

    private var hasLegacyData: Bool {
        guard let legacy = perGraph[nil] else { return false }
        return legacy.isEmpty == false
    }

    private var legacyCard: some View {
        StatsCard {
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

                GraphStatsCompact(counts: perGraph[nil])
            }
        }
    }

    // MARK: - Per Graph

    private var perGraphDisclosure: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup(isExpanded: $showPerGraph) {
                    VStack(spacing: 12) {
                        ForEach(uniqueGraphs) { g in
                            GraphStatsCard(
                                title: g.name,
                                subtitle: (g.id == activeGraphID) ? "Aktiv" : nil,
                                counts: perGraph[g.id]
                            )
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack {
                        Text("Pro Graph")
                            .font(.headline)
                        Spacer()
                        Text("\(uniqueGraphs.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
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
                    }

                    await Task.yield()
                }

                if pickedGraphID != nil && activeMedia == nil {
                    if let gid = pickedGraphID {
                        activeMedia = try service.mediaSnapshot(for: gid)
                        activeStructure = try service.structureSnapshot(for: gid)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Small UI building blocks

private struct StatsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
    }
}

private struct InfoPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

private struct KPICard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

private struct PlaceholderBlock: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct StatLine: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

private struct BreakdownRow: View {
    let icon: String
    let label: String
    let count: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text(label)
                Spacer()
                Text("\(count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            ProgressView(value: Double(count), total: Double(max(1, total)))
        }
    }
}

private struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

private struct LargestAttachmentRow: View {
    let item: GraphLargestAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForKind(item.contentKind))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatBytes(Int64(item.byteCount)) ?? "—")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        let ext = item.fileExtension
        let kind = kindLabel(item.contentKind)
        if ext == "?" { return kind }
        return "\(kind) • .\(ext)"
    }

    private func kindLabel(_ kind: AttachmentContentKind) -> String {
        switch kind {
        case .file: return "Datei"
        case .video: return "Video"
        case .galleryImage: return "Bild"
        }
    }

    private func iconForKind(_ kind: AttachmentContentKind) -> String {
        switch kind {
        case .file: return "doc"
        case .video: return "video"
        case .galleryImage: return "photo"
        }
    }
}

private struct HubRow: View {
    let rank: Int
    let hub: GraphHubItem

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()

            Image(systemName: iconForKind(hub.kind))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(hub.label)
                    .lineLimit(1)
                Text("Degree: \(hub.degree)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func iconForKind(_ kind: NodeKind) -> String {
        switch kind {
        case .entity: return "cube"
        case .attribute: return "tag"
        }
    }
}

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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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

// MARK: - Formatting helpers

private func formatBytes(_ bytes: Int64?) -> String? {
    guard let bytes else { return nil }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func formatInt(_ value: Int?) -> String {
    guard let value else { return "—" }
    return "\(value)"
}

private func formatInt(_ a: Int?, plus b: Int?) -> String {
    guard let a, let b else { return "—" }
    return "\(a + b)"
}

private func formatRatio(numerator: Int, denominator: Int) -> String {
    if denominator <= 0 { return "—" }
    let value = Double(numerator) / Double(denominator)
    let rounded = (value * 100).rounded() / 100
    return "\(rounded)"
}
