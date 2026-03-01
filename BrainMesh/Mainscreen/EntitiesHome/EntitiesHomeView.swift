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
}
