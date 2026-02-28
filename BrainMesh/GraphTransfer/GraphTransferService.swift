//
//  GraphTransferService.swift
//  BrainMesh
//
//  Actor-based service for graph export/import.
//  (Skeleton only in PR GT1)
//

import Foundation
import os
import SwiftData
import UniformTypeIdentifiers

actor GraphTransferService {

    static let shared = GraphTransferService()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "GraphTransferService")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    // MARK: - Public Types

    struct ExportOptions: Sendable {
        var includeNotes: Bool
        var includeIcons: Bool
        var includeImages: Bool

        init(includeNotes: Bool = true, includeIcons: Bool = true, includeImages: Bool = false) {
            self.includeNotes = includeNotes
            self.includeIcons = includeIcons
            self.includeImages = includeImages
        }
    }

    // MARK: - API (Stubs in PR GT1)

    func exportGraph(graphID: UUID, options: ExportOptions) async throws -> URL {
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
        let data = try Self.encode(exportFile)
        let fileURL = try Self.makeExportFileURL(graphName: graph.name)

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

    func inspectFile(url: URL) async throws -> ImportPreview {
        guard container != nil else { throw GraphTransferError.notConfigured }

        let data = try Self.readFileData(url: url)
        let file = try Self.decode(data)
        try Self.validate(exportFile: file)

        return ImportPreview(
            graphName: file.graph.name,
            exportedAt: file.exportedAt,
            version: file.version,
            counts: file.counts
        )
    }

    func importGraph(
        from url: URL,
        mode: ImportMode,
        progress: (@Sendable (GraphTransferProgress) -> Void)? = nil
    ) async throws -> ImportResult {
        guard let container else { throw GraphTransferError.notConfigured }

        progress?(GraphTransferProgress(phase: .inspecting, completed: 0, label: "Datei wird geprüft…"))

        let data = try Self.readFileData(url: url)
        let file = try Self.decode(data)
        try Self.validate(exportFile: file)

        switch mode {
        case .asNewGraphRemap:
            return try await Self.importAsNewGraphRemap(file: file, container: container, progress: progress)
        }
    }
}

// MARK: - Import

private extension GraphTransferService {

