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

    @State private var focusEntity: MetaEntity?
    @State private var showFocusPicker = false
    @State private var hops: Int = 1

    @State private var showAttributes: Bool = true

    @State private var searchText: String = ""

    @State private var maxNodes: Int = 140
    @State private var maxLinks: Int = 800

    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []

    @State private var positions: [NodeKey: CGPoint] = [:]
    @State private var velocities: [NodeKey: CGVector] = [:]

    // NEW: pinned nodes
    @State private var pinned: Set<NodeKey> = []

    @State private var scale: CGFloat = 1.0
    @State private var pan: CGSize = .zero

    @State private var isLoading = false
    @State private var loadError: String?

    @State private var selectedEntity: MetaEntity?
    @State private var selectedAttribute: MetaAttribute?

    private let debounceNanos: UInt64 = 250_000_000

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider()

                ZStack {
                    if let loadError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Fehler").font(.headline)
                            Text(loadError).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Erneut versuchen") { Task { await loadGraph() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else if nodes.isEmpty && !isLoading {
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
                    } else {
                        GraphCanvasView(
                            nodes: nodes,
                            edges: edges,
                            positions: $positions,
                            velocities: $velocities,
                            pinned: $pinned,
                            scale: $scale,
                            pan: $pan,
                            onTap: { key in
                                switch key.kind {
                                case .entity:
                                    if let e = fetchEntity(id: key.uuid) {
                                        focusEntity = e
                                        Task { await loadGraph() }
                                    }
                                case .attribute:
                                    if let a = fetchAttribute(id: key.uuid) {
                                        selectedAttribute = a
                                    }
                                }
                            }
                        )
                        .overlay(alignment: .topLeading) {
                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Lade…").foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Graph")
            .navigationBarTitleDisplayMode(.inline)

            .sheet(isPresented: $showFocusPicker) {
                NodePickerView(kind: .entity) { picked in
                    if let entity = fetchEntity(id: picked.id) {
                        focusEntity = entity
                        showFocusPicker = false
                        Task { await loadGraph() }
                    } else {
                        showFocusPicker = false
                    }
                }
            }

            .sheet(item: $selectedEntity) { entity in
                NavigationStack { EntityDetailView(entity: entity) }
            }

            .sheet(item: $selectedAttribute) { attr in
                NavigationStack { AttributeDetailView(attribute: attr) }
            }

            .task { await loadGraph() }

            .task(id: searchText) {
                guard focusEntity == nil else { return }
                isLoading = true
                try? await Task.sleep(nanoseconds: debounceNanos)
                if Task.isCancelled { return }
                await loadGraph()
            }

            .task(id: hops) {
                guard focusEntity != nil else { return }
                await loadGraph()
            }

            .task(id: showAttributes) {
                guard focusEntity != nil else { return }
                await loadGraph()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fokus").font(.caption).foregroundStyle(.secondary)
                    if let f = focusEntity {
                        Text(f.name).font(.headline).lineLimit(1)
                    } else {
                        Text("Keiner").font(.headline).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let f = focusEntity {
                    Button {
                        selectedEntity = f
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if focusEntity != nil {
                    Button {
                        focusEntity = nil
                        Task { await loadGraph() }
                    } label: {
                        Label("Fokus löschen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                Button { showFocusPicker = true } label: {
                    Label("Fokus wählen", systemImage: "scope")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            HStack(spacing: 12) {
                Stepper("Hops: \(hops)", value: $hops, in: 1...3)
                    .disabled(focusEntity == nil)

                Spacer()

                Toggle("Attribute anzeigen", isOn: $showAttributes)
                    .disabled(focusEntity == nil)
            }
            .padding(.horizontal)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Globaler Filter (Entitätenname)…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(focusEntity != nil)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Nodes: \(maxNodes)").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(maxNodes) }, set: { maxNodes = Int($0) }),
                           in: 60...260, step: 10)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Links: \(maxLinks)").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(maxLinks) }, set: { maxLinks = Int($0) }),
                           in: 300...4000, step: 100)
                }
            }
            .padding(.horizontal)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) {
                        scale = 1.0
                        pan = .zero
                    }
                } label: {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await loadGraph(resetLayout: true) }
                } label: {
                    Label("Neu layouten", systemImage: "wand.and.rays")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            HStack(spacing: 10) {
                Text("Pinned: \(pinned.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !pinned.isEmpty {
                    Button("Unpin all") {
                        pinned.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            Text("Drag Node = move + auto-pin · Double-Tap Node = pin/unpin · Drag leer = pan")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
        }
        .background(.background)
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

            // pinned auf existierende nodes beschränken (sonst wächst Set ewig)
            let nodeKeys = Set(nodes.map(\.key))
            pinned = pinned.intersection(nodeKeys)

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
            for e in ents {
                for a in e.attributes { attrOwner[a.id] = e.id }
            }

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
                    predicate: #Predicate<MetaLink> { l in
                        l.sourceKindRaw == k && l.sourceID == id
                    },
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
                    predicate: #Predicate<MetaLink> { l in
                        l.targetKindRaw == k && l.targetID == id
                    },
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

        // pinned positions wenn vorhanden beibehalten
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

// MARK: - Graph Canvas View (Drag + Pin)

struct GraphCanvasView: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    @Binding var positions: [NodeKey: CGPoint]
    @Binding var velocities: [NodeKey: CGVector]
    @Binding var pinned: Set<NodeKey>

    @Binding var scale: CGFloat
    @Binding var pan: CGSize

    let onTap: (NodeKey) -> Void

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

                    switch n.key.kind {
                    case .entity:
                        let r: CGFloat = 16
                        let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(isPinned ? 0.22 : 0.15)))
                        context.stroke(Path(ellipseIn: rect), with: .color(.primary.opacity(isPinned ? 0.80 : 0.55)), lineWidth: isPinned ? 2 : 1)
                        context.draw(Text(n.label).font(.caption), at: CGPoint(x: s.x, y: s.y + 26), anchor: .center)
                        if isPinned {
                            context.draw(Text("📌").font(.caption2), at: CGPoint(x: s.x + 18, y: s.y - 18), anchor: .center)
                        }

                    case .attribute:
                        let w: CGFloat = 28
                        let h: CGFloat = 22
                        let rect = CGRect(x: s.x - w/2, y: s.y - h/2, width: w, height: h)
                        let rr = Path(roundedRect: rect, cornerRadius: 6)
                        context.fill(rr, with: .color(.primary.opacity(isPinned ? 0.16 : 0.10)))
                        context.stroke(rr, with: .color(.primary.opacity(isPinned ? 0.75 : 0.45)), lineWidth: isPinned ? 2 : 1)
                        context.draw(Text(n.label).font(.caption2), at: CGPoint(x: s.x, y: s.y + 22), anchor: .center)
                        if isPinned {
                            context.draw(Text("📌").font(.caption2), at: CGPoint(x: s.x + 18, y: s.y - 14), anchor: .center)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(doubleTapPinGesture(in: size)) // double tap > single tap
            .gesture(singleTapGesture(in: size))
            .gesture(dragGesture(in: size))
            .gesture(zoomGesture())
            .onAppear { startSimulation() }
            .onDisappear { stopSimulation() }
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

    private func singleTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                let worldTap = toWorld(value.location, center: center)
                if let key = hitTest(worldTap: worldTap) {
                    onTap(key)
                }
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
                    // decide mode based on start point
                    let worldStart = toWorld(value.startLocation, center: center)
                    if let key = hitTest(worldTap: worldStart) {
                        draggingKey = key
                        dragStartWorld = positions[key] ?? worldStart
                        velocities[key] = .zero
                    } else {
                        dragStartPan = panStart
                    }
                }

                if let key = draggingKey {
                    // drag node in world space
                    let dx = value.translation.width / scale
                    let dy = value.translation.height / scale
                    positions[key] = CGPoint(x: dragStartWorld.x + dx, y: dragStartWorld.y + dy)
                    velocities[key] = .zero
                } else {
                    // pan canvas
                    pan = CGSize(width: dragStartPan.width + value.translation.width,
                                height: dragStartPan.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if let key = draggingKey {
                    // auto-pin on drag end
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
