//
//  NodeDetailShared+Core.AnchorsPills.swift
//  BrainMesh
//
//  Shared anchors + pill models for Entity/Attribute detail screens.
//

import SwiftUI

// MARK: - Anchors

enum NodeDetailAnchor: String {
    case details
    case notes
    case connections
    case media
    case attributes
}

// MARK: - Pills

struct NodeStatPill: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.id = systemImage + "|" + title
    }
}
