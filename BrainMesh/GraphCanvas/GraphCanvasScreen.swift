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
    // NOTE: Must not be `private` because several view helpers live in separate extension files.
    @EnvironmentObject var onboarding: OnboardingCoordinator

    // ✅ Active Graph (Multi-Graph)
    @AppStorage("BMActiveGraphID") var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    var graphs: [MetaGraph]

    @State var showGraphPicker = false

    // NOTE: Must not be `private` because GraphCanvasScreen is split into multiple files via extensions.
    @AppStorage("BMOnboardingHidden") var onboardingHidden: Bool = false
    @AppStorage("BMOnboardingCompleted") var onboardingCompleted: Bool = false

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

    // ✅ Derived render state (cached)
    // Previously computed inside `body` on every re-render.
    // During physics ticks, `positions/velocities` change frequently which triggers many re-renders.
    // Caching keeps the per-frame work minimal.
    @State private var drawEdgesCache: [GraphEdge] = []
    @State private var lensCache: LensContext = LensContext.build(
        enabled: false,
        hideNonRelevant: false,
        depth: 2,
        selection: nil,
        edges: []
    )
    @State private var physicsRelevantCache: Set<NodeKey>? = nil

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

    // ✅ Cancellable loads (avoid overlapping work when multiple triggers fire quickly)
    // NOTE: Must not be `private` because the load pipeline lives in extension files.
    @State var loadTask: Task<Void, Never>?

    // MiniMap emphasis
    @State var miniMapEmphasized: Bool = false
    @State var miniMapPulseTask: Task<Void, Never>?

    // Sheets
    @State var selectedEntity: MetaEntity?
    @State var selectedAttribute: MetaAttribute?

    @MainActor
    private func recomputeDerivedState() {
        let newDrawEdges = edgesForDisplay()

        // ✅ Auto-Spotlight (erzwingt hideNonRelevant=true, depth=1 sobald selection != nil)
        let autoSpotlight = (selection != nil)
        let effectiveLensEnabled = autoSpotlight ? true : lensEnabled
        let effectiveLensHide = autoSpotlight ? true : lensHideNonRelevant
        let effectiveLensDepth = autoSpotlight ? 1 : lensDepth

        let newLens = LensContext.build(
            enabled: effectiveLensEnabled,
            hideNonRelevant: effectiveLensHide,
            depth: effectiveLensDepth,
            selection: selection,
            edges: newDrawEdges
        )

        // ✅ Physik-Relevanz: im Spotlight nur auf Selection+Nachbarn simulieren
        let newPhysicsRelevant: Set<NodeKey>? = (autoSpotlight ? newLens.relevant : nil)

        if drawEdgesCache != newDrawEdges { drawEdgesCache = newDrawEdges }
        if lensCache != newLens { lensCache = newLens }
        if physicsRelevantCache != newPhysicsRelevant { physicsRelevantCache = newPhysicsRelevant }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Canvas / Graph
                if let loadError {
                    errorView(loadError)
                } else if nodes.isEmpty && !isLoading {
                    emptyView
                } else {
                    GraphCanvasView(
                        nodes: nodes,
                        iconSymbolCache: iconSymbolCache,
                        drawEdges: drawEdgesCache,
                        physicsEdges: edges,
                        directedEdgeNotes: directedEdgeNotes,
                        lens: lensCache,
                        workMode: workMode,
                        collisionStrength: CGFloat(collisionStrength),
                        physicsRelevant: physicsRelevantCache,
                        selectedImagePath: selectedImagePath(),
                        onTapSelectedThumbnail: {
                            guard let key = selection else { return }
                            openDetails(for: key)
                        },
                        positions: $positions,
                        velocities: $velocities,
                        pinned: $pinned,
                        selection: $selection,
                        scale: $scale,
                        pan: $pan,
                        cameraCommand: $cameraCommand,
                        onTapNode: { keyOrNil in
                            selection = keyOrNil
                        }
                    )
                }

                loadingChipOverlay
                sideStatusOverlay
                miniMapOverlay(drawEdges: drawEdgesCache)

                // Action chip for selection
                if let key = selection, let selected = nodeForKey(key) {
                    actionChip(for: selected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 12)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // NOTE:
                // SwiftUI will collapse overflowing toolbar items into a system “…” overflow button.
                // On some devices / layouts this overflow button can become non-interactive.
                // We avoid the overflow entirely by keeping the top bar intentionally small:
                // - Graph Picker (leading)
                // - Inspector (trailing)
                // Everything else stays reachable inside the Inspector.

                ToolbarItem(placement: .topBarLeading) {
                    Button { showGraphPicker = true } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .accessibilityLabel("Graph wählen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInspector = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Inspector")
                }
            }

            // ✅ Graph Picker
            .sheet(isPresented: $showGraphPicker) {
                GraphPickerSheet()
            }

            // Focus picker
            .sheet(isPresented: $showFocusPicker) {
                NodePickerView(kind: .entity) { picked in
                    if let entity = fetchEntity(id: picked.id) {
                        focusEntity = entity
                        selection = NodeKey(kind: .entity, uuid: entity.id)
                        showFocusPicker = false
                        scheduleLoadGraph(resetLayout: true)
                    } else {
                        showFocusPicker = false
                    }
                }
            }

            // Inspector
            .sheet(isPresented: $showInspector) {
                inspectorSheet
            }

            // Detail sheets
            .sheet(item: $selectedEntity) { entity in
                NavigationStack { EntityDetailView(entity: entity) }
                    .onDisappear {
                        refreshNodeCaches(for: NodeKey(kind: .entity, uuid: entity.id))
                    }
            }
            .sheet(item: $selectedAttribute) { attr in
                NavigationStack { AttributeDetailView(attribute: attr) }
                    .onDisappear {
                        refreshNodeCaches(for: NodeKey(kind: .attribute, uuid: attr.id))
                    }
            }

            // Initial load (und Safety: ActiveGraphID setzen, falls leer)
            .task(id: graphs.count) {
                await ensureActiveGraphAndLoadIfNeeded()
            }

            // ✅ Graph change => reset view state + reload
            .onChange(of: activeGraphIDString) { _, _ in
                focusEntity = nil
                selection = nil
                pinned.removeAll()
                scheduleLoadGraph(resetLayout: true)
            }

            // Neighborhood reload
            .task(id: hops) {
                guard focusEntity != nil else { return }
                scheduleLoadGraph(resetLayout: true)
            }

            .task(id: showAttributes) {
                guard focusEntity != nil else { return }
                scheduleLoadGraph(resetLayout: true)
            }
        }
        .onChange(of: pan) { _, _ in pulseMiniMap() }
        .onChange(of: scale) { _, _ in pulseMiniMap() }
        .onAppear {
            recomputeDerivedState()
        }
        .onDisappear {
            // Best-effort: If the screen goes away, stop any in-flight load.
            loadTask?.cancel()
        }

        // ✅ Derived state updates (only when its true inputs change)
        .onChange(of: edges) { _, _ in recomputeDerivedState() }
        .onChange(of: nodes) { _, _ in recomputeDerivedState() }
        .onChange(of: labelCache) { _, _ in recomputeDerivedState() }
        .onChange(of: showAllLinksForSelection) { _, _ in recomputeDerivedState() }
        .onChange(of: lensEnabled) { _, _ in recomputeDerivedState() }
        .onChange(of: lensHideNonRelevant) { _, _ in recomputeDerivedState() }
        .onChange(of: lensDepth) { _, _ in recomputeDerivedState() }

        // ✅ Selection change: reset “more”
        .onChange(of: selection) { _, newSelection in
            showAllLinksForSelection = false

            if let key = newSelection {
                Task {
                    await ensureLocalMainImageCacheForSelectionIfNeeded(key)
                }
            }

            recomputeDerivedState()
        }
}

    // MARK: - Cancellable loading

    func scheduleLoadGraph(resetLayout: Bool) {
        Task { @MainActor in
            loadTask?.cancel()
            loadTask = Task {
                await loadGraph(resetLayout: resetLayout)
            }
        }
    }

}
