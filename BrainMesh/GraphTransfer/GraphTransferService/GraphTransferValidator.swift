//
//  GraphTransferValidator.swift
//  BrainMesh
//
//  Format + version validation for export/import files.
//

import Foundation

enum GraphTransferValidator {
    nonisolated static func validate(exportFile: GraphExportFileV1) throws {
        guard exportFile.format == GraphTransferFormat.formatID else {
            throw GraphTransferError.invalidFormat
        }
        guard exportFile.version == GraphTransferFormat.version else {
            throw GraphTransferError.unsupportedVersion(found: exportFile.version)
        }
        _ = try authoritativeDetailValues(in: exportFile)
    }

    nonisolated static func authoritativeDetailValues(
        in exportFile: GraphExportFileV1
    ) throws -> [DetailFieldValueDTO] {
        let sourceGraphID = exportFile.graph.id
        guard exportFile.entities.allSatisfy({
            $0.graphID == nil || $0.graphID == sourceGraphID
        }),
        exportFile.attributes.allSatisfy({
            $0.graphID == nil || $0.graphID == sourceGraphID
        }),
        exportFile.detailFieldDefinitions.allSatisfy({
            $0.graphID == nil || $0.graphID == sourceGraphID
        }),
        exportFile.detailFieldValues.allSatisfy({
            $0.graphID == nil || $0.graphID == sourceGraphID
        }) else {
            DetailDataIntegrityObservability.logRejectedWrite(
                .crossGraphAssignment
            )
            throw GraphTransferError.invalidDetailData
        }

        let entitiesByID = Dictionary(
            grouping: exportFile.entities,
            by: \.id
        )
        let attributesByID = Dictionary(
            grouping: exportFile.attributes,
            by: \.id
        )
        let fieldsByID = Dictionary(
            grouping: exportFile.detailFieldDefinitions,
            by: \.id
        )
        guard entitiesByID.values.allSatisfy({ $0.count == 1 }),
              attributesByID.values.allSatisfy({ $0.count == 1 }),
              fieldsByID.values.allSatisfy({ $0.count == 1 }) else {
            throw GraphTransferError.invalidDetailData
        }
        for attribute in exportFile.attributes {
            guard let ownerEntityID = attribute.ownerEntityID,
                  entitiesByID[ownerEntityID]?.count == 1 else {
                throw GraphTransferError.invalidDetailData
            }
        }
        for field in exportFile.detailFieldDefinitions {
            guard entitiesByID[field.entityID]?.count == 1,
                  DetailFieldType(rawValue: field.typeRaw) != nil else {
                throw GraphTransferError.invalidDetailData
            }
        }

        var groupedValues: [DetailValueAuthorityKey: [DetailValueIntegritySnapshot]] = [:]
        var dtoByID: [UUID: DetailFieldValueDTO] = [:]
        var fieldByKey: [DetailValueAuthorityKey: DetailFieldIntegritySnapshot] = [:]
        var attributeByKey: [DetailValueAuthorityKey: DetailAttributeIntegritySnapshot] = [:]

        for dto in exportFile.detailFieldValues {
            guard dtoByID.updateValue(dto, forKey: dto.id) == nil,
                  let attributeDTO = attributesByID[dto.attributeID]?.first,
                  let ownerEntityID = attributeDTO.ownerEntityID,
                  entitiesByID[ownerEntityID]?.count == 1,
                  let fieldDTO = fieldsByID[dto.fieldID]?.first,
                  fieldDTO.entityID == ownerEntityID,
                  let fieldType = DetailFieldType(rawValue: fieldDTO.typeRaw) else {
                throw GraphTransferError.invalidDetailData
            }

            let field = DetailFieldIntegritySnapshot(
                id: fieldDTO.id,
                graphID: sourceGraphID,
                entityID: fieldDTO.entityID,
                ownerID: fieldDTO.entityID,
                ownerGraphID: sourceGraphID,
                type: fieldType
            )
            let attribute = DetailAttributeIntegritySnapshot(
                id: attributeDTO.id,
                graphID: sourceGraphID,
                ownerEntityID: ownerEntityID,
                ownerGraphID: sourceGraphID
            )
            guard let key = DetailDataIntegrityPolicy.key(
                for: field,
                attribute: attribute
            ) else {
                throw GraphTransferError.invalidDetailData
            }
            let value = DetailValueIntegritySnapshot(
                id: dto.id,
                graphID: sourceGraphID,
                attributeID: dto.attributeID,
                fieldID: dto.fieldID,
                relationshipAttributeID: dto.attributeID,
                relationshipGraphID: sourceGraphID,
                relationshipEntityID: ownerEntityID,
                relationshipEntityGraphID: sourceGraphID,
                storage: DetailTypedStorageSnapshot(
                    stringValue: dto.stringValue,
                    intValue: dto.intValue,
                    doubleValue: dto.doubleValue,
                    dateValue: dto.dateValue,
                    boolValue: dto.boolValue
                )
            )
            groupedValues[key, default: []].append(value)
            fieldByKey[key] = field
            attributeByKey[key] = attribute
        }

        var authoritative: [DetailFieldValueDTO] = []
        authoritative.reserveCapacity(groupedValues.count)
        let keys = groupedValues.keys.sorted { lhs, rhs in
            if lhs.attributeID != rhs.attributeID {
                return lhs.attributeID.uuidString < rhs.attributeID.uuidString
            }
            return lhs.fieldID.uuidString < rhs.fieldID.uuidString
        }
        for key in keys {
            guard let field = fieldByKey[key],
                  let attribute = attributeByKey[key] else {
                throw GraphTransferError.invalidDetailData
            }
            let resolution = DetailDataIntegrityPolicy.resolveAuthority(
                field: field,
                attribute: attribute,
                records: groupedValues[key] ?? []
            )
            guard case .authoritative(let recordID, _, _) = resolution,
                  let dto = dtoByID[recordID] else {
                throw GraphTransferError.invalidDetailData
            }
            authoritative.append(dto)
        }
        return authoritative
    }
}
