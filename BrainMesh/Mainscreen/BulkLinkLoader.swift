//
//  BulkLinkLoader.swift
//  BrainMesh
//
//  P0.1: Load existing link sets for BulkLinkView off the UI thread.
//  Goal: Avoid SwiftData fetches inside SwiftUI's render/update cycle.
//

import Foundation
import SwiftData

actor BulkLinkLoader {

    static let shared = BulkLinkLoader()

    private var container: AnyModelContainer? = nil

    func configure(container: AnyModelContainer) {
        self.container = container
    }

    func loadSnapshot(sourceKindRaw: Int, sourceID: UUID, graphID: UUID?) async throws -> BulkLinkSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.BulkLinkLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "BulkLinkLoader not configured"]
            )
        }

        let sKindRaw = sourceKindRaw
        let sID = sourceID
        let gid = graphID

        return try await Task.detached(priority: .utility) { [configuredContainer, sKindRaw, sID, gid] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let outgoing = try BulkLinkLoader.fetchOutgoingTargets(
                context: context,
                sourceKindRaw: sKindRaw,
                sourceID: sID,
                graphID: gid
            )

            let incoming = try BulkLinkLoader.fetchIncomingSources(
                context: context,
                sourceKindRaw: sKindRaw,
                sourceID: sID,
                graphID: gid
            )

            return BulkLinkSnapshot(
                existingOutgoingTargets: outgoing,
                existingIncomingSources: incoming
            )
        }.value
    }

    private static func fetchOutgoingTargets(
        context: ModelContext,
        sourceKindRaw: Int,
        sourceID: UUID,
        graphID: UUID?
    ) throws -> Set<NodeRefKey> {
        let sKind = sourceKindRaw
        let sID = sourceID

        let predicate: Predicate<MetaLink>
        if let gid = graphID {
            predicate = #Predicate { l in
                l.sourceKindRaw == sKind &&
                l.sourceID == sID &&
                l.graphID == gid
            }
        } else {
            predicate = #Predicate { l in
                l.sourceKindRaw == sKind &&
                l.sourceID == sID
            }
        }

        let fd = FetchDescriptor<MetaLink>(predicate: predicate)
        let outgoing = try context.fetch(fd)
        return Set(outgoing.map { NodeRefKey(kind: $0.targetKind, id: $0.targetID) })
    }

    private static func fetchIncomingSources(
        context: ModelContext,
        sourceKindRaw: Int,
        sourceID: UUID,
        graphID: UUID?
    ) throws -> Set<NodeRefKey> {
        let sKind = sourceKindRaw
        let sID = sourceID

        let predicate: Predicate<MetaLink>
        if let gid = graphID {
            predicate = #Predicate { l in
                l.targetKindRaw == sKind &&
                l.targetID == sID &&
                l.graphID == gid
            }
        } else {
            predicate = #Predicate { l in
                l.targetKindRaw == sKind &&
                l.targetID == sID
            }
        }

        let fd = FetchDescriptor<MetaLink>(predicate: predicate)
        let incoming = try context.fetch(fd)
        return Set(incoming.map { NodeRefKey(kind: $0.sourceKind, id: $0.sourceID) })
    }
}
