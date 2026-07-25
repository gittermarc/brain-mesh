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

    let graphID: UUID?
    let nodes: [GraphNode]
    let iconSymbolCache: [NodeKey: String]

    // ✅ getrennt: was wir zeichnen vs. was die Physik nutzt
    let drawEdges: [GraphEdge]
    let physicsEdges: [GraphEdge]

    let staticRenderSnapshot: GraphCanvasStaticRenderSnapshot
    let lens: LensContext
    let detailsFocusRenderPlan: GraphDetailsRenderPlan

    /// Transient Copilot emphasis. This is presentation-only and never mutates the graph.
    let copilotHighlightedNodes: Set<NodeKey>

    let workMode: WorkMode
    let collisionStrength: CGFloat

    /// External gate: only run the physics timer while the canvas is actually visible and the app is active.
    /// (GraphCanvasScreen is the source of truth for this.)
    let simulationAllowed: Bool

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
    @State var physicsRuntime = GraphPhysicsRuntime()
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
            let nodeKeys: [NodeKey] = nodes.map { $0.key }

            let canvas = ZStack {
                GraphCanvasBackground(theme: theme)

                Canvas { context, _ in
                    renderCanvas(in: context, size: size, alphas: alphas, theme: theme, colorScheme: scheme)
                }

                // ✅ Selection Thumbnail Overlay (nur near + nur wenn Bild vorhanden)
                selectionThumbnailOverlay(size: size, thumbAlpha: alphas.thumbAlpha)
            }

            // Keep the modifier graph in named stages. The individual
            // expressions stay small enough for Swift's type checker while
            // preserving the exact modifier order and runtime behavior.
            let interactiveCanvas = canvas
                .contentShape(Rectangle())
                .highPriorityGesture(doubleTapPinGesture(in: size))
                .gesture(singleTapSelectGesture(in: size))
                .gesture(dragGesture(in: size))
                .gesture(zoomGesture())

            let lifecycleCanvas = interactiveCanvas
                .onAppear {
                    updateSimulationState()
                    refreshThumbnailCache()
                }
                .onDisappear { stopSimulation() }
                .onChange(of: simulationAllowed) { _, _ in
                    updateSimulationState()
                }
                .onChange(of: graphID) { _, _ in
                    wakeSimulationIfNeeded(reason: .graphChanged)
                }

            let graphInputCanvas = lifecycleCanvas
                .onChange(of: nodeKeys) { _, _ in
                    wakeSimulationIfNeeded(reason: .nodeSet)
                }
                .onChange(of: physicsEdges) { _, _ in
                    wakeSimulationIfNeeded(reason: .edges)
                }
                .onChange(of: physicsRelevant) { _, _ in
                    wakeSimulationIfNeeded(reason: .spotlight)
                }

            let cameraCanvas = graphInputCanvas
                .onChange(of: cameraCommand?.id) { _, _ in
                    guard let cmd = cameraCommand else { return }
                    applyCameraCommand(cmd, in: size)
                    cameraCommand = nil
                }

            let interactionCanvas = cameraCanvas
                .onChange(of: selection) { _, _ in
                    wakeSimulationIfNeeded(reason: .selection)
                    refreshThumbnailCache()
                }
                .onChange(of: pinned) { _, _ in
                    wakeSimulationIfNeeded(reason: .pinning)
                }
                .onChange(of: draggingKey) { previous, current in
                    wakeSimulationIfNeeded(
                        reason: previous != nil && current == nil
                            ? .draggingEnded
                            : .draggingStarted
                    )
                }

            let physicsConfigurationCanvas = interactionCanvas
                .onChange(of: workMode) { _, _ in
                    wakeSimulationIfNeeded(reason: .workMode)
                }
                .onChange(of: collisionStrength) { _, _ in
                    wakeSimulationIfNeeded(
                        reason: .collisionStrength
                    )
                }

            physicsConfigurationCanvas
                .onChange(of: positions) { _, _ in
                    externalPhysicsStateDidChange()
                }
                .onChange(of: velocities) { _, _ in
                    externalPhysicsStateDidChange()
                }
                .onChange(of: selectedImagePath) { _, _ in refreshThumbnailCache() }
        }
    }
}
