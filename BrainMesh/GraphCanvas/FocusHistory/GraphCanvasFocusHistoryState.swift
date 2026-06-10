//
//  GraphCanvasFocusHistoryState.swift
//  BrainMesh
//
//  Pure state engine for local GraphCanvas focus history.
//

import Foundation

nonisolated struct GraphCanvasFocusHistoryState: Equatable, Sendable {
    static let defaultMaxItemsPerGraph = 20

    private(set) var items: [GraphCanvasFocusHistoryItem]

    init(items: [GraphCanvasFocusHistoryItem] = [], maxItemsPerGraph: Int = GraphCanvasFocusHistoryState.defaultMaxItemsPerGraph) {
        self.items = GraphCanvasFocusHistoryState.prunedAndSorted(items, maxItemsPerGraph: max(1, maxItemsPerGraph))
    }

    func items(graphID: UUID, limit: Int = GraphCanvasFocusHistoryState.defaultMaxItemsPerGraph) -> [GraphCanvasFocusHistoryItem] {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return [] }

        return items
            .filter { $0.graphID == graphID }
            .sorted(by: GraphCanvasFocusHistoryState.sortItems)
            .prefix(safeLimit)
            .map { $0 }
    }

    func previousItem(graphID: UUID, currentEntityID: UUID?) -> GraphCanvasFocusHistoryItem? {
        items(graphID: graphID, limit: GraphCanvasFocusHistoryState.defaultMaxItemsPerGraph)
            .first { item in
                guard let currentEntityID else { return true }
                return item.entityID != currentEntityID
            }
    }

    mutating func recordFocus(
        graphID: UUID,
        entityID: UUID,
        label: String,
        focusedAt: Date,
        maxItemsPerGraph: Int = GraphCanvasFocusHistoryState.defaultMaxItemsPerGraph
    ) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = GraphCanvasFocusHistoryItem(
            graphID: graphID,
            entityID: entityID,
            label: trimmedLabel.isEmpty ? "Unbenannte Entität" : trimmedLabel,
            focusedAt: focusedAt
        )

        items.removeAll { $0.identity == item.identity }
        items.insert(item, at: 0)
        sanitize(maxItemsPerGraph: maxItemsPerGraph)
    }

    mutating func remove(graphID: UUID, entityID: UUID) {
        let identity = GraphCanvasFocusHistoryIdentity(graphID: graphID, entityID: entityID)
        items.removeAll { $0.identity == identity }
    }

    mutating func clear(graphID: UUID) {
        items.removeAll { $0.graphID == graphID }
    }

    mutating func sanitize(maxItemsPerGraph: Int = GraphCanvasFocusHistoryState.defaultMaxItemsPerGraph) {
        items = GraphCanvasFocusHistoryState.prunedAndSorted(items, maxItemsPerGraph: max(1, maxItemsPerGraph))
    }

    nonisolated static func prunedAndSorted(
        _ source: [GraphCanvasFocusHistoryItem],
        maxItemsPerGraph: Int
    ) -> [GraphCanvasFocusHistoryItem] {
        var deduped: [GraphCanvasFocusHistoryIdentity: GraphCanvasFocusHistoryItem] = [:]
        for item in source {
            let existing = deduped[item.identity]
            if existing == nil || sortItems(item, existing!) {
                deduped[item.identity] = item
            }
        }

        let sorted = deduped.values.sorted(by: sortItems)
        var countsByGraph: [UUID: Int] = [:]
        var output: [GraphCanvasFocusHistoryItem] = []
        output.reserveCapacity(sorted.count)

        for item in sorted {
            let currentCount = countsByGraph[item.graphID, default: 0]
            guard currentCount < maxItemsPerGraph else { continue }
            countsByGraph[item.graphID] = currentCount + 1
            output.append(item)
        }

        return output
    }

    nonisolated static func sortItems(
        _ lhs: GraphCanvasFocusHistoryItem,
        _ rhs: GraphCanvasFocusHistoryItem
    ) -> Bool {
        if lhs.focusedAt != rhs.focusedAt {
            return lhs.focusedAt > rhs.focusedAt
        }

        let lhsLabel = BMSearch.fold(lhs.label)
        let rhsLabel = BMSearch.fold(rhs.label)
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }

        if lhs.graphID != rhs.graphID {
            return lhs.graphID.uuidString < rhs.graphID.uuidString
        }

        return lhs.entityID.uuidString < rhs.entityID.uuidString
    }
}
