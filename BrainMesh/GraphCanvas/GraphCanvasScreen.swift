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
    @Environment(\.modelContext) private var modelContext

    // ✅ Active Graph (Multi-Graph)
    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showGraphPicker = false

    private var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    // Focus/Neighborhood
    @State private var focusEntity: MetaEntity?
    @State private var showFocusPicker = false
    @State private var hops: Int = 1
    @State private var workMode: WorkMode = .explore

    @State private var showGraphPhotoFullscreen = false
    @State private var graphFullscreenImage: UIImage?
    @State private var cachedFullImagePath: String?
    @State private var cachedFullImage: UIImage?

    // Toggles
    @State private var showAttributes: Bool = true

    // ✅ Lens
    @State private var lensEnabled: Bool = true
    @State private var lensHideNonRelevant: Bool = false
    @State private var lensDepth: Int = 2 // 1 = nur Nachbarn, 2 = Nachbarn+Nachbarn

    // Performance knobs
    @State private var maxNodes: Int = 140
    @State private var maxLinks: Int = 800

    // ✅ Physics tuning
    @State private var collisionStrength: Double = 0.030

    // Graph
    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []                         // ✅ alle Kanten (Physik / Daten)
    @State private var positions: [NodeKey: CGPoint] = [:]
    @State private var velocities: [NodeKey: CGVector] = [:]

    // ✅ Notizen GERICHETET: source -> target
    @State private var directedEdgeNotes: [DirectedEdgeKey: String] = [:]

    // Pinning + Selection
    @State private var pinned: Set<NodeKey> = []
    @State private var selection: NodeKey? = nil

    // ✅ Degree cap (Link edges) + “more”
    private let degreeCap: Int = 12
    @State private var showAllLinksForSelection: Bool = false

    // Camera
    @State private var scale: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var cameraCommand: CameraCommand? = nil

    // Loading/UI
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showInspector = false

    // MiniMap emphasis
    @State private var miniMapEmphasized: Bool = false
    @State private var miniMapPulseTask: Task<Void, Never>?

    // Sheets
    @State private var selectedEntity: MetaEntity?
    @State private var selectedAttribute: MetaAttribute?

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

                // Loading overlay
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Lade…").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                // Side status (hochkant links)
                GeometryReader { geo in
                    let x = geo.safeAreaInsets.leading + 16
                    sideStatusBar
                        .rotationEffect(.degrees(-90))
                        .fixedSize()
                        .position(x: x, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)

                // MiniMap (zeigt dieselben “drawEdges”, also in Default nodes-only quasi ohne Linien)
                GeometryReader { geo in
                    MiniMapView(
                        nodes: nodes,
                        edges: drawEdges,
                        positions: positions,
                        selection: selection,
                        focus: focusKey,
                        scale: scale,
                        pan: pan,
                        canvasSize: geo.size
                    )
                    .frame(width: 180, height: 125)
                    .opacity(miniMapEmphasized ? 1.0 : 0.55)
                    .scaleEffect(miniMapEmphasized ? 1.02 : 1.0)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                .allowsHitTesting(false)

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
            }
            .sheet(item: $selectedAttribute) { attr in
                NavigationStack { AttributeDetailView(attribute: attr) }
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

    // MARK: - Side status bar

    private var sideStatusBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(activeGraphName) · \(focusEntity == nil ? "Global" : "Fokus")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(focusEntity?.name ?? "Alle Entitäten")
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Divider().frame(height: 20)

            Text("N \(nodes.count) · L \(edges.count) · 📌 \(pinned.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var focusKey: NodeKey? {
        guard let f = focusEntity else { return nil }
        return NodeKey(kind: .entity, uuid: f.id)
    }

    private func pulseMiniMap() {
        miniMapPulseTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { miniMapEmphasized = true }
        miniMapPulseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.25)) { miniMapEmphasized = false }
        }
    }

    // MARK: - Spotlight edges (Nodes-only default + Degree cap)

    private func edgesForDisplay() -> [GraphEdge] {
        // ✅ Default: nodes-only (keine Linien)
        guard let sel = selection else { return [] }

        // ✅ Nur direkte Kanten des selektierten Nodes
        let incident = edges.filter { $0.a == sel || $0.b == sel }

        let containment = incident.filter { $0.type == .containment }
        var links = incident.filter { $0.type == .link }

        // stabilere Reihenfolge
        links.sort { displayLabel(for: otherEnd(of: $0, sel: sel)) < displayLabel(for: otherEnd(of: $1, sel: sel)) }

        if !showAllLinksForSelection {
            links = Array(links.prefix(degreeCap))
        }

        return (containment + links).unique()
    }

    private func otherEnd(of e: GraphEdge, sel: NodeKey) -> NodeKey {
        (e.a == sel) ? e.b : e.a
    }

    private func displayLabel(for key: NodeKey) -> String {
        // in nodes steckt nur "label" (Attribute nicht mit owner prefix) — daher hier smarter:
        switch key.kind {
        case .entity:
            return fetchEntity(id: key.uuid)?.name ?? (nodes.first(where: { $0.key == key })?.label ?? "")
        case .attribute:
            // displayName ist schöner (Owner · Attr)
            if let a = fetchAttribute(id: key.uuid) { return a.displayName }
            return nodes.first(where: { $0.key == key })?.label ?? ""
        }
    }

    private func hiddenLinkCountForSelection() -> Int {
        guard let sel = selection else { return 0 }
        if showAllLinksForSelection { return 0 }
        let incidentLinkCount = edges.filter { $0.type == .link && ($0.a == sel || $0.b == sel) }.count
        return max(0, incidentLinkCount - degreeCap)
    }

    // MARK: - Action chip

    private func actionChip(for node: GraphNode) -> some View {
        let isPinned = pinned.contains(node.key)
        let hiddenLinks = hiddenLinkCountForSelection()

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.key.kind == .entity ? "Entität" : "Attribut")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(nodeLabel(for: node))
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            // ✅ Degree cap “more”
            if hiddenLinks > 0 {
                Button {
                    showAllLinksForSelection = true
                } label: {
                    Label("Mehr (\(hiddenLinks))", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .help("Weitere Links dieser Node anzeigen")
            } else if showAllLinksForSelection {
                Button {
                    showAllLinksForSelection = false
                } label: {
                    Label("Weniger", systemImage: "chevron.up.circle")
                }
                .buttonStyle(.bordered)
            }

            // ✅ Expand
            Button {
                Task { await expand(from: node.key) }
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.bordered)
            .help("Nachbarn aufklappen")

            Button {
                cameraCommand = CameraCommand(kind: .center(node.key))
            } label: {
                Image(systemName: "dot.scope")
            }
            .buttonStyle(.bordered)

            if node.key.kind == .entity {
                Button {
                    if let e = fetchEntity(id: node.key.uuid) {
                        focusEntity = e
                        Task { await loadGraph() }
                        cameraCommand = CameraCommand(kind: .center(node.key))
                    }
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                openDetails(for: node.key)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)

            Button {
                if isPinned { pinned.remove(node.key) }
                else { pinned.insert(node.key) }
                velocities[node.key] = .zero
            } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.bordered)

            Button {
                selection = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6, y: 2)
        .frame(maxWidth: 640)
    }

    private func nodeLabel(for node: GraphNode) -> String {
        if node.key.kind == .attribute, let a = fetchAttribute(id: node.key.uuid) {
            return a.displayName
        }
        return node.label
    }

    private func openDetails(for key: NodeKey) {
        switch key.kind {
        case .entity:
            if let e = fetchEntity(id: key.uuid) { selectedEntity = e }
        case .attribute:
            if let a = fetchAttribute(id: key.uuid) { selectedAttribute = a }
        }
    }

    // MARK: - Inspector sheet

    private var inspectorSheet: some View {
        NavigationStack {
            Form {

                Section("Graph") {
                    HStack {
                        Text("Aktiv")
                        Spacer()
                        Text(activeGraphName).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Button {
                        showGraphPicker = true
                    } label: {
                        Label("Graph wechseln", systemImage: "square.stack.3d.up")
                    }
                }

                Section("Modus") {
                    HStack {
                        Text("Fokus")
                        Spacer()
                        Text(focusEntity?.name ?? "Keiner")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Picker("Arbeitsmodus", selection: $workMode) {
                            ForEach(WorkMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Button {
                        showFocusPicker = true
                    } label: {
                        Label("Fokus wählen", systemImage: "scope")
                    }

                    Button(role: .destructive) {
                        focusEntity = nil
                        selection = nil
                        Task { await loadGraph() }
                    } label: {
                        Label("Fokus löschen", systemImage: "xmark.circle")
                    }
                    .disabled(focusEntity == nil)
                }

                Section("Neighborhood") {
                    Stepper("Hops: \(hops)", value: $hops, in: 1...3)
                        .disabled(focusEntity == nil)

                    Toggle("Attribute anzeigen", isOn: $showAttributes)
                        .disabled(focusEntity == nil)
                }

                Section("Lens") {
                    Toggle("Lens aktiv", isOn: $lensEnabled)

                    Toggle("Nicht relevante ausblenden", isOn: $lensHideNonRelevant)
                        .disabled(!lensEnabled)

                    Stepper("Lens Tiefe: \(lensDepth)", value: $lensDepth, in: 1...2)
                        .disabled(!lensEnabled)

                    if selection != nil {
                        Text("Spotlight aktiv: Selection → nur direkte Nachbarn (Tiefe 1) + Rest ausgeblendet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Wenn eine Node ausgewählt ist, werden Nachbarn hervorgehoben und der Rest gedimmt (oder ausgeblendet).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Layout & Physics") {
                    Button {
                        stabilizeLayout()
                    } label: {
                        Label("Layout stabilisieren", systemImage: "pin.circle")
                    }
                    .disabled(nodes.isEmpty)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collisions: \(collisionStrength, format: .number.precision(.fractionLength(3)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $collisionStrength, in: 0.0...0.09, step: 0.005)
                    }

                    Text("Tipp: Wenn du viel overlap hast → Collisions hoch. Wenn es „zittert“ → Collisions runter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Limits") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max Nodes: \(maxNodes)").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(maxNodes) }, set: { maxNodes = Int($0) }),
                               in: 60...260, step: 10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max Links: \(maxLinks)").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(maxLinks) }, set: { maxLinks = Int($0) }),
                               in: 300...4000, step: 100)
                    }

                    Button {
                        Task { await loadGraph(resetLayout: true) }
                    } label: {
                        Label("Neu laden & layouten", systemImage: "wand.and.rays")
                    }
                }

                Section("Pins") {
                    HStack {
                        Text("Pinned")
                        Spacer()
                        Text("\(pinned.count)").foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        pinned.removeAll()
                    } label: {
                        Label("Unpin all", systemImage: "pin.slash")
                    }
                    .disabled(pinned.isEmpty)
                }
            }
            .navigationTitle("Inspector")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { showInspector = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stabilizeLayout() {
        let all = Set(nodes.map(\.key))
        pinned = all
        for k in all {
            velocities[k] = .zero
        }
    }

    // MARK: - Views

    private func errorView(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Fehler").font(.headline)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await loadGraph() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Noch nichts zu sehen").font(.headline)
            Text("Lege Entitäten und Links an – dann Fokus setzen oder global anzeigen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Data loading

    @MainActor
    private func ensureActiveGraphAndLoadIfNeeded() async {
        if activeGraphID == nil, let first = graphs.first {
            activeGraphIDString = first.id.uuidString
            return
        }
        await loadGraph()
    }

    @MainActor
    private func loadGraph(resetLayout: Bool = true) async {
        isLoading = true
        loadError = nil

        do {
            if let focus = focusEntity {
                try loadNeighborhood(centerID: focus.id, hops: hops, includeAttributes: showAttributes)
            } else {
                try loadGlobal()
            }

            let nodeKeys = Set(nodes.map(\.key))
            pinned = pinned.intersection(nodeKeys)
            if let sel = selection, !nodeKeys.contains(sel) { selection = nil }

            let validDirected = Set(edges.flatMap {
                [
                    DirectedEdgeKey.make(source: $0.a, target: $0.b, type: $0.type),
                    DirectedEdgeKey.make(source: $0.b, target: $0.a, type: $0.type)
                ]
            })
            directedEdgeNotes = directedEdgeNotes.filter { validDirected.contains($0.key) }

            if resetLayout { seedLayout(preservePinned: true) }
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func loadGlobal() throws {
        var eFD: FetchDescriptor<MetaEntity>
        if let gid = activeGraphID {
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in e.graphID == gid || e.graphID == nil },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            eFD = FetchDescriptor(sortBy: [SortDescriptor(\MetaEntity.name)])
        }
        eFD.fetchLimit = maxNodes
        let ents = try modelContext.fetch(eFD)

        let kEntity = NodeKind.entity.rawValue
        var lFD: FetchDescriptor<MetaLink>
        if let gid = activeGraphID {
            lFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    (l.graphID == gid || l.graphID == nil) &&
                    l.sourceKindRaw == kEntity && l.targetKindRaw == kEntity
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        } else {
            lFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    l.sourceKindRaw == kEntity && l.targetKindRaw == kEntity
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        }
        lFD.fetchLimit = maxLinks
        let links = try modelContext.fetch(lFD)

        let nodeIDs = Set(ents.map { $0.id })
        let filteredLinks = links.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }

        nodes = ents.map { GraphNode(key: NodeKey(kind: .entity, uuid: $0.id), label: $0.name) }

        var notes: [DirectedEdgeKey: String] = [:]
        edges = filteredLinks.map { l in
            let s = NodeKey(kind: .entity, uuid: l.sourceID)
            let t = NodeKey(kind: .entity, uuid: l.targetID)

            if let n = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                let k = DirectedEdgeKey.make(source: s, target: t, type: .link)
                if notes[k] == nil { notes[k] = n }
            }

            return GraphEdge(a: s, b: t, type: .link)
        }.unique()

        directedEdgeNotes = notes
    }

    private func loadNeighborhood(centerID: UUID, hops: Int, includeAttributes: Bool) throws {
        let kEntity = NodeKind.entity.rawValue
        let gid = activeGraphID

        var visitedEntities: Set<UUID> = [centerID]
        var frontier: Set<UUID> = [centerID]
        var collectedEntityLinks: [MetaLink] = []

        for _ in 1...hops {
            if visitedEntities.count >= maxNodes { break }

            var next: Set<UUID> = []

            for nodeID in frontier {
                if visitedEntities.count >= maxNodes { break }

                let nID = nodeID

                var outFD: FetchDescriptor<MetaLink>
                if let gid {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.sourceID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.sourceID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                outFD.fetchLimit = maxLinks
                let outLinks = (try? modelContext.fetch(outFD)) ?? []

                for l in outLinks {
                    collectedEntityLinks.append(l)
                    next.insert(l.targetID)
                    if collectedEntityLinks.count >= maxLinks { break }
                }

                if collectedEntityLinks.count >= maxLinks { break }

                var inFD: FetchDescriptor<MetaLink>
                if let gid {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.targetID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.targetID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                inFD.fetchLimit = maxLinks
                let inLinks = (try? modelContext.fetch(inFD)) ?? []

                for l in inLinks {
                    collectedEntityLinks.append(l)
                    next.insert(l.sourceID)
                    if collectedEntityLinks.count >= maxLinks { break }
                }
            }

            next.subtract(visitedEntities)
            visitedEntities.formUnion(next)
            frontier = next
            if frontier.isEmpty { break }
        }

        var ents: [MetaEntity] = []
        ents.reserveCapacity(min(visitedEntities.count, maxNodes))
        for id in visitedEntities.prefix(maxNodes) {
            if let e = fetchEntity(id: id) { ents.append(e) }
        }
        ents.sort { $0.name < $1.name }

        var attrs: [MetaAttribute] = []
        if includeAttributes {
            let remaining = max(0, maxNodes - ents.count)
            if remaining > 0 {
                for e in ents {
                    let sortedAttrs = e.attributesList.sorted { $0.name < $1.name }
                    for a in sortedAttrs {
                        if let gid, !(a.graphID == gid || a.graphID == nil) { continue }
                        attrs.append(a)
                        if attrs.count >= remaining { break }
                    }
                    if attrs.count >= remaining { break }
                }
            }
        }

        var newNodes: [GraphNode] = []
        newNodes.reserveCapacity(ents.count + attrs.count)
        for e in ents { newNodes.append(GraphNode(key: NodeKey(kind: .entity, uuid: e.id), label: e.name)) }
        for a in attrs { newNodes.append(GraphNode(key: NodeKey(kind: .attribute, uuid: a.id), label: a.name)) }

        let nodeKeySet = Set(newNodes.map(\.key))

        var notes: [DirectedEdgeKey: String] = [:]
        var newEdges: [GraphEdge] = []
        newEdges.reserveCapacity(maxLinks)

        for l in collectedEntityLinks {
            let a = NodeKey(kind: .entity, uuid: l.sourceID)
            let b = NodeKey(kind: .entity, uuid: l.targetID)
            if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                newEdges.append(GraphEdge(a: a, b: b, type: .link))

                if let n = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    let k = DirectedEdgeKey.make(source: a, target: b, type: .link)
                    if notes[k] == nil { notes[k] = n }
                }
            }
            if newEdges.count >= maxLinks { break }
        }

        if includeAttributes {
            var attrOwner: [UUID: UUID] = [:]
            for e in ents { for a in e.attributesList { attrOwner[a.id] = e.id } }

            for a in attrs {
                if let ownerID = attrOwner[a.id] {
                    let ek = NodeKey(kind: .entity, uuid: ownerID)
                    let ak = NodeKey(kind: .attribute, uuid: a.id)
                    if nodeKeySet.contains(ek) && nodeKeySet.contains(ak) {
                        newEdges.append(GraphEdge(a: ek, b: ak, type: .containment))
                    }
                    if newEdges.count >= maxLinks { break }
                }
            }
        }

        if includeAttributes, newEdges.count < maxLinks {
            let remaining = maxLinks - newEdges.count
            let perNodeCap = max(20, remaining / max(1, newNodes.count))

            var linkEdges: [GraphEdge] = []

            for n in newNodes {
                if linkEdges.count >= remaining { break }
                let k = n.key.kind.rawValue
                let id = n.key.uuid

                var outFD: FetchDescriptor<MetaLink>
                if let gid {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.sourceKindRaw == k && l.sourceID == id
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in l.sourceKindRaw == k && l.sourceID == id },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                outFD.fetchLimit = perNodeCap
                let out = (try? modelContext.fetch(outFD)) ?? []

                for l in out {
                    let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                    let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)
                    if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                        linkEdges.append(GraphEdge(a: a, b: b, type: .link))

                        if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                            if notes[dk] == nil { notes[dk] = note }
                        }
                    }
                    if linkEdges.count >= remaining { break }
                }

                if linkEdges.count >= remaining { break }

                var inFD: FetchDescriptor<MetaLink>
                if let gid {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.targetKindRaw == k && l.targetID == id
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in l.targetKindRaw == k && l.targetID == id },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                inFD.fetchLimit = perNodeCap
                let inc = (try? modelContext.fetch(inFD)) ?? []

                for l in inc {
                    let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                    let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)
                    if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                        linkEdges.append(GraphEdge(a: a, b: b, type: .link))

                        if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                            if notes[dk] == nil { notes[dk] = note }
                        }
                    }
                    if linkEdges.count >= remaining { break }
                }
            }

            newEdges.append(contentsOf: linkEdges.unique().prefix(remaining))
        }

        nodes = newNodes
        edges = newEdges.unique()
        directedEdgeNotes = notes
    }

    // MARK: - Expand (incremental)

    @MainActor
    private func expand(from key: NodeKey) async {
        if nodes.isEmpty { return }
        if nodes.count >= maxNodes { return }

        isLoading = true
        defer { isLoading = false }

        let existingKeys = Set(nodes.map(\.key))
        var newKeys: [NodeKey] = []
        var newEdges: [GraphEdge] = []
        var newNotes = directedEdgeNotes

        func ensureNode(_ nk: NodeKey) {
            guard !existingKeys.contains(nk) else { return }
            if !newKeys.contains(nk) { newKeys.append(nk) }
        }

        func labelFor(_ nk: NodeKey) -> String? {
            switch nk.kind {
            case .entity:
                return fetchEntity(id: nk.uuid)?.name
            case .attribute:
                return fetchAttribute(id: nk.uuid)?.name
            }
        }

        let kindRaw = key.kind.rawValue
        let id = key.uuid

        let perExpandCap = min(220, max(40, maxLinks / 6))
        let gid = activeGraphID

        var outFD: FetchDescriptor<MetaLink>
        var inFD: FetchDescriptor<MetaLink>

        if let gid {
            outFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    (l.graphID == gid || l.graphID == nil) &&
                    l.sourceKindRaw == kindRaw && l.sourceID == id
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
            inFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    (l.graphID == gid || l.graphID == nil) &&
                    l.targetKindRaw == kindRaw && l.targetID == id
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        } else {
            outFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in l.sourceKindRaw == kindRaw && l.sourceID == id },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
            inFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in l.targetKindRaw == kindRaw && l.targetID == id },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        }

        outFD.fetchLimit = perExpandCap
        inFD.fetchLimit = perExpandCap

        let outLinks = (try? modelContext.fetch(outFD)) ?? []
        let inLinks = (try? modelContext.fetch(inFD)) ?? []

        for l in outLinks {
            let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
            let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)

            if !existingKeys.contains(b) && (existingKeys.count + newKeys.count) >= maxNodes { break }

            ensureNode(a)
            ensureNode(b)
            newEdges.append(GraphEdge(a: a, b: b, type: .link))

            if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                if newNotes[dk] == nil { newNotes[dk] = note }
            }
            if (edges.count + newEdges.count) >= maxLinks { break }
        }

        if (edges.count + newEdges.count) < maxLinks {
            for l in inLinks {
                let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)

                if !existingKeys.contains(a) && (existingKeys.count + newKeys.count) >= maxNodes { break }

                ensureNode(a)
                ensureNode(b)
                newEdges.append(GraphEdge(a: a, b: b, type: .link))

                if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                    if newNotes[dk] == nil { newNotes[dk] = note }
                }
                if (edges.count + newEdges.count) >= maxLinks { break }
            }
        }

        if showAttributes {
            switch key.kind {
            case .entity:
                if let e = fetchEntity(id: key.uuid) {
                    let remaining = max(0, maxNodes - (existingKeys.count + newKeys.count))
                    if remaining > 0 {
                        let sortedAttrs = e.attributesList.sorted { $0.name < $1.name }
                        for a in sortedAttrs.prefix(remaining) {
                            if let gid, !(a.graphID == gid || a.graphID == nil) { continue }
                            let ak = NodeKey(kind: .attribute, uuid: a.id)
                            ensureNode(ak)
                            newEdges.append(GraphEdge(a: key, b: ak, type: .containment))
                            if (edges.count + newEdges.count) >= maxLinks { break }
                        }
                    }
                }
            case .attribute:
                if let a = fetchAttribute(id: key.uuid), let owner = a.owner {
                    let ek = NodeKey(kind: .entity, uuid: owner.id)
                    if !existingKeys.contains(ek), (existingKeys.count + newKeys.count) < maxNodes {
                        ensureNode(ek)
                    }
                    newEdges.append(GraphEdge(a: ek, b: key, type: .containment))
                }
            }
        }

        var appendedNodes: [GraphNode] = []
        appendedNodes.reserveCapacity(newKeys.count)

        for nk in newKeys {
            guard let label = labelFor(nk) else { continue }
            appendedNodes.append(GraphNode(key: nk, label: label))
        }

        if appendedNodes.isEmpty && newEdges.isEmpty {
            return
        }

        nodes.append(contentsOf: appendedNodes)

        let mergedEdges = (edges + newEdges).unique()
        edges = Array(mergedEdges.prefix(maxLinks))

        directedEdgeNotes = newNotes

        seedNewNodesNear(key, newNodeKeys: appendedNodes.map(\.key))
    }

    @MainActor
    private func seedNewNodesNear(_ centerKey: NodeKey, newNodeKeys: [NodeKey]) {
        guard !newNodeKeys.isEmpty else { return }
        guard let cp = positions[centerKey] else {
            for (i, k) in newNodeKeys.enumerated() {
                let angle = (CGFloat(i) / CGFloat(max(1, newNodeKeys.count))) * (.pi * 2)
                let p = CGPoint(x: cos(angle) * 140, y: sin(angle) * 140)
                positions[k] = p
                velocities[k] = .zero
            }
            return
        }

        let rBase: CGFloat = 90
        for (i, k) in newNodeKeys.enumerated() {
            if positions[k] != nil { continue }
            let angle = (CGFloat(i) / CGFloat(max(1, newNodeKeys.count))) * (.pi * 2)
            let r = rBase + CGFloat((i % 4)) * 14
            let p = CGPoint(x: cp.x + cos(angle) * r, y: cp.y + sin(angle) * r)
            positions[k] = p
            velocities[k] = .zero
        }
    }

    // MARK: - Helpers

    private func nodeForKey(_ key: NodeKey) -> GraphNode? {
        nodes.first(where: { $0.key == key })
    }

    private func fetchEntity(id: UUID) -> MetaEntity? {
        let nodeID = id
        let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in e.id == nodeID })
        guard let e = try? modelContext.fetch(fd).first else { return nil }
        if let gid = activeGraphID {
            return (e.graphID == gid || e.graphID == nil) ? e : nil
        }
        return e
    }

    private func fetchAttribute(id: UUID) -> MetaAttribute? {
        let nodeID = id
        let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in a.id == nodeID })
        guard let a = try? modelContext.fetch(fd).first else { return nil }
        if let gid = activeGraphID {
            return (a.graphID == gid || a.graphID == nil) ? a : nil
        }
        return a
    }

    private func selectedImagePath() -> String? {
        guard let sel = selection else { return nil }
        switch sel.kind {
        case .entity:
            return fetchEntity(id: sel.uuid)?.imagePath
        case .attribute:
            return fetchAttribute(id: sel.uuid)?.imagePath
        }
    }

    private var selectedImagePathValue: String? { selectedImagePath() }

    private func prefetchSelectedFullImage() {
        let path = selectedImagePathValue
        guard path != cachedFullImagePath else { return }

        cachedFullImagePath = path
        cachedFullImage = nil

        guard let path, !path.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let img = ImageStore.loadUIImage(path: path)
            DispatchQueue.main.async {
                if cachedFullImagePath == path {
                    cachedFullImage = img
                }
            }
        }
    }

    private func seedLayout(preservePinned: Bool) {
        let oldPos = positions

        positions.removeAll(keepingCapacity: true)
        velocities.removeAll(keepingCapacity: true)
        guard !nodes.isEmpty else { return }

        if preservePinned {
            for k in pinned {
                if let p = oldPos[k] {
                    positions[k] = p
                    velocities[k] = .zero
                }
            }
        }

        let entityNodes = nodes.filter { $0.key.kind == .entity }
        let attrNodes = nodes.filter { $0.key.kind == .attribute }

        let radius: CGFloat = 220
        for (i, n) in entityNodes.enumerated() {
            if pinned.contains(n.key), positions[n.key] != nil { continue }
            let angle = (CGFloat(i) / CGFloat(max(1, entityNodes.count))) * (.pi * 2)
            let p = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            positions[n.key] = p
            velocities[n.key] = .zero
        }

        let containment = edges.filter { $0.type == .containment }
        var owner: [NodeKey: [NodeKey]] = [:]
        for e in containment {
            if e.a.kind == .entity && e.b.kind == .attribute {
                owner[e.a, default: []].append(e.b)
            } else if e.b.kind == .entity && e.a.kind == .attribute {
                owner[e.b, default: []].append(e.a)
            }
        }

        for a in attrNodes {
            if pinned.contains(a.key), positions[a.key] != nil { continue }
            positions[a.key] = positions[a.key] ?? CGPoint(x: 0, y: 0)
            velocities[a.key] = .zero
        }

        let satRadius: CGFloat = 70
        for (ek, attrs) in owner {
            guard let ep = positions[ek] else { continue }
            for (i, ak) in attrs.enumerated() {
                if pinned.contains(ak), positions[ak] != nil { continue }
                let angle = (CGFloat(i) / CGFloat(max(1, attrs.count))) * (.pi * 2)
                let p = CGPoint(x: ep.x + cos(angle) * satRadius, y: ep.y + sin(angle) * satRadius)
                positions[ak] = p
                velocities[ak] = .zero
            }
        }
    }
}
