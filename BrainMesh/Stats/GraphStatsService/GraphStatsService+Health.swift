//
//  GraphStatsService+Health.swift
//  BrainMesh
//

import Foundation
import SwiftData

nonisolated extension GraphStatsService {
    func healthSnapshot(for graphID: UUID?) throws -> GraphHealthSnapshot {
        let counts = try counts(for: graphID)
        let structure = try structureSnapshot(for: graphID)
        let media = try mediaSnapshot(for: graphID)
        return try healthSnapshot(
            for: graphID,
            counts: counts,
            structure: structure,
            media: media
        )
    }

    func healthSnapshot(
        for graphID: UUID?,
        counts: GraphCounts,
        structure: GraphStructureSnapshot,
        media: GraphMediaSnapshot
    ) throws -> GraphHealthSnapshot {
        let entities = try healthEntities(for: graphID)
        let attributes = try healthAttributes(for: graphID)
        let links = try healthLinks(for: graphID)
        let detailSchemas = try healthDetailSchemas(for: graphID)
        let attachments = try healthAttachments(for: graphID)

        return GraphHealthIssueEngine.makeSnapshot(
            graphID: graphID,
            counts: counts,
            entities: entities,
            attributes: attributes,
            links: links,
            detailSchemas: detailSchemas,
            attachments: attachments,
            structure: structure,
            media: media
        )
    }
}

private nonisolated extension GraphStatsService {
    func healthEntities(for graphID: UUID?) throws -> [GraphHealthEntityNodeInput] {
        let entities = try context.fetch(
            FetchDescriptor<MetaEntity>(
                predicate: entityGraphPredicate(for: graphID),
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        )

        return entities.map { entity in
            GraphHealthEntityNodeInput(
                id: entity.id,
                label: entity.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? shortID(entity.id) : entity.name
            )
        }
    }

    func healthAttributes(for graphID: UUID?) throws -> [GraphHealthAttributeNodeInput] {
        let attributes = try context.fetch(
            FetchDescriptor<MetaAttribute>(
                predicate: attributeGraphPredicate(for: graphID),
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        )

        return attributes.map { attribute in
            GraphHealthAttributeNodeInput(
                id: attribute.id,
                label: attribute.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? shortID(attribute.id) : attribute.displayName,
                ownerEntityID: attribute.owner?.id
            )
        }
    }

    func healthLinks(for graphID: UUID?) throws -> [GraphHealthLinkEndpointInput] {
        let links = try context.fetch(
            FetchDescriptor<MetaLink>(predicate: linkGraphPredicate(for: graphID))
        )

        return links.map { link in
            GraphHealthLinkEndpointInput(
                sourceKindRaw: link.sourceKindRaw,
                sourceID: link.sourceID,
                targetKindRaw: link.targetKindRaw,
                targetID: link.targetID
            )
        }
    }

    func healthDetailSchemas(for graphID: UUID?) throws -> [GraphHealthDetailSchemaInput] {
        let fields = try context.fetch(
            FetchDescriptor<MetaDetailFieldDefinition>(predicate: detailFieldGraphPredicate(for: graphID))
        )

        return fields.map { field in
            GraphHealthDetailSchemaInput(entityID: field.entityID)
        }
    }

    func healthAttachments(for graphID: UUID?) throws -> [GraphHealthAttachmentMetadataInput] {
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: attachmentGraphPredicate(for: graphID),
            sortBy: [SortDescriptor(\MetaAttachment.byteCount, order: .reverse)]
        )
        let attachments = try context.fetch(descriptor)
        return attachments.map { attachment in
            GraphHealthAttachmentMetadataInput(
                id: attachment.id,
                title: attachment.title,
                originalFilename: attachment.originalFilename,
                ownerKindRaw: attachment.ownerKindRaw,
                ownerID: attachment.ownerID,
                byteCount: attachment.byteCount
            )
        }
    }
}
