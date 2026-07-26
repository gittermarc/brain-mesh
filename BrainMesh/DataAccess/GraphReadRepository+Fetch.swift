//
//  GraphReadRepository+Fetch.swift
//  BrainMesh
//
//  Internal fetch and mapping batches for GraphReadRepository.
//

import Foundation
import SwiftData

extension GraphReadRepository {
    func fetchEntities(
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [GraphEntityDTO] {
        try checkCancellation()
        let models = try context.fetch(GraphScopedFetches.entities(in: scope))
        try checkCancellation()

        var values: [GraphEntityDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.entity(model, scope: scope))
        }
        try checkCancellation()
        return values.sorted(by: Self.entitySort)
    }

    func fetchAttributes(
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [GraphAttributeDTO] {
        try checkCancellation()
        let models = try context.fetch(GraphScopedFetches.attributes(in: scope))
        try checkCancellation()

        var values: [GraphAttributeDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.attribute(model, scope: scope))
        }
        try checkCancellation()
        return values.sorted(by: Self.attributeSort)
    }

    func fetchLinks(
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [GraphLinkDTO] {
        try checkCancellation()
        let models = try context.fetch(GraphScopedFetches.links(in: scope))
        try checkCancellation()

        var values: [GraphLinkDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.link(model, scope: scope))
        }
        try checkCancellation()
        return values.sorted(by: Self.linkSort)
    }

    func fetchDetailFieldDefinitions(
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [GraphDetailFieldDefinitionDTO] {
        try checkCancellation()
        let models = try context.fetch(GraphScopedFetches.detailFieldDefinitions(in: scope))
        try checkCancellation()
        let values = try mapDetailFieldDefinitions(models, scope: scope)
        try checkCancellation()
        return values.sorted(by: Self.detailFieldSort)
    }

    func fetchDetailValues(
        in scope: GraphScope,
        context: ModelContext,
        models prefetchedModels: [MetaDetailFieldValue]? = nil,
        prefetchedDefinitions: [GraphDetailFieldDefinitionDTO]? = nil,
        prefetchedAttributes: [GraphAttributeDTO]? = nil
    ) throws -> [GraphDetailValueDTO] {
        try checkCancellation()
        let models: [MetaDetailFieldValue]
        if let prefetchedModels {
            models = prefetchedModels
        } else {
            models = try context.fetch(GraphScopedFetches.detailValues(in: scope))
        }
        try checkCancellation()

        let definitions: [GraphDetailFieldDefinitionDTO]
        if let prefetchedDefinitions {
            definitions = prefetchedDefinitions
        } else {
            let fieldIDs = Array(Set(models.map(\.fieldID)))
            if fieldIDs.isEmpty {
                definitions = []
            } else {
                let fieldModels = try context.fetch(
                    GraphScopedFetches.detailFieldDefinitions(ids: fieldIDs, in: scope)
                )
                definitions = try mapDetailFieldDefinitions(fieldModels, scope: scope)
            }
        }
        try checkCancellation()

        let attributes: [GraphAttributeDTO]
        if let prefetchedAttributes {
            attributes = prefetchedAttributes
        } else {
            let attributeIDs = Array(Set(models.map(\.attributeID)))
            if attributeIDs.isEmpty {
                attributes = []
            } else {
                let attributeModels = try context.fetch(
                    GraphScopedFetches.attributes(ids: attributeIDs, in: scope)
                )
                attributes = try mapAttributes(attributeModels, scope: scope)
            }
        }
        try checkCancellation()

        let definitionMap = Self.detailFieldMap(definitions)
        let attributeMap = Self.attributeMap(attributes)
        var groupedModels: [DetailValueAuthorityKey: [MetaDetailFieldValue]] = [:]
        var fieldSnapshots: [DetailValueAuthorityKey: DetailFieldIntegritySnapshot] = [:]
        var attributeSnapshots: [DetailValueAuthorityKey: DetailAttributeIntegritySnapshot] = [:]

        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            guard let field = definitionMap[model.fieldID],
                  let attribute = attributeMap[model.attributeID],
                  let ownerEntityID = attribute.ownerEntityID else {
                continue
            }
            let fieldSnapshot = DetailFieldIntegritySnapshot(
                id: field.id,
                graphID: field.scope.graphID,
                entityID: field.entityID,
                ownerID: field.entityID,
                ownerGraphID: field.scope.graphID,
                type: field.type
            )
            let attributeSnapshot = DetailAttributeIntegritySnapshot(
                id: attribute.id,
                graphID: attribute.scope.graphID,
                ownerEntityID: ownerEntityID,
                ownerGraphID: attribute.scope.graphID
            )
            guard let key = DetailDataIntegrityPolicy.key(
                for: fieldSnapshot,
                attribute: attributeSnapshot
            ) else {
                continue
            }
            groupedModels[key, default: []].append(model)
            fieldSnapshots[key] = fieldSnapshot
            attributeSnapshots[key] = attributeSnapshot
        }

        var values: [GraphDetailValueDTO] = []
        values.reserveCapacity(groupedModels.count)
        let orderedKeys = groupedModels.keys.sorted { lhs, rhs in
            if lhs.attributeID != rhs.attributeID {
                return lhs.attributeID.uuidString < rhs.attributeID.uuidString
            }
            return lhs.fieldID.uuidString < rhs.fieldID.uuidString
        }
        for (index, key) in orderedKeys.enumerated() {
            try checkCancellation(at: index)
            guard let fieldSnapshot = fieldSnapshots[key],
                  let attributeSnapshot = attributeSnapshots[key] else {
                continue
            }
            let candidates = groupedModels[key] ?? []
            let resolution = DetailDataIntegrityPolicy.resolveAuthority(
                field: fieldSnapshot,
                attribute: attributeSnapshot,
                records: candidates.map {
                    DetailDataModelSnapshotMapper.value($0)
                }
            )
            guard case .authoritative(let recordID, let authoritativeValue, _) = resolution,
                  let model = candidates.first(where: { $0.id == recordID }) else {
                continue
            }
            values.append(
                GraphReadDTOMapper.detailValue(
                    model,
                    scope: scope,
                    field: definitionMap[model.fieldID],
                    attribute: attributeMap[model.attributeID],
                    authoritativeValue: authoritativeValue
                )
            )
        }
        try checkCancellation()
        return values.sorted(by: Self.detailValueSort)
    }

