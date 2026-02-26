//
//  MetaLink.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation
import SwiftData

@Model
final class MetaLink {

    var id: UUID = UUID()
    var createdAt: Date = Date()

    var note: String? = nil {
        didSet {
            noteFolded = BMSearch.fold(note ?? "")
        }
    }

    /// Stored search index for `note` (folded/normalized).
    /// Keep this in sync via the `note` didSet.
    var noteFolded: String = ""

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    var sourceLabel: String = ""
    var targetLabel: String = ""

    var sourceKindRaw: Int = NodeKind.entity.rawValue
    var sourceID: UUID = UUID()

    var targetKindRaw: Int = NodeKind.entity.rawValue
    var targetID: UUID = UUID()

    init(
        sourceKind: NodeKind,
        sourceID: UUID,
        sourceLabel: String,
        targetKind: NodeKind,
        targetID: UUID,
        targetLabel: String,
        note: String? = nil,
        graphID: UUID? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.note = note
        self.noteFolded = BMSearch.fold(note ?? "")

        self.graphID = graphID

        self.sourceKindRaw = sourceKind.rawValue
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel

        self.targetKindRaw = targetKind.rawValue
        self.targetID = targetID
        self.targetLabel = targetLabel
    }

    var sourceKind: NodeKind { NodeKind(rawValue: sourceKindRaw) ?? .entity }
    var targetKind: NodeKind { NodeKind(rawValue: targetKindRaw) ?? .entity }
}
