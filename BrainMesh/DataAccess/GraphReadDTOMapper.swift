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
        attribute: GraphAttributeDTO?
    ) -> GraphDetailValueDTO {
        GraphDetailValueDTO(
            id: value.id,
            scope: scope,
            attributeID: value.attributeID,
            attributeLabel: attribute?.displayLabel,
            fieldID: value.fieldID,
            fieldName: field?.name,
            fieldTypeRaw: field?.typeRaw,
            value: detailValuePayload(value, fieldType: field?.type)
        )
    }

    private static func detailValuePayload(
        _ value: MetaDetailFieldValue,
        fieldType: DetailFieldType?
    ) -> GraphDetailValuePayload {
        switch fieldType {
        case .singleLineText, .multiLineText:
            return value.stringValue.map(GraphDetailValuePayload.text) ?? .empty
        case .numberInt:
            return value.intValue.map(GraphDetailValuePayload.integer) ?? .empty
        case .numberDouble:
            return value.doubleValue.map(GraphDetailValuePayload.decimal) ?? .empty
        case .date:
            return value.dateValue.map(GraphDetailValuePayload.date) ?? .empty
        case .toggle:
            return value.boolValue.map(GraphDetailValuePayload.boolean) ?? .empty
        case .singleChoice:
            return value.stringValue.map(GraphDetailValuePayload.choice) ?? .empty
        case .none:
            if let stringValue = value.stringValue {
                return .text(stringValue)
            }
            if let intValue = value.intValue {
                return .integer(intValue)
            }
            if let doubleValue = value.doubleValue {
                return .decimal(doubleValue)
            }
            if let dateValue = value.dateValue {
                return .date(dateValue)
            }
            if let boolValue = value.boolValue {
                return .boolean(boolValue)
            }
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
