//
//  GraphTransferService+ExportCore.swift
//  BrainMesh
//
//  Shared value-only core graph export builder for .bmgraph and .bmbackup.
//

import Foundation
import SwiftData

nonisolated struct GraphTransferCoreExportPayload: Sendable {
    var graphName: String
    var exportFile: GraphExportFileV1
}

extension GraphTransferService {

    func makeGraphExportFileV1(
        context: ModelContext,
        graphID: UUID,
        options: ExportOptions,
        exportedAt: Date = Date()
    ) throws -> GraphTransferCoreExportPayload {
        var graphFD = FetchDescriptor<MetaGraph>(predicate: #Predicate { graph in
            graph.id == graphID
        })
        graphFD.fetchLimit = 1

        guard let graph = try context.fetch(graphFD).first else {
            throw GraphTransferError.graphNotFound(graphID: graphID)
        }

        let gid = graphID

        let entities = try context.fetch(FetchDescriptor<MetaEntity>(predicate: #Predicate { entity in
            entity.graphID == gid
        }))

        let attributes = try context.fetch(FetchDescriptor<MetaAttribute>(predicate: #Predicate { attribute in
            attribute.graphID == gid
        }))

        let fetchedFieldDefs = try context.fetch(FetchDescriptor<MetaDetailFieldDefinition>(predicate: #Predicate { definition in
            definition.graphID == gid
        }))

        let fetchedFieldValues = try context.fetch(FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate { value in
            value.graphID == gid
        }))
        let fieldDefs = fetchedFieldDefs.filter { field in
            let snapshot = DetailDataModelSnapshotMapper.field(field)
            return snapshot.graphID == graphID
                && DetailDataIntegrityPolicy.fieldViolations(snapshot).isEmpty
        }
        let fieldValues = authoritativeDetailValues(
            values: fetchedFieldValues,
            fields: fieldDefs,
            attributes: attributes,
            graphID: graphID
        )

        let links = try context.fetch(FetchDescriptor<MetaLink>(predicate: #Predicate { link in
            link.graphID == gid
        }))

        let graphDTO = GraphDTO(id: graph.id, createdAt: graph.createdAt, name: graph.name)

        let entitiesDTO: [EntityDTO] = entities
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { entity in
                EntityDTO(
                    id: entity.id,
                    createdAt: entity.createdAt,
                    graphID: entity.graphID,
                    name: entity.name,
                    notes: options.includeNotes ? entity.notes : "",
                    iconSymbolName: options.includeIcons ? entity.iconSymbolName : nil,
                    imageData: options.includeImages ? entity.imageData : nil
                )
            }

        let attributesDTO: [AttributeDTO] = attributes
            .sorted(by: { $0.name < $1.name })
            .map { attribute in
                AttributeDTO(
                    id: attribute.id,
                    graphID: attribute.graphID,
                    ownerEntityID: attribute.owner?.id,
                    name: attribute.name,
                    notes: options.includeNotes ? attribute.notes : "",
                    iconSymbolName: options.includeIcons ? attribute.iconSymbolName : nil,
                    imageData: options.includeImages ? attribute.imageData : nil
                )
            }

        let fieldDefsDTO: [DetailFieldDefinitionDTO] = fieldDefs
            .sorted(by: {
                if $0.entityID == $1.entityID { return $0.sortIndex < $1.sortIndex }
                return $0.entityID.uuidString < $1.entityID.uuidString
            })
            .map { definition in
                DetailFieldDefinitionDTO(
                    id: definition.id,
                    graphID: definition.graphID,
                    entityID: definition.entityID,
                    name: definition.name,
                    typeRaw: definition.typeRaw,
                    sortIndex: definition.sortIndex,
                    isPinned: definition.isPinned,
                    unit: definition.unit,
                    options: definition.options
                )
            }

        let fieldValuesDTO: [DetailFieldValueDTO] = fieldValues
            .sorted(by: {
                if $0.attributeID == $1.attributeID { return $0.fieldID.uuidString < $1.fieldID.uuidString }
                return $0.attributeID.uuidString < $1.attributeID.uuidString
            })
            .map { value in
                DetailFieldValueDTO(
                    id: value.id,
                    graphID: value.graphID,
                    attributeID: value.attributeID,
                    fieldID: value.fieldID,
                    stringValue: value.stringValue,
                    intValue: value.intValue,
                    doubleValue: value.doubleValue,
                    dateValue: value.dateValue,
                    boolValue: value.boolValue
                )
            }

        let linksDTO: [LinkDTO] = links
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { link in
                LinkDTO(
                    id: link.id,
                    createdAt: link.createdAt,
                    graphID: link.graphID,
                    note: options.includeNotes ? link.note : nil,
                    sourceLabel: link.sourceLabel,
                    targetLabel: link.targetLabel,
                    sourceKindRaw: link.sourceKindRaw,
                    sourceID: link.sourceID,
                    targetKindRaw: link.targetKindRaw,
                    targetID: link.targetID
                )
            }

        let counts = CountsDTO(
            graphs: 1,
            entities: entitiesDTO.count,
            attributes: attributesDTO.count,
            detailFieldDefinitions: fieldDefsDTO.count,
            detailFieldValues: fieldValuesDTO.count,
            links: linksDTO.count
        )

        let exportFile = GraphExportFileV1(
            exportedAt: exportedAt,
            appVersion: Self.appVersionString,
            appBuild: Self.appBuildString,
            counts: counts,
            graph: graphDTO,
            entities: entitiesDTO,
            attributes: attributesDTO,
            detailFieldDefinitions: fieldDefsDTO,
            detailFieldValues: fieldValuesDTO,
            links: linksDTO
        )

        return GraphTransferCoreExportPayload(graphName: graph.name, exportFile: exportFile)
    }

    private func authoritativeDetailValues(
        values: [MetaDetailFieldValue],
        fields: [MetaDetailFieldDefinition],
        attributes: [MetaAttribute],
        graphID: UUID
    ) -> [MetaDetailFieldValue] {
        let fieldsByID = Dictionary(grouping: fields, by: \.id)
        let attributesByID = Dictionary(grouping: attributes, by: \.id)
        var grouped: [DetailValueAuthorityKey: [MetaDetailFieldValue]] = [:]
        var fieldByKey: [DetailValueAuthorityKey: MetaDetailFieldDefinition] = [:]
        var attributeByKey: [DetailValueAuthorityKey: MetaAttribute] = [:]

        for value in values {
            guard fieldsByID[value.fieldID]?.count == 1,
                  let field = fieldsByID[value.fieldID]?.first,
                  attributesByID[value.attributeID]?.count == 1,
                  let attribute = attributesByID[value.attributeID]?.first,
                  attribute.graphID == graphID else {
                continue
            }
            let fieldSnapshot = DetailDataModelSnapshotMapper.field(field)
            let attributeSnapshot = DetailDataModelSnapshotMapper.attribute(attribute)
            guard let key = DetailDataIntegrityPolicy.key(
                for: fieldSnapshot,
                attribute: attributeSnapshot
            ) else {
                continue
            }
            grouped[key, default: []].append(value)
            fieldByKey[key] = field
            attributeByKey[key] = attribute
        }

        var authoritative: [MetaDetailFieldValue] = []
        for key in grouped.keys.sorted(by: Self.detailAuthorityKeyOrder) {
            guard let field = fieldByKey[key],
                  let attribute = attributeByKey[key] else {
                continue
            }
            let candidates = grouped[key] ?? []
            let resolution = DetailDataModelSnapshotMapper.authority(
                field: field,
                attribute: attribute,
                records: candidates
            )
            guard let recordID = resolution.authoritativeRecordID,
                  let value = candidates.first(where: { $0.id == recordID }) else {
                continue
            }
            authoritative.append(value)
        }
        return authoritative
    }

    private static func detailAuthorityKeyOrder(
        _ lhs: DetailValueAuthorityKey,
        _ rhs: DetailValueAuthorityKey
    ) -> Bool {
        if lhs.attributeID != rhs.attributeID {
            return lhs.attributeID.uuidString < rhs.attributeID.uuidString
        }
        return lhs.fieldID.uuidString < rhs.fieldID.uuidString
    }
}
