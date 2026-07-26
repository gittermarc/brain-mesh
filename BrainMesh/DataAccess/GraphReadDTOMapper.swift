//
//  GraphReadDTOMapper.swift
//  BrainMesh
//
//  SwiftData models are converted to value-only DTOs before leaving a repository actor.
//

import Foundation

nonisolated enum GraphReadDTOMapper {
    static func graph(_ graph: MetaGraph, scope: GraphScope) -> GraphMetadataDTO {
        GraphMetadataDTO(
            id: graph.id,
            scope: scope,
            name: graph.name,
            createdAt: graph.createdAt
        )
    }

    static func entity(_ entity: MetaEntity, scope: GraphScope) -> GraphEntityDTO {
        GraphEntityDTO(
            id: entity.id,
            scope: scope,
            name: entity.name,
            notes: entity.notes,
            iconSymbolName: entity.iconSymbolName,
            createdAt: entity.createdAt
        )
    }

    static func attribute(_ attribute: MetaAttribute, scope: GraphScope) -> GraphAttributeDTO {
        let scopedOwner = attribute.owner.flatMap { owner in
            owner.graphID == scope.graphID ? owner : nil
        }
        let ownerLabel = scopedOwner?.name
        let displayLabel: String
        if let ownerLabel {
            displayLabel = "\(ownerLabel) · \(attribute.name)"
        } else {
            displayLabel = attribute.name
        }

        return GraphAttributeDTO(
            id: attribute.id,
            scope: scope,
            ownerEntityID: scopedOwner?.id,
            ownerLabel: ownerLabel,
            name: attribute.name,
            displayLabel: displayLabel,
            notes: attribute.notes,
            iconSymbolName: attribute.iconSymbolName
        )
    }

    static func link(_ link: MetaLink, scope: GraphScope) -> GraphLinkDTO {
        GraphLinkDTO(
            id: link.id,
            scope: scope,
            createdAt: link.createdAt,
            sourceKindRaw: link.sourceKindRaw,
            sourceID: link.sourceID,
            sourceLabel: link.sourceLabel,
            targetKindRaw: link.targetKindRaw,
            targetID: link.targetID,
            targetLabel: link.targetLabel,
            note: link.note
        )
    }

    static func detailFieldDefinition(
        _ field: MetaDetailFieldDefinition,
        scope: GraphScope
    ) -> GraphDetailFieldDefinitionDTO {
        let scopedOwner = field.owner.flatMap { owner in
            owner.graphID == scope.graphID ? owner : nil
        }

        return GraphDetailFieldDefinitionDTO(
            id: field.id,
            scope: scope,
            entityID: field.entityID,
            entityLabel: scopedOwner?.name,
            name: field.name,
            typeRaw: field.typeRaw,
            sortIndex: field.sortIndex,
            isPinned: field.isPinned,
            unit: field.unit,
            options: field.options
        )
    }

    static func detailValue(
        _ value: MetaDetailFieldValue,
        scope: GraphScope,
        field: GraphDetailFieldDefinitionDTO?,
        attribute: GraphAttributeDTO?,
        authoritativeValue: DetailTypedValue
    ) -> GraphDetailValueDTO {
        GraphDetailValueDTO(
            id: value.id,
            scope: scope,
            attributeID: value.attributeID,
            attributeLabel: attribute?.displayLabel,
            fieldID: value.fieldID,
            fieldName: field?.name,
            fieldTypeRaw: field?.typeRaw,
            value: detailValuePayload(authoritativeValue)
        )
    }

    private static func detailValuePayload(
        _ value: DetailTypedValue
    ) -> GraphDetailValuePayload {
        switch value {
        case .text(let text):
            return .text(text)
        case .integer(let integer):
            return .integer(integer)
        case .decimal(let decimal):
            return .decimal(decimal)
        case .date(let date):
            return .date(date)
        case .boolean(let boolean):
            return .boolean(boolean)
        case .choice(let choice):
            return .choice(choice)
        case .empty:
            return .empty
        }
    }

    static func attachmentMetadata(
        _ attachment: MetaAttachment,
        scope: GraphScope,
        ownerLabel: String?
    ) -> GraphAttachmentMetadataDTO {
        GraphAttachmentMetadataDTO(
            id: attachment.id,
            scope: scope,
            createdAt: attachment.createdAt,
            ownerKindRaw: attachment.ownerKindRaw,
            ownerID: attachment.ownerID,
            ownerLabel: ownerLabel,
            contentKindRaw: attachment.contentKindRaw,
            title: attachment.title,
            originalFilename: attachment.originalFilename,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            byteCount: attachment.byteCount
        )
    }
}
