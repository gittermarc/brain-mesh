//
//  GraphReadRepository+Sorting.swift
//  BrainMesh
//
//  Deterministic value-only ordering and lookup maps for repository snapshots.
//

import Foundation

extension GraphReadRepository {
    nonisolated static func entitySort(
        lhs: GraphEntityDTO,
        rhs: GraphEntityDTO
    ) -> Bool {
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func attributeSort(
        lhs: GraphAttributeDTO,
        rhs: GraphAttributeDTO
    ) -> Bool {
        let lhsLabel = BMSearch.fold(lhs.displayLabel)
        let rhsLabel = BMSearch.fold(rhs.displayLabel)
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func linkSort(lhs: GraphLinkDTO, rhs: GraphLinkDTO) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func detailFieldSort(
        lhs: GraphDetailFieldDefinitionDTO,
        rhs: GraphDetailFieldDefinitionDTO
    ) -> Bool {
        if lhs.entityID != rhs.entityID {
            return lhs.entityID.uuidString < rhs.entityID.uuidString
        }
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func detailValueSort(
        lhs: GraphDetailValueDTO,
        rhs: GraphDetailValueDTO
    ) -> Bool {
        if lhs.attributeID != rhs.attributeID {
            return lhs.attributeID.uuidString < rhs.attributeID.uuidString
        }
        if lhs.fieldID != rhs.fieldID {
            return lhs.fieldID.uuidString < rhs.fieldID.uuidString
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func attachmentSort(
        lhs: GraphAttachmentMetadataDTO,
        rhs: GraphAttachmentMetadataDTO
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func detailFieldMap(
        _ values: [GraphDetailFieldDefinitionDTO]
    ) -> [UUID: GraphDetailFieldDefinitionDTO] {
        var result: [UUID: GraphDetailFieldDefinitionDTO] = [:]
        result.reserveCapacity(values.count)
        for value in values {
            result[value.id] = value
        }
        return result
    }

    nonisolated static func attributeMap(
        _ values: [GraphAttributeDTO]
    ) -> [UUID: GraphAttributeDTO] {
        var result: [UUID: GraphAttributeDTO] = [:]
        result.reserveCapacity(values.count)
        for value in values {
            result[value.id] = value
        }
        return result
    }
}
