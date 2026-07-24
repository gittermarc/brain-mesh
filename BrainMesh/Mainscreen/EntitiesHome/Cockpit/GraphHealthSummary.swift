//
//  GraphHealthSummary.swift
//  BrainMesh
//
//  Pure graph-health summary used by the Home Cockpit data layer.
//

import Foundation

nonisolated struct GraphHealthCounts: Equatable, Sendable {
    let entities: Int
    let attributes: Int
    let links: Int
    let attachments: Int
    let attachmentBytes: Int64

    static let zero = GraphHealthCounts(
        entities: 0,
        attributes: 0,
        links: 0,
        attachments: 0,
        attachmentBytes: 0
    )
}

nonisolated struct GraphHealthEntityInput: Equatable, Sendable {
    let id: UUID
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthAttributeInput: Equatable, Sendable {
    let id: UUID
    let ownerEntityID: UUID?
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthLinkInput: Equatable, Sendable {
    let sourceKindRaw: Int
    let sourceID: UUID
    let targetKindRaw: Int
    let targetID: UUID
}

nonisolated struct GraphHealthDetailFieldInput: Equatable, Sendable {
    let entityID: UUID
}

nonisolated struct GraphHealthAttachmentInput: Equatable, Sendable {
    let ownerKindRaw: Int
    let ownerID: UUID
    let byteCount: Int
}

nonisolated struct GraphHealthSummary: Equatable, Sendable {
    let counts: GraphHealthCounts
    let allEntityIDs: [UUID]
    let isolatedEntityIDs: [UUID]
    let entityIDsWithoutAttributes: [UUID]
    let entityIDsWithoutDetails: [UUID]
    let mediaRichEntityIDs: [UUID]

    static let empty = GraphHealthSummary(
        counts: .zero,
        allEntityIDs: [],
        isolatedEntityIDs: [],
        entityIDsWithoutAttributes: [],
        entityIDsWithoutDetails: [],
        mediaRichEntityIDs: []
    )

    var hasActionableHints: Bool {
        isolatedEntityIDs.isEmpty == false
            || entityIDsWithoutAttributes.isEmpty == false
            || entityIDsWithoutDetails.isEmpty == false
            || mediaRichEntityIDs.isEmpty == false
    }

    func replacingCounts(
        with statsCounts: GraphCounts
    ) -> GraphHealthSummary {
        GraphHealthSummary(
            counts: GraphHealthCounts(
                entities: statsCounts.entities,
                attributes: statsCounts.attributes,
                links: statsCounts.links,
                attachments: statsCounts.attachments,
                attachmentBytes: statsCounts.attachmentBytes
            ),
            allEntityIDs: allEntityIDs,
            isolatedEntityIDs: isolatedEntityIDs,
            entityIDsWithoutAttributes: entityIDsWithoutAttributes,
            entityIDsWithoutDetails: entityIDsWithoutDetails,
            mediaRichEntityIDs: mediaRichEntityIDs
        )
    }

    static func make(
        entities: [GraphHealthEntityInput],
        attributes: [GraphHealthAttributeInput],
        links: [GraphHealthLinkInput],
        detailFields: [GraphHealthDetailFieldInput],
        attachments: [GraphHealthAttachmentInput]
    ) -> GraphHealthSummary {
        var attachmentBytes: Int64 = 0
        for attachment in attachments {
            attachmentBytes += Int64(attachment.byteCount)
        }

        let categories = GraphHealthEntityCategoryEngine.make(
            entities: entities.map { entity in
                GraphHealthEntityCategoryEntityInput(
                    id: entity.id,
                    hasHeaderImage: entity.hasHeaderImage
                )
            },
            attributes: attributes.map { attribute in
                GraphHealthEntityCategoryAttributeInput(
                    id: attribute.id,
                    ownerEntityID: attribute.ownerEntityID,
                    hasHeaderImage: attribute.hasHeaderImage
                )
            },
            links: links.map { link in
                GraphHealthLinkEndpointInput(
                    sourceKindRaw: link.sourceKindRaw,
                    sourceID: link.sourceID,
                    targetKindRaw: link.targetKindRaw,
                    targetID: link.targetID
                )
            },
            detailSchemas: detailFields.map { field in
                GraphHealthDetailSchemaInput(entityID: field.entityID)
            },
            attachments: attachments.map { attachment in
                GraphHealthEntityCategoryAttachmentInput(
                    ownerKindRaw: attachment.ownerKindRaw,
                    ownerID: attachment.ownerID
                )
            }
        )

        return GraphHealthSummary(
            counts: GraphHealthCounts(
                entities: entities.count,
                attributes: attributes.count,
                links: links.count,
                attachments: attachments.count,
                attachmentBytes: attachmentBytes
            ),
            allEntityIDs: categories.allEntityIDs,
            isolatedEntityIDs: categories.isolatedEntityIDs,
            entityIDsWithoutAttributes: categories.entityIDsWithoutAttributes,
            entityIDsWithoutDetails: categories.entityIDsWithoutDetails,
            mediaRichEntityIDs: categories.entityIDsWithMedia
        )
    }
}
