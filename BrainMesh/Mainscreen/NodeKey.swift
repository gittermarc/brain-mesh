//
//  NodeRefKey.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation

/// Stable, kind-aware key for nodes (safe for mixed lists of entities + attributes).
///
/// NOTE: GraphCanvas already defines a `NodeKey` type.
/// This type intentionally uses a different name to avoid ambiguous lookups.
struct NodeRefKey: Hashable {
    let kind: NodeKind
    let id: UUID

    init(kind: NodeKind, id: UUID) {
        self.kind = kind
        self.id = id
    }

    init(nodeRef: NodeRef) {
        self.kind = nodeRef.kind
        self.id = nodeRef.id
    }
}
