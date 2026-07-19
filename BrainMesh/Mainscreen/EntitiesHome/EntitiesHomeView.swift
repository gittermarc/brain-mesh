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
    @EnvironmentObject var commandCenter: CommandCenterCoordinator
    @EnvironmentObject var recentNodeStore: RecentNodeStore
    @EnvironmentObject var tabRouter: RootTabRouter
    @EnvironmentObject var graphJump: GraphJumpCoordinator
    @EnvironmentObject var entitiesHomeRouting: EntitiesHomeRoutingCoordinator

    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    var graphs: [MetaGraph]

    @State var searchText = ""
    @State var showAddEntity = false
    @State var showGraphPicker = false
    @State var showViewOptions = false
    @State var preferExpandedToolbarActions = false

    @AppStorage(BMAppStorageKeys.entitiesHomeSort) var entitiesHomeSortRaw: String = EntitiesHomeSortOption.nameAZ.rawValue

    @AppStorage(BMAppStorageKeys.onboardingHidden) var onboardingHidden: Bool = false
    @AppStorage(BMAppStorageKeys.onboardingCompleted) var onboardingCompleted: Bool = false

    // MARK: - Fetch-based list state (graph-scoped + debounced)
    @State var rows: [EntitiesHomeRow] = []
    @State var isLoading = false
    @State var loadError: String?
    @State var deletionErrorMessage: String?

    @State var cockpitSnapshot: EntitiesHomeCockpitSnapshot = .empty
    @State var isCockpitLoading = false
    @State var cockpitErrorMessage: String?
    @State var selectedQuickFilter: EntitiesHomeQuickFilter = .all

    var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    var resolvedEntitiesHomeAppearance: EntitiesHomeAppearanceSettings {
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

    var sortOption: EntitiesHomeSortOption {
        EntitiesHomeSortOption(rawValue: entitiesHomeSortRaw) ?? .nameAZ
    }

    var sortBinding: Binding<EntitiesHomeSortOption> {
        Binding(
            get: { EntitiesHomeSortOption(rawValue: entitiesHomeSortRaw) ?? .nameAZ },
            set: { entitiesHomeSortRaw = $0.rawValue }
        )
    }

    var isSearchActive: Bool {
        BMSearch.fold(searchText).isEmpty == false
    }

    var shouldShowCockpit: Bool {
        displaySettings.entitiesHome.showCockpit && !isSearchActive && activeGraphID != nil
    }

    var quickFiltersAreActive: Bool {
        shouldShowCockpit && cockpitSnapshot.graphID == activeGraphID
    }

    var effectiveQuickFilter: EntitiesHomeQuickFilter {
        guard quickFiltersAreActive else { return .all }
        return EntitiesHomeQuickFilterEngine.effectiveFilter(
            selectedFilter: selectedQuickFilter,
            isSearchActive: false
        )
    }

    var visibleRows: [EntitiesHomeRow] {
        EntitiesHomeQuickFilterEngine.filteredRows(
            rows,
            selectedFilter: effectiveQuickFilter,
            snapshot: cockpitSnapshot,
            isSearchActive: false
        )
    }

    var shouldShowQuickFilterEmptyState: Bool {
        EntitiesHomeQuickFilterEngine.shouldShowFilterEmptyState(
            allRows: rows,
            filteredRows: visibleRows,
            selectedFilter: effectiveQuickFilter,
            isSearchActive: false
        )
    }

    var cockpitTaskToken: String {
        let recentSignature = recentNodeStore
            .recentItems(graphID: activeGraphID, limit: 8)
            .map { item in
                "\(item.id)|\(item.openedAt.timeIntervalSince1970)"
            }
            .joined(separator: ";")
        return "\(activeGraphIDString)|\(displaySettings.entitiesHome.showCockpit)|\(recentSignature)"
    }

}
