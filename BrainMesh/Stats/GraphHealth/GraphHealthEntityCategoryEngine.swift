//
//  GraphHealthEntityCategoryEngine.swift
//  BrainMesh
//
//  Shared value-only entity classification for Stats and Entities Home.
//

import Foundation

nonisolated struct GraphHealthEntityCategoryEntityInput: Equatable, Sendable {
    let id: UUID
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthEntityCategoryAttributeInput: Equatable, Sendable {
    let id: UUID
    let ownerEntityID: UUID?
    let hasHeaderImage: Bool
}

nonisolated struct GraphHealthEntityCategoryAttachmentInput: Equatable, Sendable {
    let ownerKindRaw: Int
    let ownerID: UUID
}

nonisolated struct GraphHealthEntityCategorySnapshot: Equatable, Sendable {
    let allEntityIDs: [UUID]
    let isolatedEntityIDs: [UUID]
    let entityIDsWithoutAttributes: [UUID]
    let entityIDsWithoutDetails: [UUID]
    let entityIDsWithMedia: [UUID]

    static let empty = GraphHealthEntityCategorySnapshot(
        allEntityIDs: [],
        isolatedEntityIDs: [],
        entityIDsWithoutAttributes: [],
        entityIDsWithoutDetails: [],
        entityIDsWithMedia: []
    )
}

nonisolated enum GraphHealthEntityCategoryEngine {
    static func make(
        entities: [GraphHealthEntityCategoryEntityInput],
        attributes: [GraphHealthEntityCategoryAttributeInput],
        links: [GraphHealthLinkEndpointInput],
        detailSchemas: [GraphHealthDetailSchemaInput],
        attachments: [GraphHealthEntityCategoryAttachmentInput]
    ) -> GraphHealthEntityCategorySnapshot {
        let allEntityIDs = Set(entities.map(\.id))
        guard allEntityIDs.isEmpty == false else {
            return .empty
        }

        let entityKindRaw = NodeKind.entity.rawValue
        let attributeKindRaw = NodeKind.attribute.rawValue
        let entityIDsWithAttributes = Set(
            attributes.compactMap(\.ownerEntityID)
        ).intersection(allEntityIDs)
        let entityIDsWithDetails = Set(
            detailSchemas.map(\.entityID)
        ).intersection(allEntityIDs)

        var linkedEntityIDs = Set<UUID>()
        linkedEntityIDs.reserveCapacity(
            min(allEntityIDs.count, links.count * 2)
        )

        for link in links {
            if link.sourceKindRaw == entityKindRaw,
               allEntityIDs.contains(link.sourceID) {
                linkedEntityIDs.insert(link.sourceID)
            }
            if link.targetKindRaw == entityKindRaw,
               allEntityIDs.contains(link.targetID) {
                linkedEntityIDs.insert(link.targetID)
            }
        }

        let attributeOwnerByID = Dictionary(
            uniqueKeysWithValues: attributes.compactMap {
                attribute -> (UUID, UUID)? in
                guard let ownerEntityID = attribute.ownerEntityID else {
                    return nil
                }
                return (attribute.id, ownerEntityID)
            }
        )
        var entityIDsWithMedia = Set(
            entities.filter(\.hasHeaderImage).map(\.id)
        )
        for attribute in attributes where attribute.hasHeaderImage {
            if let ownerEntityID = attribute.ownerEntityID,
               allEntityIDs.contains(ownerEntityID) {
                entityIDsWithMedia.insert(ownerEntityID)
            }
        }
        for attachment in attachments {
            if attachment.ownerKindRaw == entityKindRaw,
               allEntityIDs.contains(attachment.ownerID) {
                entityIDsWithMedia.insert(attachment.ownerID)
            } else if attachment.ownerKindRaw == attributeKindRaw,
                      let ownerEntityID =
                        attributeOwnerByID[attachment.ownerID],
                      allEntityIDs.contains(ownerEntityID) {
                entityIDsWithMedia.insert(ownerEntityID)
            }
        }

        return GraphHealthEntityCategorySnapshot(
            allEntityIDs: sortedIDs(allEntityIDs),
            isolatedEntityIDs: sortedIDs(
                allEntityIDs.subtracting(linkedEntityIDs)
            ),
            entityIDsWithoutAttributes: sortedIDs(
                allEntityIDs.subtracting(entityIDsWithAttributes)
            ),
            entityIDsWithoutDetails: sortedIDs(
                allEntityIDs.subtracting(entityIDsWithDetails)
            ),
            entityIDsWithMedia: sortedIDs(
                entityIDsWithMedia.intersection(allEntityIDs)
            )
        )
    }

    private static func sortedIDs(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }
}
