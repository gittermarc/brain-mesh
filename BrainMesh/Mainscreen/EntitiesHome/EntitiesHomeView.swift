//
//  EntitiesHomeView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct EntitiesHomeView: View {
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var onboarding: OnboardingCoordinator
    @EnvironmentObject var appearance: AppearanceStore
    @EnvironmentObject var displaySettings: DisplaySettingsStore

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    var graphs: [MetaGraph]

    @State var searchText = ""
    @State var showAddEntity = false
    @State var showGraphPicker = false
    @State var showViewOptions = false

    @AppStorage("BMEntitiesHomeSort") private var entitiesHomeSortRaw: String = EntitiesHomeSortOption.nameAZ.rawValue

    @AppStorage("BMOnboardingHidden") private var onboardingHidden: Bool = false
    @AppStorage("BMOnboardingCompleted") private var onboardingCompleted: Bool = false

    // MARK: - Fetch-based list state (graph-scoped + debounced)
    @State var rows: [EntitiesHomeRow] = []
    @State var isLoading = false
    @State var loadError: String?

    private let debounceNanos: UInt64 = 250_000_000

    private var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    private var resolvedEntitiesHomeAppearance: EntitiesHomeAppearanceSettings {
        var base = appearance.settings.entitiesHome
        let ds = displaySettings.entitiesHome

        base.layout = (ds.layout == .grid) ? .grid : .list
        base.density = mapDensity(ds.density)

        base.showAttributeCount = ds.showAttributeCount
        base.showLinkCount = ds.showLinkCount
        base.showNotesPreview = ds.showNotesPreview
        base.preferThumbnailOverIcon = ds.preferThumbnailOverIcon

        return base
    }

    private func mapDensity(_ density: EntitiesHomeRowDensity) -> EntitiesHomeDensity {
        switch density {
        case .compact:
            return .compact
        case .standard:
            return .normal
        case .comfortable:
            return .cozy
        }
    }

    private var taskToken: String {
        // Triggers reload when either the active graph, the search term or relevant computed-data flags change.
        let includeAttrs = (resolvedEntitiesHomeAppearance.showAttributeCount || sortOption.needsAttributeCounts) ? "1" : "0"
        let includeLinks = (resolvedEntitiesHomeAppearance.showLinkCount || sortOption.needsLinkCounts) ? "1" : "0"
        let includeNotes = (resolvedEntitiesHomeAppearance.showNotesPreview || displaySettings.entitiesHome.metaLine == .notesPreview) ? "1" : "0"
        return "\(activeGraphIDString)|\(searchText)|\(includeAttrs)|\(includeLinks)|\(includeNotes)"
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
                    if resolvedEntitiesHomeAppearance.layout == .grid {
                        EntitiesHomeGrid(
                            rows: rows,
                            isLoading: isLoading,
                            settings: resolvedEntitiesHomeAppearance,
                            display: displaySettings.entitiesHome,
                            onDelete: { id in
                                deleteEntityIDs([id])
                            }
                        )
                    } else {
                        EntitiesHomeList(
                            rows: rows,
                            isLoading: isLoading,
                            settings: resolvedEntitiesHomeAppearance,
                            display: displaySettings.entitiesHome,
                            onDelete: deleteEntities,
                            onDeleteID: { id in
                                deleteEntityIDs([id])
                            }
                        )
                    }
                }
            }
            .navigationTitle("Entitäten")
            .searchable(text: $searchText, prompt: "Entität oder Attribut suchen…")
            .toolbar {
                EntitiesHomeToolbar(
                    activeGraphName: activeGraphName,
                    showGraphPicker: $showGraphPicker,
                    showViewOptions: $showViewOptions,
                    sortSelection: sortBinding,
                    showAddEntity: $showAddEntity
                )
            }
            .sheet(isPresented: $showViewOptions) {
                EntitiesHomeDisplaySheet(isPresented: $showViewOptions)
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
            .onChange(of: entitiesHomeSortRaw) { _, _ in
                // Apply sorting instantly without waiting for a reload.
                rows = sortOption.apply(to: rows)
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

    @MainActor func reload(forFolded folded: String) async {
        do {
            let includeAttributeCounts = (resolvedEntitiesHomeAppearance.showAttributeCount || sortOption.needsAttributeCounts)
            let includeLinkCounts = (resolvedEntitiesHomeAppearance.showLinkCount || sortOption.needsLinkCounts)
            let includeNotesPreview = (resolvedEntitiesHomeAppearance.showNotesPreview || displaySettings.entitiesHome.metaLine == .notesPreview)

            let snapshot = try await EntitiesHomeLoader.shared.loadSnapshot(
                activeGraphID: activeGraphID,
                foldedSearch: folded,
                includeAttributeCounts: includeAttributeCounts,
                includeLinkCounts: includeLinkCounts,
                includeNotesPreview: includeNotesPreview
            )
            rows = sortOption.apply(to: snapshot.rows)
            isLoading = false
            loadError = nil
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private var sortOption: EntitiesHomeSortOption {
        EntitiesHomeSortOption(rawValue: entitiesHomeSortRaw) ?? .nameAZ
    }

    private var sortBinding: Binding<EntitiesHomeSortOption> {
        Binding(
            get: { EntitiesHomeSortOption(rawValue: entitiesHomeSortRaw) ?? .nameAZ },
            set: { entitiesHomeSortRaw = $0.rawValue }
        )
    }
}

struct EntityDetailRouteView: View {
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

enum EntitiesHomeSortOption: String, CaseIterable, Identifiable {
    case nameAZ
    case nameZA
    case createdNewest
    case createdOldest
    case attributesMost
    case attributesLeast
    case linksMost
    case linksLeast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAZ: return "Name (A–Z)"
        case .nameZA: return "Name (Z–A)"
        case .createdNewest: return "Erstellt (neu → alt)"
        case .createdOldest: return "Erstellt (alt → neu)"
        case .attributesMost: return "Attribute (viel → wenig)"
        case .attributesLeast: return "Attribute (wenig → viel)"
        case .linksMost: return "Links (viel → wenig)"
        case .linksLeast: return "Links (wenig → viel)"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAZ, .nameZA:
            return "textformat"
        case .createdNewest, .createdOldest:
            return "calendar"
        case .attributesMost, .attributesLeast:
            return "list.bullet.rectangle"
        case .linksMost, .linksLeast:
            return "link"
        }
    }

    var needsAttributeCounts: Bool {
        switch self {
        case .attributesMost, .attributesLeast:
            return true
        default:
            return false
        }
    }

    var needsLinkCounts: Bool {
        switch self {
        case .linksMost, .linksLeast:
            return true
        default:
            return false
        }
    }

    func apply(to rows: [EntitiesHomeRow]) -> [EntitiesHomeRow] {
        rows.sorted { lhs, rhs in
            switch self {
            case .nameAZ:
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .nameZA:
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: false)

            case .createdNewest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .createdOldest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .attributesMost:
                if lhs.attributeCount != rhs.attributeCount { return lhs.attributeCount > rhs.attributeCount }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .attributesLeast:
                if lhs.attributeCount != rhs.attributeCount { return lhs.attributeCount < rhs.attributeCount }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .linksMost:
                let la = lhs.linkCount ?? 0
                let ra = rhs.linkCount ?? 0
                if la != ra { return la > ra }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)

            case .linksLeast:
                let la = lhs.linkCount ?? 0
                let ra = rhs.linkCount ?? 0
                if la != ra { return la < ra }
                return EntitiesHomeSortOption.compareName(lhs, rhs, ascending: true)
            }
        }
    }

    private static func compareName(_ lhs: EntitiesHomeRow, _ rhs: EntitiesHomeRow, ascending: Bool) -> Bool {
        let cmp = lhs.name.localizedStandardCompare(rhs.name)
        if cmp == .orderedSame {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        if ascending {
            return cmp == .orderedAscending
        } else {
            return cmp == .orderedDescending
        }
    }
}
