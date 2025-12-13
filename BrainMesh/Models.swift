//
//  Models.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import Foundation
import SwiftData

enum NodeKind: Int, Codable, CaseIterable {
    case entity = 0
    case attribute = 1
}

// Helper für case-/diacritic-insensitive Suche
enum BMSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Model
final class MetaEntity {
    @Attribute(.unique) var id: UUID

    var name: String {
        didSet {
            nameFolded = BMSearch.fold(name)
            for a in attributes { a.recomputeSearchLabelFolded() }
        }
    }

    var nameFolded: String

    @Relationship(deleteRule: .cascade)
    var attributes: [MetaAttribute]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.attributes = []
    }
}

@Model
final class MetaAttribute {
    @Attribute(.unique) var id: UUID

    var name: String {
        didSet {
            nameFolded = BMSearch.fold(name)
            recomputeSearchLabelFolded()
        }
    }

    var nameFolded: String

    var entity: MetaEntity? {
        didSet { recomputeSearchLabelFolded() }
    }

    var searchLabelFolded: String

    init(name: String, entity: MetaEntity? = nil) {
        self.id = UUID()
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.entity = entity
        self.searchLabelFolded = ""
        self.searchLabelFolded = BMSearch.fold(self.displayName)
    }

    func recomputeSearchLabelFolded() {
        searchLabelFolded = BMSearch.fold(displayName)
    }

    var displayName: String {
        if let e = entity { return "\(e.name) · \(name)" }
        return name
    }
}

@Model
final class MetaLink {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var note: String?

    var sourceLabel: String
    var targetLabel: String

    var sourceKindRaw: Int
    var sourceID: UUID

    var targetKindRaw: Int
    var targetID: UUID

    init(sourceKind: NodeKind,
         sourceID: UUID,
         sourceLabel: String,
         targetKind: NodeKind,
         targetID: UUID,
         targetLabel: String,
         note: String? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.note = note

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
