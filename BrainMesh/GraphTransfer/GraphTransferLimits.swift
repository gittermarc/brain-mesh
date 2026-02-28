//
//  GraphTransferLimits.swift
//  BrainMesh
//
//  Limits used by graph transfer UX.
//

import Foundation

enum GraphTransferLimits {
    /// Free users can have at most this many graphs. The next one requires Pro.
    /// Keep in sync with Pro limits.
    static let freeMaxGraphs: Int = ProLimits.freeGraphLimit
}
