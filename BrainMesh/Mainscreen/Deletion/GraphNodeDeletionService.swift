//
//  GraphNodeDeletionService.swift
//  BrainMesh
//
//  Centralized, graph-scoped deletion for entities and attributes.
//

import Foundation
import SwiftData
import os

@MainActor
enum GraphNodeDeletionService {

    nonisolated struct Result: Equatable, Sendable {
        let requestedEntityCount: Int
        let requestedAttributeCount: Int
        let deletedEntityCount: Int
        let deletedAttributeCount: Int
        let deletedDetailFieldCount: Int
        let deletedDetailValueCount: Int
        let deletedLinkCount: Int
        let deletedAttachmentCount: Int

        static let empty = Result(
            requestedEntityCount: 0,
            requestedAttributeCount: 0,
            deletedEntityCount: 0,
            deletedAttributeCount: 0,
            deletedDetailFieldCount: 0,
            deletedDetailValueCount: 0,
            deletedLinkCount: 0,
            deletedAttachmentCount: 0
        )
    }

    nonisolated enum DeletionError: LocalizedError, Equatable, Sendable {
        case missingGraphScope
        case mixedGraphScope
        case crossGraphRelationship
        case cancelled
        case persistenceFailure

        var errorDescription: String? {
            switch self {
            case .missingGraphScope:
                return
                    "Die Löschung wurde abgebrochen, weil der Datensatz keinem Graphen eindeutig zugeordnet ist. Bitte öffne den Graph erneut und versuche es noch einmal."
            case .mixedGraphScope:
                return "Die ausgewählten Datensätze gehören nicht zum selben Graphen und wurden nicht gelöscht."
            case .crossGraphRelationship:
                return
                    "Die Löschung wurde aus Sicherheitsgründen abgebrochen, weil abhängige Datensätze einem anderen Graphen zugeordnet sind."
            case .cancelled:
                return "Die Löschung wurde abgebrochen. Es wurden keine Änderungen übernommen."
            case .persistenceFailure:
                return "Die Löschung konnte nicht vollständig gespeichert werden. Es wurden keine unvollständigen Änderungen übernommen."
            }
        }
    }

    private nonisolated enum Operation: String, Sendable {
        case attribute
        case attributeBatch = "attribute_batch"
        case entity
        case entityBatch = "entity_batch"
    }

    private struct PreparedAttributeDeletion {
        let requestedAttributeCount: Int
        let attributes: [MetaAttribute]
        let orphanDetailValues: [MetaDetailFieldValue]
        let detailValueCount: Int
        let linkPlan: LinkCleanup.DeletionPlan
        let attachmentPlan: AttachmentCleanup.DeletionPlan
    }

    private struct PreparedEntityDeletion {
        let requestedEntityCount: Int
        let entities: [MetaEntity]
        let childAttributes: [MetaAttribute]
        let detailFields: [MetaDetailFieldDefinition]
        let orphanDetailValues: [MetaDetailFieldValue]
        let detailValueCount: Int
        let linkPlan: LinkCleanup.DeletionPlan
        let attachmentPlan: AttachmentCleanup.DeletionPlan
    }

    private static let log = Logger(
        subsystem: "BrainMesh",
        category: "GraphNodeDeletionService"
    )

    @discardableResult
    static func deleteAttribute(
        _ attribute: MetaAttribute,
        in modelContext: ModelContext
    ) throws -> Result {
        try deleteAttributes(
            [attribute],
            operation: .attribute,
            in: modelContext
        )
    }

    @discardableResult
    static func deleteAttributes(
        _ attributes: [MetaAttribute],
        in modelContext: ModelContext
    ) throws -> Result {
        try deleteAttributes(
            attributes,
            operation: .attributeBatch,
            in: modelContext
        )
    }

    @discardableResult
    static func deleteEntity(
        _ entity: MetaEntity,
        in modelContext: ModelContext
    ) throws -> Result {
        try deleteEntities(
            [entity],
            operation: .entity,
            in: modelContext
        )
    }

