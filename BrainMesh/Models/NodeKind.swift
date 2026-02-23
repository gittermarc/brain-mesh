//
//  NodeKind.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation

nonisolated enum NodeKind: Int, Codable, CaseIterable, Sendable {
    case entity = 0
    case attribute = 1
}