    static func importAsNewGraphRemap(
        file: GraphExportFileV1,
        container: AnyModelContainer,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> ImportResult {
        let context = ModelContext(container.container)
        context.autosaveEnabled = false

        progress?(GraphTransferProgress(phase: .creatingGraph, completed: 0, label: "Neuer Graph wird angelegt…"))

        let newGraphID = UUID()

        let graph = MetaGraph(name: file.graph.name)
        graph.id = newGraphID
        graph.createdAt = file.graph.createdAt
        context.insert(graph)

        // Remap dictionaries
        var entityIDMap: [UUID: UUID] = [:]
        var attributeIDMap: [UUID: UUID] = [:]
        var fieldIDMap: [UUID: UUID] = [:]

        var entitiesByNewID: [UUID: MetaEntity] = [:]
        var attributesByNewID: [UUID: MetaAttribute] = [:]

        // Batch save helper
        var insertedSinceLastSave = 0
        func maybeSave() throws {
            if insertedSinceLastSave >= 500 {
                do {
                    try context.save()
                    insertedSinceLastSave = 0
                } catch {
                    throw GraphTransferError.saveFailed(underlying: String(describing: error))
                }
            }
        }

        // 1) Entities
        let totalEntities = file.entities.count
        progress?(GraphTransferProgress(phase: .entities, completed: 0, total: totalEntities, label: "Entitäten werden importiert…"))

        for (idx, dto) in file.entities.enumerated() {
            if idx % 50 == 0 { try Task.checkCancellation() }
            if idx % 200 == 0 { await Task.yield() }

            let newID = UUID()
            entityIDMap[dto.id] = newID

            let entity = MetaEntity(name: dto.name, graphID: newGraphID, iconSymbolName: dto.iconSymbolName)
            entity.id = newID
            entity.createdAt = dto.createdAt
            entity.notes = dto.notes
            entity.imageData = dto.imageData
            entity.imagePath = nil

            context.insert(entity)
            entitiesByNewID[newID] = entity

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % 50 == 0 || idx + 1 == totalEntities {
                progress?(GraphTransferProgress(phase: .entities, completed: idx + 1, total: totalEntities, label: "Entitäten: \(idx + 1)/\(totalEntities)"))
            }
        }

        // 2) Detail field definitions
        let totalFields = file.detailFieldDefinitions.count
        progress?(GraphTransferProgress(phase: .fields, completed: 0, total: totalFields, label: "Details-Felder werden importiert…"))

        for (idx, dto) in file.detailFieldDefinitions.enumerated() {
            if idx % 50 == 0 { try Task.checkCancellation() }
            if idx % 200 == 0 { await Task.yield() }

            guard let newOwnerEntityID = entityIDMap[dto.entityID],
                  let owner = entitiesByNewID[newOwnerEntityID]
            else {
                continue
            }

            let newID = UUID()
            fieldIDMap[dto.id] = newID

            let type = DetailFieldType(rawValue: dto.typeRaw) ?? .singleLineText
            let def = MetaDetailFieldDefinition(
                owner: owner,
                name: dto.name,
                type: type,
                sortIndex: dto.sortIndex,
                unit: dto.unit,
                options: dto.options,
                isPinned: dto.isPinned
            )
            def.id = newID
            def.graphID = newGraphID
            owner.addDetailField(def)

            context.insert(def)
            insertedSinceLastSave += 1
            try maybeSave()

            if idx % 50 == 0 || idx + 1 == totalFields {
                progress?(GraphTransferProgress(phase: .fields, completed: idx + 1, total: totalFields, label: "Felder: \(idx + 1)/\(totalFields)"))
            }
        }

        // 3) Attributes
        let totalAttributes = file.attributes.count
        progress?(GraphTransferProgress(phase: .attributes, completed: 0, total: totalAttributes, label: "Attribute werden importiert…"))

        for (idx, dto) in file.attributes.enumerated() {
            if idx % 50 == 0 { try Task.checkCancellation() }
            if idx % 200 == 0 { await Task.yield() }

            guard let oldOwnerID = dto.ownerEntityID,
                  let newOwnerID = entityIDMap[oldOwnerID],
                  let owner = entitiesByNewID[newOwnerID]
            else {
                // Attribute without owner are ignored (would be orphaned and mostly useless in UI).
                continue
            }

            let newID = UUID()
            attributeIDMap[dto.id] = newID

            let attr = MetaAttribute(name: dto.name, owner: owner, graphID: newGraphID, iconSymbolName: dto.iconSymbolName)
            attr.id = newID
            attr.notes = dto.notes
            attr.imageData = dto.imageData
            attr.imagePath = nil
            owner.addAttribute(attr)

            context.insert(attr)
            attributesByNewID[newID] = attr

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % 50 == 0 || idx + 1 == totalAttributes {
                progress?(GraphTransferProgress(phase: .attributes, completed: idx + 1, total: totalAttributes, label: "Attribute: \(idx + 1)/\(totalAttributes)"))
            }
        }

        // 4) Detail field values
        let totalValues = file.detailFieldValues.count
        progress?(GraphTransferProgress(phase: .values, completed: 0, total: totalValues, label: "Details-Werte werden importiert…"))

        var importedValues = 0
        for (idx, dto) in file.detailFieldValues.enumerated() {
            if idx % 100 == 0 { try Task.checkCancellation() }
            if idx % 300 == 0 { await Task.yield() }

            guard let newAttrID = attributeIDMap[dto.attributeID],
                  let attr = attributesByNewID[newAttrID]
            else {
                continue
            }
            guard let newFieldID = fieldIDMap[dto.fieldID] else {
                continue
            }

            let value = MetaDetailFieldValue(attribute: attr, fieldID: newFieldID)
            value.id = UUID()
            value.graphID = newGraphID

            value.stringValue = dto.stringValue
            value.intValue = dto.intValue
            value.doubleValue = dto.doubleValue
            value.dateValue = dto.dateValue
            value.boolValue = dto.boolValue

            if attr.detailValues == nil { attr.detailValues = [] }
            // De-dupe per attribute+field (defensive against legacy duplicates).
            if attr.detailValues?.contains(where: { $0.fieldID == newFieldID }) == true {
                continue
            }
            attr.detailValues?.append(value)

            context.insert(value)
            importedValues += 1

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % 100 == 0 || idx + 1 == totalValues {
                progress?(GraphTransferProgress(phase: .values, completed: idx + 1, total: totalValues, label: "Werte: \(idx + 1)/\(totalValues)"))
            }
        }

        // 5) Links
        let totalLinks = file.links.count
        progress?(GraphTransferProgress(phase: .links, completed: 0, total: totalLinks, label: "Links werden importiert…"))

        var importedLinks = 0
        var skippedLinks = 0

        for (idx, dto) in file.links.enumerated() {
            if idx % 100 == 0 { try Task.checkCancellation() }
            if idx % 300 == 0 { await Task.yield() }

            guard let newSourceID = remapNodeID(kindRaw: dto.sourceKindRaw, oldID: dto.sourceID, entityIDMap: entityIDMap, attributeIDMap: attributeIDMap),
                  let newTargetID = remapNodeID(kindRaw: dto.targetKindRaw, oldID: dto.targetID, entityIDMap: entityIDMap, attributeIDMap: attributeIDMap)
            else {
                skippedLinks += 1
                continue
            }

            let sourceKind = NodeKind(rawValue: dto.sourceKindRaw) ?? .entity
            let targetKind = NodeKind(rawValue: dto.targetKindRaw) ?? .entity

            let link = MetaLink(
                sourceKind: sourceKind,
                sourceID: newSourceID,
                sourceLabel: dto.sourceLabel,
                targetKind: targetKind,
                targetID: newTargetID,
                targetLabel: dto.targetLabel,
                note: dto.note,
                graphID: newGraphID
            )

            link.id = UUID()
            link.createdAt = dto.createdAt
            context.insert(link)
            importedLinks += 1

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % 100 == 0 || idx + 1 == totalLinks {
                progress?(GraphTransferProgress(phase: .links, completed: idx + 1, total: totalLinks, label: "Links: \(idx + 1)/\(totalLinks)"))
            }
        }

        // Final save
        progress?(GraphTransferProgress(phase: .saving, completed: 0, label: "Speichere…"))
        do {
            try context.save()
        } catch {
            throw GraphTransferError.saveFailed(underlying: String(describing: error))
        }

        let insertedCounts = CountsDTO(
            graphs: 1,
            entities: entitiesByNewID.count,
            attributes: attributesByNewID.count,
            detailFieldDefinitions: fieldIDMap.count,
            detailFieldValues: importedValues,
            links: importedLinks
        )

        progress?(GraphTransferProgress(phase: .done, completed: 1, total: 1, label: "Fertig"))

        return ImportResult(
            newGraphID: newGraphID,
            insertedCounts: insertedCounts,
            skippedLinks: skippedLinks
        )
    }

    static func remapNodeID(
        kindRaw: Int,
        oldID: UUID,
        entityIDMap: [UUID: UUID],
        attributeIDMap: [UUID: UUID]
    ) -> UUID? {
        if kindRaw == NodeKind.entity.rawValue {
            return entityIDMap[oldID]
        }
        if kindRaw == NodeKind.attribute.rawValue {
            return attributeIDMap[oldID]
        }
        return nil
    }
}

// MARK: - Helpers

private extension GraphTransferService {

