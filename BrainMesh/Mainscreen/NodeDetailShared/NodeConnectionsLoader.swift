//
//  NodeConnectionsLoader.swift
//  BrainMesh
//
//  P0.2: Load node connections (links) off the UI thread for the "Alle" connections screen.
//  Goal: Avoid blocking the main thread with SwiftData fetches when opening a node with many links.
//

import Foundation
import SwiftData
import os

/// Value-only row snapshot for a link row inside the connections list.
///
/// Important: Do NOT pass SwiftData `@Model` instances across concurrency boundaries.
/// The UI navigates by `peerID`/`peerKindRaw` and resolves the model from its main `ModelContext`.
struct LinkRowDTO: Identifiable, Hashable, Sendable {
    /// The `MetaLink.id`
    let id: UUID

    /// The "other side" of the link for the current list direction.
    let peerKindRaw: Int
    let peerID: UUID
    let peerLabel: String

    let note: String?
    let createdAt: Date
}

/// Snapshot DTO returned to the UI.
/// This is intentionally a value-only container so the UI can commit state in one go.
struct NodeConnectionsSnapshot: @unchecked Sendable {
    let outgoing: [LinkRowDTO]
    let incoming: [LinkRowDTO]

    static let empty = NodeConnectionsSnapshot(outgoing: [], incoming: [])
}

actor NodeConnectionsLoader {

    static let shared = NodeConnectionsLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "NodeConnectionsLoader")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func loadSnapshot(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?) async throws -> NodeConnectionsSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.NodeConnectionsLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "NodeConnectionsLoader not configured"]
            )
        }

        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID

        return try await Task.detached(priority: .utility) { [configuredContainer, kindRaw, oid, gid] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let outgoing = try NodeConnectionsLoader.fetchOutgoingRows(
                context: context,
                kindRaw: kindRaw,
                ownerID: oid,
                graphID: gid
            )

            let incoming = try NodeConnectionsLoader.fetchIncomingRows(
                context: context,
                kindRaw: kindRaw,
                ownerID: oid,
                graphID: gid
            )

            return NodeConnectionsSnapshot(outgoing: outgoing, incoming: incoming)
        }.value
    }

    private static func fetchOutgoingRows(
        context: ModelContext,
        kindRaw: Int,
        ownerID: UUID,
        graphID: UUID?
    ) throws -> [LinkRowDTO] {
        let k = kindRaw
        let oid = ownerID

        let predicate: Predicate<MetaLink>
        if let gid = graphID {
            predicate = #Predicate { l in
                l.sourceKindRaw == k &&
                l.sourceID == oid &&
                l.graphID == gid
            }
        } else {
            predicate = #Predicate { l in
                l.sourceKindRaw == k &&
                l.sourceID == oid
            }
        }

        let fd = FetchDescriptor<MetaLink>(
            predicate: predicate,
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )

        let links = try context.fetch(fd)
        return links.map { l in
            LinkRowDTO(
                id: l.id,
                peerKindRaw: l.targetKindRaw,
                peerID: l.targetID,
                peerLabel: l.targetLabel,
                note: l.note,
                createdAt: l.createdAt
            )
        }
    }

    private static func fetchIncomingRows(
        context: ModelContext,
        kindRaw: Int,
        ownerID: UUID,
        graphID: UUID?
    ) throws -> [LinkRowDTO] {
        let k = kindRaw
        let oid = ownerID

        let predicate: Predicate<MetaLink>
        if let gid = graphID {
            predicate = #Predicate { l in
                l.targetKindRaw == k &&
                l.targetID == oid &&
                l.graphID == gid
            }
        } else {
            predicate = #Predicate { l in
                l.targetKindRaw == k &&
                l.targetID == oid
            }
        }

        let fd = FetchDescriptor<MetaLink>(
            predicate: predicate,
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )

        let links = try context.fetch(fd)
        return links.map { l in
            LinkRowDTO(
                id: l.id,
                peerKindRaw: l.sourceKindRaw,
                peerID: l.sourceID,
                peerLabel: l.sourceLabel,
                note: l.note,
                createdAt: l.createdAt
            )
        }
    }
}