    @discardableResult
    static func deleteEntities(
        _ entities: [MetaEntity],
        in modelContext: ModelContext
    ) throws -> Result {
        try deleteEntities(
            entities,
            operation: .entityBatch,
            in: modelContext
        )
    }

    private static func deleteAttributes(
        _ attributes: [MetaAttribute],
        operation: Operation,
        in modelContext: ModelContext
    ) throws -> Result {
        guard !attributes.isEmpty else { return .empty }

        let prepared: PreparedAttributeDeletion
        do {
            try Task.checkCancellation()
            prepared = try prepareAttributeDeletion(
                attributes,
                in: modelContext
            )
            try Task.checkCancellation()
        } catch {
            throw mappedPreparationError(error, operation: operation)
        }

        let linkResult = LinkCleanup.applyDeletion(
            prepared.linkPlan,
            in: modelContext
        )
        let attachmentResult = AttachmentCleanup.applyDeletion(
            prepared.attachmentPlan,
            in: modelContext
        )

        for value in prepared.orphanDetailValues {
            modelContext.delete(value)
        }

        for attribute in prepared.attributes {
            attribute.owner?.removeAttribute(attribute)
            modelContext.delete(attribute)
        }

        let result = Result(
            requestedEntityCount: 0,
            requestedAttributeCount: prepared.requestedAttributeCount,
            deletedEntityCount: 0,
            deletedAttributeCount: prepared.attributes.count,
            deletedDetailFieldCount: 0,
            deletedDetailValueCount: prepared.detailValueCount,
            deletedLinkCount: linkResult.deletedCount,
            deletedAttachmentCount: attachmentResult.deletedCount
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            logFailure(error, operation: operation, stage: "save")
            throw DeletionError.persistenceFailure
        }

        AttachmentCleanup.deleteCachedFiles(for: attachmentResult)
        logSuccess(result, operation: operation)
        return result
    }

    private static func deleteEntities(
        _ entities: [MetaEntity],
        operation: Operation,
        in modelContext: ModelContext
    ) throws -> Result {
        guard !entities.isEmpty else { return .empty }

        let prepared: PreparedEntityDeletion
        do {
            try Task.checkCancellation()
            prepared = try prepareEntityDeletion(
                entities,
                in: modelContext
            )
            try Task.checkCancellation()
        } catch {
            throw mappedPreparationError(error, operation: operation)
        }

        let linkResult = LinkCleanup.applyDeletion(
            prepared.linkPlan,
            in: modelContext
        )
        let attachmentResult = AttachmentCleanup.applyDeletion(
            prepared.attachmentPlan,
            in: modelContext
        )

        for value in prepared.orphanDetailValues {
            modelContext.delete(value)
        }

        for entity in prepared.entities {
            modelContext.delete(entity)
        }

        let result = Result(
            requestedEntityCount: prepared.requestedEntityCount,
            requestedAttributeCount: 0,
            deletedEntityCount: prepared.entities.count,
            deletedAttributeCount: prepared.childAttributes.count,
            deletedDetailFieldCount: prepared.detailFields.count,
            deletedDetailValueCount: prepared.detailValueCount,
            deletedLinkCount: linkResult.deletedCount,
            deletedAttachmentCount: attachmentResult.deletedCount
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            logFailure(error, operation: operation, stage: "save")
            throw DeletionError.persistenceFailure
        }

        AttachmentCleanup.deleteCachedFiles(for: attachmentResult)
        logSuccess(result, operation: operation)
        return result
    }

    private static func prepareAttributeDeletion(
        _ attributes: [MetaAttribute],
        in modelContext: ModelContext
    ) throws -> PreparedAttributeDeletion {
        let graphID = try commonGraphID(attributes.map(\.graphID))
        let requestedIDs = Set(attributes.map(\.id))
        let gid = graphID

        let attributeDescriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate { attribute in
                attribute.graphID == gid
            }
        )
        let storedAttributes = uniqueModels(
            try modelContext.fetch(attributeDescriptor).filter { attribute in
                requestedIDs.contains(attribute.id)
            }
        )

        try validateAttributeRelationships(
            uniqueModels(attributes + storedAttributes),
            graphID: graphID
        )

