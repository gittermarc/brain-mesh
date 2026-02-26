//
//  NodeDetailShared+Connections.Direction.swift
//  BrainMesh
//
//  Link direction segment used across connections UI.
//

import SwiftUI

enum NodeLinkDirectionSegment: String, CaseIterable, Identifiable {
    case outgoing
    case incoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outgoing: return "Ausgehend"
        case .incoming: return "Eingehend"
        }
    }

    var systemImage: String {
        switch self {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        }
    }
}
