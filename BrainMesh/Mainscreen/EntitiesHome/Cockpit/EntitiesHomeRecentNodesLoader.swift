//
//  EntitiesHomeRecentNodesLoader.swift
//  BrainMesh
//
//  Lightweight, graph-scoped loader for the Entities Home recent-node cards.
//

import Foundation
import SwiftData

nonisolated struct EntitiesHomeRecentNodesLoadMetrics: Equatable, Sendable {
    let requestedEntityCount: Int
    let requestedAttributeCount: Int
    let entityFetchCount: Int
    let attributeFetchCount: Int

    static let zero = EntitiesHomeRecentNodesLoadMetrics(
        requestedEntityCount: 0,
        requestedAttributeCount: 0,
        entityFetchCount: 0,
        attributeFetchCount: 0
    )

    var fullGraphFetchCount: Int {
        0
    }

    var linkFetchCount: Int {
        0
    }

    var detailFieldFetchCount: Int {
        0
    }

    var attachmentFetchCount: Int {
        0
    }
}

actor EntitiesHomeRecentNodesLoader {
    static let shared = EntitiesHomeRecentNodesLoader()

    private struct SelectedHistoryItem: Sendable {
        let nodeKind: NodeKind
        let nodeID: UUID
        let openedAt: Date
    }

    private struct EntityRecord: Sendable {
        let id: UUID
        let name: String
        let iconSymbolName: String?
    }

    private struct AttributeRecord: Sendable {
        let id: UUID
        let name: String
        let iconSymbolName: String?
        let ownerEntityID: UUID?
    }

    private struct LoadResult: Sendable {
        let nodes: [EntitiesHomeCockpitRecentNode]
        let metrics: EntitiesHomeRecentNodesLoadMetrics
    }

    private var container: AnyModelContainer?
    private var lastMetrics: EntitiesHomeRecentNodesLoadMetrics = .zero

    func configure(container: AnyModelContainer) {
        self.container = container
        lastMetrics = .zero
    }

    func load(
        graphID: UUID,
        recentItems: [RecentNodeItem],
        limit: Int
    ) async throws -> [EntitiesHomeCockpitRecentNode] {
        try Task.checkCancellation()

        let selectedItems = Self.selectHistoryItems(
            graphID: graphID,
            recentItems: recentItems,
            limit: limit
        )
        guard selectedItems.isEmpty == false else {
            lastMetrics = .zero
            return []
        }

        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: container?.identity
        )
        guard let configuredContainer = container else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeRecentNodesLoader",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "EntitiesHomeRecentNodesLoader not configured"
                ]
            )
        }

        let task = Task.detached(priority: .utility) {
            try Self.loadSelectedItems(
                selectedItems,
                graphID: graphID,
                container: configuredContainer
            )
        }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }

        try Task.checkCancellation()
        lastMetrics = result.metrics
        return result.nodes
    }

    func lastLoadMetricsForTesting() -> EntitiesHomeRecentNodesLoadMetrics {
        lastMetrics
    }
}

private extension EntitiesHomeRecentNodesLoader {
    static let maximumLimit = 30
    static let fetchChunkSize = 200

    private static func selectHistoryItems(
        graphID: UUID,
        recentItems: [RecentNodeItem],
        limit: Int
    ) -> [SelectedHistoryItem] {
        let safeLimit = max(0, min(limit, maximumLimit))
        guard safeLimit > 0 else { return [] }

        let filtered = recentItems.filter { item in
            item.graphID == graphID && item.nodeKind != nil
        }
        var deduplicatedByIdentity: [
            RecentNodeIdentity: RecentNodeItem
        ] = [:]
        deduplicatedByIdentity.reserveCapacity(filtered.count)

        for item in filtered {
            let identity = RecentNodeIdentity(
                graphID: item.graphID,
                nodeKindRaw: item.nodeKindRaw,
                nodeID: item.nodeID
            )
            guard let existing = deduplicatedByIdentity[identity] else {
                deduplicatedByIdentity[identity] = item
                continue
            }
            if historyItemPrecedes(item, existing) {
                deduplicatedByIdentity[identity] = item
            }
        }

        return deduplicatedByIdentity.values
            .sorted(by: historyItemPrecedes)
            .prefix(safeLimit)
            .compactMap { item in
                guard let nodeKind = item.nodeKind else {
                    return nil
                }
                return SelectedHistoryItem(
                    nodeKind: nodeKind,
                    nodeID: item.nodeID,
                    openedAt: item.openedAt
                )
            }
    }

