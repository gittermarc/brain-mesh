//
//  DetailsModels.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation
import SwiftData

// MARK: - Details (Schema + Werte)

enum DetailFieldType: Int, Codable, CaseIterable, Identifiable {
    case singleLineText = 0
    case multiLineText = 1
    case numberInt = 2
    case numberDouble = 3
    case date = 4
    case toggle = 5
    case singleChoice = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .singleLineText: return "Text"
        case .multiLineText: return "Mehrzeilig"
        case .numberInt: return "Zahl (Int)"
        case .numberDouble: return "Zahl (Double)"
        case .date: return "Datum"
        case .toggle: return "Ja/Nein"
        case .singleChoice: return "Auswahl"
        }
    }

    var systemImage: String {
        switch self {
        case .singleLineText: return "textformat"
        case .multiLineText: return "text.justify"
        case .numberInt: return "number"
        case .numberDouble: return "number"
        case .date: return "calendar"
        case .toggle: return "checkmark.circle"
        case .singleChoice: return "list.bullet"
        }
    }

    var supportsUnit: Bool {
        switch self {
        case .numberInt, .numberDouble: return true
        default: return false
        }
    }

    var supportsOptions: Bool {
        self == .singleChoice
    }
}

@Model
final class MetaDetailFieldDefinition {
    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    // Scalars für Stabilität/Queries
    var entityID: UUID = UUID()

    var name: String = "" {
        didSet { nameFolded = BMSearch.fold(name) }
    }

    var nameFolded: String = ""

    /// Stored as Int to keep SwiftData/CloudKit schema simple.
    var typeRaw: Int = 0

    /// Display order.
    var sortIndex: Int = 0

    /// Up to 3 fields can be pinned (enforced in UI).
    var isPinned: Bool = false

    /// For number fields.
    var unit: String? = nil

    /// For choice fields (JSON encoded array of strings).
    var optionsJSON: String? = nil

    // ❗️Inverse comes from MetaEntity.detailFields
    // ⚠️ NICHT "entity" nennen (Konflikt mit Core Data / CloudKit)
    @Relationship(deleteRule: .nullify, originalName: "entity")
    var owner: MetaEntity? = nil {
        didSet {
            if let e = owner {
                entityID = e.id
                if graphID == nil { graphID = e.graphID }
            }
        }
    }

    init(
        owner: MetaEntity,
        name: String,
        type: DetailFieldType,
        sortIndex: Int,
        unit: String? = nil,
        options: [String] = [],
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.owner = owner
        self.entityID = owner.id
        self.graphID = owner.graphID

        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleaned
        self.nameFolded = BMSearch.fold(cleaned)

        self.typeRaw = type.rawValue
        self.sortIndex = sortIndex
        self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPinned = isPinned
        self.setOptions(options)
    }

    var type: DetailFieldType {
        get { DetailFieldType(rawValue: typeRaw) ?? .singleLineText }
        set { typeRaw = newValue.rawValue }
    }

    var options: [String] {
        guard let optionsJSON, let data = optionsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setOptions(_ options: [String]) {
        let cleaned = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.isEmpty {
            optionsJSON = nil
            return
        }

        if let data = try? JSONEncoder().encode(cleaned), let str = String(data: data, encoding: .utf8) {
            optionsJSON = str
        } else {
            optionsJSON = nil
        }
    }
}

@Model
final class MetaDetailFieldValue {
    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    // Scalars für Stabilität/Queries
    var attributeID: UUID = UUID()
    var fieldID: UUID = UUID()

    // Typed storage (so Sort/Filter später sauber möglich ist)
    var stringValue: String? = nil
    var intValue: Int? = nil
    var doubleValue: Double? = nil
    var dateValue: Date? = nil
    var boolValue: Bool? = nil

    // ❗️Inverse comes from MetaAttribute.detailValues
    var attribute: MetaAttribute? = nil {
        didSet {
            if let a = attribute {
                attributeID = a.id
                if graphID == nil { graphID = a.graphID }
            }
        }
    }

    init(attribute: MetaAttribute, fieldID: UUID) {
        self.id = UUID()
        self.attribute = attribute
        self.attributeID = attribute.id
        self.graphID = attribute.graphID
        self.fieldID = fieldID
    }

    func clearTypedValues() {
        stringValue = nil
        intValue = nil
        doubleValue = nil
        dateValue = nil
        boolValue = nil
    }
}
