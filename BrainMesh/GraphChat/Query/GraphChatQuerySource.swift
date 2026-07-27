//
//  GraphChatQuerySource.swift
//  BrainMesh
//
//  Narrow, value-only source snapshots for deterministic detail queries.
//

import Foundation
import SwiftData

nonisolated struct GraphChatQuerySourceSnapshot: Sendable {
    let graphScope: GraphScope
    let entity: GraphEntityDTO
    let attributes: [GraphAttributeDTO]
    let fields: [GraphDetailFieldDefinitionDTO]
    let values: [GraphDetailValueDTO]
    let integrityConflictedValueKeys: Set<DetailValueAuthorityKey>

    init(
        graphScope: GraphScope,
        entity: GraphEntityDTO,
        attributes: [GraphAttributeDTO],
        fields: [GraphDetailFieldDefinitionDTO],
        values: [GraphDetailValueDTO],
        integrityConflictedValueKeys: Set<DetailValueAuthorityKey> = []
    ) {
        self.graphScope = graphScope
        self.entity = entity
        self.attributes = attributes
        self.fields = fields
        self.values = values
        self.integrityConflictedValueKeys = integrityConflictedValueKeys
    }
}

nonisolated protocol GraphChatQueryReading: Sendable {
    func graphChatQuerySource(
        entityID: UUID,
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) async throws -> GraphChatQuerySourceSnapshot?
}

extension GraphReadRepository: GraphChatQueryReading {
    func graphChatQuerySource(
        entityID: UUID,
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) async throws -> GraphChatQuerySourceSnapshot? {
        let context = try await makeReadContext()
        try checkCancellation()

        guard let entityModel = try context.fetch(
            GraphScopedFetches.entity(id: entityID, in: scope)
        ).first else {
            return nil
        }
        let entity = GraphReadDTOMapper.entity(entityModel, scope: scope)
        try checkCancellation()

        let attributeModels = entityModel.attributesList.filter {
            $0.graphID == scope.graphID
        }
        let attributes = try mapAttributes(attributeModels, scope: scope)
        let attributeIDs = attributes.map(\.id)
        try checkCancellation()

        guard fieldIDs.isEmpty == false else {
            return GraphChatQuerySourceSnapshot(
                graphScope: scope,
                entity: entity,
                attributes: attributes,
                fields: [],
                values: []
            )
        }

        let sortedFieldIDs = fieldIDs.sorted { $0.uuidString < $1.uuidString }
        let fieldModels = try context.fetch(
            GraphScopedFetches.detailFieldDefinitions(ids: sortedFieldIDs, in: scope)
        )
        let fields = try mapDetailFieldDefinitions(fieldModels, scope: scope)
            .filter { $0.entityID == entityID }
            .sorted(by: GraphReadRepository.detailFieldSort)
        let validFieldIDs = fields.map(\.id)
        try checkCancellation()

        guard validFieldIDs.isEmpty == false else {
            return GraphChatQuerySourceSnapshot(
                graphScope: scope,
                entity: entity,
                attributes: attributes,
                fields: [],
                values: []
            )
        }
        guard attributeIDs.isEmpty == false else {
            return GraphChatQuerySourceSnapshot(
                graphScope: scope,
                entity: entity,
                attributes: [],
                fields: fields,
                values: []
            )
        }

        let valueModels = try context.fetch(
            GraphScopedFetches.detailValues(
                fieldIDs: validFieldIDs,
                attributeIDs: attributeIDs,
                in: scope
            )
        )
        let authority = try fetchDetailValueAuthority(
            in: scope,
            context: context,
            models: valueModels,
            prefetchedDefinitions: fields,
            prefetchedAttributes: attributes
        )
        try checkCancellation()

        return GraphChatQuerySourceSnapshot(
            graphScope: scope,
            entity: entity,
            attributes: attributes,
            fields: fields,
            values: authority.values,
            integrityConflictedValueKeys: authority.conflictedKeys
        )
    }
}
