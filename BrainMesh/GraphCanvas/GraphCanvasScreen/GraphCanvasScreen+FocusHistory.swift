//
//  GraphCanvasScreen+FocusHistory.swift
//  BrainMesh
//
//  Focus-history integration for GraphCanvasScreen.
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Focus mutations

    @MainActor
    func setFocusEntity(
        _ entity: MetaEntity,
        recordInHistory: Bool,
        selectFocus: Bool = true,
        resetHops: Bool = true,
        resetLayout: Bool = true,
        centerAfterLoad: Bool = true,
        scheduleReload: Bool = true
    ) {
        let key = NodeKey(kind: .entity, uuid: entity.id)

        focusEntity = entity
        if resetHops {
            hops = 1
        }
        if selectFocus {
            selection = key
        }
        if recordInHistory {
            recordFocusHistory(entity)
        }
        if centerAfterLoad {
            pendingCenterAfterLoad = key
        }
        if scheduleReload {
            scheduleLoadGraph(resetLayout: resetLayout)
        }
    }

    @MainActor
    func clearFocusEntity(scheduleReload: Bool = true) {
        focusEntity = nil
        selection = nil
        pendingCenterAfterLoad = nil
        if scheduleReload {
            scheduleLoadGraph(resetLayout: true)
        }
    }

    @MainActor
    private func recordFocusHistory(_ entity: MetaEntity) {
        guard let graphID = activeGraphID else { return }
        focusHistoryStore.recordFocus(
            graphID: graphID,
            entityID: entity.id,
            label: entity.name
        )
    }

    // MARK: - Focus history queries

    func focusHistoryItemsForActiveGraph(limit: Int = 8) -> [GraphCanvasFocusHistoryItem] {
        guard let graphID = activeGraphID else { return [] }
        return focusHistoryStore.items(graphID: graphID, limit: limit)
    }

    func previousFocusHistoryItem() -> GraphCanvasFocusHistoryItem? {
        guard let graphID = activeGraphID else { return nil }
        return focusHistoryStore.previousItem(graphID: graphID, currentEntityID: focusEntity?.id)
    }

    func hasFocusHistoryForActiveGraph() -> Bool {
        guard let graphID = activeGraphID else { return false }
        return !focusHistoryStore.items(graphID: graphID, limit: 1).isEmpty
    }

    // MARK: - Focus history actions

    @MainActor
    func applyPreviousFocusHistoryItem() {
        guard let item = previousFocusHistoryItem() else { return }
        applyFocusHistoryItem(item)
    }

    @MainActor
    func applyFocusHistoryItem(_ item: GraphCanvasFocusHistoryItem) {
        guard activeGraphID == item.graphID else { return }

        guard let entity = fetchEntity(id: item.entityID) else {
            focusHistoryStore.remove(graphID: item.graphID, entityID: item.entityID)
            return
        }

        setFocusEntity(
            entity,
            recordInHistory: true,
            selectFocus: true,
            resetHops: true,
            resetLayout: true,
            centerAfterLoad: true,
            scheduleReload: true
        )
    }

    @MainActor
    func clearFocusHistoryForActiveGraph() {
        guard let graphID = activeGraphID else { return }
        focusHistoryStore.clear(graphID: graphID)
    }

    // MARK: - Center after focus load

    @MainActor
    func applyPendingFocusCenterAfterLoadIfNeeded(availableKeys: Set<NodeKey>) {
        guard let key = pendingCenterAfterLoad else { return }
        pendingCenterAfterLoad = nil
        guard availableKeys.contains(key) else { return }
        centerOnNodeAfterLayout(key)
    }
}
