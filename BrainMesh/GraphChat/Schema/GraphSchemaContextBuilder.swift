//
//  GraphSchemaContextBuilder.swift
//  BrainMesh
//
//  Pure, cancellable construction of a chat schema context from its narrow source DTO.
//

import Foundation

nonisolated struct GraphSchemaContextBuilder: Sendable {
    let limits: GraphSchemaLimits

    init(limits: GraphSchemaLimits = .default) {
        self.limits = limits
    }

    func build(
        source: GraphSchemaSourceSnapshotDTO,
        cacheKey: GraphSchemaContextCacheKey
    ) throws -> GraphSchemaContext {
        let requestedExampleFieldIDs = source.sourceScope.exampleFieldIDSet
        let includedEntities = Array(
            source.entities.prefix(limits.maximumEntities)
        )
        let includedEntityIDs = Set(includedEntities.map(\.id))
        let sourceEntityIDs = Set(source.entities.map(\.id))

        var nodesByEntityID: [UUID: [GraphSchemaSourceNodeDTO]] = [:]
        nodesByEntityID.reserveCapacity(includedEntities.count)
        for (index, node) in source.nodes.enumerated() {
            try checkCancellation(at: index)
            guard sourceEntityIDs.contains(node.ownerEntityID) else {
                continue
            }
            nodesByEntityID[node.ownerEntityID, default: []].append(node)
        }

        var definitionsByEntityID:
            [UUID: [GraphSchemaSourceFieldDefinitionDTO]] = [:]
        definitionsByEntityID.reserveCapacity(includedEntities.count)
        for (index, definition) in source.fieldDefinitions.enumerated() {
            try checkCancellation(at: index)
            guard sourceEntityIDs.contains(definition.entityID) else {
                continue
            }
            definitionsByEntityID[definition.entityID, default: []]
                .append(definition)
        }
        for entityID in definitionsByEntityID.keys {
            definitionsByEntityID[entityID]?.sort(by: Self.fieldSort)
        }

        let valuesByFieldID = try groupedExampleValues(
            source.exampleValues,
            requestedFieldIDs: requestedExampleFieldIDs
        )

        var entities: [GraphSchemaEntity] = []
        entities.reserveCapacity(includedEntities.count)
        var entityResolutions:
            [GraphEntityAlias: GraphSchemaEntityResolution] = [:]
        entityResolutions.reserveCapacity(includedEntities.count)
        var fieldResolutions:
            [GraphFieldAlias: GraphSchemaFieldResolution] = [:]
        fieldResolutions.reserveCapacity(
            min(source.fieldDefinitions.count, limits.maximumFieldsTotal)
        )
        var nodeEntityIDs: [NodeRefKey: UUID] = [:]
        nodeEntityIDs.reserveCapacity(source.entities.count + source.nodes.count)
        var nodesByKey: [NodeRefKey: GraphSchemaNodeResolution] = [:]
        nodesByKey.reserveCapacity(source.entities.count + source.nodes.count)

        var nextFieldNumber = 1
        var includedFieldCount = 0
        var includedChoiceOptionCount = 0
        var sourceChoiceOptionCount = 0
        var includedExampleCount = 0
        var sourceExampleCount = 0
        var stringsWereTruncated = false

        for (entityIndex, entity) in includedEntities.enumerated() {
            try checkCancellation(at: entityIndex)
            let entityAlias = GraphEntityAlias("E\(entityIndex + 1)")
            let entityName = truncate(
                entity.name,
                didTruncate: &stringsWereTruncated
            )
            let entityResolution = GraphSchemaEntityResolution(
                alias: entityAlias,
                entityID: entity.id,
                name: entity.name
            )
            entityResolutions[entityAlias] = entityResolution
            nodeEntityIDs[entity.nodeKey] = entity.id
            nodesByKey[entity.nodeKey] = GraphSchemaNodeResolution(
                node: entity.nodeKey,
                ownerEntityID: entity.id,
                displayName: entity.name
            )

            let entityNodes = nodesByEntityID[entity.id] ?? []
            for node in entityNodes {
                nodeEntityIDs[node.nodeKey] = entity.id
                nodesByKey[node.nodeKey] = GraphSchemaNodeResolution(
                    node: node.nodeKey,
                    ownerEntityID: entity.id,
                    displayName: node.displayName
                )
            }

            let sourceDefinitions = definitionsByEntityID[entity.id] ?? []
            let remainingGlobalCapacity =
                limits.maximumFieldsTotal - includedFieldCount
            let entityCapacity = min(
                limits.maximumFieldsPerEntity,
                max(remainingGlobalCapacity, 0)
            )
            let includedDefinitions = Array(
                sourceDefinitions.prefix(entityCapacity)
            )
            var schemaFields: [GraphSchemaField] = []
            schemaFields.reserveCapacity(includedDefinitions.count)

            for (fieldIndex, definition) in includedDefinitions.enumerated() {
                try checkCancellation(at: fieldIndex)
                let fieldAlias = GraphFieldAlias("F\(nextFieldNumber)")
                nextFieldNumber += 1
                includedFieldCount += 1

                sourceChoiceOptionCount += definition.options.count
                let includedOptions = Array(
                    definition.options.prefix(
                        limits.maximumChoiceOptionsPerField
                    )
                )
                includedChoiceOptionCount += includedOptions.count
                let choiceOptions = includedOptions.map {
                    truncate($0, didTruncate: &stringsWereTruncated)
                }

                let allExamples = valuesByFieldID[definition.id] ?? []
                sourceExampleCount += allExamples.count
                let includedExamples = Array(
                    allExamples.prefix(limits.maximumExampleValuesPerField)
                )
                includedExampleCount += includedExamples.count
                let exampleValues = includedExamples.map {
                    truncate($0, didTruncate: &stringsWereTruncated)
                }

                let fieldName = truncate(
                    definition.name,
                    didTruncate: &stringsWereTruncated
                )
                let unit = definition.unit.map {
                    truncate($0, didTruncate: &stringsWereTruncated)
                }

                schemaFields.append(
                    GraphSchemaField(
                        alias: fieldAlias,
                        name: fieldName,
                        type: definition.type,
                        unit: unit,
                        choiceOptions: choiceOptions,
                        isPinned: definition.isPinned,
                        sortIndex: definition.sortIndex,
                        exampleValues: exampleValues,
                        optionsWereTruncated:
                            definition.options.count > includedOptions.count,
                        examplesWereTruncated:
                            allExamples.count > includedExamples.count
                    )
                )

                fieldResolutions[fieldAlias] = GraphSchemaFieldResolution(
                    alias: fieldAlias,
                    entityAlias: entityAlias,
                    entityID: entity.id,
                    fieldID: definition.id,
                    name: definition.name,
                    type: definition.type,
                    unit: definition.unit,
                    choiceOptions: includedOptions,
                    isPinned: definition.isPinned,
                    sortIndex: definition.sortIndex
                )
            }

            entities.append(
                GraphSchemaEntity(
                    alias: entityAlias,
                    name: entityName,
                    attributeCount: entityNodes.count,
                    fields: schemaFields,
                    fieldsWereTruncated:
                        sourceDefinitions.count > includedDefinitions.count
                )
            )
        }

        let promptAliasMap = GraphSchemaAliasMap(
            graphScope: source.scope,
            entitiesByAlias: entityResolutions,
            fieldsByAlias: fieldResolutions,
            nodeEntityIDs: nodeEntityIDs,
            nodesByKey: nodesByKey
        )

        var foundationalEntityResolutions = entityResolutions
        var foundationalFieldResolutions = fieldResolutions
        var foundationalNodeEntityIDs = nodeEntityIDs
        var foundationalNodesByKey = nodesByKey
        var resolvedFieldIDs = Set(
            foundationalFieldResolutions.values.map(\.fieldID)
        )
        for (entityIndex, entity) in source.entities.enumerated() {
            try checkCancellation(at: entityIndex)
            let entityAlias = GraphEntityAlias("E\(entityIndex + 1)")
            if foundationalEntityResolutions[entityAlias] == nil {
                foundationalEntityResolutions[entityAlias] =
                    GraphSchemaEntityResolution(
                        alias: entityAlias,
                        entityID: entity.id,
                        name: entity.name
                    )
            }
            foundationalNodeEntityIDs[entity.nodeKey] = entity.id
            foundationalNodesByKey[entity.nodeKey] =
                GraphSchemaNodeResolution(
                    node: entity.nodeKey,
                    ownerEntityID: entity.id,
                    displayName: entity.name
                )
            for node in nodesByEntityID[entity.id] ?? [] {
                foundationalNodeEntityIDs[node.nodeKey] = entity.id
                foundationalNodesByKey[node.nodeKey] =
                    GraphSchemaNodeResolution(
                        node: node.nodeKey,
                        ownerEntityID: entity.id,
                        displayName: node.name
                    )
            }

            for definition in definitionsByEntityID[entity.id] ?? [] {
                guard resolvedFieldIDs.insert(definition.id).inserted else {
                    continue
                }
                let fieldAlias = GraphFieldAlias("F\(nextFieldNumber)")
                nextFieldNumber += 1
                foundationalFieldResolutions[fieldAlias] =
                    GraphSchemaFieldResolution(
                        alias: fieldAlias,
                        entityAlias: entityAlias,
                        entityID: entity.id,
                        fieldID: definition.id,
                        name: definition.name,
                        type: definition.type,
                        unit: definition.unit,
                        choiceOptions: definition.options,
                        isPinned: definition.isPinned,
                        sortIndex: definition.sortIndex
                    )
            }
        }

        let sourceFieldCount = source.fieldDefinitions.filter {
            includedEntityIDs.contains($0.entityID)
        }.count
        let truncation = GraphSchemaTruncation(
            sourceEntityCount: source.entities.count,
            includedEntityCount: entities.count,
            sourceFieldCount: sourceFieldCount,
            includedFieldCount: includedFieldCount,
            sourceChoiceOptionCount: sourceChoiceOptionCount,
            includedChoiceOptionCount: includedChoiceOptionCount,
            sourceExampleValueCount: sourceExampleCount,
            includedExampleValueCount: includedExampleCount,
            stringsWereTruncated: stringsWereTruncated
        )
        let graphName = truncate(
            source.graph.name,
            didTruncate: &stringsWereTruncated
        )
        let finalTruncation = GraphSchemaTruncation(
            sourceEntityCount: truncation.sourceEntityCount,
            includedEntityCount: truncation.includedEntityCount,
            sourceFieldCount: truncation.sourceFieldCount,
            includedFieldCount: truncation.includedFieldCount,
            sourceChoiceOptionCount: truncation.sourceChoiceOptionCount,
            includedChoiceOptionCount: truncation.includedChoiceOptionCount,
            sourceExampleValueCount: truncation.sourceExampleValueCount,
            includedExampleValueCount: truncation.includedExampleValueCount,
            stringsWereTruncated: stringsWereTruncated
        )
        let snapshot = GraphSchemaSnapshot(
            graphName: graphName,
            entities: entities,
            truncation: finalTruncation
        )
        let foundationalAliasMap = GraphSchemaAliasMap(
            graphScope: source.scope,
            entitiesByAlias: foundationalEntityResolutions,
            fieldsByAlias: foundationalFieldResolutions,
            nodeEntityIDs: foundationalNodeEntityIDs,
            nodesByKey: foundationalNodesByKey
        )

        return GraphSchemaContext(
            identity: .cached(cacheKey),
            graphScope: source.scope,
            snapshot: snapshot,
            aliases: promptAliasMap,
            foundationalAliases: foundationalAliasMap
        )
    }

    private func groupedExampleValues(
        _ values: [GraphSchemaSourceExampleValueDTO],
        requestedFieldIDs: Set<UUID>
    ) throws -> [UUID: [GraphSchemaExampleValue]] {
        guard requestedFieldIDs.isEmpty == false,
              limits.maximumExampleValuesPerField > 0 else {
            return [:]
        }

        var result: [UUID: [GraphSchemaExampleValue]] = [:]
        var seen: [UUID: Set<GraphSchemaExampleValue>] = [:]
        for (index, value) in values.enumerated() {
            try checkCancellation(at: index)
            guard requestedFieldIDs.contains(value.fieldID),
                  let example = Self.exampleValue(from: value.value),
                  seen[value.fieldID, default: []].insert(example).inserted else {
                continue
            }
            result[value.fieldID, default: []].append(example)
        }
        for fieldID in result.keys {
            result[fieldID]?.sort(by: Self.exampleSort)
        }
        return result
    }

    private func truncate(
        _ value: String,
        didTruncate: inout Bool
    ) -> String {
        guard value.count > limits.maximumStringLength else { return value }
        didTruncate = true
        return String(value.prefix(limits.maximumStringLength))
    }

    private func truncate(
        _ value: GraphSchemaExampleValue,
        didTruncate: inout Bool
    ) -> GraphSchemaExampleValue {
        switch value {
        case .text(let text):
            return .text(truncate(text, didTruncate: &didTruncate))
        case .choice(let choice):
            return .choice(truncate(choice, didTruncate: &didTruncate))
        case .integer, .decimal, .date, .boolean:
            return value
        }
    }

    private func checkCancellation(at index: Int) throws {
        if index.isMultiple(of: 64) {
            try Task.checkCancellation()
        }
    }

    private static func fieldSort(
        _ lhs: GraphSchemaSourceFieldDefinitionDTO,
        _ rhs: GraphSchemaSourceFieldDefinitionDTO
    ) -> Bool {
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func exampleValue(
        from payload: GraphDetailValuePayload
    ) -> GraphSchemaExampleValue? {
        switch payload {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed)
        case .integer(let value):
            return .integer(value)
        case .decimal(let value):
            return value.isFinite ? .decimal(value) : nil
        case .date(let value):
            return .date(value)
        case .boolean(let value):
            return .boolean(value)
        case .choice(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .choice(trimmed)
        case .empty:
            return nil
        }
    }

    private static func exampleSort(
        _ lhs: GraphSchemaExampleValue,
        _ rhs: GraphSchemaExampleValue
    ) -> Bool {
        exampleSortKey(lhs) < exampleSortKey(rhs)
    }

    private static func exampleSortKey(
        _ value: GraphSchemaExampleValue
    ) -> String {
        switch value {
        case .text(let text):
            return "0:\(BMSearch.fold(text))"
        case .integer(let integer):
            return "1:\(String(format: "%020d", integer))"
        case .decimal(let decimal):
            return "2:\(String(format: "%024.8f", decimal))"
        case .date(let date):
            return "3:\(date.timeIntervalSinceReferenceDate)"
        case .boolean(let boolean):
            return "4:\(boolean ? 1 : 0)"
        case .choice(let choice):
            return "5:\(BMSearch.fold(choice))"
        }
    }
}

