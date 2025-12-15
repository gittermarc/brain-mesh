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

// MARK: - Graph (Workspace)

@Model
final class MetaGraph {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var name: String = "" {
        didSet { nameFolded = BMSearch.fold(name) }
    }
    var nameFolded: String = ""

    init(name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleaned.isEmpty ? "Neuer Graph" : cleaned
        self.nameFolded = BMSearch.fold(self.name)
        self.createdAt = Date()
    }
}

@Model
final class MetaEntity {

    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für sanfte Migration alter Daten.
    var graphID: UUID? = nil

    var name: String = "" {
        didSet {
            nameFolded = BMSearch.fold(name)
            for a in attributesList { a.recomputeSearchLabelFolded() }
        }
    }

    var nameFolded: String = ""
    var notes: String = ""

    // ✅ CloudKit-sync: Bilddaten (JPEG, klein gehalten)
    var imageData: Data? = nil

    // ✅ Lokaler Cache (Dateiname in AppSupport/BrainMeshImages). Kann leer sein.
    var imagePath: String? = nil

    // ✅ Relationship optional + Cascade ok
    // ✅ Inverse NUR HIER definieren (eine Seite!)
    @Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner)
    var attributes: [MetaAttribute]? = nil

    init(name: String, graphID: UUID? = nil) {
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.graphID = graphID
        self.attributes = []
    }

    // MARK: - Convenience

    /// De-dupe by id (falls aus der Vergangenheit schon Dopplungen entstanden sind)
    var attributesList: [MetaAttribute] {
        guard let attributes else { return [] }
        var seen = Set<UUID>()
        return attributes.filter { seen.insert($0.id).inserted }
    }

    /// Eine Quelle der Wahrheit: wir setzen owner hier explizit.
    func addAttribute(_ attr: MetaAttribute) {
        if attributes == nil { attributes = [] }
        if attributes?.contains(where: { $0.id == attr.id }) == true { return }
        attributes?.append(attr)

        // ✅ Scope Attribute in denselben Graph wie die Entität
        if attr.graphID == nil { attr.graphID = self.graphID }
        attr.owner = self
    }

    func removeAttribute(_ attr: MetaAttribute) {
        attributes?.removeAll { $0.id == attr.id }
        if attr.owner?.id == self.id { attr.owner = nil }
    }
}

@Model
final class MetaAttribute {

    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    var name: String = "" {
        didSet {
            nameFolded = BMSearch.fold(name)
            recomputeSearchLabelFolded()
        }
    }

    var nameFolded: String = ""
    var notes: String = ""

    // ✅ CloudKit-sync: Bilddaten (JPEG, klein gehalten)
    var imageData: Data? = nil

    // ✅ Lokaler Cache (Dateiname in AppSupport/BrainMeshImages). Kann leer sein.
    var imagePath: String? = nil

    // ✅ NICHT "entity" nennen (Konflikt mit Core Data)
    // ❗️KEIN inverse hier, sonst Macro-Zirkularität
    var owner: MetaEntity? = nil {
        didSet {
            // ✅ wenn owner gesetzt ist, Graph scope angleichen
            if let o = owner, graphID == nil { graphID = o.graphID }
            recomputeSearchLabelFolded()
        }
    }

    var searchLabelFolded: String = ""

    init(name: String, owner: MetaEntity? = nil, graphID: UUID? = nil) {
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.owner = owner
        self.graphID = graphID ?? owner?.graphID
        self.searchLabelFolded = BMSearch.fold(self.displayName)
    }

    func recomputeSearchLabelFolded() {
        searchLabelFolded = BMSearch.fold(displayName)
    }

    var displayName: String {
        if let e = owner { return "\(e.name) · \(name)" }
        return name
    }
}

@Model
final class MetaLink {

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String? = nil

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
