//
//  GraphSchemaModels.swift
//  BrainMesh
//
//  Compact prompt-facing schema snapshots and app-side alias resolution.
//

import Foundation

nonisolated struct GraphEntityAlias: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    var description: String {
        rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated struct GraphFieldAlias: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    var description: String {
        rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

nonisolated enum GraphSchemaExampleValue: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case date(Date)
    case boolean(Bool)
    case choice(String)
}

nonisolated struct GraphSchemaField: Hashable, Sendable {
    let alias: GraphFieldAlias
    let name: String
    let type: DetailFieldType
    let unit: String?
    let choiceOptions: [String]
    let isPinned: Bool
    let sortIndex: Int
    let exampleValues: [GraphSchemaExampleValue]
    let optionsWereTruncated: Bool
    let examplesWereTruncated: Bool
}

nonisolated struct GraphSchemaEntity: Hashable, Sendable {
    let alias: GraphEntityAlias
    let name: String
    let attributeCount: Int
    let fields: [GraphSchemaField]
    let fieldsWereTruncated: Bool
}

nonisolated struct GraphSchemaTruncation: Hashable, Sendable {
    let sourceEntityCount: Int
    let includedEntityCount: Int
    let sourceFieldCount: Int
    let includedFieldCount: Int
    let sourceChoiceOptionCount: Int
    let includedChoiceOptionCount: Int
    let sourceExampleValueCount: Int
    let includedExampleValueCount: Int
    let stringsWereTruncated: Bool

    var isTruncated: Bool {
        sourceEntityCount != includedEntityCount
            || sourceFieldCount != includedFieldCount
            || sourceChoiceOptionCount != includedChoiceOptionCount
            || sourceExampleValueCount != includedExampleValueCount
            || stringsWereTruncated
    }
}

nonisolated struct GraphSchemaSnapshot: Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let graphName: String
    let entities: [GraphSchemaEntity]
    let truncation: GraphSchemaTruncation

    init(
        version: Int = GraphSchemaSnapshot.currentVersion,
        graphName: String,
        entities: [GraphSchemaEntity],
        truncation: GraphSchemaTruncation
    ) {
        self.version = version
        self.graphName = graphName
        self.entities = entities
        self.truncation = truncation
    }
}

nonisolated struct GraphSchemaEntityResolution: Hashable, Sendable {
    let alias: GraphEntityAlias
    let entityID: UUID
    let name: String
}

nonisolated struct GraphSchemaFieldResolution: Hashable, Sendable {
    let alias: GraphFieldAlias
    let entityAlias: GraphEntityAlias
    let entityID: UUID
    let fieldID: UUID
    let name: String
    let type: DetailFieldType
    let unit: String?
    let choiceOptions: [String]
}

nonisolated struct GraphSchemaNodeResolution: Hashable, Sendable {
    let node: NodeRefKey
    let ownerEntityID: UUID
    let displayName: String
}

nonisolated struct GraphSchemaAliasMap: Sendable {
    let graphScope: GraphScope
    let entitiesByAlias: [GraphEntityAlias: GraphSchemaEntityResolution]
    let fieldsByAlias: [GraphFieldAlias: GraphSchemaFieldResolution]
    let nodeEntityIDs: [NodeRefKey: UUID]
    let nodesByKey: [NodeRefKey: GraphSchemaNodeResolution]

    init(
        graphScope: GraphScope,
        entitiesByAlias: [GraphEntityAlias: GraphSchemaEntityResolution],
        fieldsByAlias: [GraphFieldAlias: GraphSchemaFieldResolution],
        nodeEntityIDs: [NodeRefKey: UUID],
        nodesByKey: [NodeRefKey: GraphSchemaNodeResolution] = [:]
    ) {
        self.graphScope = graphScope
        self.entitiesByAlias = entitiesByAlias
        self.fieldsByAlias = fieldsByAlias
        self.nodeEntityIDs = nodeEntityIDs
        self.nodesByKey = nodesByKey
    }

    func entity(for alias: GraphEntityAlias) -> GraphSchemaEntityResolution? {
        entitiesByAlias[alias]
    }

    func entity(id: UUID) -> GraphSchemaEntityResolution? {
        entitiesByAlias.values.first { $0.entityID == id }
    }

    func field(for alias: GraphFieldAlias) -> GraphSchemaFieldResolution? {
        fieldsByAlias[alias]
    }

    func owningEntityID(for node: NodeRefKey) -> UUID? {
        nodesByKey[node]?.ownerEntityID ?? nodeEntityIDs[node]
    }

    func contains(entityID: UUID) -> Bool {
        entitiesByAlias.values.contains { $0.entityID == entityID }
    }
}

nonisolated struct GraphSchemaContext: Sendable {
    let graphScope: GraphScope
    let snapshot: GraphSchemaSnapshot
    let aliases: GraphSchemaAliasMap
    let foundationalAliases: GraphSchemaAliasMap

    init(
        graphScope: GraphScope,
        snapshot: GraphSchemaSnapshot,
        aliases: GraphSchemaAliasMap,
        foundationalAliases: GraphSchemaAliasMap? = nil
    ) {
        self.graphScope = graphScope
        self.snapshot = snapshot
        self.aliases = aliases
        self.foundationalAliases = foundationalAliases ?? aliases
    }
}

nonisolated struct GraphSchemaLimits: Hashable, Sendable {
    let maximumEntities: Int
    let maximumFieldsPerEntity: Int
    let maximumFieldsTotal: Int
    let maximumChoiceOptionsPerField: Int
    let maximumExampleValuesPerField: Int
    let maximumStringLength: Int

    static let `default` = GraphSchemaLimits(
        maximumEntities: 64,
        maximumFieldsPerEntity: 32,
        maximumFieldsTotal: 256,
        maximumChoiceOptionsPerField: 24,
        maximumExampleValuesPerField: 2,
        maximumStringLength: 120
    )

    init(
        maximumEntities: Int,
        maximumFieldsPerEntity: Int,
        maximumFieldsTotal: Int,
        maximumChoiceOptionsPerField: Int,
        maximumExampleValuesPerField: Int,
        maximumStringLength: Int
    ) {
        precondition(maximumEntities > 0)
        precondition(maximumFieldsPerEntity > 0)
        precondition(maximumFieldsTotal > 0)
        precondition(maximumChoiceOptionsPerField > 0)
        precondition(maximumExampleValuesPerField >= 0)
        precondition(maximumStringLength > 0)

        self.maximumEntities = maximumEntities
        self.maximumFieldsPerEntity = maximumFieldsPerEntity
        self.maximumFieldsTotal = maximumFieldsTotal
        self.maximumChoiceOptionsPerField = maximumChoiceOptionsPerField
        self.maximumExampleValuesPerField = maximumExampleValuesPerField
        self.maximumStringLength = maximumStringLength
    }
}