    func fetchAttachmentMetadata(
        in scope: GraphScope,
        context: ModelContext,
        models prefetchedModels: [MetaAttachment]? = nil,
        prefetchedEntities: [GraphEntityDTO]? = nil,
        prefetchedAttributes: [GraphAttributeDTO]? = nil
    ) throws -> [GraphAttachmentMetadataDTO] {
        try checkCancellation()
        let models: [MetaAttachment]
        if let prefetchedModels {
            models = prefetchedModels
        } else {
            models = try context.fetch(GraphScopedFetches.attachments(in: scope))
        }
        try checkCancellation()

        let entityIDs = Set(
            models.lazy
                .filter { $0.ownerKindRaw == NodeKind.entity.rawValue }
                .map(\.ownerID)
        )
        let attributeIDs = Set(
            models.lazy
                .filter { $0.ownerKindRaw == NodeKind.attribute.rawValue }
                .map(\.ownerID)
        )

        let entities: [GraphEntityDTO]
        if let prefetchedEntities {
            entities = prefetchedEntities.filter { entityIDs.contains($0.id) }
        } else if entityIDs.isEmpty {
            entities = []
        } else {
            let entityModels = try context.fetch(
                GraphScopedFetches.entities(ids: Array(entityIDs), in: scope)
            )
            entities = try mapEntities(entityModels, scope: scope)
        }
        try checkCancellation()

        let attributes: [GraphAttributeDTO]
        if let prefetchedAttributes {
            attributes = prefetchedAttributes.filter { attributeIDs.contains($0.id) }
        } else if attributeIDs.isEmpty {
            attributes = []
        } else {
            let attributeModels = try context.fetch(
                GraphScopedFetches.attributes(ids: Array(attributeIDs), in: scope)
            )
            attributes = try mapAttributes(attributeModels, scope: scope)
        }
        try checkCancellation()

        var entityLabels: [UUID: String] = [:]
        entityLabels.reserveCapacity(entities.count)
        for entity in entities {
            entityLabels[entity.id] = entity.name
        }

        var attributeLabels: [UUID: String] = [:]
        attributeLabels.reserveCapacity(attributes.count)
        for attribute in attributes {
            attributeLabels[attribute.id] = attribute.displayLabel
        }

        var values: [GraphAttachmentMetadataDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            let ownerLabel: String?
            switch NodeKind(rawValue: model.ownerKindRaw) {
            case .some(.entity):
                ownerLabel = entityLabels[model.ownerID]
            case .some(.attribute):
                ownerLabel = attributeLabels[model.ownerID]
            case .none:
                ownerLabel = nil
            }
            values.append(
                GraphReadDTOMapper.attachmentMetadata(
                    model,
                    scope: scope,
                    ownerLabel: ownerLabel
                )
            )
        }
        try checkCancellation()
        return values.sorted(by: Self.attachmentSort)
    }

    func mapEntities(
        _ models: [MetaEntity],
        scope: GraphScope
    ) throws -> [GraphEntityDTO] {
        var values: [GraphEntityDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.entity(model, scope: scope))
        }
        try checkCancellation()
        return values
    }

    func mapAttributes(
        _ models: [MetaAttribute],
        scope: GraphScope
    ) throws -> [GraphAttributeDTO] {
        var values: [GraphAttributeDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.attribute(model, scope: scope))
        }
        try checkCancellation()
        return values
    }

    func mapDetailFieldDefinitions(
        _ models: [MetaDetailFieldDefinition],
        scope: GraphScope
    ) throws -> [GraphDetailFieldDefinitionDTO] {
        var values: [GraphDetailFieldDefinitionDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            let snapshot = DetailDataModelSnapshotMapper.field(model)
            guard snapshot.graphID == scope.graphID,
                  DetailDataIntegrityPolicy.fieldViolations(snapshot).isEmpty else {
                continue
            }
            values.append(GraphReadDTOMapper.detailFieldDefinition(model, scope: scope))
        }
        try checkCancellation()
        return values
    }
}
