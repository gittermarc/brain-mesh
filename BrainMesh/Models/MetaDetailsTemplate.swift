//
//  MetaDetailsTemplate.swift
//  BrainMesh
//
//  User-saved Details schema templates ("Meine Sets").
//

import Foundation
import SwiftData

@Model
final class MetaDetailsTemplate {

    var id: UUID = UUID()

    // We default to `.distantPast` to avoid making migrated records look "new".
    var createdAt: Date = Date.distantPast

    // ✅ Graph scope (Multi-DB). Optional for soft migration.
    var graphID: UUID? = nil

    var name: String = "" {
        didSet { nameFolded = BMSearch.fold(name) }
    }

    var nameFolded: String = ""

    /// JSON-encoded array of `FieldDef`.
    /// Stored as String to keep SwiftData/CloudKit schema simple.
    var fieldsJSON: String = ""

    init(name: String, graphID: UUID?, fields: [FieldDef]) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleaned.isEmpty ? "Set" : cleaned
        self.nameFolded = BMSearch.fold(self.name)

        self.createdAt = Date()
        self.graphID = graphID

        self.setFields(fields)
    }

    // MARK: - Fields

    struct FieldDef: Codable, Hashable {
        var name: String
        var typeRaw: Int
        var unit: String?
        var options: [String]
        var isPinned: Bool

        init(name: String, typeRaw: Int, unit: String? = nil, options: [String] = [], isPinned: Bool = false) {
            self.name = name
            self.typeRaw = typeRaw
            self.unit = unit
            self.options = options
            self.isPinned = isPinned
        }
    }

    var fields: [FieldDef] {
        guard let data = fieldsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([FieldDef].self, from: data)) ?? []
    }

    func setFields(_ fields: [FieldDef]) {
        if fields.isEmpty {
            fieldsJSON = "[]"
            return
        }

        if let data = try? JSONEncoder().encode(fields),
           let str = String(data: data, encoding: .utf8) {
            fieldsJSON = str
        } else {
            fieldsJSON = "[]"
        }
    }
}
