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

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var searchText = ""
    @State private var showAddEntity = false
    @State private var showGraphPicker = false
    @State private var showSettings = false

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
        // triggers reload when either the active graph or the search term changes
        "\(activeGraphIDString)|\(searchText)"
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
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: row.iconSymbolName ?? "cube")
                                        .font(.system(size: 18, weight: .semibold))
                                        .frame(width: 24, height: 24, alignment: .top)
                                        .foregroundStyle(.tint)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.name).font(.headline)
                                        Text("\(row.attributeCount) Attribute")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteEntities)
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

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showAddEntity) {
                AddEntityView()
            }
            .sheet(isPresented: $showGraphPicker) {
                GraphPickerSheet()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
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
                    Task { await reload(forFolded: BMSearch.fold(searchText)) }
                }
            }
        }
    }

    @MainActor private func reload(forFolded folded: String) async {
        do {
            let snapshot = try await EntitiesHomeLoader.shared.loadSnapshot(
                activeGraphID: activeGraphID,
                foldedSearch: folded
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

        let entitiesToDelete: [MetaEntity] = idsToDelete.compactMap { fetchEntity(by: $0) }

        for entity in entitiesToDelete {
            // Attachments are not part of the graph rendering; they live only on detail level.
            // They also do not cascade automatically, so we explicitly clean them up.
            AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: entity.id, in: modelContext)
            for attr in entity.attributesList {
                AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            }

            deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID ?? activeGraphID)
            modelContext.delete(entity)
        }

        // Update local list immediately and then re-fetch to stay in sync with SwiftData.
        rows.removeAll { r in entitiesToDelete.contains(where: { $0.id == r.id }) }
        Task { await reload(forFolded: BMSearch.fold(searchText)) }
    }

    private func deleteLinks(referencing kind: NodeKind, id: UUID, graphID: UUID?) {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        let fdSource = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == k &&
                l.sourceID == nodeID &&
                (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdSource) {
            for l in links { modelContext.delete(l) }
        }

        let fdTarget = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.targetKindRaw == k &&
                l.targetID == nodeID &&
                (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdTarget) {
            for l in links { modelContext.delete(l) }
        }
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
