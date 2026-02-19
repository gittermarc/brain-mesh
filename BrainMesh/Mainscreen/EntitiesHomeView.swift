//
//  EntitiesHomeView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct EntitiesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var onboarding: OnboardingCoordinator
    @EnvironmentObject private var appearance: AppearanceStore

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var searchText = ""
    @State private var showAddEntity = false
    @State private var showGraphPicker = false

    @AppStorage("BMOnboardingHidden") private var onboardingHidden: Bool = false
    @AppStorage("BMOnboardingCompleted") private var onboardingCompleted: Bool = false

    // MARK: - Fetch-based list state (graph-scoped + debounced)
    @State private var rows: [EntitiesHomeRow] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let debounceNanos: UInt64 = 250_000_000

    private var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    private var taskToken: String {
        // triggers reload when either the active graph, the search term or relevant computed-data flags change
        let includeLinks = appearance.settings.entitiesHome.showLinkCount ? "1" : "0"
        return "\(activeGraphIDString)|\(searchText)|\(includeLinks)"
    }

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
                    if appearance.settings.entitiesHome.layout == .grid {
                        EntitiesHomeGrid(
                            rows: rows,
                            isLoading: isLoading,
                            settings: appearance.settings.entitiesHome,
                            onDelete: { id in
                                deleteEntityIDs([id])
                            }
                        )
                    } else {
                        List {
                            if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Suche…").foregroundStyle(.secondary)
                                }
                            }

                            ForEach(rows) { row in
                                NavigationLink {
                                    EntityDetailRouteView(entityID: row.id)
                                } label: {
                                    EntitiesHomeListRow(row: row, settings: appearance.settings.entitiesHome)
                                }
                            }
                            .onDelete(perform: deleteEntities)
                        }
                    }
                }
            }
            .navigationTitle("Entitäten")
            .searchable(text: $searchText, prompt: "Entität oder Attribut suchen…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showGraphPicker = true } label: {
                        Label(activeGraphName, systemImage: "square.stack.3d.up")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAddEntity = true } label: { Image(systemName: "plus") }
                }
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

    @MainActor private func reload(forFolded folded: String) async {
        do {
            let snapshot = try await EntitiesHomeLoader.shared.loadSnapshot(
                activeGraphID: activeGraphID,
                foldedSearch: folded,
                includeLinkCounts: appearance.settings.entitiesHome.showLinkCount
            )
            rows = snapshot.rows
            isLoading = false
            loadError = nil
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func fetchEntity(by id: UUID) -> MetaEntity? {
        var fd = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { e in
                e.id == id
            }
        )
        fd.fetchLimit = 1
        return try? modelContext.fetch(fd).first
    }

    private func deleteEntities(at offsets: IndexSet) {
        let idsToDelete: [UUID] = offsets.compactMap { idx in
            guard rows.indices.contains(idx) else { return nil }
            return rows[idx].id
        }
        deleteEntityIDs(idsToDelete)
    }

    private func deleteEntityIDs(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }

        let entitiesToDelete: [MetaEntity] = ids.compactMap { fetchEntity(by: $0) }
        if entitiesToDelete.isEmpty { return }

        for entity in entitiesToDelete {
            // Attachments are not part of the graph rendering; they live only on detail level.
            // They also do not cascade automatically, so we explicitly clean them up.
            AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: entity.id, in: modelContext)
            for attr in entity.attributesList {
                AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            }

            LinkCleanup.deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID ?? activeGraphID, in: modelContext)
            modelContext.delete(entity)
        }

        // Update local list immediately and then re-fetch to stay in sync with SwiftData.
        rows.removeAll { r in ids.contains(r.id) }
        Task {
            await EntitiesHomeLoader.shared.invalidateCache(for: activeGraphID)
            await reload(forFolded: BMSearch.fold(searchText))
        }
    }
}

