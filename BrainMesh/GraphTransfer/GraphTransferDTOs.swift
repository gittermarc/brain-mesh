//
//  GraphTransferDTOs.swift
//  BrainMesh
//
//  Value-only export/import DTOs (Codable).
//  Keep this layer independent from SwiftData models.
//

import Foundation

// MARK: - Envelope meta

struct CountsDTO: Codable, Sendable {
    var graphs: Int
    var entities: Int
    var attributes: Int
    var detailFieldDefinitions: Int
    var detailFieldValues: Int
    var links: Int

    init(
        graphs: Int = 0,
        entities: Int = 0,
        attributes: Int = 0,
        detailFieldDefinitions: Int = 0,
        detailFieldValues: Int = 0,
        links: Int = 0
    ) {
        self.graphs = graphs
        self.entities = entities
        self.attributes = attributes
        self.detailFieldDefinitions = detailFieldDefinitions
        self.detailFieldValues = detailFieldValues
        self.links = links
    }
}

// MARK: - Core objects

struct GraphDTO: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var name: String

    init(id: UUID, createdAt: Date, name: String) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
    }
}

struct EntityDTO: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var graphID: UUID?

    var name: String
    var notes: String

    var iconSymbolName: String?
    var imageData: Data?

    init(
        id: UUID,
        createdAt: Date,
        graphID: UUID?,
        name: String,
        notes: String,
        iconSymbolName: String?,
        imageData: Data?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.graphID = graphID
        self.name = name
        self.notes = notes
        self.iconSymbolName = iconSymbolName
        self.imageData = imageData
    }
}

struct AttributeDTO: Codable, Sendable {
    var id: UUID
    var graphID: UUID?

    /// ID of the owning entity (relationships are rebuilt during import).
    var ownerEntityID: UUID?

    var name: String
    var notes: String

    var iconSymbolName: String?
    var imageData: Data?

    init(
        id: UUID,
        graphID: UUID?,
        ownerEntityID: UUID?,
        name: String,
        notes: String,
        iconSymbolName: String?,
        imageData: Data?
    ) {
        self.id = id
        self.graphID = graphID
        self.ownerEntityID = ownerEntityID
        self.name = name
        self.notes = notes
        self.iconSymbolName = iconSymbolName
        self.imageData = imageData
    }
}

struct DetailFieldDefinitionDTO: Codable, Sendable {
    var id: UUID
    var graphID: UUID?

    var entityID: UUID

    var name: String
    var typeRaw: Int
    var sortIndex: Int
    var isPinned: Bool

    var unit: String?
    var options: [String]

    init(
        id: UUID,
        graphID: UUID?,
        entityID: UUID,
        name: String,
        typeRaw: Int,
        sortIndex: Int,
        isPinned: Bool,
        unit: String?,
        options: [String]
    ) {
        self.id = id
        self.graphID = graphID
        self.entityID = entityID
        self.name = name
        self.typeRaw = typeRaw
        self.sortIndex = sortIndex
        self.isPinned = isPinned
        self.unit = unit
        self.options = options
    }
}

struct DetailFieldValueDTO: Codable, Sendable {
    var id: UUID
    var graphID: UUID?

    var attributeID: UUID
    var fieldID: UUID

    var stringValue: String?
    var intValue: Int?
    var doubleValue: Double?
    var dateValue: Date?
    var boolValue: Bool?

    init(
        id: UUID,
        graphID: UUID?,
        attributeID: UUID,
        fieldID: UUID,
        stringValue: String?,
        intValue: Int?,
        doubleValue: Double?,
        dateValue: Date?,
        boolValue: Bool?
    ) {
        self.id = id
        self.graphID = graphID
        self.attributeID = attributeID
        self.fieldID = fieldID
        self.stringValue = stringValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }
}

struct LinkDTO: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var graphID: UUID?

    var note: String?

    var sourceLabel: String
    var targetLabel: String

    var sourceKindRaw: Int
    var sourceID: UUID

    var targetKindRaw: Int
    var targetID: UUID

    init(
        id: UUID,
        createdAt: Date,
        graphID: UUID?,
        note: String?,
        sourceLabel: String,
        targetLabel: String,
        sourceKindRaw: Int,
        sourceID: UUID,
        targetKindRaw: Int,
        targetID: UUID
    ) {
        self.id = id
        self.createdAt = createdAt
        self.graphID = graphID
        self.note = note
        self.sourceLabel = sourceLabel
        self.targetLabel = targetLabel
        self.sourceKindRaw = sourceKindRaw
        self.sourceID = sourceID
        self.targetKindRaw = targetKindRaw
        self.targetID = targetID
    }
}
