//
//  GraphCanvasScreen.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData
import UIKit

struct GraphCanvasScreen: View {
    @Environment(\.modelContext) var modelContext

    // ✅ Active Graph (Multi-Graph)
    @AppStorage("BMActiveGraphID") var activeGraphIDString: String = ""
    var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    var graphs: [MetaGraph]

    @State var showGraphPicker = false
    @State var showSettings = false

    var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    // Focus/Neighborhood
    @State var focusEntity: MetaEntity?
    @State var showFocusPicker = false
    @State var hops: Int = 1
    @State var workMode: WorkMode = .explore

    @State var showGraphPhotoFullscreen = false
    @State var graphFullscreenImage: UIImage?
    @State var cachedFullImagePath: String?
    @State var cachedFullImage: UIImage?

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

    // MiniMap emphasis
    @State var miniMapEmphasized: Bool = false
    @State var miniMapPulseTask: Task<Void, Never>?

    // Sheets
    @State var selectedEntity: MetaEntity?
    @State var selectedAttribute: MetaAttribute?

    var body: some View {

        // ✅ Nodes-only Default + Spotlight edges (nur direct selection edges)
        let drawEdges = edgesForDisplay()

        // ✅ Auto-Spotlight (erzwingt hideNonRelevant=true, depth=1 sobald selection != nil)
        let autoSpotlight = (selection != nil)
        let effectiveLensEnabled = autoSpotlight ? true : lensEnabled
        let effectiveLensHide = autoSpotlight ? true : lensHideNonRelevant
        let effectiveLensDepth = autoSpotlight ? 1 : lensDepth

        let lens = LensContext.build(
            enabled: effectiveLensEnabled,
            hideNonRelevant: effectiveLensHide,
            depth: effectiveLensDepth,
            selection: selection,
            edges: drawEdges
        )

        // ✅ Physik-Relevanz: im Spotlight nur auf Selection+Nachbarn simulieren (damit Hidden-Nodes nicht “mitdrücken”)
        let physicsRelevant: Set<NodeKey>? = (autoSpotlight ? lens.relevant : nil)

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
                        drawEdges: drawEdges,
                        physicsEdges: edges,
                        directedEdgeNotes: directedEdgeNotes,
                        lens: lens,
                        workMode: workMode,
                        collisionStrength: CGFloat(collisionStrength),
                        physicsRelevant: physicsRelevant,
                        selectedImagePath: selectedImagePath(),
                        onTapSelectedThumbnail: {
                            if let img = cachedFullImage {
                                graphFullscreenImage = img
                                showGraphPhotoFullscreen = true
                                return
                            }
                            // Fallback (sollte selten sein)
                            guard let path = selectedImagePathValue,
                                  let full = ImageStore.loadUIImage(path: path) else { return }
                            graphFullscreenImage = full
                            showGraphPhotoFullscreen = true
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
                miniMapOverlay(drawEdges: drawEdges)

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
                ToolbarItemGroup(placement: .topBarTrailing) {

                    Button { showGraphPicker = true } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .accessibilityLabel("Graph wählen")

                    Button {
                        showFocusPicker = true
                    } label: {
                        Image(systemName: "scope")
                    }

                    Button {
                        workMode = (workMode == .explore) ? .edit : .explore
                    } label: {
                        Image(systemName: workMode.icon)
                    }
                    .accessibilityLabel(workMode == .explore ? "In Edit-Modus wechseln" : "In Explore-Modus wechseln")

                    Button {
                        if let sel = selection { cameraCommand = CameraCommand(kind: .center(sel)) }
                        else if let f = focusEntity { cameraCommand = CameraCommand(kind: .center(NodeKey(kind: .entity, uuid: f.id))) }
                    } label: {
                        Image(systemName: "dot.scope")
                    }
                    .disabled(selection == nil && focusEntity == nil)

                    Button {
                        cameraCommand = CameraCommand(kind: .fitAll)
                    } label: {
                        Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                    .disabled(nodes.isEmpty)

                    Button {
                        cameraCommand = CameraCommand(kind: .reset)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }

                    Button {
                        showInspector = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }

            // ✅ Graph Picker
            .sheet(isPresented: $showGraphPicker) {
                GraphPickerSheet()
            }

            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }

            // Focus picker
            .sheet(isPresented: $showFocusPicker) {
                NodePickerView(kind: .entity) { picked in
                    if let entity = fetchEntity(id: picked.id) {
                        focusEntity = entity
                        selection = NodeKey(kind: .entity, uuid: entity.id)
                        showFocusPicker = false
                        Task { await loadGraph() }
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
                Task { await loadGraph(resetLayout: true) }
            }

            // Neighborhood reload
            .task(id: hops) {
                guard focusEntity != nil else { return }
                await loadGraph()
            }

            .task(id: showAttributes) {
                guard focusEntity != nil else { return }
                await loadGraph()
            }
        }
        .onChange(of: pan) { _, _ in pulseMiniMap() }
        .onChange(of: scale) { _, _ in pulseMiniMap() }
        .onAppear { prefetchSelectedFullImage() }

        // ✅ Selection change: reset “more”
        .onChange(of: selection) { _, _ in
            showAllLinksForSelection = false
            prefetchSelectedFullImage()
        }

        .onChange(of: selectedImagePathValue) { _, _ in prefetchSelectedFullImage() }
        .fullScreenCover(isPresented: $showGraphPhotoFullscreen) {
            if let img = graphFullscreenImage {
                FullscreenPhotoView(image: img)
            }
        }
    }

}
