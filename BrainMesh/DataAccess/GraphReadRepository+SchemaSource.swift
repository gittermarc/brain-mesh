//
//  GraphReadRepository+SchemaSource.swift
//  BrainMesh
//
//  Narrow SwiftData fetch path for graph-chat schema construction.
//

import Foundation
import SwiftData

extension GraphReadRepository {
    func schemaSourceSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID> = []
    ) async throws -> GraphSchemaSourceSnapshotDTO {
        let context = try await makeReadContext()
        let sourceScope = GraphSchemaSourceScope(
            exampleFieldIDs: exampleFieldIDs
        )
        try checkCancellation()

        schemaSourceInstrumentation.record(.graph)
        guard let graphModel = try context.fetch(
            GraphScopedFetches.graph(in: scope)
        ).first else {
            throw GraphReadRepositoryError.graphNotFound(scope)
        }
        try checkCancellation()

        schemaSourceInstrumentation.record(.entities)
        let entityModels = try context.fetch(
            GraphScopedFetches.entities(in: scope)
        )
        try checkCancellation()
        var entities: [GraphSchemaSourceEntityDTO] = []
        entities.reserveCapacity(entityModels.count)
        for (index, model) in entityModels.enumerated() {
            try checkCancellation(at: index)
            guard model.graphID == scope.graphID else { continue }
            entities.append(
                GraphSchemaSourceEntityDTO(
                    id: model.id,
                    scope: scope,
                    name: model.name,
                    createdAt: model.createdAt
                )
            )
        }
        entities.sort(by: Self.schemaSourceEntitySort)
        var entityNames: [UUID: String] = [:]
        entityNames.reserveCapacity(entities.count)
        for entity in entities where entityNames[entity.id] == nil {
            entityNames[entity.id] = entity.name
        }
        let entityIDs = Set(entityNames.keys)

        schemaSourceInstrumentation.record(.nodes)
        let nodeModels = try context.fetch(
            GraphScopedFetches.attributes(in: scope)
        )
        try checkCancellation()
        var nodes: [GraphSchemaSourceNodeDTO] = []
        nodes.reserveCapacity(nodeModels.count)
        for (index, model) in nodeModels.enumerated() {
            try checkCancellation(at: index)
            guard model.graphID == scope.graphID,
                  let owner = model.owner,
                  owner.graphID == scope.graphID,
                  entityIDs.contains(owner.id),
                  let ownerName = entityNames[owner.id] else {
                continue
            }
            nodes.append(
                GraphSchemaSourceNodeDTO(
                    id: model.id,
                    scope: scope,
                    ownerEntityID: owner.id,
                    name: model.name,
                    displayName: "\(ownerName) · \(model.name)"
                )
            )
        }
        nodes.sort(by: Self.schemaSourceNodeSort)

        schemaSourceInstrumentation.record(.fieldDefinitions)
        let fieldModels = try context.fetch(
            GraphScopedFetches.detailFieldDefinitions(in: scope)
        )
        try checkCancellation()
        var fields: [GraphSchemaSourceFieldDefinitionDTO] = []
        fields.reserveCapacity(fieldModels.count)
        for (index, model) in fieldModels.enumerated() {
            try checkCancellation(at: index)
            let integrity = DetailDataModelSnapshotMapper.field(model)
            guard integrity.graphID == scope.graphID,
                  DetailDataIntegrityPolicy.fieldViolations(integrity).isEmpty,
                  entityIDs.contains(model.entityID) else {
                continue
            }
            fields.append(
                GraphSchemaSourceFieldDefinitionDTO(
                    id: model.id,
                    scope: scope,
                    entityID: model.entityID,
                    name: model.name,
                    typeRaw: model.typeRaw,
                    sortIndex: model.sortIndex,
                    isPinned: model.isPinned,
                    unit: model.unit,
                    options: model.options
                )
            )
        }
        fields.sort(by: Self.schemaSourceFieldSort)
        try checkCancellation()

        let validRequestedFieldIDs = sourceScope.exampleFieldIDSet
            .intersection(Set(fields.map(\.id)))
        let examples: [GraphSchemaSourceExampleValueDTO]
        if validRequestedFieldIDs.isEmpty || nodes.isEmpty {
            examples = []
        } else {
            schemaSourceInstrumentation.record(.exampleValues)
            let valueModels = try context.fetch(
                GraphScopedFetches.detailValues(
                    fieldIDs: Array(validRequestedFieldIDs),
                    attributeIDs: nodes.map(\.id),
                    in: scope
                )
            )
            try checkCancellation()

            // Reuse the centralized authority policy with narrow compatibility values. These
            // values are created from already fetched schema rows and trigger no extra fetches.
            let compatibilityFields = fields.map { field in
                GraphDetailFieldDefinitionDTO(
                    id: field.id,
                    scope: field.scope,
                    entityID: field.entityID,
                    entityLabel: entityNames[field.entityID],
                    name: field.name,
                    typeRaw: field.typeRaw,
                    sortIndex: field.sortIndex,
                    isPinned: field.isPinned,
                    unit: field.unit,
                    options: field.options
                )
            }
            let compatibilityNodes = nodes.map { node in
                GraphAttributeDTO(
                    id: node.id,
                    scope: node.scope,
                    ownerEntityID: node.ownerEntityID,
                    ownerLabel: entityNames[node.ownerEntityID],
                    name: node.name,
                    displayLabel: node.displayName,
                    notes: "",
                    iconSymbolName: nil
                )
            }
            let authority = try fetchDetailValueAuthority(
                in: scope,
                context: context,
                models: valueModels,
                prefetchedDefinitions: compatibilityFields,
                prefetchedAttributes: compatibilityNodes
            )
            examples = authority.values.map { value in
                GraphSchemaSourceExampleValueDTO(
                    id: value.id,
                    scope: value.scope,
                    attributeID: value.attributeID,
                    fieldID: value.fieldID,
                    value: value.value
                )
            }
        }
        try checkCancellation()

        return GraphSchemaSourceSnapshotDTO(
            scope: scope,
            sourceScope: sourceScope,
            graph: GraphReadDTOMapper.graph(graphModel, scope: scope),
            entities: entities,
            nodes: nodes,
            fieldDefinitions: fields,
            exampleValues: examples
        )
    }

    nonisolated private static func schemaSourceEntitySort(
        _ lhs: GraphSchemaSourceEntityDTO,
        _ rhs: GraphSchemaSourceEntityDTO
    ) -> Bool {
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func schemaSourceNodeSort(
        _ lhs: GraphSchemaSourceNodeDTO,
        _ rhs: GraphSchemaSourceNodeDTO
    ) -> Bool {
        let lhsName = BMSearch.fold(lhs.displayName)
        let rhsName = BMSearch.fold(rhs.displayName)
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func schemaSourceFieldSort(
        _ lhs: GraphSchemaSourceFieldDefinitionDTO,
        _ rhs: GraphSchemaSourceFieldDefinitionDTO
    ) -> Bool {
        if lhs.entityID != rhs.entityID {
            return lhs.entityID.uuidString < rhs.entityID.uuidString
        }
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
