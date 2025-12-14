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

    // CloudKit: keine Unique Constraints → kein @Attribute(.unique)
    var id: UUID = UUID()

    var name: String = "" {
        didSet {
            nameFolded = BMSearch.fold(name)
            for a in attributesList { a.recomputeSearchLabelFolded() }
        }
    }

    var nameFolded: String = ""

    var notes: String = ""
    var imagePath: String? = nil

    // ✅ CloudKit verlangt: Relationships optional
    // ✅ Inverse NUR AUF EINER SEITE setzen (sonst Macro-Zirkularität)
    @Relationship(deleteRule: .cascade, inverse: \MetaAttribute.entity)
    var attributes: [MetaAttribute]? = nil

    init(name: String) {
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.attributes = []
    }

    // MARK: - Convenience

    var attributesList: [MetaAttribute] { attributes ?? [] }

    func addAttribute(_ attr: MetaAttribute) {
        if attributes == nil { attributes = [] }
        attributes?.append(attr)
        // inverse (zur Sicherheit)
        attr.entity = self
    }

    func removeAttribute(_ attr: MetaAttribute) {
        attributes?.removeAll { $0.id == attr.id }
        if attr.entity?.id == self.id { attr.entity = nil }
    }
}

@Model
final class MetaAttribute {

    var id: UUID = UUID()

    var name: String = "" {
        didSet {
            nameFolded = BMSearch.fold(name)
            recomputeSearchLabelFolded()
        }
    }

    var nameFolded: String = ""

    var notes: String = ""
    var imagePath: String? = nil

    // ✅ Optional relationship (CloudKit ok)
    // ❗️Kein @Relationship(inverse: ...) hier, sonst Macro-Zirkularität mit MetaEntity.attributes
    var entity: MetaEntity? = nil {
        didSet { recomputeSearchLabelFolded() }
    }

    var searchLabelFolded: String = ""

    init(name: String, entity: MetaEntity? = nil) {
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.entity = entity
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

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String? = nil

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
        note: String? = nil
    ) {
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
