//
//  NodeRef.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import Foundation

/// Lightweight reference used in pickers and link-creation flows.
struct NodeRef: Identifiable, Hashable {
    let kind: NodeKind
    let id: UUID
    let label: String
    let iconSymbolName: String?
}
