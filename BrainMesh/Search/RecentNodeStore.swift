//
//  RecentNodeStore.swift
//  BrainMesh
//
//  Local, privacy-preserving recents foundation for node detail openings.
//

import Combine
import Foundation

nonisolated struct RecentNodeItem: Codable, Hashable, Identifiable, Sendable {
    let graphID: UUID?
    let nodeKindRaw: Int
    let nodeID: UUID
    let label: String
    let iconSymbolName: String
    let openedAt: Date

    var id: String {
        RecentNodeIdentity(graphID: graphID, nodeKindRaw: nodeKindRaw, nodeID: nodeID).id
    }

    var nodeKind: NodeKind? {
        NodeKind(rawValue: nodeKindRaw)
    }

    var nodeKey: NodeKey? {
        guard let nodeKind else { return nil }
        return NodeKey(kind: nodeKind, uuid: nodeID)
    }
}

nonisolated struct RecentNodeIdentity: Hashable, Sendable {
    let graphID: UUID?
    let nodeKindRaw: Int
    let nodeID: UUID

    var id: String {
        let graphPart = graphID?.uuidString ?? "legacy"
        return "\(graphPart)|\(nodeKindRaw)|\(nodeID.uuidString)"
    }
}

final class RecentNodeStore: ObservableObject {
    static let defaultMaxItemsPerGraph = 30

    @Published private(set) var items: [RecentNodeItem]

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxItemsPerGraph: Int
    private let encoder = JSONEncoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = BMAppStorageKeys.recentNodesV1,
        maxItemsPerGraph: Int = RecentNodeStore.defaultMaxItemsPerGraph
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maxItemsPerGraph = max(1, maxItemsPerGraph)
        self.items = RecentNodeStore.loadItems(
            defaults: defaults,
            storageKey: storageKey,
            maxItemsPerGraph: self.maxItemsPerGraph
        )
    }

    func recordOpen(
        graphID: UUID?,
        nodeKind: NodeKind,
        nodeID: UUID,
        label: String,
        iconSymbolName: String?,
        openedAt: Date = Date()
    ) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIconSymbolName = iconSymbolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIconSymbolName: String
        if let trimmedIconSymbolName, !trimmedIconSymbolName.isEmpty {
            resolvedIconSymbolName = trimmedIconSymbolName
        } else {
            resolvedIconSymbolName = fallbackIconSymbolName(for: nodeKind)
        }

        let item = RecentNodeItem(
            graphID: graphID,
            nodeKindRaw: nodeKind.rawValue,
            nodeID: nodeID,
            label: trimmedLabel.isEmpty ? fallbackLabel(for: nodeKind) : trimmedLabel,
            iconSymbolName: resolvedIconSymbolName,
            openedAt: openedAt
        )

        let identity = item.identity
        items.removeAll { $0.identity == identity }
        items.insert(item, at: 0)
        items = RecentNodeStore.prunedAndSorted(items, maxItemsPerGraph: maxItemsPerGraph)
        persist()
    }

    func recentItems(graphID: UUID?, limit: Int = RecentNodeStore.defaultMaxItemsPerGraph) -> [RecentNodeItem] {
        recentItems(graphID: graphID, nodeKind: nil, limit: limit)
    }

    func recentItems(graphID: UUID?, nodeKind: NodeKind?, limit: Int = RecentNodeStore.defaultMaxItemsPerGraph) -> [RecentNodeItem] {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return [] }

        return items
            .filter { item in
                item.graphID == graphID && item.nodeKind != nil && (nodeKind == nil || item.nodeKind == nodeKind)
            }
            .sorted(by: RecentNodeStore.sortItems)
            .prefix(safeLimit)
            .map { $0 }
    }

    func remove(graphID: UUID?, nodeKind: NodeKind, nodeID: UUID) {
        let identity = RecentNodeIdentity(graphID: graphID, nodeKindRaw: nodeKind.rawValue, nodeID: nodeID)
        items.removeAll { $0.identity == identity }
        persist()
    }

    func clear(graphID: UUID?) {
        items.removeAll { $0.graphID == graphID }
        persist()
    }

    private func persist() {
        do {
            let data = try encoder.encode(items)
            defaults.set(data, forKey: storageKey)
        } catch {
            defaults.removeObject(forKey: storageKey)
        }
    }

    private func fallbackLabel(for nodeKind: NodeKind) -> String {
        switch nodeKind {
        case .entity:
            return "Unbenannte Entität"
        case .attribute:
            return "Unbenanntes Attribut"
        }
    }

    private func fallbackIconSymbolName(for nodeKind: NodeKind) -> String {
        switch nodeKind {
        case .entity:
            return "circle.hexagongrid"
        case .attribute:
            return "tag"
        }
    }

    private static func loadItems(
        defaults: UserDefaults,
        storageKey: String,
        maxItemsPerGraph: Int
    ) -> [RecentNodeItem] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([RecentNodeItem].self, from: data)
            return prunedAndSorted(decoded, maxItemsPerGraph: maxItemsPerGraph)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return []
        }
    }

    private static func prunedAndSorted(_ source: [RecentNodeItem], maxItemsPerGraph: Int) -> [RecentNodeItem] {
        var deduped: [RecentNodeIdentity: RecentNodeItem] = [:]
        for item in source where item.nodeKind != nil {
            let existing = deduped[item.identity]
            if existing == nil || item.openedAt > existing!.openedAt {
                deduped[item.identity] = item
            }
        }

        let sorted = deduped.values.sorted(by: sortItems)
        var countsByGraph: [String: Int] = [:]
        var output: [RecentNodeItem] = []
        output.reserveCapacity(sorted.count)

        for item in sorted {
            let graphKey = item.graphID?.uuidString ?? "legacy"
            let currentCount = countsByGraph[graphKey, default: 0]
            guard currentCount < maxItemsPerGraph else { continue }
            countsByGraph[graphKey] = currentCount + 1
            output.append(item)
        }

        return output
    }

    private static func sortItems(_ lhs: RecentNodeItem, _ rhs: RecentNodeItem) -> Bool {
        if lhs.openedAt != rhs.openedAt {
            return lhs.openedAt > rhs.openedAt
        }

        let lhsLabel = BMSearch.fold(lhs.label)
        let rhsLabel = BMSearch.fold(rhs.label)
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }

        if lhs.nodeKindRaw != rhs.nodeKindRaw {
            return lhs.nodeKindRaw < rhs.nodeKindRaw
        }

        return lhs.nodeID.uuidString < rhs.nodeID.uuidString
    }
}

private extension RecentNodeItem {
    var identity: RecentNodeIdentity {
        RecentNodeIdentity(graphID: graphID, nodeKindRaw: nodeKindRaw, nodeID: nodeID)
    }
}
