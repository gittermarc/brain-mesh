//
//  AttributeDetailView+Links.swift
//  BrainMesh
//
//  P0.3a Split: Connections (links) section UI composition
//

import SwiftUI

extension AttributeDetailView {

    @ViewBuilder
    func connectionsSectionView() -> some View {
        NodeConnectionsCard(
            ownerKind: .attribute,
            ownerID: attribute.id,
            graphID: attribute.graphID,
            outgoing: outgoingLinks,
            incoming: incomingLinks,
            segment: $segment,
            previewLimit: 4
        )
        .id(NodeDetailAnchor.connections.rawValue)
    }
}
