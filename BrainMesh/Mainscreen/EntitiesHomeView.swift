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
    @State private var items: [MetaEntity] = []
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
                } else if isLoading && items.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Lade Entitäten…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else if items.isEmpty {
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

                        ForEach(items) { entity in
                            NavigationLink {
                                EntityDetailView(entity: entity)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: entity.iconSymbolName ?? "cube")
                                        .font(.system(size: 18, weight: .semibold))
                                        .frame(width: 24, height: 24, alignment: .top)
                                        .foregroundStyle(.tint)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entity.name).font(.headline)
                                        Text("\(entity.attributesList.count) Attribute")
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
            items = try fetchEntities(foldedSearch: folded)
            isLoading = false
            loadError = nil
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func fetchEntities(foldedSearch s: String) throws -> [MetaEntity] {
        let gid = activeGraphID

        // Empty search: show *all* entities for the active graph (plus legacy nil-scope)
        if s.isEmpty {
            let fd = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    gid == nil || e.graphID == gid || e.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
            return try modelContext.fetch(fd)
        }

        let term = s
        var unique: [UUID: MetaEntity] = [:]

        // 1) Entity name match
        var fdEntities = FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { e in
                (gid == nil || e.graphID == gid || e.graphID == nil) &&
                e.nameFolded.contains(term)
            },
            sortBy: [SortDescriptor(\MetaEntity.name)]
        )
        for e in try modelContext.fetch(fdEntities) {
            unique[e.id] = e
        }

        // 2) Attribute displayName match (entity · attribute)
        let fdAttrs = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { a in
                (gid == nil || a.graphID == gid || a.graphID == nil) &&
                a.searchLabelFolded.contains(term)
            },
            sortBy: [SortDescriptor(\MetaAttribute.name)]
        )
        let attrs = try modelContext.fetch(fdAttrs)

        // Note: `#Predicate` doesn't reliably support `ids.contains(e.id)` for UUID arrays.
        // We therefore resolve owners directly from the matching attributes.
        for a in attrs {
            guard let owner = a.owner else { continue }
            if gid == nil || owner.graphID == gid || owner.graphID == nil {
                unique[owner.id] = owner
            }
        }

        // Stable sort
        return unique.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func deleteEntities(at offsets: IndexSet) {
        let entitiesToDelete: [MetaEntity] = offsets.compactMap { idx -> MetaEntity? in
            guard items.indices.contains(idx) else { return nil }
            return items[idx]
        }

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
        items.removeAll { e in entitiesToDelete.contains(where: { $0.id == e.id }) }
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
