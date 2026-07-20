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
    typealias CacheFileDeletion = @MainActor (AttachmentCleanup.Result) -> Void
    typealias HeaderImageDeletion = @MainActor ([String]) -> Void

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

        var hasDeletedData: Bool {
            deletedEntityCount > 0 ||
            deletedAttributeCount > 0 ||
            deletedDetailFieldCount > 0 ||
            deletedDetailValueCount > 0 ||
            deletedLinkCount > 0 ||
            deletedAttachmentCount > 0
        }
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
                return "Die Löschung wurde abgebrochen, weil der Datensatz keinem Graphen eindeutig zugeordnet ist. Bitte öffne den Graph erneut und versuche es noch einmal."
            case .mixedGraphScope:
                return "Die ausgewählten Datensätze gehören nicht zum selben Graphen und wurden nicht gelöscht."
            case .crossGraphRelationship:
                return "Die Löschung wurde aus Sicherheitsgründen abgebrochen, weil abhängige Datensätze einem anderen Graphen zugeordnet sind."
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
        let graphID: UUID
        let requestedAttributeCount: Int
        let attributes: [MetaAttribute]
        let detailValues: [MetaDetailFieldValue]
        let orphanDetailValues: [MetaDetailFieldValue]
        let linkPlan: LinkCleanup.DeletionPlan
        let attachmentPlan: AttachmentCleanup.DeletionPlan
        let headerImagePaths: [String]
    }

    private struct PreparedEntityDeletion {
        let graphID: UUID
        let requestedEntityCount: Int
        let entities: [MetaEntity]
        let childAttributes: [MetaAttribute]
        let detailFields: [MetaDetailFieldDefinition]
        let orphanDetailFields: [MetaDetailFieldDefinition]
        let detailValues: [MetaDetailFieldValue]
        let orphanDetailValues: [MetaDetailFieldValue]
        let linkPlan: LinkCleanup.DeletionPlan
        let attachmentPlan: AttachmentCleanup.DeletionPlan
        let headerImagePaths: [String]
    }

    private static let log = Logger(
        subsystem: "BrainMesh",
        category: "GraphNodeDeletionService"
    )

    @discardableResult
    static func deleteAttribute(
        _ attribute: MetaAttribute,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        cacheFileDeletion: CacheFileDeletion = { result in
            AttachmentCleanup.deleteCachedFiles(for: result)
        },
        headerImageDeletion: HeaderImageDeletion = { paths in
            for path in paths { ImageStore.delete(path: path) }
        }
    ) async throws -> Result {
        try await deleteAttributes(
            [attribute],
            operation: .attribute,
            in: modelContext,
            committer: committer,
            cacheFileDeletion: cacheFileDeletion,
            headerImageDeletion: headerImageDeletion
        )
    }

    @discardableResult
    static func deleteAttributes(
        _ attributes: [MetaAttribute],
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        cacheFileDeletion: CacheFileDeletion = { result in
            AttachmentCleanup.deleteCachedFiles(for: result)
        },
        headerImageDeletion: HeaderImageDeletion = { paths in
            for path in paths { ImageStore.delete(path: path) }
        }
    ) async throws -> Result {
        try await deleteAttributes(
            attributes,
            operation: .attributeBatch,
            in: modelContext,
            committer: committer,
            cacheFileDeletion: cacheFileDeletion,
            headerImageDeletion: headerImageDeletion
        )
    }

    @discardableResult
    static func deleteEntity(
        _ entity: MetaEntity,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        cacheFileDeletion: CacheFileDeletion = { result in
            AttachmentCleanup.deleteCachedFiles(for: result)
        },
        headerImageDeletion: HeaderImageDeletion = { paths in
            for path in paths { ImageStore.delete(path: path) }
        }
    ) async throws -> Result {
        try await deleteEntities(
            [entity],
            operation: .entity,
            in: modelContext,
            committer: committer,
            cacheFileDeletion: cacheFileDeletion,
            headerImageDeletion: headerImageDeletion
        )
    }

    @discardableResult
    static func deleteEntities(
        _ entities: [MetaEntity],
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter(),
        cacheFileDeletion: CacheFileDeletion = { result in
            AttachmentCleanup.deleteCachedFiles(for: result)
        },
        headerImageDeletion: HeaderImageDeletion = { paths in
            for path in paths { ImageStore.delete(path: path) }
        }
    ) async throws -> Result {
        try await deleteEntities(
            entities,
            operation: .entityBatch,
            in: modelContext,
            committer: committer,
            cacheFileDeletion: cacheFileDeletion,
            headerImageDeletion: headerImageDeletion
        )
    }

    private static func deleteAttributes(
        _ attributes: [MetaAttribute],
        operation: Operation,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter,
        cacheFileDeletion: CacheFileDeletion,
        headerImageDeletion: HeaderImageDeletion
    ) async throws -> Result {
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

        let result = Result(
            requestedEntityCount: 0,
            requestedAttributeCount: prepared.requestedAttributeCount,
            deletedEntityCount: 0,
            deletedAttributeCount: prepared.attributes.count,
            deletedDetailFieldCount: 0,
            deletedDetailValueCount: prepared.detailValues.count,
            deletedLinkCount: prepared.linkPlan.mutationReferences.count,
            deletedAttachmentCount: prepared.attachmentPlan.mutationReferences.count
        )
        guard result.hasDeletedData else {
            return result
        }

        let batch: GraphMutationBatch
        do {
            batch = try GraphMutationBatchFactory.nodeDeletion(
                graphID: prepared.graphID,
                links: prepared.linkPlan.mutationReferences,
                detailValues: prepared.detailValues.map(makeDetailValueReference),
                detailSchemas: [],
                attachments: prepared.attachmentPlan.mutationReferences,
                attributeIDs: prepared.attributes.map(\.id),
                entityIDs: []
            )
        } catch {
            logFailure(error, operation: operation, stage: "classification")
            throw DeletionError.persistenceFailure
        }

        do {
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

        do {
            try await committer.commit(batch, in: modelContext)
        } catch {
            throw mappedCommitError(error, operation: operation)
        }

        cacheFileDeletion(attachmentResult)
        headerImageDeletion(prepared.headerImagePaths)
        logSuccess(
            Result(
                requestedEntityCount: result.requestedEntityCount,
                requestedAttributeCount: result.requestedAttributeCount,
                deletedEntityCount: result.deletedEntityCount,
                deletedAttributeCount: result.deletedAttributeCount,
                deletedDetailFieldCount: result.deletedDetailFieldCount,
                deletedDetailValueCount: result.deletedDetailValueCount,
                deletedLinkCount: linkResult.deletedCount,
                deletedAttachmentCount: attachmentResult.deletedCount
            ),
            operation: operation
        )
        return result
    }

    private static func deleteEntities(
        _ entities: [MetaEntity],
        operation: Operation,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter,
        cacheFileDeletion: CacheFileDeletion,
        headerImageDeletion: HeaderImageDeletion
    ) async throws -> Result {
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

        let detailSchemas = Dictionary(grouping: prepared.detailFields, by: \.entityID)
            .map { ownerEntityID, definitions in
                GraphMutationDetailSchemaCleanupReference(
                    ownerEntityID: ownerEntityID,
                    definitionIDs: definitions.map(\.id)
                )
            }
        let result = Result(
            requestedEntityCount: prepared.requestedEntityCount,
            requestedAttributeCount: 0,
            deletedEntityCount: prepared.entities.count,
            deletedAttributeCount: prepared.childAttributes.count,
            deletedDetailFieldCount: prepared.detailFields.count,
            deletedDetailValueCount: prepared.detailValues.count,
            deletedLinkCount: prepared.linkPlan.mutationReferences.count,
            deletedAttachmentCount: prepared.attachmentPlan.mutationReferences.count
        )
        guard result.hasDeletedData else {
            return result
        }

        let batch: GraphMutationBatch
        do {
            batch = try GraphMutationBatchFactory.nodeDeletion(
                graphID: prepared.graphID,
                links: prepared.linkPlan.mutationReferences,
                detailValues: prepared.detailValues.map(makeDetailValueReference),
                detailSchemas: detailSchemas,
                attachments: prepared.attachmentPlan.mutationReferences,
                attributeIDs: prepared.childAttributes.map(\.id),
                entityIDs: prepared.entities.map(\.id)
            )
        } catch {
            logFailure(error, operation: operation, stage: "classification")
            throw DeletionError.persistenceFailure
        }

        do {
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

        for definition in prepared.orphanDetailFields {
            modelContext.delete(definition)
        }

        for entity in prepared.entities {
            modelContext.delete(entity)
        }

        do {
            try await committer.commit(batch, in: modelContext)
        } catch {
            throw mappedCommitError(error, operation: operation)
        }

        cacheFileDeletion(attachmentResult)
        headerImageDeletion(prepared.headerImagePaths)
        logSuccess(
            Result(
                requestedEntityCount: result.requestedEntityCount,
                requestedAttributeCount: result.requestedAttributeCount,
                deletedEntityCount: result.deletedEntityCount,
                deletedAttributeCount: result.deletedAttributeCount,
                deletedDetailFieldCount: result.deletedDetailFieldCount,
                deletedDetailValueCount: result.deletedDetailValueCount,
                deletedLinkCount: linkResult.deletedCount,
                deletedAttachmentCount: attachmentResult.deletedCount
            ),
            operation: operation
        )
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
            graphID: graphID,
            requestedAttributeCount: requestedIDs.count,
            attributes: storedAttributes,
            detailValues: matchingDetailValues,
            orphanDetailValues: orphanDetailValues,
            linkPlan: linkPlan,
            attachmentPlan: attachmentPlan,
            headerImagePaths: stableImagePaths(storedAttributes.map(\.imagePath))
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

        let relationshipChildren = entityModelsForValidation.flatMap(\.attributesList)
        let relationshipChildIDs = Set(relationshipChildren.map(\.id))

        let attributeDescriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate { attribute in
                attribute.graphID == gid
            }
        )
        let fetchedChildren = try modelContext.fetch(attributeDescriptor).filter { attribute in
            guard let ownerID = attribute.owner?.id else { return false }
            return requestedEntityIDs.contains(ownerID)
        }
        let childAttributes = uniqueModels(relationshipChildren + fetchedChildren)

        try validateAttributeRelationships(
            childAttributes,
            graphID: graphID
        )

        var childAttributeIDs = relationshipChildIDs
        childAttributeIDs.formUnion(childAttributes.map(\.id))

        let relationshipDetailFields = entityModelsForValidation.flatMap(\.detailFieldsList)
        let detailFieldDescriptor = FetchDescriptor<MetaDetailFieldDefinition>(
            predicate: #Predicate { definition in
                definition.graphID == gid
            }
        )
        let fetchedDetailFields = try modelContext.fetch(detailFieldDescriptor).filter { definition in
            requestedEntityIDs.contains(definition.entityID)
        }
        let detailFields = uniqueModels(relationshipDetailFields + fetchedDetailFields)
        if detailFields.contains(where: { $0.graphID != graphID }) {
            throw DeletionError.crossGraphRelationship
        }
        let storedEntityIDs = Set(storedEntities.map(\.id))
        let orphanDetailFields = detailFields.filter { definition in
            guard let owner = definition.owner else { return true }
            return storedEntityIDs.contains(owner.id) == false
        }

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
            graphID: graphID,
            requestedEntityCount: requestedEntityIDs.count,
            entities: storedEntities,
            childAttributes: childAttributes,
            detailFields: detailFields,
            orphanDetailFields: orphanDetailFields,
            detailValues: matchingDetailValues,
            orphanDetailValues: orphanDetailValues,
            linkPlan: linkPlan,
            attachmentPlan: attachmentPlan,
            headerImagePaths: stableImagePaths(
                storedEntities.map(\.imagePath) + childAttributes.map(\.imagePath)
            )
        )
    }

    private static func makeDetailValueReference(
        _ value: MetaDetailFieldValue
    ) -> GraphMutationDetailValueReference {
        GraphMutationDetailValueReference(
            id: value.id,
            ownerAttributeID: value.attributeID,
            fieldID: value.fieldID
        )
    }

    private static func stableImagePaths(_ paths: [String?]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard let path, !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
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

    private static func mappedCommitError(
        _ error: Swift.Error,
        operation: Operation
    ) -> Swift.Error {
        if error is CancellationError {
            logFailure(error, operation: operation, stage: "cancelled")
            return DeletionError.cancelled
        }
        logFailure(error, operation: operation, stage: "save")
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
