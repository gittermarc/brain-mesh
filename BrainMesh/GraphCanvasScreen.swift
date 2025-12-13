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

    // Global filter (nur wenn kein Fokus)
    @State private var searchText: String = ""

    // Performance knobs
    @State private var maxNodes: Int = 120
    @State private var maxLinks: Int = 600

    // Graph data
    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []

    // Layout state
    @State private var positions: [UUID: CGPoint] = [:]
    @State private var velocities: [UUID: CGVector] = [:]

    // Pan/Zoom (view space)
    @State private var scale: CGFloat = 1.0
    @State private var pan: CGSize = .zero

    // Loading
    @State private var isLoading = false
    @State private var loadError: String?

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
                            Text(loadError)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
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
                            scale: $scale,
                            pan: $pan,
                            onTapNode: { id in
                                // Tap setzt Fokus (Neighborhood)
                                if let entity = fetchEntity(id: id) {
                                    focusEntity = entity
                                    Task { await loadGraph() }
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
            .task { await loadGraph() }
            .task(id: searchText) {
                // nur global relevant
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
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            // Focus row
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fokus")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let f = focusEntity {
                        Text(f.name)
                            .font(.headline)
                            .lineLimit(1)
                    } else {
                        Text("Keiner")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if focusEntity != nil {
                    Button {
                        focusEntity = nil
                        Task { await loadGraph() }
                    } label: {
                        Label("Fokus löschen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    showFocusPicker = true
                } label: {
                    Label("Fokus wählen", systemImage: "scope")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            // Hops + hint
            HStack(spacing: 12) {
                Stepper("Hops: \(hops)", value: $hops, in: 1...3)
                    .disabled(focusEntity == nil)

                Spacer()

                Text("Tip: Tap auf Node setzt Fokus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Global filter (nur ohne Fokus)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Globaler Filter (Entitätenname)…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(focusEntity != nil)
            }
            .padding(.horizontal)

            // Limits
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Nodes: \(maxNodes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(maxNodes) }, set: { maxNodes = Int($0) }),
                           in: 40...250, step: 10)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Links: \(maxLinks)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(maxLinks) }, set: { maxLinks = Int($0) }),
                           in: 200...3000, step: 100)
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
            .padding(.bottom, 10)
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
                try loadNeighborhood(centerID: focus.id, hops: hops)
            } else {
                try loadGlobal()
            }

            if resetLayout { seedLayout() }
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func loadGlobal() throws {
        let folded = BMSearch.fold(searchText)

        // Entities (limitiert)
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

        // Entity↔Entity Links (limitiert) -> danach auf nodeIDs filtern
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

        nodes = ents.map { GraphNode(id: $0.id, label: $0.name) }
        edges = filteredLinks.map { GraphEdge(a: $0.sourceID, b: $0.targetID) }.unique()
    }

    private func loadNeighborhood(centerID: UUID, hops: Int) throws {
        let kEntity = NodeKind.entity.rawValue

        var visited: Set<UUID> = [centerID]
        var frontier: Set<UUID> = [centerID]
        var collectedEdges: [GraphEdge] = []

        // BFS bis hops (klein!)
        for _ in 1...hops {
            if visited.count >= maxNodes || collectedEdges.count >= maxLinks { break }

            var next: Set<UUID> = []

            for nodeID in frontier {
                if visited.count >= maxNodes || collectedEdges.count >= maxLinks { break }

                // Outgoing
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
                    collectedEdges.append(GraphEdge(a: l.sourceID, b: l.targetID))
                    next.insert(l.targetID)
                    if collectedEdges.count >= maxLinks { break }
                }

                if collectedEdges.count >= maxLinks { break }

                // Incoming
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
                    collectedEdges.append(GraphEdge(a: l.sourceID, b: l.targetID))
                    next.insert(l.sourceID)
                    if collectedEdges.count >= maxLinks { break }
                }
            }

            next.subtract(visited)
            visited.formUnion(next)
            frontier = next

            if frontier.isEmpty { break }
        }

        // Prune + unique
        var uniqueEdges = collectedEdges.unique()
        uniqueEdges = uniqueEdges.filter { visited.contains($0.a) && visited.contains($0.b) }

        // Entities für visited IDs laden (einzeln, aber maxNodes begrenzt)
        var ents: [MetaEntity] = []
        ents.reserveCapacity(min(visited.count, maxNodes))

        for id in visited.prefix(maxNodes) {
            if let e = fetchEntity(id: id) {
                ents.append(e)
            }
        }

        // Sort für stabilere Darstellung
        ents.sort { $0.name < $1.name }

        nodes = ents.map { GraphNode(id: $0.id, label: $0.name) }
        edges = uniqueEdges.filter { edge in
            // Sicherheitsfilter auf wirklich vorhandene Nodes
            let ids = Set(nodes.map(\.id))
            return ids.contains(edge.a) && ids.contains(edge.b)
        }
    }

    private func fetchEntity(id: UUID) -> MetaEntity? {
        let nodeID = id
        let fd = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { e in e.id == nodeID }
        )
        return try? modelContext.fetch(fd).first
    }

    private func seedLayout() {
        positions.removeAll(keepingCapacity: true)
        velocities.removeAll(keepingCapacity: true)
        guard !nodes.isEmpty else { return }

        let radius: CGFloat = 220
        for (i, n) in nodes.enumerated() {
            let angle = (CGFloat(i) / CGFloat(nodes.count)) * (.pi * 2)
            let p = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            positions[n.id] = p
            velocities[n.id] = .zero
        }
    }
}

