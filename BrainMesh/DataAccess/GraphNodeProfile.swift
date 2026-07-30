//
//  GraphNodeProfile.swift
//  BrainMesh
//
//  Complete, value-only node profile domain shared by authoritative read paths.
//

import Foundation

nonisolated enum GraphNodeProfileReadError:
    Error,
    Equatable,
    Sendable
{
    case invalidLimits
}

nonisolated enum GraphNodeProfileLimitSource:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case appPolicy
}

nonisolated struct GraphNodeProfileResultWindow:
    Hashable,
    Sendable
{
    let totalCount: Int
    let returnedCount: Int
    let limit: Int
    let limitReached: Bool
    let limitSource: GraphNodeProfileLimitSource?

    init(
        totalCount: Int,
        returnedCount: Int,
        limit: Int
    ) {
        precondition(totalCount >= 0)
        precondition(returnedCount >= 0)
        precondition(limit >= 0)
        precondition(returnedCount <= totalCount)
        precondition(returnedCount <= limit)

        self.totalCount = totalCount
        self.returnedCount = returnedCount
        self.limit = limit
        self.limitReached = returnedCount < totalCount
        self.limitSource =
            returnedCount < totalCount
            ? .appPolicy
            : nil
    }
}

nonisolated struct GraphNodeProfileLimits:
    Hashable,
    Sendable
{
    let detailValueLimit: Int
    let incomingConnectionLimit: Int
    let outgoingConnectionLimit: Int
    let attachmentLimit: Int

    init(
        detailValueLimit: Int,
        incomingConnectionLimit: Int,
        outgoingConnectionLimit: Int,
        attachmentLimit: Int
    ) {
        precondition(detailValueLimit >= 0)
        precondition(incomingConnectionLimit >= 0)
        precondition(outgoingConnectionLimit >= 0)
        precondition(attachmentLimit >= 0)

        self.detailValueLimit = detailValueLimit
        self.incomingConnectionLimit =
            incomingConnectionLimit
        self.outgoingConnectionLimit =
            outgoingConnectionLimit
        self.attachmentLimit = attachmentLimit
    }
}

nonisolated struct GraphNodeProfileOwner:
    Hashable,
    Sendable
{
    let entityID: UUID
    let visibleName: String

    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .entity, id: entityID)
    }
}

nonisolated struct GraphNodeProfileDetailValue:
    Identifiable,
    Hashable,
    Sendable
{
    let valueID: UUID
    let fieldID: UUID
    let fieldName: String
    let fieldType: DetailFieldType
    let unit: String?
    let value: GraphDetailValuePayload

    var id: UUID {
        valueID
    }
}

nonisolated struct GraphNodeProfileEndpoint:
    Identifiable,
    Hashable,
    Sendable
{
    let nodeKey: NodeRefKey
    let visibleName: String
    let displayName: String
    let ownerEntity: GraphNodeProfileOwner?

    var id: NodeRefKey {
        nodeKey
    }

    var kind: NodeKind {
        nodeKey.kind
    }
}

nonisolated enum GraphNodeProfileConnectionDirection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case incoming
    case outgoing
}

nonisolated struct GraphNodeProfileConnection:
    Identifiable,
    Hashable,
    Sendable
{
    let linkID: UUID
    let createdAt: Date
    let direction: GraphNodeProfileConnectionDirection
    let source: GraphNodeProfileEndpoint
    let target: GraphNodeProfileEndpoint
    let note: String?

    var id: UUID {
        linkID
    }

    var sourceReference: NodeRefKey {
        source.nodeKey
    }

    var targetReference: NodeRefKey {
        target.nodeKey
    }

    var counterpart: GraphNodeProfileEndpoint {
        switch direction {
        case .incoming:
            return source
        case .outgoing:
            return target
        }
    }
}

nonisolated struct GraphNodeProfile:
    Hashable,
    Sendable
{
    let scope: GraphScope
    let nodeKey: NodeRefKey
    let visibleName: String
    let displayName: String
    let ownerEntity: GraphNodeProfileOwner?
    let notes: String
    let detailValues: [GraphNodeProfileDetailValue]
    let incomingConnections: [GraphNodeProfileConnection]
    let outgoingConnections: [GraphNodeProfileConnection]
    let attachments: [GraphAttachmentMetadataDTO]
    let directLinkCount: Int
    let detailValueWindow: GraphNodeProfileResultWindow
    let incomingConnectionWindow:
        GraphNodeProfileResultWindow
    let outgoingConnectionWindow:
        GraphNodeProfileResultWindow
    let attachmentWindow: GraphNodeProfileResultWindow

    var kind: NodeKind {
        nodeKey.kind
    }

    var hasNotes: Bool {
        notes.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == false
    }
}

nonisolated protocol GraphNodeProfileReading: Sendable {
    func nodeProfile(
        _ nodeKey: NodeRefKey,
        in scope: GraphScope,
        limits: GraphNodeProfileLimits
    ) async throws -> GraphNodeProfile?
}
