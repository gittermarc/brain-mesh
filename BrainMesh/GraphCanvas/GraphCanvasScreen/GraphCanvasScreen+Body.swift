//
//  GraphCanvasScreen+Body.swift
//  BrainMesh
//

import SwiftData
import SwiftUI

extension GraphCanvasScreen {
    var body: some View {
        graphCanvasObservationView
    }

    private var graphCanvasVisualView: some View {
        ZStack {
            // Canvas / Graph
            if let loadError {
                errorView(loadError)
            } else if nodes.isEmpty && !isLoading {
                emptyView
            } else {
                GraphCanvasView(
                    graphID: activeGraphID,
                    nodes: nodes,
                    iconSymbolCache: iconSymbolCache,
                    drawEdges: drawEdgesCache,
                    physicsEdges: edges,
                    staticRenderSnapshot: staticRenderSnapshot,
                    lens: lensCache,
                    detailsFocusRenderPlan: detailsFocusRenderPlanCache,
                    copilotHighlightedNodes: copilotHighlightedNodes,
                    workMode: workMode,
                    collisionStrength: CGFloat(collisionStrength),
                    simulationAllowed: simulationAllowed,
                    physicsRelevant: physicsRelevantCache,
                    selectedImagePath: selectedImagePath(),
                    onTapSelectedThumbnail: {
                        guard let key = selection else { return }
                        openDetails(for: key)
                    },
                    positions: $positions,
                    pinned: $pinned,
                    selection: selectionBinding,
                    scale: $scale,
                    pan: $pan,
                    cameraCommand: $cameraCommand,
                    onTapNode: { keyOrNil in
                        selection = keyOrNil
                    }
                )
            }

            loadingChipOverlay

            if !GraphCanvasModePolicy.policy(for: workMode).usesQuietChrome {
                sideStatusOverlay
                miniMapOverlay(drawEdges: drawEdgesCache)
                limitNoticeOverlay
            }

            // Action rail for selection
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
        .onAppear { isScreenVisible = true }
        .onDisappear { isScreenVisible = false }
        .toolbar {
            // NOTE:
            // SwiftUI will collapse overflowing toolbar items into a system overflow button.
            // On some devices / layouts this overflow button can become non-interactive.
            // We avoid the overflow entirely by keeping the top bar intentionally small:
            // - Graph Picker (leading)
            // - Inspector (trailing)
            // Everything else stays reachable inside the Inspector.

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showGraphPicker = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .accessibilityLabel("Graph wählen")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if supportsCopilotInspector {
                    Button {
                        isCopilotInspectorPresented.toggle()
                    } label: {
                        Image(systemName: isCopilotInspectorPresented ? "sidebar.right" : "sidebar.right")
                    }
                    .accessibilityLabel(
                        isCopilotInspectorPresented
                            ? "Graph Copilot schließen"
                            : "Graph Copilot öffnen"
                    )
                    .keyboardShortcut("g", modifiers: [.command, .option])
                }

                Button {
                    showInspector = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Inspector")
            }
        }
    }

    private var graphCanvasSheetView: some View {
        graphCanvasVisualView
            // ✅ Graph Picker
            .sheet(isPresented: $showGraphPicker) {
                GraphPickerSheet()
            }

            // Focus picker
            .sheet(isPresented: $showFocusPicker) {
                NodePickerView(kind: .entity) { picked in
                    if let entity = fetchEntity(id: picked.id) {
                        showFocusPicker = false
                        setFocusEntity(
                            entity,
                            recordInHistory: true,
                            selectFocus: true,
                            resetHops: true,
                            resetLayout: true,
                            centerAfterLoad: true,
                            scheduleReload: true
                        )
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

                        // ✅ If schema/pinning changed, refresh the peek and prepared details-focus state.
                        recomputeDetailsPeek(for: selection)
                        recomputeDetailsFocusPreparedState()
                    }
            }
            .sheet(item: $selectedAttribute) { attr in
                NavigationStack { AttributeDetailView(attribute: attr) }
                    .onDisappear {
                        refreshNodeCaches(for: NodeKey(kind: .attribute, uuid: attr.id))

                        // ✅ If details values changed, refresh the peek and prepared details-focus state.
                        recomputeDetailsPeek(for: selection)
                        recomputeDetailsFocusPreparedState()
                    }
            }

            // ✅ Tap-to-Edit for Details Peek chips
            .sheet(
                item: $detailsValueEditRequest,
                onDismiss: {
                    recomputeDetailsPeek(for: selection)
                    recomputeDetailsFocusPreparedState()
                }
            ) { req in
                DetailsValueEditorSheet(attribute: req.attribute, field: req.field)
            }

            .sheet(item: $detailsFocusEditorRequest) { request in
                GraphDetailsFocusEditorSheet(
                    request: request,
                    activeFocusState: detailsFocusState,
                    onApply: { newFocusState in
                        detailsFocusState = newFocusState
                    },
                    onClear: {
                        clearDetailsFocus()
                    }
                )
            }
    }

    private var graphCanvasOperationalView: some View {
        graphCanvasSheetView
            // Initial load (und Safety: ActiveGraphID setzen, falls leer)
            .task(id: graphs.count) {
                await ensureActiveGraphAndLoadIfNeeded()
            }

            // ✅ Graph change => reset view state + reload
            .onChange(of: activeGraphIDString) { _, _ in
                derivedStateScheduler.beginGraphTransition(to: activeGraphID)

                // Reset anything that is graph-scoped.
                clearFocusEntity(scheduleReload: false)
                canvasSelection.clear()
                copilotHighlightedNodes.removeAll()
                graphCopilotWorkspaceCoordinator.clearTransientState()
                pinned.removeAll()
                detailsFocusState = nil
                detailsFocusPreparedState = .empty
                detailsFocusSummaryCache = .empty
                detailsFocusRenderPlanCache = .empty
                loadSummary = nil
                dismissedLimitNoticeFingerprint = nil
                viewPresetMessage = nil
                pendingViewPresetSelectionAfterLoad = nil
                pendingViewPresetCenterAfterLoad = nil

                // If a cross-screen jump is pending, prepare the graph state so the next load can include the node.
                if let jump = graphJump.pendingJump {
                    stageGraphJump(jump)
                    prepareGraphStateForJump(jump)
                }

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

    private var graphCanvasNavigationView: some View {
        NavigationStack {
            graphCanvasOperationalView
        }
    }

    private var graphCanvasCopilotView: some View {
        graphCanvasNavigationView
            .inspector(isPresented: copilotInspectorBinding) {
                if let activeGraphID {
                    GraphCopilotWorkspaceView(
                        graphID: activeGraphID,
                        graphName: activeGraphName,
                        preferredWidth: $copilotInspectorWidth,
                        onClose: { isCopilotInspectorPresented = false }
                    )
                    .inspectorColumnWidth(
                        min: 320,
                        ideal: CGFloat(
                            GraphCopilotWorkspacePresentationPolicy.normalizedInspectorWidth(
                                copilotInspectorWidth
                            )
                        ),
                        max: 620
                    )
                }
            }
            .sheet(item: $graphCopilotWorkspaceCoordinator.presentedResultSet) { presentation in
                GraphCopilotResultSetSheet(
                    presentation: presentation,
                    onFocus: { node in
                        graphCopilotWorkspaceCoordinator.requestFocus(
                            node,
                            in: presentation.graphScope
                        )
                    },
                    onAddAll: { nodes in
                        graphCopilotWorkspaceCoordinator.requestAddToSelection(
                            nodes,
                            in: presentation.graphScope
                        )
                    },
                    onReplaceAll: { nodes in
                        graphCopilotWorkspaceCoordinator.requestReplaceSelection(
                            nodes,
                            in: presentation.graphScope
                        )
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    private var graphCanvasLifecycleView: some View {
        graphCanvasCopilotView
            .onChange(of: pan) { _, _ in pulseMiniMap() }
            .onChange(of: scale) { _, _ in pulseMiniMap() }
            .onAppear {
                if !nodes.isEmpty {
                    refreshStaticRenderSnapshot(
                        nodes: nodes,
                        directedEdgeNotes: directedEdgeNotes
                    )
                    scheduleDerivedStateUpdate(
                        input: derivedStateInputSnapshot,
                        reason: .initial
                    )
                }
                synchronizeCopilotHighlights()
                publishCopilotCanvasContext()
                handlePendingCopilotCommand()

                // Seed MiniMap snapshot so it can render immediately after the first layout.
                miniMapPositionsSnapshot = positions

                // ✅ Details Peek: handle state restoration / app relaunch.
                // `selection` can be restored without triggering `.onChange`, so we recompute once on appear.
                recomputeDetailsPeek(for: selection)

                // ✅ If we switched to the Graph tab via a pending jump, apply it (fast path) or stage a safe reload.
                Task { @MainActor in
                    handlePendingJumpIfNeeded()
                }
            }
            .onDisappear {
                // Best-effort: If the screen goes away, stop any in-flight load.
                loadTask?.cancel()
                derivedStateScheduler.cancel()
                graphCopilotWorkspaceCoordinator.setCanvasVisible(
                    false,
                    graphScope: activeGraphID.map { GraphScope(graphID: $0) }
                )
            }
            .onChange(of: tabRouter.selection) { _, selection in
                handleCanvasTabSelection(selection)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    handleCanvasTabSelection(tabRouter.selection)
                } else {
                    suspendCanvasOwnedWork()
                }
            }

            // ✅ MiniMap throttling: only refresh MiniMap positions while the simulation runs.
            // This keeps the Canvas in MiniMapView from redrawing at 30 FPS.
            .task(id: simulationAllowed) {
                guard simulationAllowed else { return }

                // Start with a fresh snapshot.
                await MainActor.run {
                    miniMapPositionsSnapshot = positions
                }

                // 5 FPS is usually plenty for a MiniMap overlay.
                let intervalNs: UInt64 = 200_000_000

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: intervalNs)
                    if Task.isCancelled { return }

                    // Only commit if changed to avoid unnecessary invalidations.
                    await MainActor.run {
                        if miniMapPositionsSnapshot != positions {
                            miniMapPositionsSnapshot = positions
                        }
                    }
                }
            }
    }

    private var graphCanvasDerivedObservationView: some View {
        graphCanvasLifecycleView
            // ✅ Cross-screen jump listener (Entity/Attribute detail → Graph)
            .onChange(of: graphJump.pendingJump) { _, _ in
                Task { @MainActor in
                    handlePendingJumpIfNeeded()
                }
            }

            // ✅ One value-only observation replaces the former derived-state fan-out.
            .onChange(of: derivedStateInputSnapshot) { previous, current in
                scheduleDerivedStateUpdate(
                    input: current,
                    reason: GraphCanvasDerivedStateTriggerReason.classify(
                        previous: previous,
                        current: current
                    )
                )
            }
    }

    private var graphCanvasObservationView: some View {
        graphCanvasDerivedObservationView
            // ✅ Selection change: reset “more”
            .onChange(of: selection) { _, newSelection in
                handleSelectionChange(newSelection)
            }
            .onChange(of: canvasSelection) { _, _ in
                publishCopilotCanvasContext()
            }
            .onChange(of: nodes) { _, _ in
                copilotHighlightedNodes.formIntersection(Set(nodes.map(\.key)))
                publishCopilotCanvasContext()
            }
            .onChange(of: graphCopilotWorkspaceCoordinator.pendingCanvasCommand?.id) { _, _ in
                handlePendingCopilotCommand()
            }
            .onChange(of: graphCopilotWorkspaceCoordinator.highlightedNodes) { _, _ in
                synchronizeCopilotHighlights()
            }
    }
}