        let detailValueDescriptor = FetchDescriptor<MetaDetailFieldValue>(
            predicate: #Predicate { value in
                value.graphID == gid
            }
        )
        let matchingDetailValues = uniqueModels(
            try modelContext.fetch(detailValueDescriptor).filter { value in
                requestedIDs.contains(value.attributeID)
            }
        )
        try validateDetailValueRelationships(
            matchingDetailValues,
            graphID: graphID
        )

        let storedAttributeIDs = Set(storedAttributes.map(\.id))
        let orphanDetailValues = matchingDetailValues.filter { value in
            guard let relatedAttribute = value.attribute else { return true }
            return !storedAttributeIDs.contains(relatedAttribute.id)
        }

        let nodes = Set(
            requestedIDs.map { id in
                NodeRefKey(kind: .attribute, id: id)
            }
        )
        let linkPlan = try LinkCleanup.prepareDeletion(
            referencing: nodes,
            graphID: graphID,
            in: modelContext
        )
        let attachmentPlan = try AttachmentCleanup.prepareDeletion(
            owners: nodes,
            graphID: graphID,
            in: modelContext
        )

        return PreparedAttributeDeletion(
            requestedAttributeCount: requestedIDs.count,
            attributes: storedAttributes,
            orphanDetailValues: orphanDetailValues,
            detailValueCount: matchingDetailValues.count,
            linkPlan: linkPlan,
            attachmentPlan: attachmentPlan
        )
    }

    private static func prepareEntityDeletion(
        _ entities: [MetaEntity],
        in modelContext: ModelContext
    ) throws -> PreparedEntityDeletion {
        let graphID = try commonGraphID(entities.map(\.graphID))
        let requestedEntityIDs = Set(entities.map(\.id))
        let gid = graphID

        let entityDescriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { entity in
                entity.graphID == gid
            }
        )
        let storedEntities = uniqueModels(
            try modelContext.fetch(entityDescriptor).filter { entity in
                requestedEntityIDs.contains(entity.id)
            }
        )

        let entityModelsForValidation = uniqueModels(entities + storedEntities)
        try validateEntityRelationships(
            entityModelsForValidation,
            graphID: graphID
        )

        let relationshipChildIDs = Set(
            entityModelsForValidation
                .flatMap(\.attributesList)
                .map(\.id)
        )

        let attributeDescriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate { attribute in
                attribute.graphID == gid
            }
        )
        let allGraphAttributes = try modelContext.fetch(attributeDescriptor)
        let childAttributes = uniqueModels(
            allGraphAttributes.filter { attribute in
                guard let ownerID = attribute.owner?.id else { return false }
                return requestedEntityIDs.contains(ownerID)
            }
        )

        try validateAttributeRelationships(
            childAttributes,
            graphID: graphID
        )

        var childAttributeIDs = relationshipChildIDs
        childAttributeIDs.formUnion(childAttributes.map(\.id))

        let detailFields = uniqueModels(
            storedEntities.flatMap(\.detailFieldsList)
        )

        let detailValueDescriptor = FetchDescriptor<MetaDetailFieldValue>(
            predicate: #Predicate { value in
                value.graphID == gid
            }
        )
        let matchingDetailValues = uniqueModels(
            try modelContext.fetch(detailValueDescriptor).filter { value in
                childAttributeIDs.contains(value.attributeID)
            }
        )
        try validateDetailValueRelationships(
            matchingDetailValues,
            graphID: graphID
        )

        let childAttributeIDSet = Set(childAttributes.map(\.id))
        let orphanDetailValues = matchingDetailValues.filter { value in
            guard let relatedAttribute = value.attribute else { return true }
            return !childAttributeIDSet.contains(relatedAttribute.id)
        }

        var nodeReferences = Set(
            requestedEntityIDs.map { id in
                NodeRefKey(kind: .entity, id: id)
            }
        )
        nodeReferences.formUnion(
            childAttributeIDs.map { id in
                NodeRefKey(kind: .attribute, id: id)
            }
        )

        let linkPlan = try LinkCleanup.prepareDeletion(
            referencing: nodeReferences,
            graphID: graphID,
            in: modelContext
        )
        let attachmentPlan = try AttachmentCleanup.prepareDeletion(
            owners: nodeReferences,
            graphID: graphID,
            in: modelContext
        )

        return PreparedEntityDeletion(
            requestedEntityCount: requestedEntityIDs.count,
            entities: storedEntities,
            childAttributes: childAttributes,
            detailFields: detailFields,
            orphanDetailValues: orphanDetailValues,
            detailValueCount: matchingDetailValues.count,
            linkPlan: linkPlan,
            attachmentPlan: attachmentPlan
        )
    }

    private static func commonGraphID(_ graphIDs: [UUID?]) throws -> UUID {
        let concreteGraphIDs = graphIDs.compactMap { $0 }
        guard concreteGraphIDs.count == graphIDs.count,
            let firstGraphID = concreteGraphIDs.first
        else {
            throw DeletionError.missingGraphScope
        }
        guard concreteGraphIDs.allSatisfy({ $0 == firstGraphID }) else {
            throw DeletionError.mixedGraphScope
        }
        return firstGraphID
    }

    private static func validateEntityRelationships(
        _ entities: [MetaEntity],
        graphID: UUID
    ) throws {
        for entity in entities {
            if entity.attributesList.contains(where: { $0.graphID != graphID }) {
                throw DeletionError.crossGraphRelationship
            }
            if entity.detailFieldsList.contains(where: { $0.graphID != graphID }) {
                throw DeletionError.crossGraphRelationship
            }
        }
    }

    private static func validateAttributeRelationships(
        _ attributes: [MetaAttribute],
        graphID: UUID
    ) throws {
        for attribute in attributes {
            if let owner = attribute.owner, owner.graphID != graphID {
                throw DeletionError.crossGraphRelationship
            }
            if attribute.detailValuesList.contains(where: { $0.graphID != graphID }) {
                throw DeletionError.crossGraphRelationship
            }
        }
    }

    private static func validateDetailValueRelationships(
        _ values: [MetaDetailFieldValue],
        graphID: UUID
    ) throws {
        for value in values {
            if let attribute = value.attribute, attribute.graphID != graphID {
                throw DeletionError.crossGraphRelationship
            }
        }
    }

    private static func uniqueModels<Model: AnyObject>(_ models: [Model]) -> [Model] {
        var seen = Set<ObjectIdentifier>()
        return models.filter { model in
            seen.insert(ObjectIdentifier(model)).inserted
        }
    }

    private static func mappedPreparationError(
        _ error: Swift.Error,
        operation: Operation
    ) -> Swift.Error {
        if let deletionError = error as? DeletionError {
            logFailure(deletionError, operation: operation, stage: "validation")
            return deletionError
        }
        if error is CancellationError {
            logFailure(error, operation: operation, stage: "cancelled")
            return DeletionError.cancelled
        }

        logFailure(error, operation: operation, stage: "prepare")
        return DeletionError.persistenceFailure
    }

    private static func logSuccess(
        _ result: Result,
        operation: Operation
    ) {
        log.info(
            "node_delete_completed operation=\(operation.rawValue, privacy: .public) requested_entities=\(result.requestedEntityCount, privacy: .public) requested_attributes=\(result.requestedAttributeCount, privacy: .public) deleted_entities=\(result.deletedEntityCount, privacy: .public) deleted_attributes=\(result.deletedAttributeCount, privacy: .public) deleted_detail_fields=\(result.deletedDetailFieldCount, privacy: .public) deleted_detail_values=\(result.deletedDetailValueCount, privacy: .public) deleted_links=\(result.deletedLinkCount, privacy: .public) deleted_attachments=\(result.deletedAttachmentCount, privacy: .public)"
        )
    }

    private static func logFailure(
        _ error: Swift.Error,
        operation: Operation,
        stage: String
    ) {
        let nsError = error as NSError
        log.error(
            "node_delete_failed operation=\(operation.rawValue, privacy: .public) stage=\(stage, privacy: .public) error_domain=\(nsError.domain, privacy: .public) error_code=\(nsError.code, privacy: .public)"
        )
    }
}
