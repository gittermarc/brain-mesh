//
//  NodeRef+Convenience.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation

extension MetaEntity {
    var nodeRef: NodeRef {
        NodeRef(
            kind: .entity,
            id: id,
            label: name.isEmpty ? "Entität" : name,
            iconSymbolName: iconSymbolName
        )
    }
}

extension MetaAttribute {
    var nodeRef: NodeRef {
        NodeRef(
            kind: .attribute,
            id: id,
            label: displayName,
            iconSymbolName: iconSymbolName
        )
    }
}
