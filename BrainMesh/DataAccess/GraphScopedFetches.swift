//
//  GraphScopedFetches.swift
//  BrainMesh
//
//  Central FetchDescriptor factories for the non-optional graph read layer.
//

import Foundation
import SwiftData

nonisolated enum GraphScopedFetches {
    static func graph(in scope: GraphScope) -> FetchDescriptor<MetaGraph> {
        let graphID = scope.graphID
        var descriptor = FetchDescriptor<MetaGraph>(
            predicate: #Predicate<MetaGraph> { graph in
                graph.id == graphID
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func entities(in scope: GraphScope) -> FetchDescriptor<MetaEntity> {
        let graphID = scope.graphID
        return FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { entity in
                entity.graphID == graphID
            },
            sortBy: [SortDescriptor(\MetaEntity.name)]
        )
    }

    static func entity(id: UUID, in scope: GraphScope) -> FetchDescriptor<MetaEntity> {
        let graphID = scope.graphID
        let entityID = id
        var descriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { entity in
                entity.graphID == graphID && entity.id == entityID
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func entities(ids: [UUID], in scope: GraphScope) -> FetchDescriptor<MetaEntity> {
        let graphID = scope.graphID
        let entityIDs = ids
        return FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { entity in
                entity.graphID == graphID && entityIDs.contains(entity.id)
            },
            sortBy: [SortDescriptor(\MetaEntity.name)]
        )
    }

    static func attributes(in scope: GraphScope) -> FetchDescriptor<MetaAttribute> {
        let graphID = scope.graphID
        return FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == graphID
            },
            sortBy: [SortDescriptor(\MetaAttribute.name)]
        )
    }

    static func attribute(id: UUID, in scope: GraphScope) -> FetchDescriptor<MetaAttribute> {
        let graphID = scope.graphID
        let attributeID = id
        var descriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == graphID && attribute.id == attributeID
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func attributes(ids: [UUID], in scope: GraphScope) -> FetchDescriptor<MetaAttribute> {
        let graphID = scope.graphID
        let attributeIDs = ids
        return FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == graphID && attributeIDs.contains(attribute.id)
            },
            sortBy: [SortDescriptor(\MetaAttribute.name)]
        )
    }

    static func links(in scope: GraphScope) -> FetchDescriptor<MetaLink> {
        let graphID = scope.graphID
        return FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { link in
                link.graphID == graphID
            },
            sortBy: [SortDescriptor(\MetaLink.createdAt)]
        )
    }

    static func outgoingLinks(
        from nodeKey: NodeRefKey,
        in scope: GraphScope
    ) -> FetchDescriptor<MetaLink> {
        let graphID = scope.graphID
        let kindRaw = nodeKey.kind.rawValue
        let nodeID = nodeKey.id
        return FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { link in
                link.graphID == graphID
                    && link.sourceKindRaw == kindRaw
                    && link.sourceID == nodeID
            },
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
    }

    static func incomingLinks(
        to nodeKey: NodeRefKey,
        in scope: GraphScope
    ) -> FetchDescriptor<MetaLink> {
        let graphID = scope.graphID
        let kindRaw = nodeKey.kind.rawValue
        let nodeID = nodeKey.id
        return FetchDescriptor<MetaLink>(
            predicate: #Predicate<MetaLink> { link in
                link.graphID == graphID
                    && link.targetKindRaw == kindRaw
                    && link.targetID == nodeID
            },
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
    }

    static func detailFieldDefinitions(
        in scope: GraphScope
    ) -> FetchDescriptor<MetaDetailFieldDefinition> {
        let graphID = scope.graphID
        return FetchDescriptor<MetaDetailFieldDefinition>(
            predicate: #Predicate<MetaDetailFieldDefinition> { field in
                field.graphID == graphID
            },
            sortBy: [
                SortDescriptor(\MetaDetailFieldDefinition.sortIndex),
                SortDescriptor(\MetaDetailFieldDefinition.name),
            ]
        )
    }

    static func detailFieldDefinitions(
        ids: [UUID],
        in scope: GraphScope
    ) -> FetchDescriptor<MetaDetailFieldDefinition> {
        let graphID = scope.graphID
        let fieldIDs = ids
        return FetchDescriptor<MetaDetailFieldDefinition>(
            predicate: #Predicate<MetaDetailFieldDefinition> { field in
                field.graphID == graphID && fieldIDs.contains(field.id)
            },
            sortBy: [
                SortDescriptor(\MetaDetailFieldDefinition.sortIndex),
                SortDescriptor(\MetaDetailFieldDefinition.name),
            ]
        )
    }

    static func detailFieldDefinitions(
        entityID: UUID,
        in scope: GraphScope
    ) -> FetchDescriptor<MetaDetailFieldDefinition> {
        let graphID = scope.graphID
        let ownerID = entityID
        return FetchDescriptor<MetaDetailFieldDefinition>(
            predicate: #Predicate<MetaDetailFieldDefinition> { field in
                field.graphID == graphID && field.entityID == ownerID
            },
            sortBy: [
                SortDescriptor(\MetaDetailFieldDefinition.sortIndex),
                SortDescriptor(\MetaDetailFieldDefinition.name),
            ]
        )
    }

    static func detailValues(in scope: GraphScope) -> FetchDescriptor<MetaDetailFieldValue> {
        let graphID = scope.graphID
        return FetchDescriptor<MetaDetailFieldValue>(
            predicate: #Predicate<MetaDetailFieldValue> { value in
                value.graphID == graphID
            }
        )
    }

    static func detailValues(
        attributeID: UUID,
        in scope: GraphScope
    ) -> FetchDescriptor<MetaDetailFieldValue> {
        let graphID = scope.graphID
        let ownerID = attributeID
        return FetchDescriptor<MetaDetailFieldValue>(
            predicate: #Predicate<MetaDetailFieldValue> { value in
                value.graphID == graphID && value.attributeID == ownerID
            }
        )
    }

    static func detailValues(
        fieldID: UUID,
        in scope: GraphScope
    ) -> FetchDescriptor<MetaDetailFieldValue> {
        let graphID = scope.graphID
        let definitionID = fieldID
        return FetchDescriptor<MetaDetailFieldValue>(
            predicate: #Predicate<MetaDetailFieldValue> { value in
                value.graphID == graphID && value.fieldID == definitionID
            }
        )
    }

    static func attachments(in scope: GraphScope) -> FetchDescriptor<MetaAttachment> {
        let graphID = scope.graphID
        return FetchDescriptor<MetaAttachment>(
            predicate: #Predicate<MetaAttachment> { attachment in
                attachment.graphID == graphID
            },
            sortBy: [SortDescriptor(\MetaAttachment.createdAt)]
        )
    }

    static func attachments(
        owner nodeKey: NodeRefKey,
        in scope: GraphScope
    ) -> FetchDescriptor<MetaAttachment> {
        let graphID = scope.graphID
        let ownerKindRaw = nodeKey.kind.rawValue
        let ownerID = nodeKey.id
        return FetchDescriptor<MetaAttachment>(
            predicate: #Predicate<MetaAttachment> { attachment in
                attachment.graphID == graphID
                    && attachment.ownerKindRaw == ownerKindRaw
                    && attachment.ownerID == ownerID
            },
            sortBy: [SortDescriptor(\MetaAttachment.createdAt)]
        )
    }
}
