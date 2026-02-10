//
//  GraphCanvasView.swift
//  BrainMesh
//
//  Extracted from GraphCanvasScreen.swift (P0.1)
//  Split into partials (P0.1 follow-up): Rendering / Gestures / Physics / Camera
//

import SwiftUI
import UIKit

struct GraphCanvasView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.colorScheme) private var colorScheme

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

    // NOTE: Zugriff in Extensions -> nicht `private` (private == file-scope)
    @State var timer: Timer?
    @State var panStart: CGSize = .zero
    @State var scaleStart: CGFloat = 1.0

    // drag state
    @State var draggingKey: NodeKey?
    @State var dragStartWorld: CGPoint = .zero
    @State var dragStartPan: CGSize = .zero

    // ✅ cache thumbnail (wichtig: NICHT pro Frame von Disk lesen)
    @State var cachedThumbPath: String?
    @State var cachedThumb: UIImage?

    private var theme: GraphTheme {
        GraphTheme(settings: appearance.settings.graph)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let alphas = zoomAlphas()
            let theme = self.theme
            let scheme = colorScheme

            ZStack {
                GraphCanvasBackground(theme: theme)

                Canvas { context, _ in
                    renderCanvas(in: context, size: size, alphas: alphas, theme: theme, colorScheme: scheme)
                }

                // ✅ Selection Thumbnail Overlay (nur near + nur wenn Bild vorhanden)
                selectionThumbnailOverlay(size: size, thumbAlpha: alphas.thumbAlpha)
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
}
