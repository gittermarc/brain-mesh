//
//  NodeConnectionsLoader.swift
//  BrainMesh
//
//  Background loader for full connection lists and bounded detail previews.
//

import Foundation
import SwiftData
import os

/// Value-only row snapshot shared by the full list and the bounded detail preview.
///
/// SwiftData models never leave `NodeConnectionsLoader`. Navigation resolves the peer
/// only at the destination by using `peerKindRaw` and `peerID`.
nonisolated struct LinkRowDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let peerKindRaw: Int
    let peerID: UUID
    let peerLabel: String
    let note: String?
    let createdAt: Date

    var peerKind: NodeKind? {
        NodeKind(rawValue: peerKindRaw)
    }

    var navigationTarget: NodeRefKey? {
        guard let peerKind else { return nil }
        return NodeRefKey(kind: peerKind, id: peerID)
    }
}

/// Unbounded snapshot used only by the existing full connections list.
nonisolated struct NodeConnectionsSnapshot: Equatable, Sendable {
    let outgoing: [LinkRowDTO]
    let incoming: [LinkRowDTO]

    static let empty = NodeConnectionsSnapshot(outgoing: [], incoming: [])
}

/// Bounded, value-only detail-preview snapshot with exact counts.
nonisolated struct NodeConnectionsPreviewSnapshot: Equatable, Sendable {
    /// A defensive ceiling prevents an accidental caller value from turning the preview
    /// path into another full-list fetch.
    static let maximumPreviewLimit = 50

    let outgoingPreview: [LinkRowDTO]
    let incomingPreview: [LinkRowDTO]
    let outgoingCount: Int
    let incomingCount: Int

    static let empty = NodeConnectionsPreviewSnapshot(
        outgoingPreview: [],
        incomingPreview: [],
        outgoingCount: 0,
        incomingCount: 0
    )

    var totalCount: Int {
        outgoingCount + incomingCount
    }
}

typealias NodeConnectionsCancellationCheck =
    @Sendable () throws -> Void

actor NodeConnectionsLoader {

    static let shared = NodeConnectionsLoader()

    private var container: AnyModelContainer?
    private let additionalCancellationCheck: NodeConnectionsCancellationCheck
    private let log = Logger(
        subsystem: "BrainMesh",
        category: "NodeConnectionsLoader"
    )

    init(
        container: AnyModelContainer? = nil,
        cancellationCheck: @escaping NodeConnectionsCancellationCheck = {}
    ) {
        self.container = container
        self.additionalCancellationCheck = cancellationCheck
    }

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("configured")
        #endif
    }

    /// Loads the complete connection rows for the existing full-list screen.
    ///
    /// This method intentionally retains the previous optional graph behavior and
    /// unbounded result semantics. The bounded detail preview uses
    /// `loadPreviewSnapshot` instead.
    func loadSnapshot(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) async throws -> NodeConnectionsSnapshot {
        let configuredContainer = try await configuredContainer()
        let kindRaw = ownerKind.rawValue
        let cancellationCheck = additionalCancellationCheck

        let task = Task.detached(priority: .utility) {
            try Self.checkCancellation(cancellationCheck)

            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let outgoing = try Self.fetchFullOutgoingRows(
                context: context,
                kindRaw: kindRaw,
                ownerID: ownerID,
                graphID: graphID,
                cancellationCheck: cancellationCheck
            )
            try Self.checkCancellation(cancellationCheck)

            let incoming = try Self.fetchFullIncomingRows(
                context: context,
                kindRaw: kindRaw,
                ownerID: ownerID,
                graphID: graphID,
                cancellationCheck: cancellationCheck
            )
            try Self.checkCancellation(cancellationCheck)

            return NodeConnectionsSnapshot(
                outgoing: outgoing,
                incoming: incoming
            )
        }

        return try await Self.valuePropagatingCancellation(from: task)
    }

    /// Loads a graph-scoped, fetch-limited preview with exact directional counts.
    ///
    /// Count queries never materialize full link arrays. A zero limit performs only
    /// the two count queries and skips link and peer fetches entirely.
    func loadPreviewSnapshot(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID,
        previewLimit: Int
    ) async throws -> NodeConnectionsPreviewSnapshot {
        let configuredContainer = try await configuredContainer()
        let safeLimit = min(
            max(0, previewLimit),
            NodeConnectionsPreviewSnapshot.maximumPreviewLimit
        )
        let cancellationCheck = additionalCancellationCheck

        let task = Task.detached(priority: .utility) {
            try Self.checkCancellation(cancellationCheck)

            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            return try Self.makePreviewSnapshot(
                context: context,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                previewLimit: safeLimit,
                cancellationCheck: cancellationCheck
            )
        }

        return try await Self.valuePropagatingCancellation(from: task)
    }

    private func configuredContainer() async throws -> AnyModelContainer {
        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: container?.identity
        )
        try Self.checkCancellation(additionalCancellationCheck)

        guard let container else {
            throw NSError(
                domain: "BrainMesh.NodeConnectionsLoader",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "NodeConnectionsLoader not configured"
                ]
            )
        }
        return container
    }
}

