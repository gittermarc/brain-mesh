//
//  GraphCanvasScreen+Body.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

extension GraphCanvasScreen {
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
                        iconSymbolCache: iconSymbolCache,
                        drawEdges: drawEdgesCache,
                        physicsEdges: edges,
                        directedEdgeNotes: directedEdgeNotes,
                        lens: lensCache,
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
                miniMapOverlay(drawEdges: drawEdgesCache)
    
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
            .onAppear { isScreenVisible = true }
            .onDisappear { isScreenVisible = false }
            .toolbar {
                // NOTE:
                // SwiftUI will collapse overflowing toolbar items into a system “…” overflow button.
                // On some devices / layouts this overflow button can become non-interactive.
                // We avoid the overflow entirely by keeping the top bar intentionally small:
                // - Graph Picker (leading)
                // - Inspector (trailing)
                // Everything else stays reachable inside the Inspector.
    
                ToolbarItem(placement: .topBarLeading) {
                    Button { showGraphPicker = true } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .accessibilityLabel("Graph wählen")
                }
    
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInspector = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Inspector")
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
                        scheduleLoadGraph(resetLayout: true)
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
    
                        // ✅ If schema/pinning changed, refresh the peek for the current selection.
                        recomputeDetailsPeek(for: selection)
                    }
            }
            .sheet(item: $selectedAttribute) { attr in
                NavigationStack { AttributeDetailView(attribute: attr) }
                    .onDisappear {
                        refreshNodeCaches(for: NodeKey(kind: .attribute, uuid: attr.id))
    
                        // ✅ If details values changed, refresh the peek for the current selection.
                        recomputeDetailsPeek(for: selection)
                    }
            }
    
            // ✅ Tap-to-Edit for Details Peek chips
            .sheet(item: $detailsValueEditRequest, onDismiss: {
                recomputeDetailsPeek(for: selection)
            }) { req in
                DetailsValueEditorSheet(attribute: req.attribute, field: req.field)
            }
    
            // Initial load (und Safety: ActiveGraphID setzen, falls leer)
            .task(id: graphs.count) {
                await ensureActiveGraphAndLoadIfNeeded()
            }
    
            // ✅ Graph change => reset view state + reload
            .onChange(of: activeGraphIDString) { _, _ in
                // Reset anything that is graph-scoped.
                focusEntity = nil
                selection = nil
                pinned.removeAll()
    
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
        .onChange(of: pan) { _, _ in pulseMiniMap() }
        .onChange(of: scale) { _, _ in pulseMiniMap() }
        .onAppear {
            recomputeDerivedState()
    
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
    
        // ✅ Cross-screen jump listener (Entity/Attribute detail → Graph)
        .onChange(of: graphJump.pendingJump) { _, _ in
            Task { @MainActor in
                handlePendingJumpIfNeeded()
            }
        }
    
        // ✅ Derived state updates (only when its true inputs change)
        .onChange(of: edges) { _, _ in recomputeDerivedState() }
        .onChange(of: nodes) { _, _ in recomputeDerivedState() }
        .onChange(of: labelCache) { _, _ in recomputeDerivedState() }
        .onChange(of: showAllLinksForSelection) { _, _ in recomputeDerivedState() }
        .onChange(of: lensEnabled) { _, _ in recomputeDerivedState() }
        .onChange(of: lensHideNonRelevant) { _, _ in recomputeDerivedState() }
        .onChange(of: lensDepth) { _, _ in recomputeDerivedState() }
    
        // ✅ Selection change: reset “more”
        .onChange(of: selection) { _, newSelection in
            showAllLinksForSelection = false
    
            if let key = newSelection {
                Task {
                    await ensureLocalMainImageCacheForSelectionIfNeeded(key)
                }
            }
    
            // ✅ Details Peek (Option A): precompute only when selection changes.
            recomputeDetailsPeek(for: newSelection)
    
            recomputeDerivedState()
        }
    }
}
