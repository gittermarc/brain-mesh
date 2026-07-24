//
//  AttributeLinksPreviewLoadTriggerPolicy.swift
//  BrainMesh
//
//  Shared value-only lifecycle and stale-result policy for Entity and Attribute
//  connection previews. The filename remains stable to avoid project-file churn.
//

import Foundation

nonisolated struct NodeConnectionsPreviewLoadIdentity:
    Hashable,
    Sendable
{
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?
}

nonisolated struct NodeConnectionsPreviewLoadToken:
    Equatable,
    Sendable
{
    let identity: NodeConnectionsPreviewLoadIdentity
    let generation: UInt
}

nonisolated struct NodeConnectionsPreviewLoadTriggerPolicy:
    Equatable,
    Sendable
{
    private(set) var loadedTaskIdentity:
        NodeConnectionsPreviewLoadIdentity?
    private(set) var isAddLinkPresented: Bool = false
    private(set) var isBulkLinkPresented: Bool = false

    private var generation: UInt = 0
    private var activeToken: NodeConnectionsPreviewLoadToken?

    mutating func registerTaskIdentity(
        _ identity: NodeConnectionsPreviewLoadIdentity
    ) -> Bool {
        guard loadedTaskIdentity != identity else { return false }
        loadedTaskIdentity = identity
        return true
    }

    mutating func beginLoad(
        for identity: NodeConnectionsPreviewLoadIdentity
    ) -> NodeConnectionsPreviewLoadToken {
        generation &+= 1
        let token = NodeConnectionsPreviewLoadToken(
            identity: identity,
            generation: generation
        )
        activeToken = token
        return token
    }

    func accepts(
        _ token: NodeConnectionsPreviewLoadToken,
        currentIdentity: NodeConnectionsPreviewLoadIdentity
    ) -> Bool {
        activeToken == token && token.identity == currentIdentity
    }

    mutating func resetTaskLifecycle() {
        loadedTaskIdentity = nil
        isAddLinkPresented = false
        isBulkLinkPresented = false
        invalidatePendingLoad()
    }

    mutating func invalidatePendingLoad() {
        generation &+= 1
        activeToken = nil
    }

    mutating func registerAddLinkPresentation(
        _ isPresented: Bool
    ) -> Bool {
        let shouldReload = isAddLinkPresented && !isPresented
        isAddLinkPresented = isPresented
        return shouldReload
    }

    mutating func registerBulkLinkPresentation(
        _ isPresented: Bool
    ) -> Bool {
        let shouldReload = isBulkLinkPresented && !isPresented
        isBulkLinkPresented = isPresented
        return shouldReload
    }
}
