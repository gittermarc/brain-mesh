//
//  GraphCanvasView.swift
//  BrainMesh
//
//  Extracted from GraphCanvasScreen.swift (P0.1)
//

import SwiftUI
import UIKit

struct GraphCanvasView: View {
    let nodes: [GraphNode]

    // ✅ getrennt: was wir zeichnen vs. was die Physik nutzt
    let drawEdges: [GraphEdge]
    let physicsEdges: [GraphEdge]

    let directedEdgeNotes: [DirectedEdgeKey: String]
    let lens: LensContext

    let workMode: WorkMode
    let collisionStrength: CGFloat

    // ✅ Spotlight Physik: nur auf relevanten Nodes simulieren (selection+neighbors)
    let physicsRelevant: Set<NodeKey>?

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

            let entityLabelAlpha = fade(scale, from: 0.55, to: 0.88)
            let attributeLabelAlpha = fade(scale, from: 1.20, to: 1.42)
            let noteAlpha = fade(scale, from: 1.32, to: 1.52)
            let showNotes = (noteAlpha > 0.02) && (selection != nil)

            let thumbAlpha = fade(scale, from: 1.26, to: 1.42)

            // ✅ Label priority: bei selection nur Selected + Nachbarn labeln
            let spotlightLabelsOnly = (selection != nil)