// MARK: - Graph model

struct GraphNode: Identifiable, Hashable {
    let id: UUID
    let label: String
}

struct GraphEdge: Hashable {
    // undirected (normalisiert)
    let a: UUID
    let b: UUID

    init(a: UUID, b: UUID) {
        if a.uuidString <= b.uuidString {
            self.a = a; self.b = b
        } else {
            self.a = b; self.b = a
        }
    }
}

extension Array where Element == GraphEdge {
    func unique() -> [GraphEdge] {
        Array(Set(self))
    }
}

// MARK: - Graph Canvas View

struct GraphCanvasView: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]

    @Binding var positions: [UUID: CGPoint]
    @Binding var velocities: [UUID: CGVector]

    @Binding var scale: CGFloat
    @Binding var pan: CGSize

    let onTapNode: (UUID) -> Void

    @State private var timer: Timer?
    @State private var panStart: CGSize = .zero
    @State private var scaleStart: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            Canvas { context, _ in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

                // Edges
                for e in edges {
                    guard let p1 = positions[e.a], let p2 = positions[e.b] else { continue }
                    let a = toScreen(p1, center: center)
                    let b = toScreen(p2, center: center)

                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                }

                // Nodes
                for n in nodes {
                    guard let p = positions[n.id] else { continue }
                    let s = toScreen(p, center: center)
                    let r: CGFloat = 16

                    let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.15)))
                    context.stroke(Path(ellipseIn: rect), with: .color(.primary.opacity(0.55)), lineWidth: 1)

                    let text = Text(n.label).font(.caption)
                    context.draw(text, at: CGPoint(x: s.x, y: s.y + 26), anchor: .center)
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture().simultaneously(with: zoomGesture()))
            .gesture(tapGesture(in: geo.size))
            .onAppear { startSimulation() }
            .onDisappear { stopSimulation() }
        }
    }

    private func toWorld(_ screen: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(
            x: (screen.x - center.x) / scale,
            y: (screen.y - center.y) / scale
        )
    }

    private func toScreen(_ world: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + world.x * scale,
            y: center.y + world.y * scale
        )
    }

    private func tapGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                let worldTap = toWorld(value.location, center: center)

                let hitRadius: CGFloat = 22
                var best: (UUID, CGFloat)?

                for n in nodes {
                    guard let p = positions[n.id] else { continue }
                    let dx = p.x - worldTap.x
                    let dy = p.y - worldTap.y
                    let d = sqrt(dx*dx + dy*dy)
                    if d <= hitRadius {
                        if best == nil || d < best!.1 { best = (n.id, d) }
                    }
                }

                if let id = best?.0 { onTapNode(id) }
            }
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                pan = CGSize(width: panStart.width + value.translation.width,
                            height: panStart.height + value.translation.height)
            }
            .onEnded { _ in
                panStart = pan
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

    // MARK: - Force simulation

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

    private func stepSimulation() {
        guard nodes.count >= 2 else { return }

        // Tunables
        let repulsion: CGFloat = 8000
        let spring: CGFloat = 0.02
        let restLength: CGFloat = 120
        let damping: CGFloat = 0.85
        let maxSpeed: CGFloat = 18

        var pos = positions
        var vel = velocities

        // Repulsion O(n^2) -> deshalb maxNodes begrenzen (machen wir)
        for i in 0..<nodes.count {
            let a = nodes[i].id
            guard let pa = pos[a] else { continue }

            var force = CGVector(dx: 0, dy: 0)

            for j in 0..<nodes.count where j != i {
                let b = nodes[j].id
                guard let pb = pos[b] else { continue }
                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist2 = max(dx*dx + dy*dy, 40)
                let f = repulsion / dist2
                force.dx += dx * f
                force.dy += dy * f
            }

            vel[a, default: .zero].dx += force.dx * 0.00002
            vel[a, default: .zero].dy += force.dy * 0.00002
        }

        // Springs
        for e in edges {
            guard let p1 = pos[e.a], let p2 = pos[e.b] else { continue }
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dist = max(sqrt(dx*dx + dy*dy), 1)
            let diff = dist - restLength
            let fx = (dx / dist) * diff * spring
            let fy = (dy / dist) * diff * spring

            vel[e.a, default: .zero].dx += fx
            vel[e.a, default: .zero].dy += fy
            vel[e.b, default: .zero].dx -= fx
            vel[e.b, default: .zero].dy -= fy
        }

        // Integrate
        for n in nodes {
            let id = n.id
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
