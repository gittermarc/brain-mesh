//
//  GraphCanvasScreen.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct GraphCanvasScreen: View {
    @Environment(\.modelContext) private var modelContext

    // Focus/Neighborhood
    @State private var focusEntity: MetaEntity?
    @State private var showFocusPicker = false
    @State private var hops: Int = 1

    // Toggles
    @State private var showAttributes: Bool = true

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
                        positions: $positions,
                        velocities: $velocities,
                        pinned: $pinned,
                        selection: $selection,
                        scale: $scale,
                        pan: $pan,
                        cameraCommand: $cameraCommand,
                        onTapNode: { keyOrNil in
                            // Single tap = selection (oder clear)
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
                    .opacity(miniMapEmphasized ? 1.0 : 0.55)
                    .scaleEffect(miniMapEmphasized ? 1.02 : 1.0)
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

                // ✅ MiniMap (oben rechts)
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
    }

    // MARK: - Minimal top bar

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

    // ✅ Helper für MiniMap Focus-Markierung
    private var focusKey: NodeKey? {
        guard let f = focusEntity else { return nil }
        return NodeKey(kind: .entity, uuid: f.id)
    }
    
    private func pulseMiniMap() {
        // bereits geplantes "Abdimmen" abbrechen
        miniMapPulseTask?.cancel()

        // sofort hoch
        withAnimation(.easeOut(duration: 0.12)) {
            miniMapEmphasized = true
        }

        // nach kurzer Pause wieder runter
        miniMapPulseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000) // 0.65s
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                miniMapEmphasized = false
            }
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
        .frame(maxWidth: 520)
    }

    private func nodeLabel(for node: GraphNode) -> String {
        // Für Attribute wollen wir lieber den DisplayName (Entity · Attr), falls möglich:
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

    // MARK: - Inspector sheet (entkoppelt die "Regler" vom Canvas)

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

                Section("Orientierung") {
                    Text("Single Tap = Auswahl (Selection).")
                    Text("Buttons oben: Center (Selection/Fokus), Fit-to-Graph, Reset.")
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

            // pinned/selection auf existierende nodes beschränken
            let nodeKeys = Set(nodes.map(\.key))
            pinned = pinned.intersection(nodeKeys)
            if let sel = selection, !nodeKeys.contains(sel) { selection = nil }

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
        edges = filteredLinks.map {
            GraphEdge(a: NodeKey(kind: .entity, uuid: $0.sourceID),
                      b: NodeKey(kind: .entity, uuid: $0.targetID),
                      type: .link)
        }.unique()
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
                    let sortedAttrs = e.attributes.sorted { $0.name < $1.name }
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

        var newEdges: [GraphEdge] = []
        newEdges.reserveCapacity(maxLinks)

        for l in collectedEntityLinks {
            let a = NodeKey(kind: .entity, uuid: l.sourceID)
            let b = NodeKey(kind: .entity, uuid: l.targetID)
            if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                newEdges.append(GraphEdge(a: a, b: b, type: .link))
            }
            if newEdges.count >= maxLinks { break }
        }

        if includeAttributes {
            var attrOwner: [UUID: UUID] = [:]
            for e in ents { for a in e.attributes { attrOwner[a.id] = e.id } }

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
                    }
                    if linkEdges.count >= remaining { break }
                }
            }

            newEdges.append(contentsOf: linkEdges.unique().prefix(remaining))
        }

        nodes = newNodes
        edges = newEdges.unique()
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

// ✅ MiniMap View (unten im File, aber innerhalb derselben Datei)
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

            // edges
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

            // nodes
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

            // viewport rect
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

            // frame
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

// MARK: - Graph Canvas View (Selection + Drag/Pin + Camera commands)

struct GraphCanvasView: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]

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

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            Canvas { context, _ in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

                // edges
                for e in edges {
                    guard let p1 = positions[e.a], let p2 = positions[e.b] else { continue }
                    let a = toScreen(p1, center: center)
                    let b = toScreen(p2, center: center)

                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)

                    switch e.type {
                    case .containment:
                        context.stroke(path, with: .color(.secondary.opacity(0.22)), lineWidth: 1)
                    case .link:
                        context.stroke(path, with: .color(.secondary.opacity(0.40)), lineWidth: 1)
                    }
                }

                // nodes
                for n in nodes {
                    guard let p = positions[n.key] else { continue }
                    let s = toScreen(p, center: center)
                    let isPinned = pinned.contains(n.key)
                    let isSelected = (selection == n.key)

                    switch n.key.kind {
                    case .entity:
                        let r: CGFloat = 16
                        let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)

                        context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(isPinned ? 0.22 : 0.15)))
                        context.stroke(Path(ellipseIn: rect),
                                       with: .color(.primary.opacity(isSelected ? 0.95 : (isPinned ? 0.80 : 0.55))),
                                       lineWidth: isSelected ? 3 : (isPinned ? 2 : 1))
                        context.draw(Text(n.label).font(.caption), at: CGPoint(x: s.x, y: s.y + 26), anchor: .center)

                        if isPinned {
                            context.draw(Text("📌").font(.caption2),
                                         at: CGPoint(x: s.x + 18, y: s.y - 18),
                                         anchor: .center)
                        }

                    case .attribute:
                        let w: CGFloat = 28
                        let h: CGFloat = 22
                        let rect = CGRect(x: s.x - w/2, y: s.y - h/2, width: w, height: h)
                        let rr = Path(roundedRect: rect, cornerRadius: 6)

                        context.fill(rr, with: .color(.primary.opacity(isPinned ? 0.16 : 0.10)))
                        context.stroke(rr,
                                       with: .color(.primary.opacity(isSelected ? 0.95 : (isPinned ? 0.75 : 0.45))),
                                       lineWidth: isSelected ? 3 : (isPinned ? 2 : 1))
                        context.draw(Text(n.label).font(.caption2), at: CGPoint(x: s.x, y: s.y + 22), anchor: .center)

                        if isPinned {
                            context.draw(Text("📌").font(.caption2),
                                         at: CGPoint(x: s.x + 18, y: s.y - 14),
                                         anchor: .center)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(doubleTapPinGesture(in: size))
            .gesture(singleTapSelectGesture(in: size))
            .gesture(dragGesture(in: size))
            .gesture(zoomGesture())
            .onAppear { startSimulation() }
            .onDisappear { stopSimulation() }
            .onChange(of: cameraCommand?.id) { _, _ in
                guard let cmd = cameraCommand else { return }
                applyCameraCommand(cmd, in: size)
                cameraCommand = nil
            }
        }
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
            // Bounding box im World-Space
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
                onTapNode(hit) // nil = clear selection
            }
    }

    private func doubleTapPinGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
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

                if draggingKey == nil {
                    let worldStart = toWorld(value.startLocation, center: center)
                    if let key = hitTest(worldTap: worldStart) {
                        draggingKey = key
                        selection = key // Drag = auch auswählen
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
                if let key = draggingKey {
                    pinned.insert(key) // auto-pin
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
        pinned.contains(key) || (draggingKey == key)
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

        // Repulsion O(n^2)
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

        // Springs
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

        // Integrate
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