            ZStack {
                Canvas { context, _ in
                    let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

                    // edges (DRAW)
                    for e in drawEdges {
                        if lens.hideNonRelevant && (lens.isHidden(e.a) || lens.isHidden(e.b)) { continue }

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

                        // ✅ Notizen: nur im Nah-Zoom + nur für Kanten der selektierten Node (ausgehend)
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

                            // Labels: Default besser sichtbar; Spotlight nur relevant
                            let isRelevantInSpotlight = (lens.distance[n.key] != nil)
                            let allowLabel = (!spotlightLabelsOnly) || isRelevantInSpotlight

                            if allowLabel {
                                let baseMin: CGFloat = (selection == nil) ? 0.34 : 0.10
                                let labelA = max(max(entityLabelAlpha, baseMin), isSelected ? 1.0 : 0.0) * nodeAlpha
                                if labelA > 0.04 {
                                    let off = labelOffset(for: n.key, kind: .entity)
                                    drawLabel(
                                        n.label,
                                        at: CGPoint(x: s.x + off.x, y: s.y + 28 + off.y),
                                        alpha: labelA,
                                        isSelected: isSelected,
                                        wantHalo: (selection == nil) || isSelected || labelA < 0.92,
                                        in: context,
                                        font: .caption.weight(.semibold),
                                        maxWidth: 190
                                    )
                                }
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

                            let isRelevantInSpotlight = (lens.distance[n.key] != nil)
                            let allowLabel = (!spotlightLabelsOnly) || isRelevantInSpotlight

                            if allowLabel {
                                let labelA = max(attributeLabelAlpha, isSelected ? 1.0 : 0.0) * nodeAlpha
                                if labelA > 0.06 {
                                    let off = labelOffset(for: n.key, kind: .attribute)
                                    drawLabel(
                                        n.label,
                                        at: CGPoint(x: s.x + off.x, y: s.y + 24 + off.y),
                                        alpha: labelA,
                                        isSelected: isSelected,
                                        wantHalo: isSelected || labelA < 0.90,
                                        in: context,
                                        font: .caption2,
                                        maxWidth: 170
                                    )
                                }
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
            .onChange(of: selection) { _, _ in refreshThumbnailCache() }
            .onChange(of: selectedImagePath) { _, _ in refreshThumbnailCache() }
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

    // MARK: - Stable jitter helpers

    private func stableSeed(_ s: String) -> Int {
        var h: Int = 0
        for u in s.unicodeScalars {
            h = (h &* 31) &+ Int(u.value)
        }
        return h
    }

    private enum LabelKind { case entity, attribute }

    private func labelOffset(for key: NodeKey, kind: LabelKind) -> CGPoint {
        let h = stableSeed(key.identifier)
        let xChoices: [CGFloat] = [-14, 0, 14]
        let yChoicesEntity: [CGFloat] = [0, 6, 12]
        let yChoicesAttr: [CGFloat] = [0, -6, -12]

        let xi = abs(h) % xChoices.count
        let yi = abs(h / 7) % 3

        let x = xChoices[xi]
        let y = (kind == .entity) ? yChoicesEntity[yi] : yChoicesAttr[yi]
        return CGPoint(x: x, y: y)
    }

    // MARK: - Label drawing (Halo)

    private func drawLabel(
        _ textStr: String,
        at p: CGPoint,
        alpha: CGFloat,
        isSelected: Bool,
        wantHalo: Bool,
        in context: GraphicsContext,
        font: Font,
        maxWidth: CGFloat
    ) {
        let text = Text(textStr)
            .font(font)
            .foregroundStyle(.primary.opacity(alpha))

        let resolved = context.resolve(text)
        let measured = resolved.measure(in: CGSize(width: maxWidth, height: 60))

        if wantHalo || isSelected {
            let padX: CGFloat = 6
            let padY: CGFloat = 3
            let bg = CGRect(
                x: p.x - measured.width / 2 - padX,
                y: p.y - measured.height / 2 - padY,
                width: measured.width + padX * 2,
                height: measured.height + padY * 2
            )

            let bgPath = Path(roundedRect: bg, cornerRadius: 7)
            context.fill(bgPath, with: .color(.primary.opacity(0.12 * alpha)))
            context.stroke(bgPath, with: .color(.primary.opacity(0.20 * alpha)), lineWidth: 1)
        }

        context.draw(resolved, at: p, anchor: .center)
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
        drawEdgeNote(note, source: source, target: target, from: a, to: b, alpha: alpha, in: context)
    }

    private func drawEdgeNote(
        _ raw: String,
        source: NodeKey,
        target: NodeKey,
        from a: CGPoint,
        to b: CGPoint,
        alpha: CGFloat,
        in context: GraphicsContext
    ) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let maxChars = 46
        let textStr = trimmed.count > maxChars ? (String(trimmed.prefix(maxChars)) + "…") : trimmed

        let midBase = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)

        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1.0, sqrt(dx*dx + dy*dy))
        let nx = -dy / len
        let ny = dx / len

        let side = (stableSeed(source.identifier + "->" + target.identifier) % 2 == 0) ? CGFloat(1) : CGFloat(-1)
        var offset: CGFloat = 14
        if len < 120 { offset = 20 }

        let mid = CGPoint(x: midBase.x + nx * offset * side,
                          y: midBase.y + ny * offset * side - 8)

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

    private func approxRadius(for key: NodeKey) -> CGFloat {
        switch key.kind {
        case .entity: return 22
        case .attribute: return 18
        }
    }

    private func stepSimulation() {
        guard nodes.count >= 2 else { return }

        let repulsion: CGFloat = 8800
        let springLink: CGFloat = 0.018
        let springContain: CGFloat = 0.040
        let restLink: CGFloat = 130
        let restContain: CGFloat = 76
        let damping: CGFloat = 0.85
        let maxSpeed: CGFloat = 18

        let collisionStrength: CGFloat = max(0, self.collisionStrength)
        let collisionPadding: CGFloat = 6

        var pos = positions
        var vel = velocities

        // ✅ Spotlight Physik: nur relevante Nodes bewegen; Rest “stilllegen”
        let relevant = physicsRelevant
        let simNodes = (relevant == nil) ? nodes : nodes.filter { relevant!.contains($0.key) }

        if let relevant {
            for n in nodes where !relevant.contains(n.key) {
                vel[n.key] = .zero
            }
        }

        // repulsion + collisions
        for i in 0..<simNodes.count {
            let a = simNodes[i].key
            guard let pa = pos[a], !isFixed(a) else { continue }

            for j in 0..<simNodes.count where j != i {
                let b = simNodes[j].key
                guard let pb = pos[b] else { continue }

                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist2 = max(dx*dx + dy*dy, 40)
                let dist = sqrt(dist2)

                let f = repulsion / dist2
                addVelocity(a, dx: dx * f * 0.00002, dy: dy * f * 0.00002, vel: &vel)

                let minDist = approxRadius(for: a) + approxRadius(for: b) + collisionPadding
                if dist < minDist {
                    let overlap = (minDist - dist)
                    let nx = (dist > 0.01) ? (dx / dist) : 1
                    let ny = (dist > 0.01) ? (dy / dist) : 0
                    addVelocity(a, dx: nx * overlap * collisionStrength, dy: ny * overlap * collisionStrength, vel: &vel)
                }
            }
        }

        // springs (Physik nutzt volle Kantenliste, aber Spotlight begrenzt auf relevante Nodes)
        for e in physicsEdges {
            if let relevant {
                if !relevant.contains(e.a) || !relevant.contains(e.b) { continue }
            }
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

        // integrate
        for n in simNodes {
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