    static func validate(exportFile: GraphExportFileV1) throws {
        guard exportFile.format == GraphTransferFormat.formatID else {
            throw GraphTransferError.invalidFormat
        }
        guard exportFile.version == GraphTransferFormat.version else {
            throw GraphTransferError.unsupportedVersion(found: exportFile.version)
        }
    }

    static func decode(_ data: Data) throws -> GraphExportFileV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(GraphExportFileV1.self, from: data)
        } catch {
            throw GraphTransferError.decodeFailed(underlying: String(describing: error))
        }
    }

    static func readFileData(url: URL) throws -> Data {
        // Best-effort security-scoped access.
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == 257 || ns.code == 513 {
                throw GraphTransferError.fileAccessDenied
            }
            throw GraphTransferError.readFailed(underlying: String(describing: error))
        }
    }

    static var appVersionString: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static var appBuildString: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    static func encode(_ exportFile: GraphExportFileV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        #if DEBUG
        formatting.insert(.prettyPrinted)
        #endif
        encoder.outputFormatting = formatting
        return try encoder.encode(exportFile)
    }

    static func makeExportFileURL(graphName: String) throws -> URL {
        let dateString = exportDateString(Date())
        let cleanedName = sanitizeFilenameComponent(graphName)
        let graphComponent = cleanedName.isEmpty ? "Graph" : cleanedName

        let base = "BrainMesh-\(graphComponent)-\(dateString)"
        let tmp = FileManager.default.temporaryDirectory

        var candidate = tmp
            .appendingPathComponent(base)
            .appendingPathExtension(UTType.brainMeshGraphFilenameExtension)

        var idx = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = tmp
                .appendingPathComponent("\(base)-\(idx)")
                .appendingPathExtension(UTType.brainMeshGraphFilenameExtension)
            idx += 1
        }

        return candidate
    }

    static func exportDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    static func sanitizeFilenameComponent(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Replace forbidden characters on common filesystems.
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let replaced = trimmed
            .components(separatedBy: forbidden)
            .joined(separator: " ")

        let collapsed = replaced
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        // Keep filenames at a reasonable length.
        let maxLen = 64
        if collapsed.count <= maxLen { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLen)
        return String(collapsed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