    static func historyItemPrecedes(
        _ lhs: RecentNodeItem,
        _ rhs: RecentNodeItem
    ) -> Bool {
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

    private static func loadSelectedItems(
        _ selectedItems: [SelectedHistoryItem],
        graphID: UUID,
        container: AnyModelContainer
    ) throws -> LoadResult {
        let context = ModelContext(container.container)
        context.autosaveEnabled = false

        let requestedEntityIDs = Set(
            selectedItems
                .filter { $0.nodeKind == .entity }
                .map(\.nodeID)
        )
        let requestedAttributeIDs = Set(
            selectedItems
                .filter { $0.nodeKind == .attribute }
                .map(\.nodeID)
        )

        let attributeLoad = try fetchAttributes(
            context: context,
            graphID: graphID,
            ids: requestedAttributeIDs
        )
        try Task.checkCancellation()

        let ownerEntityIDs = Set(
            attributeLoad.records.compactMap(\.ownerEntityID)
        )
        let entityLoad = try fetchEntities(
            context: context,
            graphID: graphID,
            ids: requestedEntityIDs.union(ownerEntityIDs)
        )
        try Task.checkCancellation()

        let entitiesByID = Dictionary(
            uniqueKeysWithValues: entityLoad.records.map { ($0.id, $0) }
        )
        let attributesByID = Dictionary(
            uniqueKeysWithValues: attributeLoad.records.map { ($0.id, $0) }
        )

        var nodes: [EntitiesHomeCockpitRecentNode] = []
        nodes.reserveCapacity(selectedItems.count)

        for item in selectedItems {
            try Task.checkCancellation()

            switch item.nodeKind {
            case .entity:
                guard let entity = entitiesByID[item.nodeID] else {
                    continue
                }
                nodes.append(
                    EntitiesHomeCockpitRecentNode(
                        graphID: graphID,
                        nodeKindRaw: NodeKind.entity.rawValue,
                        nodeID: entity.id,
                        label: entity.name,
                        subtitle: "Entität",
                        iconSymbolName:
                            entity.iconSymbolName ?? "circle.hexagongrid",
                        openedAt: item.openedAt,
                        ownerEntityID: entity.id
                    )
                )

            case .attribute:
                guard let attribute = attributesByID[item.nodeID] else {
                    continue
                }
                let owner = attribute.ownerEntityID.flatMap {
                    entitiesByID[$0]
                }
                nodes.append(
                    EntitiesHomeCockpitRecentNode(
                        graphID: graphID,
                        nodeKindRaw: NodeKind.attribute.rawValue,
                        nodeID: attribute.id,
                        label: attribute.name,
                        subtitle: owner?.name ?? "Attribut",
                        iconSymbolName: attribute.iconSymbolName ?? "tag",
                        openedAt: item.openedAt,
                        ownerEntityID: owner?.id
                    )
                )
            }
        }

        return LoadResult(
            nodes: nodes,
            metrics: EntitiesHomeRecentNodesLoadMetrics(
                requestedEntityCount: requestedEntityIDs.count,
                requestedAttributeCount: requestedAttributeIDs.count,
                entityFetchCount: entityLoad.fetchCount,
                attributeFetchCount: attributeLoad.fetchCount
            )
        )
    }

    private static func fetchEntities(
        context: ModelContext,
        graphID: UUID,
        ids: Set<UUID>
    ) throws -> (records: [EntityRecord], fetchCount: Int) {
        guard ids.isEmpty == false else {
            return ([], 0)
        }

        let sortedIDs = ids.sorted { $0.uuidString < $1.uuidString }
        var records: [EntityRecord] = []
        records.reserveCapacity(sortedIDs.count)
        var fetchCount = 0

        for chunk in sortedIDs.chunked(maxSize: fetchChunkSize) {
            try Task.checkCancellation()
            let descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.graphID == graphID && chunk.contains(entity.id)
                }
            )
            fetchCount += 1
            records.append(
                contentsOf: try context.fetch(descriptor).map { entity in
                    EntityRecord(
                        id: entity.id,
                        name: entity.name,
                        iconSymbolName: entity.iconSymbolName
                    )
                }
            )
        }

        return (records, fetchCount)
    }

    private static func fetchAttributes(
        context: ModelContext,
        graphID: UUID,
        ids: Set<UUID>
    ) throws -> (records: [AttributeRecord], fetchCount: Int) {
        guard ids.isEmpty == false else {
            return ([], 0)
        }

        let sortedIDs = ids.sorted { $0.uuidString < $1.uuidString }
        var records: [AttributeRecord] = []
        records.reserveCapacity(sortedIDs.count)
        var fetchCount = 0

        for chunk in sortedIDs.chunked(maxSize: fetchChunkSize) {
            try Task.checkCancellation()
            let descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.graphID == graphID
                        && chunk.contains(attribute.id)
                }
            )
            fetchCount += 1
            records.append(
                contentsOf: try context.fetch(descriptor).map { attribute in
                    let ownerEntityID: UUID?
                    if let owner = attribute.owner,
                       owner.graphID == graphID {
                        ownerEntityID = owner.id
                    } else {
                        ownerEntityID = nil
                    }

                    return AttributeRecord(
                        id: attribute.id,
                        name: attribute.name,
                        iconSymbolName: attribute.iconSymbolName,
                        ownerEntityID: ownerEntityID
                    )
                }
            )
        }

        return (records, fetchCount)
    }
}

private nonisolated extension Array {
    func chunked(maxSize: Int) -> [[Element]] {
        precondition(maxSize > 0)
        guard isEmpty == false else { return [] }

        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + maxSize - 1) / maxSize)
        var startIndex = 0

        while startIndex < count {
            let endIndex = Swift.min(count, startIndex + maxSize)
            chunks.append(Array(self[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }
}
