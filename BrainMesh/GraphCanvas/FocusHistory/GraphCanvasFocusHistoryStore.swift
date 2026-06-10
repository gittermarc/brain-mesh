//
//  GraphCanvasFocusHistoryStore.swift
//  BrainMesh
//
//  UserDefaults-backed local focus history for GraphCanvas.
//

import Combine
import Foundation

final class GraphCanvasFocusHistoryStore: ObservableObject {
    static let defaultMaxItemsPerGraph = GraphCanvasFocusHistoryState.defaultMaxItemsPerGraph

    @Published private(set) var state: GraphCanvasFocusHistoryState

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxItemsPerGraph: Int
    private let encoder = JSONEncoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = BMAppStorageKeys.graphCanvasFocusHistoryV1,
        maxItemsPerGraph: Int = GraphCanvasFocusHistoryStore.defaultMaxItemsPerGraph
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maxItemsPerGraph = max(1, maxItemsPerGraph)
        self.state = GraphCanvasFocusHistoryStore.loadState(
            defaults: defaults,
            storageKey: storageKey,
            maxItemsPerGraph: self.maxItemsPerGraph
        )
    }

    var items: [GraphCanvasFocusHistoryItem] {
        state.items
    }

    func recordFocus(
        graphID: UUID,
        entityID: UUID,
        label: String,
        focusedAt: Date = Date()
    ) {
        var updatedState = state
        updatedState.recordFocus(
            graphID: graphID,
            entityID: entityID,
            label: label,
            focusedAt: focusedAt,
            maxItemsPerGraph: maxItemsPerGraph
        )
        state = updatedState
        persist()
    }

    func items(
        graphID: UUID,
        limit: Int = GraphCanvasFocusHistoryStore.defaultMaxItemsPerGraph
    ) -> [GraphCanvasFocusHistoryItem] {
        state.items(graphID: graphID, limit: limit)
    }

    func previousItem(
        graphID: UUID,
        currentEntityID: UUID?
    ) -> GraphCanvasFocusHistoryItem? {
        state.previousItem(graphID: graphID, currentEntityID: currentEntityID)
    }

    func remove(graphID: UUID, entityID: UUID) {
        var updatedState = state
        updatedState.remove(graphID: graphID, entityID: entityID)
        state = updatedState
        persist()
    }

    func clear(graphID: UUID) {
        var updatedState = state
        updatedState.clear(graphID: graphID)
        state = updatedState
        persist()
    }

    private func persist() {
        do {
            let data = try encoder.encode(state.items)
            defaults.set(data, forKey: storageKey)
        } catch {
            defaults.removeObject(forKey: storageKey)
        }
    }

    private static func loadState(
        defaults: UserDefaults,
        storageKey: String,
        maxItemsPerGraph: Int
    ) -> GraphCanvasFocusHistoryState {
        guard let data = defaults.data(forKey: storageKey) else {
            return GraphCanvasFocusHistoryState(maxItemsPerGraph: maxItemsPerGraph)
        }

        do {
            let decoded = try JSONDecoder().decode([GraphCanvasFocusHistoryItem].self, from: data)
            return GraphCanvasFocusHistoryState(items: decoded, maxItemsPerGraph: maxItemsPerGraph)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return GraphCanvasFocusHistoryState(maxItemsPerGraph: maxItemsPerGraph)
        }
    }
}