private struct EntitiesHomeListRow: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EntitiesHomeLeadingVisual(row: row, settings: settings)

            VStack(alignment: .leading, spacing: settings.density.secondaryTextSpacing) {
                Text(row.name)
                    .font(.headline)

                if let counts = countsLine {
                    Text(counts)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if settings.showNotesPreview, let preview = row.notesPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, settings.density.listRowVerticalPadding)
    }

    private var countsLine: String? {
        var parts: [String] = []

        if settings.showAttributeCount {
            let n = row.attributeCount
            parts.append("\(n) \(n == 1 ? "Attribut" : "Attribute")")
        }

        if settings.showLinkCount, let lc = row.linkCount {
            parts.append("\(lc) Links")
        }

        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }
}

private struct EntitiesHomeLeadingVisual: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings

    var body: some View {
        let side = settings.iconSize.listFrame
        let corner: CGFloat = max(6, min(10, side * 0.35))

        Group {
            if settings.preferThumbnailOverIcon, let path = row.imagePath, !path.isEmpty {
                NodeAsyncPreviewImageView(imagePath: path, imageData: nil) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    iconView
                }
            } else {
                iconView
            }
        }
        .frame(width: side, height: side, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var iconView: some View {
        Image(systemName: row.iconSymbolName ?? "cube")
            .font(.system(size: settings.iconSize.listPointSize, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .foregroundStyle(.tint)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }
}

private struct EntitiesHomeGrid: View {
    let rows: [EntitiesHomeRow]
    let isLoading: Bool
    let settings: EntitiesHomeAppearanceSettings
    let onDelete: (UUID) -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var columns: [GridItem] {
        let count = (hSizeClass == .regular) ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: settings.density.gridSpacing), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Suche…")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                LazyVGrid(columns: columns, spacing: settings.density.gridSpacing) {
                    ForEach(rows) { row in
                        NavigationLink {
                            EntityDetailRouteView(entityID: row.id)
                        } label: {
                            EntitiesHomeGridCell(row: row, settings: settings)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(row.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct EntitiesHomeGridCell: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: settings.density.secondaryTextSpacing) {
            HStack {
                EntitiesHomeGridThumbnail(row: row, settings: settings)
                Spacer(minLength: 0)
            }

            Text(row.name)
                .font(.headline)
                .lineLimit(2)

            if let counts = countsLine {
                Text(counts)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if settings.showNotesPreview, let preview = row.notesPreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(settings.density.gridCellPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var countsLine: String? {
        var parts: [String] = []

        if settings.showAttributeCount {
            let n = row.attributeCount
            parts.append("\(n) \(n == 1 ? "Attribut" : "Attribute")")
        }

        if settings.showLinkCount, let lc = row.linkCount {
            parts.append("\(lc) Links")
        }

        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }
}

private struct EntitiesHomeGridThumbnail: View {
    let row: EntitiesHomeRow
    let settings: EntitiesHomeAppearanceSettings

    private var side: CGFloat { settings.iconSize.gridThumbnailSize }

    var body: some View {
        Group {
            if settings.preferThumbnailOverIcon, let path = row.imagePath, !path.isEmpty {
                NodeAsyncPreviewImageView(imagePath: path, imageData: nil) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    iconView
                }
            } else {
                iconView
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconView: some View {
        Image(systemName: row.iconSymbolName ?? "cube")
            .font(.system(size: max(18, side * 0.38), weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.tint)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }
}

private struct EntityDetailRouteView: View {
    @Query private var entities: [MetaEntity]

    init(entityID: UUID) {
        _entities = Query(
            filter: #Predicate<MetaEntity> { e in
                e.id == entityID
            }
        )
    }

    var body: some View {
        if let entity = entities.first {
            EntityDetailView(entity: entity)
        } else {
            ContentUnavailableView {
                Label("Entität nicht gefunden", systemImage: "questionmark.square.dashed")
            } description: {
                Text("Diese Entität existiert nicht mehr oder wurde auf einem anderen Gerät gelöscht.")
            }
        }
    }
}