private nonisolated struct NodeConnectionsPreviewRowSeed: Sendable {
    let id: UUID
    let peerKindRaw: Int
    let peerID: UUID
    let storedPeerLabel: String
    let note: String?
    let createdAt: Date
}

private extension NodeConnectionsLoader {

    static func valuePropagatingCancellation<Value: Sendable>(
        from task: Task<Value, Error>
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func checkCancellation(
        _ additionalCheck: NodeConnectionsCancellationCheck
    ) throws {
        try Task.checkCancellation()
        try additionalCheck()
    }

    static func makePreviewSnapshot(
        context: ModelContext,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID,
        previewLimit: Int,
        cancellationCheck: NodeConnectionsCancellationCheck
    ) throws -> NodeConnectionsPreviewSnapshot {
        let kindRaw = ownerKind.rawValue
        let outgoingPredicate = makeOutgoingPredicate(
            kindRaw: kindRaw,
            ownerID: ownerID,
            graphID: graphID
        )
        let incomingPredicate = makeIncomingPredicate(
            kindRaw: kindRaw,
            ownerID: ownerID,
            graphID: graphID
        )

        let outgoingCount = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: outgoingPredicate)
        )
        try checkCancellation(cancellationCheck)

        let incomingCount = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: incomingPredicate)
        )
        try checkCancellation(cancellationCheck)

        guard previewLimit > 0 else {
            return NodeConnectionsPreviewSnapshot(
                outgoingPreview: [],
                incomingPreview: [],
                outgoingCount: outgoingCount,
                incomingCount: incomingCount
            )
        }

        let outgoingSeeds = try fetchPreviewSeeds(
            context: context,
            predicate: outgoingPredicate,
            previewLimit: previewLimit,
            isOutgoing: true,
            skipFetch: outgoingCount == 0,
            cancellationCheck: cancellationCheck
        )
        try checkCancellation(cancellationCheck)

        let incomingSeeds = try fetchPreviewSeeds(
            context: context,
            predicate: incomingPredicate,
            previewLimit: previewLimit,
            isOutgoing: false,
            skipFetch: incomingCount == 0,
            cancellationCheck: cancellationCheck
        )
        try checkCancellation(cancellationCheck)

        let currentPeerLabels = try resolveCurrentPeerLabels(
            context: context,
            seeds: outgoingSeeds + incomingSeeds,
            graphID: graphID,
            cancellationCheck: cancellationCheck
        )
        try checkCancellation(cancellationCheck)

        return NodeConnectionsPreviewSnapshot(
            outgoingPreview: try makeRows(
                from: outgoingSeeds,
                currentPeerLabels: currentPeerLabels,
                cancellationCheck: cancellationCheck
            ),
            incomingPreview: try makeRows(
                from: incomingSeeds,
                currentPeerLabels: currentPeerLabels,
                cancellationCheck: cancellationCheck
            ),
            outgoingCount: outgoingCount,
            incomingCount: incomingCount
        )
    }

    static func makeOutgoingPredicate(
        kindRaw: Int,
        ownerID: UUID,
        graphID: UUID
    ) -> Predicate<MetaLink> {
        let storedKindRaw = kindRaw
        let storedOwnerID = ownerID
        let storedGraphID = graphID

        return #Predicate<MetaLink> { link in
            link.sourceKindRaw == storedKindRaw
                && link.sourceID == storedOwnerID
                && link.graphID == storedGraphID
        }
    }

    static func makeIncomingPredicate(
        kindRaw: Int,
        ownerID: UUID,
        graphID: UUID
    ) -> Predicate<MetaLink> {
        let storedKindRaw = kindRaw
        let storedOwnerID = ownerID
        let storedGraphID = graphID

        return #Predicate<MetaLink> { link in
            link.targetKindRaw == storedKindRaw
                && link.targetID == storedOwnerID
                && link.graphID == storedGraphID
        }
    }

    static func fetchPreviewSeeds(
        context: ModelContext,
        predicate: Predicate<MetaLink>,
        previewLimit: Int,
        isOutgoing: Bool,
        skipFetch: Bool,
        cancellationCheck: NodeConnectionsCancellationCheck
    ) throws -> [NodeConnectionsPreviewRowSeed] {
        guard skipFetch == false else { return [] }

        var descriptor = FetchDescriptor<MetaLink>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\MetaLink.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = previewLimit

        let links = try context.fetch(descriptor)
        try checkCancellation(cancellationCheck)

        var seeds: [NodeConnectionsPreviewRowSeed] = []
        seeds.reserveCapacity(links.count)

        for (index, link) in links.enumerated() {
            if index.isMultiple(of: 32) {
                try checkCancellation(cancellationCheck)
            }

            seeds.append(
                NodeConnectionsPreviewRowSeed(
                    id: link.id,
                    peerKindRaw:
                        isOutgoing
                            ? link.targetKindRaw
                            : link.sourceKindRaw,
                    peerID:
                        isOutgoing
                            ? link.targetID
                            : link.sourceID,
                    storedPeerLabel:
                        isOutgoing
                            ? link.targetLabel
                            : link.sourceLabel,
                    note: link.note,
                    createdAt: link.createdAt
                )
            )
        }

        return seeds
    }

    static func resolveCurrentPeerLabels(
        context: ModelContext,
        seeds: [NodeConnectionsPreviewRowSeed],
        graphID: UUID,
        cancellationCheck: NodeConnectionsCancellationCheck
    ) throws -> [NodeRefKey: String] {
        guard seeds.isEmpty == false else { return [:] }

        let entityIDs = Array(
            Set(
                seeds.lazy
                    .filter {
                        $0.peerKindRaw == NodeKind.entity.rawValue
                    }
                    .map(\.peerID)
            )
        )
        let attributeIDs = Array(
            Set(
                seeds.lazy
                    .filter {
                        $0.peerKindRaw == NodeKind.attribute.rawValue
                    }
                    .map(\.peerID)
            )
        )
        let scope = GraphScope(graphID: graphID)
        var labels: [NodeRefKey: String] = [:]
        labels.reserveCapacity(entityIDs.count + attributeIDs.count)

        if entityIDs.isEmpty == false {
            let entities = try context.fetch(
                GraphScopedFetches.entities(ids: entityIDs, in: scope)
            )
            try checkCancellation(cancellationCheck)

            for (index, entity) in entities.enumerated() {
                if index.isMultiple(of: 32) {
                    try checkCancellation(cancellationCheck)
                }
                labels[
                    NodeRefKey(kind: .entity, id: entity.id)
                ] = entity.name
            }
        }

        if attributeIDs.isEmpty == false {
            let attributes = try context.fetch(
                GraphScopedFetches.attributes(ids: attributeIDs, in: scope)
            )
            try checkCancellation(cancellationCheck)

            for (index, attribute) in attributes.enumerated() {
                if index.isMultiple(of: 32) {
                    try checkCancellation(cancellationCheck)
                }
                let value = GraphReadDTOMapper.attribute(
                    attribute,
                    scope: scope
                )
                labels[
                    NodeRefKey(kind: .attribute, id: attribute.id)
                ] = value.displayLabel
            }
        }

        return labels
    }

    static func makeRows(
        from seeds: [NodeConnectionsPreviewRowSeed],
        currentPeerLabels: [NodeRefKey: String],
        cancellationCheck: NodeConnectionsCancellationCheck
    ) throws -> [LinkRowDTO] {
        var rows: [LinkRowDTO] = []
        rows.reserveCapacity(seeds.count)

        for (index, seed) in seeds.enumerated() {
            if index.isMultiple(of: 32) {
                try checkCancellation(cancellationCheck)
            }

            let currentLabel: String?
            if let peerKind = NodeKind(rawValue: seed.peerKindRaw) {
                currentLabel = currentPeerLabels[
                    NodeRefKey(kind: peerKind, id: seed.peerID)
                ]
            } else {
                currentLabel = nil
            }

            let fallbackLabel =
                seed.storedPeerLabel.isEmpty
                    ? "Unbekannter Node"
                    : seed.storedPeerLabel
            let displayLabel: String
            if let currentLabel,
                currentLabel
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty == false
            {
                displayLabel = currentLabel
            } else {
                displayLabel = fallbackLabel
            }

            rows.append(
                LinkRowDTO(
                    id: seed.id,
                    peerKindRaw: seed.peerKindRaw,
                    peerID: seed.peerID,
                    peerLabel: displayLabel,
                    note: seed.note,
                    createdAt: seed.createdAt
                )
            )
        }

        return rows
    }

    static func fetchFullOutgoingRows(
        context: ModelContext,
        kindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        cancellationCheck: NodeConnectionsCancellationCheck
    ) throws -> [LinkRowDTO] {
        let storedKindRaw = kindRaw
        let storedOwnerID = ownerID

        let predicate: Predicate<MetaLink>
        if let graphID {
            predicate = #Predicate { link in
                link.sourceKindRaw == storedKindRaw
                    && link.sourceID == storedOwnerID
                    && link.graphID == graphID
            }
        } else {
            predicate = #Predicate { link in
                link.sourceKindRaw == storedKindRaw
                    && link.sourceID == storedOwnerID
            }
        }

        let descriptor = FetchDescriptor<MetaLink>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\MetaLink.createdAt, order: .reverse)
            ]
        )
        let links = try context.fetch(descriptor)

        var rows: [LinkRowDTO] = []
        rows.reserveCapacity(links.count)
        for (index, link) in links.enumerated() {
            if index.isMultiple(of: 64) {
                try checkCancellation(cancellationCheck)
            }
            rows.append(
                LinkRowDTO(
                    id: link.id,
                    peerKindRaw: link.targetKindRaw,
                    peerID: link.targetID,
                    peerLabel: link.targetLabel,
                    note: link.note,
                    createdAt: link.createdAt
                )
            )
        }
        return rows
    }

    static func fetchFullIncomingRows(
        context: ModelContext,
        kindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        cancellationCheck: NodeConnectionsCancellationCheck
    ) throws -> [LinkRowDTO] {
        let storedKindRaw = kindRaw
        let storedOwnerID = ownerID

        let predicate: Predicate<MetaLink>
        if let graphID {
            predicate = #Predicate { link in
                link.targetKindRaw == storedKindRaw
                    && link.targetID == storedOwnerID
                    && link.graphID == graphID
            }
        } else {
            predicate = #Predicate { link in
                link.targetKindRaw == storedKindRaw
                    && link.targetID == storedOwnerID
            }
        }

        let descriptor = FetchDescriptor<MetaLink>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\MetaLink.createdAt, order: .reverse)
            ]
        )
        let links = try context.fetch(descriptor)

        var rows: [LinkRowDTO] = []
        rows.reserveCapacity(links.count)
        for (index, link) in links.enumerated() {
            if index.isMultiple(of: 64) {
                try checkCancellation(cancellationCheck)
            }
            rows.append(
                LinkRowDTO(
                    id: link.id,
                    peerKindRaw: link.sourceKindRaw,
                    peerID: link.sourceID,
                    peerLabel: link.sourceLabel,
                    note: link.note,
                    createdAt: link.createdAt
                )
            )
        }
        return rows
    }
}
