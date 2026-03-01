//
//  GraphCanvasScreen.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct GraphCanvasScreen: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    // NOTE: Must not be `private` because several view helpers live in separate extension files.
    @EnvironmentObject var onboarding: OnboardingCoordinator
    // NOTE: Must not be `private` because jump handling touches helpers in separate extension files.
    @EnvironmentObject var graphJump: GraphJumpCoordinator

    // ✅ Active Graph (Multi-Graph)
    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    var graphs: [MetaGraph]

    @State var showGraphPicker = false

    // NOTE: Must not be `private` because GraphCanvasScreen is split into multiple files via extensions.
    @AppStorage(BMAppStorageKeys.onboardingHidden) var onboardingHidden: Bool = false
    @AppStorage(BMAppStorageKeys.onboardingCompleted) var onboardingCompleted: Bool = false

    var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    // Focus/Neighborhood
    @State var focusEntity: MetaEntity?
    @State var showFocusPicker = false
    @State var hops: Int = 1
    @State var workMode: WorkMode = .explore

    // Toggles
    @State var showAttributes: Bool = true

    // ✅ Lens
    @State var lensEnabled: Bool = true
    @State var lensHideNonRelevant: Bool = false
    @State var lensDepth: Int = 2 // 1 = nur Nachbarn, 2 = Nachbarn+Nachbarn

    // Performance knobs
    @State var maxNodes: Int = 140
    @State var maxLinks: Int = 800

    // ✅ Physics tuning
    @State var collisionStrength: Double = 0.030

    // Graph
    @State var nodes: [GraphNode] = []
    @State var edges: [GraphEdge] = []                         // ✅ alle Kanten (Physik / Daten)
    @State var positions: [NodeKey: CGPoint] = [:]
    @State var velocities: [NodeKey: CGVector] = [:]

    // ✅ Render caches (kein SwiftData-Fetch im Render-Pfad)
    @State var labelCache: [NodeKey: String] = [:]
    @State var imagePathCache: [NodeKey: String] = [:] // non-empty paths; missing = nil
    @State var iconSymbolCache: [NodeKey: String] = [:] // non-empty SF Symbol names; missing = nil


    // ✅ Notizen GERICHETET: source -> target
    @State var directedEdgeNotes: [DirectedEdgeKey: String] = [:]

    // Pinning + Selection
    @State var pinned: Set<NodeKey> = []
    @State var selection: NodeKey? = nil

    // ✅ Details Peek (Selection chip)
    // Precomputed on selection change to keep the render path cheap.
    @State var detailsPeekChips: [GraphDetailsPeekChip] = []

    // ✅ Entity selection: list of defined detail fields (names/pinning)
    // Precomputed on selection change to keep the render path cheap.
    @State var entityFieldsPeekItems: [GraphEntityFieldPeekItem] = []

    // ✅ Details Peek editing (PR A2)
    @State var detailsValueEditRequest: GraphDetailsValueEditRequest? = nil

    // ✅ Derived render state (cached)
    // Previously computed inside `body` on every re-render.
    // During physics ticks, `positions/velocities` change frequently which triggers many re-renders.
    // Caching keeps the per-frame work minimal.
    @State var drawEdgesCache: [GraphEdge] = []
    @State var lensCache: LensContext = LensContext.build(
        enabled: false,
        hideNonRelevant: false,
        depth: 2,
        selection: nil,
        edges: []
    )
    @State var physicsRelevantCache: Set<NodeKey>? = nil

    // ✅ Degree cap (Link edges) + “more”
    // NOTE: Must not be `private` because helpers live in separate extension files.
    let degreeCap: Int = 12
    @State var showAllLinksForSelection: Bool = false

    // Camera
    @State var scale: CGFloat = 1.0
    @State var pan: CGSize = .zero
    @State var cameraCommand: CameraCommand? = nil

    // Loading/UI
    @State var isLoading = false
    @State var loadError: String?
    @State var showInspector = false

    // ✅ Visibility gate for physics timer (P0.2)
    @State var isScreenVisible: Bool = false

    // ✅ Cancellable loads (avoid overlapping work when multiple triggers fire quickly)
    // NOTE: Must not be `private` because the load pipeline lives in extension files.
    @State var loadTask: Task<Void, Never>?

    // ✅ Stale-result guard (only commit if token matches the latest scheduled load)
    @State var currentLoadToken: UUID = UUID()

    // MiniMap emphasis
    @State var miniMapEmphasized: Bool = false
    @State var miniMapPulseTask: Task<Void, Never>?

    // ✅ MiniMap throttle: only update the MiniMap inputs at a lower rate.
    // Reason: `positions` changes at 30 FPS during physics ticks and would otherwise
    // cause the MiniMap canvas to redraw excessively.
    // NOTE: Must not be `private` because the MiniMap overlay lives in a separate extension file.
    @State var miniMapPositionsSnapshot: [NodeKey: CGPoint] = [:]

    // Sheets
    @State var selectedEntity: MetaEntity?
    @State var selectedAttribute: MetaAttribute?

    // ✅ Cross-screen graph jump handling (PR 3)
    // We stage the desired selection/centering until the next load commits nodes + layout.
    // NOTE: Must not be `private` because helpers live in separate extension files.
    @State var stagedJumpID: UUID?
    @State var stagedJumpGraphID: UUID?
    @State var stagedSelectAfterLoad: NodeKey?
    @State var stagedCenterAfterLoad: NodeKey?

}
