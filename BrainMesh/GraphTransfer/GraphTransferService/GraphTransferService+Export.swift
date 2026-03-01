//
//  GraphTransferService+Export.swift
//  BrainMesh
//
//  Export implementation (DTO mapping + encoding + temp-file write).
//

import Foundation
import os
import SwiftData

extension GraphTransferService {

    func exportGraphImpl(graphID: UUID, options: ExportOptions) async throws -> URL {
        guard let container else { throw GraphTransferError.notConfigured }

        let context = ModelContext(container.container)
        context.autosaveEnabled = false

        // 1) Fetch graph
        var graphFD = FetchDescriptor<MetaGraph>(predicate: #Predicate { g in
            g.id == graphID
        })
        graphFD.fetchLimit = 1

        guard let graph = try context.fetch(graphFD).first else {
            throw GraphTransferError.graphNotFound(graphID: graphID)
        }

        // 2) Fetch all graph-scoped records
        let gid = graphID

        let entities = try context.fetch(FetchDescriptor<MetaEntity>(predicate: #Predicate { e in
            e.graphID == gid
        }))

        let attributes = try context.fetch(FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in
            a.graphID == gid
        }))

        let fieldDefs = try context.fetch(FetchDescriptor<MetaDetailFieldDefinition>(predicate: #Predicate { d in
            d.graphID == gid
        }))

        let fieldValues = try context.fetch(FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate { v in
            v.graphID == gid
        }))

        let links = try context.fetch(FetchDescriptor<MetaLink>(predicate: #Predicate { l in
            l.graphID == gid
        }))

        // 3) Map to DTOs
        let graphDTO = GraphDTO(id: graph.id, createdAt: graph.createdAt, name: graph.name)

        let entitiesDTO: [EntityDTO] = entities
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { e in
                EntityDTO(
                    id: e.id,
                    createdAt: e.createdAt,
                    graphID: e.graphID,
                    name: e.name,
                    notes: options.includeNotes ? e.notes : "",
                    iconSymbolName: options.includeIcons ? e.iconSymbolName : nil,
                    imageData: options.includeImages ? e.imageData : nil
                )
            }

        let attributesDTO: [AttributeDTO] = attributes
            .sorted(by: { $0.name < $1.name })
            .map { a in
                AttributeDTO(
                    id: a.id,
                    graphID: a.graphID,
                    ownerEntityID: a.owner?.id,
                    name: a.name,
                    notes: options.includeNotes ? a.notes : "",
                    iconSymbolName: options.includeIcons ? a.iconSymbolName : nil,
                    imageData: options.includeImages ? a.imageData : nil
                )
            }

        let fieldDefsDTO: [DetailFieldDefinitionDTO] = fieldDefs
            .sorted(by: {
                if $0.entityID == $1.entityID { return $0.sortIndex < $1.sortIndex }
                return $0.entityID.uuidString < $1.entityID.uuidString
            })
            .map { d in
                DetailFieldDefinitionDTO(
                    id: d.id,
                    graphID: d.graphID,
                    entityID: d.entityID,
                    name: d.name,
                    typeRaw: d.typeRaw,
                    sortIndex: d.sortIndex,
                    isPinned: d.isPinned,
                    unit: d.unit,
                    options: d.options
                )
            }

        let fieldValuesDTO: [DetailFieldValueDTO] = fieldValues
            .sorted(by: {
                if $0.attributeID == $1.attributeID { return $0.fieldID.uuidString < $1.fieldID.uuidString }
                return $0.attributeID.uuidString < $1.attributeID.uuidString
            })
            .map { v in
                DetailFieldValueDTO(
                    id: v.id,
                    graphID: v.graphID,
                    attributeID: v.attributeID,
                    fieldID: v.fieldID,
                    stringValue: v.stringValue,
                    intValue: v.intValue,
                    doubleValue: v.doubleValue,
                    dateValue: v.dateValue,
                    boolValue: v.boolValue
                )
            }

        let linksDTO: [LinkDTO] = links
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { l in
                LinkDTO(
                    id: l.id,
                    createdAt: l.createdAt,
                    graphID: l.graphID,
                    note: options.includeNotes ? l.note : nil,
                    sourceLabel: l.sourceLabel,
                    targetLabel: l.targetLabel,
                    sourceKindRaw: l.sourceKindRaw,
                    sourceID: l.sourceID,
                    targetKindRaw: l.targetKindRaw,
                    targetID: l.targetID
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
            exportedAt: Date(),
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

        // 4) Encode + write
        let data = try GraphTransferCodec.encode(exportFile)
        let fileURL = try GraphTransferFileIO.makeExportFileURL(graphName: graph.name)

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw GraphTransferError.writeFailed(underlying: String(describing: error))
        }

        #if DEBUG
        log.debug("✅ Exported graph \(graphID.uuidString, privacy: .public) to \(fileURL.path, privacy: .public)")
        #endif

        return fileURL
    }
}
