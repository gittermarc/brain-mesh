//
//  GraphCanvasScreen.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData
import UIKit

enum WorkMode: String, CaseIterable, Identifiable {
    case explore
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: return "Explore"
        case .edit: return "Edit"
        }
    }

    var icon: String {
        switch self {
        case .explore: return "hand.draw"
        case .edit: return "pencil.tip"
        }
    }
}


struct GraphCanvasScreen: View {
    @Environment(\.modelContext) private var modelContext

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

    // Global filter (nur wenn kein Fokus)
    @State private var searchText: String = ""

    // Performance knobs
    @State private var maxNodes: Int = 140
    @State private var maxLinks: Int = 800

    // Graph
    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []
    @State private var positions: [NodeKey: CGPoint] = [:]
    @State private var velocities: [NodeKey: CGVector] = [:]

    // ✅ Notizen GERICHETET: source -> target
    @State private var directedEdgeNotes: [DirectedEdgeKey: String] = [:]

    // Pinning + Selection
    @State private var pinned: Set<NodeKey> = []
    @State private var selection: NodeKey? = nil

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

    private let debounceNanos: UInt64 = 250_000_000

    var body: some View {
        let lens = LensContext.build(
            enabled: lensEnabled,
            hideNonRelevant: lensHideNonRelevant,
            depth: lensDepth,
            selection: selection,
            edges: edges
        )

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
                        edges: edges,
                        directedEdgeNotes: directedEdgeNotes,
                        lens: lens,
                        workMode: workMode,
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

                // MiniMap
                GeometryReader { geo in
                    MiniMapView(
                        nodes: nodes,
                        edges: edges,
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

            // Initial load
            .task { await loadGraph() }

            // Global filter reload (nur global)
            .task(id: searchText) {
                guard focusEntity == nil else { return }
                isLoading = true
                try? await Task.sleep(nanoseconds: debounceNanos)
                if Task.isCancelled { return }
                await loadGraph()
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
        .onChange(of: selection) { _, _ in prefetchSelectedFullImage() }
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
                Text(focusEntity == nil ? "Global" : "Fokus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(focusEntity?.name ?? (BMSearch.fold(searchText).isEmpty ? "Alle Entitäten" : "Filter: \(searchText)"))
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

    // MARK: - Action chip

    private func actionChip(for node: GraphNode) -> some View {
        let isPinned = pinned.contains(node.key)

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
        .frame(maxWidth: 560)
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

                    Text("Wenn eine Node ausgewählt ist, werden Nachbarn hervorgehoben und der Rest gedimmt (oder ausgeblendet).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Global") {
                    TextField("Filter (Entitätenname)…", text: $searchText)
                        .disabled(focusEntity != nil)
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
        let folded = BMSearch.fold(searchText)

        var eFD: FetchDescriptor<MetaEntity>
        if folded.isEmpty {
            eFD = FetchDescriptor(sortBy: [SortDescriptor(\MetaEntity.name)])
        } else {
            let term = folded
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in e.nameFolded.contains(term) },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }
        eFD.fetchLimit = maxNodes
        let ents = try modelContext.fetch(eFD)

        let kEntity = NodeKind.entity.rawValue
        var lFD = FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { l in
                l.sourceKindRaw == kEntity && l.targetKindRaw == kEntity
            },
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
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

        var visitedEntities: Set<UUID> = [centerID]
        var frontier: Set<UUID> = [centerID]
        var collectedEntityLinks: [MetaLink] = []

        for _ in 1...hops {
            if visitedEntities.count >= maxNodes { break }

            var next: Set<UUID> = []

            for nodeID in frontier {
                if visitedEntities.count >= maxNodes { break }

                let nID = nodeID

                var outFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate<MetaLink> { l in
                        l.sourceKindRaw == kEntity &&
                        l.targetKindRaw == kEntity &&
                        l.sourceID == nID
                    },
                    sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                )
                outFD.fetchLimit = maxLinks
                let outLinks = (try? modelContext.fetch(outFD)) ?? []

                for l in outLinks {
                    collectedEntityLinks.append(l)
                    next.insert(l.targetID)
                    if collectedEntityLinks.count >= maxLinks { break }
                }

                if collectedEntityLinks.count >= maxLinks { break }

                var inFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate<MetaLink> { l in
                        l.sourceKindRaw == kEntity &&
                        l.targetKindRaw == kEntity &&
                        l.targetID == nID
                    },
                    sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                )
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

                var outFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate<MetaLink> { l in l.sourceKindRaw == k && l.sourceID == id },
                    sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                )
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

                var inFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate<MetaLink> { l in l.targetKindRaw == k && l.targetID == id },
                    sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                )
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

        // Helper: label fetch
        func labelFor(_ nk: NodeKey) -> String? {
            switch nk.kind {
            case .entity:
                return fetchEntity(id: nk.uuid)?.name
            case .attribute:
                return fetchAttribute(id: nk.uuid)?.name
            }
        }

        // Expand Links (out + in)
        let kindRaw = key.kind.rawValue
        let id = key.uuid

        let perExpandCap = min(220, max(40, maxLinks / 6))

        var outFD = FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { l in
                l.sourceKindRaw == kindRaw && l.sourceID == id
            },
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
        outFD.fetchLimit = perExpandCap

        var inFD = FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { l in
                l.targetKindRaw == kindRaw && l.targetID == id
            },
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
        inFD.fetchLimit = perExpandCap

        let outLinks = (try? modelContext.fetch(outFD)) ?? []
        let inLinks = (try? modelContext.fetch(inFD)) ?? []

        // Build candidate edges
        for l in outLinks {
            let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
            let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)

            // respect max nodes
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

                // respect max nodes
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

        // Expand containment (attributes of entity / owner of attribute)
        if showAttributes {
            switch key.kind {
            case .entity:
                if let e = fetchEntity(id: key.uuid) {
                    let remaining = max(0, maxNodes - (existingKeys.count + newKeys.count))
                    if remaining > 0 {
                        let sortedAttrs = e.attributesList.sorted { $0.name < $1.name }
                        for a in sortedAttrs.prefix(remaining) {
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

        // Materialize new nodes with labels
        var appendedNodes: [GraphNode] = []
        appendedNodes.reserveCapacity(newKeys.count)

        for nk in newKeys {
            guard let label = labelFor(nk) else { continue }
            appendedNodes.append(GraphNode(key: nk, label: label))
        }

        if appendedNodes.isEmpty && newEdges.isEmpty {
            return
        }

        // Merge
        nodes.append(contentsOf: appendedNodes)

        let mergedEdges = (edges + newEdges).unique()
        edges = Array(mergedEdges.prefix(maxLinks))

        directedEdgeNotes = newNotes

        // Seed positions for new nodes near the expanded node
        seedNewNodesNear(key, newNodeKeys: appendedNodes.map(\.key))
    }

    @MainActor
    private func seedNewNodesNear(_ centerKey: NodeKey, newNodeKeys: [NodeKey]) {
        guard !newNodeKeys.isEmpty else { return }
        guard let cp = positions[centerKey] else {
            // Fallback: just place them around origin
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
        return try? modelContext.fetch(fd).first
    }

    private func fetchAttribute(id: UUID) -> MetaAttribute? {
        let nodeID = id
        let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in a.id == nodeID })
        return try? modelContext.fetch(fd).first
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
    
    private var selectedImagePathValue: String? {
        selectedImagePath()
    }

    private func prefetchSelectedFullImage() {
        let path = selectedImagePathValue
        guard path != cachedFullImagePath else { return }   // nichts zu tun

        cachedFullImagePath = path
        cachedFullImage = nil

        guard let path, !path.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let img = ImageStore.loadUIImage(path: path)
            DispatchQueue.main.async {
                // nur übernehmen, wenn inzwischen nicht umselected wurde
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
            let list = attrs
            for (i, ak) in list.enumerated() {
                if pinned.contains(ak), positions[ak] != nil { continue }
                let angle = (CGFloat(i) / CGFloat(max(1, list.count))) * (.pi * 2)
                let p = CGPoint(x: ep.x + cos(angle) * satRadius, y: ep.y + sin(angle) * satRadius)
                positions[ak] = p
                velocities[ak] = .zero
            }
        }
    }
}

// MARK: - Lens

private struct LensContext: Equatable {
    let enabled: Bool
    let hideNonRelevant: Bool
    let depth: Int
    let selection: NodeKey?
    let distance: [NodeKey: Int]
    let relevant: Set<NodeKey>

    static func build(enabled: Bool, hideNonRelevant: Bool, depth: Int, selection: NodeKey?, edges: [GraphEdge]) -> LensContext {
        guard enabled, let s = selection else {
            return LensContext(enabled: false, hideNonRelevant: false, depth: depth, selection: selection, distance: [:], relevant: [])
        }

        // adjacency (edges sind klein; maxLinks ~ 800 -> ok)
        var adj: [NodeKey: [NodeKey]] = [:]
        adj.reserveCapacity(edges.count * 2)
        for e in edges {
            adj[e.a, default: []].append(e.b)
            adj[e.b, default: []].append(e.a)
        }

        var dist: [NodeKey: Int] = [s: 0]
        var q: [NodeKey] = [s]
        var idx = 0

        while idx < q.count {
            let cur = q[idx]; idx += 1
            let d = dist[cur, default: 0]
            if d >= depth { continue }
            for nb in adj[cur, default: []] {
                if dist[nb] == nil {
                    dist[nb] = d + 1
                    q.append(nb)
                }
            }
        }

        let rel = Set(dist.keys)
        return LensContext(enabled: true, hideNonRelevant: hideNonRelevant, depth: depth, selection: s, distance: dist, relevant: rel)
    }

    func nodeOpacity(_ k: NodeKey) -> CGFloat {
        guard enabled, let d = distance[k] else { return hideNonRelevant ? 0.0 : 0.12 }
        switch d {
        case 0: return 1.0
        case 1: return 0.92
        case 2: return 0.55
        default: return hideNonRelevant ? 0.0 : 0.12
        }
    }

    func edgeOpacity(a: NodeKey, b: NodeKey) -> CGFloat {
        guard enabled else { return 1.0 }
        let da = distance[a]
        let db = distance[b]
        if da == nil || db == nil { return hideNonRelevant ? 0.0 : 0.10 }
        let m = max(da!, db!)
        if m <= 1 { return 0.95 }
        if m == 2 { return 0.55 }
        return hideNonRelevant ? 0.0 : 0.10
    }

    func isHidden(_ k: NodeKey) -> Bool {
        enabled && hideNonRelevant && distance[k] == nil
    }
}

// MARK: - MiniMap View

private struct MiniMapView: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let positions: [NodeKey: CGPoint]

    let selection: NodeKey?
    let focus: NodeKey?

    let scale: CGFloat
    let pan: CGSize
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, size in
            guard let bounds = worldBounds() else {
                let frame = CGRect(origin: .zero, size: size)
                context.stroke(Path(roundedRect: frame, cornerRadius: 12),
                               with: .color(.secondary.opacity(0.25)),
                               lineWidth: 1)
                return
            }

            let worldRect = bounds.insetBy(dx: -60, dy: -60)

            func map(_ p: CGPoint) -> CGPoint {
                let nx = (p.x - worldRect.minX) / max(1, worldRect.width)
                let ny = (p.y - worldRect.minY) / max(1, worldRect.height)
                return CGPoint(x: nx * size.width, y: ny * size.height)
            }

            for e in edges {
                guard let p1 = positions[e.a], let p2 = positions[e.b] else { continue }
                let a = map(p1)
                let b = map(p2)

                var path = Path()
                path.move(to: a)
                path.addLine(to: b)

                switch e.type {
                case .containment:
                    context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                case .link:
                    context.stroke(path, with: .color(.secondary.opacity(0.28)), lineWidth: 1)
                }
            }

            for n in nodes {
                guard let p = positions[n.key] else { continue }
                let s = map(p)

                let isFocus = (focus == n.key)
                let isSel = (selection == n.key)

                let r: CGFloat = (n.key.kind == .entity) ? 3.2 : 2.6
                let dot = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dot), with: .color(.primary.opacity(0.55)))

                if isFocus || isSel {
                    let rr: CGFloat = isSel ? 7.0 : 5.8
                    let ring = CGRect(x: s.x - rr, y: s.y - rr, width: rr * 2, height: rr * 2)
                    context.stroke(Path(ellipseIn: ring),
                                   with: .color(.primary.opacity(0.9)),
                                   lineWidth: isSel ? 2 : 1)
                }
            }

            let v = viewportWorldRect()
            let tl = map(CGPoint(x: v.minX, y: v.minY))
            let br = map(CGPoint(x: v.maxX, y: v.maxY))

            let vRect = CGRect(
                x: min(tl.x, br.x),
                y: min(tl.y, br.y),
                width: abs(br.x - tl.x),
                height: abs(br.y - tl.y)
            )

            context.stroke(Path(roundedRect: vRect, cornerRadius: 8),
                           with: .color(.primary.opacity(0.75)),
                           lineWidth: 2)

            let frame = CGRect(origin: .zero, size: size)
            context.stroke(Path(roundedRect: frame, cornerRadius: 12),
                           with: .color(.secondary.opacity(0.25)),
                           lineWidth: 1)
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6, y: 2)
    }

    private func worldBounds() -> CGRect? {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        var any = false
        for n in nodes {
            guard let p = positions[n.key] else { continue }
            any = true
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        guard any else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func viewportWorldRect() -> CGRect {
        let centerX = canvasSize.width / 2 + pan.width
        let centerY = canvasSize.height / 2 + pan.height

        let tl = CGPoint(x: (0 - centerX) / scale, y: (0 - centerY) / scale)
        let br = CGPoint(x: (canvasSize.width - centerX) / scale, y: (canvasSize.height - centerY) / scale)

        return CGRect(
            x: min(tl.x, br.x),
            y: min(tl.y, br.y),
            width: abs(br.x - tl.x),
            height: abs(br.y - tl.y)
        )
    }
}

// MARK: - Graph types

struct NodeKey: Hashable {
    let kind: NodeKind
    let uuid: UUID
    var identifier: String { "\(kind.rawValue)-\(uuid.uuidString)" }
}

struct GraphNode: Identifiable, Hashable {
    let key: NodeKey
    let label: String
    var id: String { key.identifier }
}

enum GraphEdgeType: Int, Hashable {
    case link = 0
    case containment = 1
}

struct GraphEdge: Hashable {
    let a: NodeKey
    let b: NodeKey
    let type: GraphEdgeType

    init(a: NodeKey, b: NodeKey, type: GraphEdgeType) {
        if a.identifier <= b.identifier {
            self.a = a; self.b = b
        } else {
            self.a = b; self.b = a
        }
        self.type = type
    }
}

extension Array where Element == GraphEdge {
    func unique() -> [GraphEdge] { Array(Set(self)) }
}

// ✅ Directed notes key: source -> target
struct DirectedEdgeKey: Hashable {
    let sourceID: String
    let targetID: String
    let type: Int

    static func make(source: NodeKey, target: NodeKey, type: GraphEdgeType) -> DirectedEdgeKey {
        DirectedEdgeKey(sourceID: source.identifier, targetID: target.identifier, type: type.rawValue)
    }
}

// MARK: - Camera commands

struct CameraCommand: Identifiable, Equatable {
    enum Kind: Equatable {
        case center(NodeKey)
        case fitAll
        case reset
    }
    let id = UUID()
    let kind: Kind
}

// MARK: - Graph Canvas View (Selection + Drag/Pin + Camera commands + Lens)

struct GraphCanvasView: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let directedEdgeNotes: [DirectedEdgeKey: String]
    fileprivate let lens: LensContext

    let workMode: WorkMode

    // ✅ Thumbnail support (nur Selection)
    let selectedImagePath: String?
    let onTapSelectedThumbnail: () -> Void

    @Binding var positions: [NodeKey: CGPoint]
    @Binding var velocities: [NodeKey: CGVector]
    @Binding var pinned: Set<NodeKey>
    @Binding var selection: NodeKey?

    @Binding var scale: CGFloat
    @Binding var pan: CGSize
    @Binding var cameraCommand: CameraCommand?

    let onTapNode: (NodeKey?) -> Void

    @State private var timer: Timer?
    @State private var panStart: CGSize = .zero
    @State private var scaleStart: CGFloat = 1.0

    // drag state
    @State private var draggingKey: NodeKey?
    @State private var dragStartWorld: CGPoint = .zero
    @State private var dragStartPan: CGSize = .zero

    // ✅ cache thumbnail (wichtig: NICHT pro Frame von Disk lesen)
    @State private var cachedThumbPath: String?
    @State private var cachedThumb: UIImage?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            // ✅ Semantic zoom opacities (weich, kein hartes “an/aus”)
            let entityLabelAlpha = fade(scale, from: 0.82, to: 0.98)          // mid
            let attributeLabelAlpha = fade(scale, from: 1.28, to: 1.48)        // near
            let noteAlpha = fade(scale, from: 1.36, to: 1.56)                  // near+
            let showNotes = noteAlpha > 0.02

            // ✅ Thumbnail nur "near"
            let thumbAlpha = fade(scale, from: 1.26, to: 1.42)

            ZStack {
                Canvas { context, _ in
                    let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

                    // edges
                    for e in edges {
                        if lens.hideNonRelevant && (lens.isHidden(e.a) || lens.isHidden(e.b)) {
                            continue
                        }

                        guard let p1 = positions[e.a], let p2 = positions[e.b] else { continue }
                        let a = toScreen(p1, center: center)
                        let b = toScreen(p2, center: center)

                        let edgeAlpha = lens.edgeOpacity(a: e.a, b: e.b)

                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)

                        let zoomEdgeFactor = max(0.65, min(1.0, scale / 1.0))
                        let baseLink = 0.40 * edgeAlpha * zoomEdgeFactor
                        let baseContain = 0.22 * edgeAlpha * zoomEdgeFactor

                        switch e.type {
                        case .containment:
                            context.stroke(path, with: .color(.secondary.opacity(baseContain)), lineWidth: 1)
                        case .link:
                            context.stroke(path, with: .color(.secondary.opacity(baseLink)), lineWidth: 1)
                        }

                        // ✅ Notizen: nur im Nah-Zoom und nur für Kanten der selektierten Node (ausgehend)
                        if showNotes, let sel = selection, e.type == .link {
                            if sel == e.a {
                                drawOutgoingNoteIfAny(source: e.a, target: e.b, from: a, to: b, alpha: noteAlpha, in: context)
                            } else if sel == e.b {
                                drawOutgoingNoteIfAny(source: e.b, target: e.a, from: b, to: a, alpha: noteAlpha, in: context)
                            }
                        }
                    }

                    // nodes
                    for n in nodes {
                        if lens.hideNonRelevant && lens.isHidden(n.key) { continue }
                        guard let p = positions[n.key] else { continue }
                        let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                        let s = toScreen(p, center: center)

                        let isPinned = pinned.contains(n.key)
                        let isSelected = (selection == n.key)

                        let nodeAlpha = lens.nodeOpacity(n.key)

                        switch n.key.kind {
                        case .entity:
                            let r: CGFloat = 16
                            let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)

                            context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity((isPinned ? 0.22 : 0.15) * nodeAlpha)))
                            context.stroke(
                                Path(ellipseIn: rect),
                                with: .color(.primary.opacity((isSelected ? 0.95 : (isPinned ? 0.80 : 0.55)) * nodeAlpha)),
                                lineWidth: isSelected ? 3 : (isPinned ? 2 : 1)
                            )

                            let labelA = max(entityLabelAlpha, isSelected ? 1.0 : 0.0) * nodeAlpha
                            if labelA > 0.06 {
                                context.draw(
                                    Text(n.label).font(.caption).foregroundStyle(.primary.opacity(labelA)),
                                    at: CGPoint(x: s.x, y: s.y + 26),
                                    anchor: .center
                                )
                            }

                            if isPinned && (entityLabelAlpha > 0.25 || isSelected) && nodeAlpha > 0.20 {
                                context.draw(Text("📌").font(.caption2),
                                             at: CGPoint(x: s.x + 18, y: s.y - 18),
                                             anchor: .center)
                            }

                        case .attribute:
                            let w: CGFloat = 28
                            let h: CGFloat = 22
                            let rect = CGRect(x: s.x - w/2, y: s.y - h/2, width: w, height: h)
                            let rr = Path(roundedRect: rect, cornerRadius: 6)

                            context.fill(rr, with: .color(.primary.opacity((isPinned ? 0.16 : 0.10) * nodeAlpha)))
                            context.stroke(
                                rr,
                                with: .color(.primary.opacity((isSelected ? 0.95 : (isPinned ? 0.75 : 0.45)) * nodeAlpha)),
                                lineWidth: isSelected ? 3 : (isPinned ? 2 : 1)
                            )

                            let labelA = max(attributeLabelAlpha, isSelected ? 1.0 : 0.0) * nodeAlpha
                            if labelA > 0.06 {
                                context.draw(
                                    Text(n.label).font(.caption2).foregroundStyle(.primary.opacity(labelA)),
                                    at: CGPoint(x: s.x, y: s.y + 22),
                                    anchor: .center
                                )
                            }

                            if isPinned && (attributeLabelAlpha > 0.25 || isSelected) && nodeAlpha > 0.20 {
                                context.draw(Text("📌").font(.caption2),
                                             at: CGPoint(x: s.x + 18, y: s.y - 14),
                                             anchor: .center)
                            }
                        }
                    }
                }

                // ✅ Selection Thumbnail Overlay (nur near + nur wenn Bild vorhanden)
                if thumbAlpha > 0.05,
                   let sel = selection,
                   let wp = positions[sel],
                   let img = cachedThumb {

                    let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                    let sp = toScreen(wp, center: center)

                    // slightly offset so it doesn't sit on top of the node
                    let rawX = sp.x + 54
                    let rawY = sp.y - 54

                    let x = min(max(44, rawX), size.width - 44)
                    let y = min(max(44, rawY), size.height - 44)

                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.45), lineWidth: 1))
                        .shadow(radius: 8, y: 3)
                        .opacity(0.25 + 0.75 * thumbAlpha)
                        .position(x: x, y: y)
                        .onTapGesture { onTapSelectedThumbnail() }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(doubleTapPinGesture(in: size))
            .gesture(singleTapSelectGesture(in: size))
            .gesture(dragGesture(in: size))
            .gesture(zoomGesture())
            .onAppear {
                startSimulation()
                refreshThumbnailCache()
            }
            .onDisappear { stopSimulation() }
            .onChange(of: cameraCommand?.id) { _, _ in
                guard let cmd = cameraCommand else { return }
                applyCameraCommand(cmd, in: size)
                cameraCommand = nil
            }
            .onChange(of: selection) { _, _ in
                refreshThumbnailCache()
            }
            .onChange(of: selectedImagePath) { _, _ in
                refreshThumbnailCache()
            }
        }
    }

    // MARK: - Thumbnail cache

    private func refreshThumbnailCache() {
        let path = selectedImagePath
        guard path != cachedThumbPath else { return }
        cachedThumbPath = path
        cachedThumb = nil

        guard let path, !path.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let full = ImageStore.loadUIImage(path: path) else { return }
            let thumb = full.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? full
            DispatchQueue.main.async {
                // only apply if still current
                if cachedThumbPath == path {
                    cachedThumb = thumb
                }
            }
        }
    }

    // MARK: - Semantic Zoom helpers

    private func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
    private func fade(_ value: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        guard b > a else { return value >= b ? 1 : 0 }
        return clamp01((value - a) / (b - a))
    }

    // MARK: - Notes

    private func drawOutgoingNoteIfAny(
        source: NodeKey,
        target: NodeKey,
        from a: CGPoint,
        to b: CGPoint,
        alpha: CGFloat,
        in context: GraphicsContext
    ) {
        let k = DirectedEdgeKey.make(source: source, target: target, type: .link)
        guard let note = directedEdgeNotes[k], !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        drawEdgeNote(note, from: a, to: b, alpha: alpha, in: context)
    }

    private func drawEdgeNote(_ raw: String, from a: CGPoint, to b: CGPoint, alpha: CGFloat, in context: GraphicsContext) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let maxChars = 46
        let textStr = trimmed.count > maxChars ? (String(trimmed.prefix(maxChars)) + "…") : trimmed

        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 10)

        let text = Text(textStr)
            .font(.caption2)
            .foregroundStyle(.primary.opacity(alpha))

        let resolved = context.resolve(text)
        let maxSize = CGSize(width: 160, height: 60)
        let measured = resolved.measure(in: maxSize)

        let pad: CGFloat = 6
        let bg = CGRect(
            x: mid.x - measured.width/2 - pad,
            y: mid.y - measured.height/2 - pad,
            width: measured.width + pad*2,
            height: measured.height + pad*2
        )

        let bgPath = Path(roundedRect: bg, cornerRadius: 8)
        context.fill(bgPath, with: .color(.primary.opacity(0.12 * alpha)))
        context.stroke(bgPath, with: .color(.primary.opacity(0.28 * alpha)), lineWidth: 1)
        context.draw(resolved, at: mid, anchor: .center)
    }

    // MARK: - Camera command handling

    private func applyCameraCommand(_ cmd: CameraCommand, in size: CGSize) {
        switch cmd.kind {
        case .reset:
            withAnimation(.snappy) {
                scale = 1.0
                pan = .zero
                panStart = .zero
                scaleStart = 1.0
            }

        case .center(let key):
            guard let p = positions[key] else { return }
            withAnimation(.snappy) {
                pan = CGSize(width: -p.x * scale, height: -p.y * scale)
                panStart = pan
            }

        case .fitAll:
            let keys = nodes.map(\.key)
            guard !keys.isEmpty else { return }
            var minX: CGFloat = .greatestFiniteMagnitude
            var minY: CGFloat = .greatestFiniteMagnitude
            var maxX: CGFloat = -.greatestFiniteMagnitude
            var maxY: CGFloat = -.greatestFiniteMagnitude

            for k in keys {
                guard let p = positions[k] else { continue }
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }

            if minX == .greatestFiniteMagnitude { return }

            let worldW = max(1, maxX - minX)
            let worldH = max(1, maxY - minY)

            let padding: CGFloat = 90
            let availW = max(1, size.width - padding)
            let availH = max(1, size.height - padding)

            let targetScale = min(availW / worldW, availH / worldH)
            let clamped = max(0.4, min(3.0, targetScale))

            let mid = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)

            withAnimation(.snappy) {
                scale = clamped
                scaleStart = clamped
                pan = CGSize(width: -mid.x * clamped, height: -mid.y * clamped)
                panStart = pan
            }
        }
    }

    // MARK: - Coordinate transforms

    private func toWorld(_ screen: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - center.x) / scale, y: (screen.y - center.y) / scale)
    }

    private func toScreen(_ world: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + world.x * scale, y: center.y + world.y * scale)
    }

    private func hitTest(worldTap: CGPoint) -> NodeKey? {
        var best: (NodeKey, CGFloat)?

        for n in nodes {
            if lens.hideNonRelevant && lens.isHidden(n.key) { continue }
            guard let p = positions[n.key] else { continue }
            let dx = p.x - worldTap.x
            let dy = p.y - worldTap.y
            let d = sqrt(dx*dx + dy*dy)

            let hitRadius: CGFloat = (n.key.kind == .entity) ? 22 : 18
            if d <= hitRadius {
                if best == nil || d < best!.1 { best = (n.key, d) }
            }
        }
        return best?.0
    }

    // MARK: - Gestures

    private func singleTapSelectGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                let worldTap = toWorld(value.location, center: center)
                let hit = hitTest(worldTap: worldTap)
                onTapNode(hit)
            }
    }

    private func doubleTapPinGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard workMode == .edit else { return }

                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                let worldTap = toWorld(value.location, center: center)
                guard let key = hitTest(worldTap: worldTap) else { return }

                if pinned.contains(key) {
                    pinned.remove(key)
                } else {
                    pinned.insert(key)
                    velocities[key] = .zero
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

                if workMode == .explore {
                    if draggingKey != nil { draggingKey = nil }
                    pan = CGSize(width: panStart.width + value.translation.width,
                                height: panStart.height + value.translation.height)
                    return
                }

                if draggingKey == nil {
                    let worldStart = toWorld(value.startLocation, center: center)
                    if let key = hitTest(worldTap: worldStart) {
                        draggingKey = key
                        selection = key
                        dragStartWorld = positions[key] ?? worldStart
                        velocities[key] = .zero
                    } else {
                        dragStartPan = panStart
                    }
                }

                if let key = draggingKey {
                    let dx = value.translation.width / scale
                    let dy = value.translation.height / scale
                    positions[key] = CGPoint(x: dragStartWorld.x + dx, y: dragStartWorld.y + dy)
                    velocities[key] = .zero
                } else {
                    pan = CGSize(width: dragStartPan.width + value.translation.width,
                                height: dragStartPan.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if workMode == .explore {
                    panStart = pan
                    draggingKey = nil
                    return
                }

                if let key = draggingKey {
                    pinned.insert(key)
                    velocities[key] = .zero
                } else {
                    panStart = pan
                }
                draggingKey = nil
            }
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { val in
                scale = max(0.4, min(3.0, scaleStart * val))
            }
            .onEnded { _ in
                scaleStart = scale
            }
    }

    // MARK: - Simulation

    private func startSimulation() {
        stopSimulation()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            stepSimulation()
        }
    }

    private func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }

    private func isFixed(_ key: NodeKey) -> Bool {
        pinned.contains(key) || (workMode == .edit && draggingKey == key)
    }

    private func addVelocity(_ key: NodeKey, dx: CGFloat, dy: CGFloat, vel: inout [NodeKey: CGVector]) {
        guard !isFixed(key) else { return }
        vel[key, default: .zero].dx += dx
        vel[key, default: .zero].dy += dy
    }

    private func stepSimulation() {
        guard nodes.count >= 2 else { return }

        let repulsion: CGFloat = 7500
        let springLink: CGFloat = 0.018
        let springContain: CGFloat = 0.040
        let restLink: CGFloat = 120
        let restContain: CGFloat = 70
        let damping: CGFloat = 0.85
        let maxSpeed: CGFloat = 18

        var pos = positions
        var vel = velocities

        for i in 0..<nodes.count {
            let a = nodes[i].key
            guard let pa = pos[a], !isFixed(a) else { continue }

            var fx: CGFloat = 0
            var fy: CGFloat = 0

            for j in 0..<nodes.count where j != i {
                let b = nodes[j].key
                guard let pb = pos[b] else { continue }

                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist2 = max(dx*dx + dy*dy, 40)
                let f = repulsion / dist2
                fx += dx * f
                fy += dy * f
            }

            addVelocity(a, dx: fx * 0.00002, dy: fy * 0.00002, vel: &vel)
        }

        for e in edges {
            guard let p1 = pos[e.a], let p2 = pos[e.b] else { continue }

            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dist = max(sqrt(dx*dx + dy*dy), 1)

            let spring = (e.type == .containment) ? springContain : springLink
            let rest = (e.type == .containment) ? restContain : restLink

            let diff = dist - rest
            let fx = (dx / dist) * diff * spring
            let fy = (dy / dist) * diff * spring

            addVelocity(e.a, dx: fx, dy: fy, vel: &vel)
            addVelocity(e.b, dx: -fx, dy: -fy, vel: &vel)
        }

        for n in nodes {
            let id = n.key

            if isFixed(id) {
                vel[id] = .zero
                continue
            }

            var v = vel[id, default: .zero]
            v.dx *= damping
            v.dy *= damping

            let speed = sqrt(v.dx*v.dx + v.dy*v.dy)
            if speed > maxSpeed {
                v.dx = (v.dx / speed) * maxSpeed
                v.dy = (v.dy / speed) * maxSpeed
            }

            var p = pos[id, default: .zero]
            p.x += v.dx
            p.y += v.dy

            pos[id] = p
            vel[id] = v
        }

        positions = pos
        velocities = vel
    }
}
