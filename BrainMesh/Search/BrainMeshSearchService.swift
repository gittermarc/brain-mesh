//
//  BrainMeshSearchService.swift
//  BrainMesh
//
//  Global graph-scoped search service. The service returns value-only DTOs and never exposes SwiftData models.
//

import Foundation
import SwiftData
import os

actor BrainMeshSearchService {
    static let shared = BrainMeshSearchService()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "BrainMeshSearchService")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func search(
        graphID: UUID?,
        foldedQuery: String,
        limit: Int
    ) async throws -> BrainMeshSearchSnapshot {
        let query = BMSearch.fold(foldedQuery)
        guard query.isEmpty == false else {
            return BrainMeshSearchSnapshot(query: query, results: [])
        }

        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.BrainMeshSearchService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "BrainMeshSearchService not configured"]
            )
        }

        let safeLimit = max(0, min(limit, 100))
        guard safeLimit > 0 else {
            return BrainMeshSearchSnapshot(query: query, results: [])
        }

        let gid = graphID

        return try await Task.detached(priority: .utility) { [configuredContainer, gid, query, safeLimit] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            try Task.checkCancellation()

            let candidates = try BrainMeshSearchService.fetchCandidates(
                context: context,
                graphID: gid,
                foldedQuery: query
            )

            try Task.checkCancellation()

            let sorted = BrainMeshSearchRanking.sortedCandidates(candidates)
            let results = sorted.prefix(safeLimit).map(\.result)
            return BrainMeshSearchSnapshot(query: query, results: Array(results))
        }.value
    }
}

private extension BrainMeshSearchService {
    static func fetchCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        var candidates: [BrainMeshSearchCandidate] = []

        candidates.append(contentsOf: try fetchEntityCandidates(context: context, graphID: graphID, foldedQuery: foldedQuery))
        try Task.checkCancellation()

        candidates.append(contentsOf: try fetchAttributeCandidates(context: context, graphID: graphID, foldedQuery: foldedQuery))
        try Task.checkCancellation()

        candidates.append(contentsOf: try fetchLinkCandidates(context: context, graphID: graphID, foldedQuery: foldedQuery))
        try Task.checkCancellation()

        candidates.append(contentsOf: try fetchDetailDefinitionCandidates(context: context, graphID: graphID, foldedQuery: foldedQuery))
        try Task.checkCancellation()

        candidates.append(contentsOf: try fetchDetailValueCandidates(context: context, graphID: graphID, foldedQuery: foldedQuery))
        try Task.checkCancellation()

        candidates.append(contentsOf: try fetchAttachmentCandidates(context: context, graphID: graphID, foldedQuery: foldedQuery))

        return candidates
    }

    static func fetchEntityCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        let descriptor: FetchDescriptor<MetaEntity>
        if let graphID {
            descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.graphID == graphID && (entity.nameFolded.contains(foldedQuery) || entity.notesFolded.contains(foldedQuery))
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.nameFolded.contains(foldedQuery) || entity.notesFolded.contains(foldedQuery)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }

        return try context.fetch(descriptor).compactMap { entity in
            let fields = [
                BrainMeshSearchRankingField(text: entity.name, reason: "Name", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: entity.notes, reason: "Notiz", priority: .notes)
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(foldedQuery: foldedQuery, fields: fields) else { return nil }

            let result = BrainMeshSearchResult(
                kind: .entity,
                id: entity.id,
                graphID: entity.graphID,
                title: entity.name,
                subtitle: "Entität",
                iconSymbolName: entity.iconSymbolName ?? BrainMeshSearchResultKind.entity.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: entity.id,
                ownerKindRaw: nil,
                ownerID: nil
            )
            return BrainMeshSearchCandidate(result: result, score: match.score)
        }
    }

    static func fetchAttributeCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.graphID == graphID && (attribute.searchLabelFolded.contains(foldedQuery) || attribute.notesFolded.contains(foldedQuery))
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.searchLabelFolded.contains(foldedQuery) || attribute.notesFolded.contains(foldedQuery)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        }

        return try context.fetch(descriptor).compactMap { attribute in
            let ownerName = attribute.owner?.name ?? "Ohne Entität"
            let displayName = attribute.displayName
            let fields = [
                BrainMeshSearchRankingField(text: attribute.name, reason: "Attribut", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: displayName, reason: "Label", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: ownerName, reason: "Entität", priority: .secondaryLabel),
                BrainMeshSearchRankingField(text: attribute.notes, reason: "Notiz", priority: .notes)
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(foldedQuery: foldedQuery, fields: fields) else { return nil }

            let result = BrainMeshSearchResult(
                kind: .attribute,
                id: attribute.id,
                graphID: attribute.graphID,
                title: attribute.name,
                subtitle: ownerName,
                iconSymbolName: attribute.iconSymbolName ?? BrainMeshSearchResultKind.attribute.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: NodeKind.attribute.rawValue,
                nodeID: attribute.id,
                ownerKindRaw: NodeKind.entity.rawValue,
                ownerID: attribute.owner?.id
            )
            return BrainMeshSearchCandidate(result: result, score: match.score)
        }
    }

    static func fetchLinkCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        let descriptor: FetchDescriptor<MetaLink>
        if let graphID {
            descriptor = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { link in
                link.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaLink>()
        }

        return try context.fetch(descriptor).compactMap { link in
            let note = link.note ?? ""
            let title = "\(link.sourceLabel) → \(link.targetLabel)"
            let fields = [
                BrainMeshSearchRankingField(text: link.sourceLabel, reason: "Quell-Label", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: link.targetLabel, reason: "Ziel-Label", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: title, reason: "Verbindung", priority: .secondaryLabel),
                BrainMeshSearchRankingField(text: note, reason: "Link-Notiz", priority: .notes)
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(foldedQuery: foldedQuery, fields: fields) else { return nil }

            let subtitle = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Link" : note
            let result = BrainMeshSearchResult(
                kind: .link,
                id: link.id,
                graphID: link.graphID,
                title: title,
                subtitle: subtitle,
                iconSymbolName: BrainMeshSearchResultKind.link.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: nil,
                ownerID: nil
            )
            return BrainMeshSearchCandidate(result: result, score: match.score)
        }
    }

    static func fetchDetailDefinitionCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        let descriptor: FetchDescriptor<MetaDetailFieldDefinition>
        if let graphID {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(
                predicate: #Predicate<MetaDetailFieldDefinition> { field in
                    field.graphID == graphID && field.nameFolded.contains(foldedQuery)
                },
                sortBy: [SortDescriptor(\MetaDetailFieldDefinition.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(
                predicate: #Predicate<MetaDetailFieldDefinition> { field in
                    field.nameFolded.contains(foldedQuery)
                },
                sortBy: [SortDescriptor(\MetaDetailFieldDefinition.name)]
            )
        }

        return try context.fetch(descriptor).compactMap { field in
            let ownerName = field.owner?.name ?? "Details-Schema"
            let fields = [
                BrainMeshSearchRankingField(text: field.name, reason: "Detailfeld", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: ownerName, reason: "Entität", priority: .secondaryLabel)
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(foldedQuery: foldedQuery, fields: fields) else { return nil }

            let result = BrainMeshSearchResult(
                kind: .detail,
                id: field.id,
                graphID: field.graphID,
                title: field.name,
                subtitle: ownerName,
                iconSymbolName: field.type.systemImage,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: NodeKind.entity.rawValue,
                ownerID: field.owner?.id ?? field.entityID
            )
            return BrainMeshSearchCandidate(result: result, score: match.score)
        }
    }

    static func fetchDetailValueCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        let valuesDescriptor: FetchDescriptor<MetaDetailFieldValue>
        if let graphID {
            valuesDescriptor = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate<MetaDetailFieldValue> { value in
                value.graphID == graphID
            })
        } else {
            valuesDescriptor = FetchDescriptor<MetaDetailFieldValue>()
        }

        let values = try context.fetch(valuesDescriptor)
        guard values.isEmpty == false else { return [] }

        let fieldIDs = Array(Set(values.map(\.fieldID)))
        let attributeIDs = Array(Set(values.map(\.attributeID)))
        let fieldMap = try fetchDetailDefinitionsByID(context: context, graphID: graphID, ids: fieldIDs)
        let attributeMap = try fetchAttributesByID(context: context, graphID: graphID, ids: attributeIDs)

        return values.compactMap { value in
            let valueFields = detailValueRankingFields(value)
            guard valueFields.isEmpty == false else { return nil }

            let field = fieldMap[value.fieldID]
            let attribute = attributeMap[value.attributeID] ?? value.attribute
            let fieldName = field?.name ?? "Detailwert"
            let attributeLabel = attribute?.displayName ?? "Attribut"
            let displayValue = detailValueDisplayText(value) ?? "Wert"

            let fields = valueFields + [
                BrainMeshSearchRankingField(text: fieldName, reason: "Detailfeld", priority: .secondaryLabel),
                BrainMeshSearchRankingField(text: attributeLabel, reason: "Attribut", priority: .secondaryLabel)
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(foldedQuery: foldedQuery, fields: fields) else { return nil }

            let result = BrainMeshSearchResult(
                kind: .detail,
                id: value.id,
                graphID: value.graphID,
                title: "\(fieldName): \(displayValue)",
                subtitle: attributeLabel,
                iconSymbolName: field?.type.systemImage ?? BrainMeshSearchResultKind.detail.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: NodeKind.attribute.rawValue,
                ownerID: attribute?.id ?? value.attributeID
            )
            return BrainMeshSearchCandidate(result: result, score: match.score)
        }
    }

    static func fetchAttachmentCandidates(
        context: ModelContext,
        graphID: UUID?,
        foldedQuery: String
    ) throws -> [BrainMeshSearchCandidate] {
        let descriptor: FetchDescriptor<MetaAttachment>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { attachment in
                attachment.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaAttachment>()
        }

        return try context.fetch(descriptor).compactMap { attachment in
            let fields = [
                BrainMeshSearchRankingField(text: attachment.title, reason: "Anhang-Titel", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: attachment.originalFilename, reason: "Dateiname", priority: .primaryLabel),
                BrainMeshSearchRankingField(text: attachment.fileExtension, reason: "Dateiendung", priority: .metadata),
                BrainMeshSearchRankingField(text: attachment.contentTypeIdentifier, reason: "Dateityp", priority: .metadata)
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(foldedQuery: foldedQuery, fields: fields) else { return nil }

            let title = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? attachment.originalFilename : attachment.title
            let subtitle = attachment.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Anhang" : attachment.originalFilename
            let result = BrainMeshSearchResult(
                kind: .attachment,
                id: attachment.id,
                graphID: attachment.graphID,
                title: title,
                subtitle: subtitle,
                iconSymbolName: attachment.contentKind.searchIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: attachment.ownerKind.rawValue,
                ownerID: attachment.ownerID
            )
            return BrainMeshSearchCandidate(result: result, score: match.score)
        }
    }

    static func fetchDetailDefinitionsByID(
        context: ModelContext,
        graphID: UUID?,
        ids: [UUID]
    ) throws -> [UUID: MetaDetailFieldDefinition] {
        guard ids.isEmpty == false else { return [:] }
        let descriptor: FetchDescriptor<MetaDetailFieldDefinition>
        if let graphID {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(predicate: #Predicate<MetaDetailFieldDefinition> { field in
                ids.contains(field.id) && field.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(predicate: #Predicate<MetaDetailFieldDefinition> { field in
                ids.contains(field.id)
            })
        }

        return Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.id, $0) })
    }

    static func fetchAttributesByID(
        context: ModelContext,
        graphID: UUID?,
        ids: [UUID]
    ) throws -> [UUID: MetaAttribute] {
        guard ids.isEmpty == false else { return [:] }
        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                ids.contains(attribute.id) && attribute.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                ids.contains(attribute.id)
            })
        }

        return Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.id, $0) })
    }

    static func detailValueRankingFields(_ value: MetaDetailFieldValue) -> [BrainMeshSearchRankingField] {
        var fields: [BrainMeshSearchRankingField] = []

        if let stringValue = value.stringValue, stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append(BrainMeshSearchRankingField(text: stringValue, reason: "Detailwert", priority: .primaryLabel))
        }

        if let intValue = value.intValue {
            fields.append(BrainMeshSearchRankingField(text: String(intValue), reason: "Detailwert", priority: .primaryLabel))
        }

        if let doubleValue = value.doubleValue {
            fields.append(BrainMeshSearchRankingField(text: String(doubleValue), reason: "Detailwert", priority: .primaryLabel))
        }

        if let dateValue = value.dateValue {
            fields.append(BrainMeshSearchRankingField(text: localizedDateText(dateValue), reason: "Detailwert", priority: .primaryLabel))
            fields.append(BrainMeshSearchRankingField(text: isoDateText(dateValue), reason: "Detailwert", priority: .metadata))
        }

        if let boolValue = value.boolValue {
            fields.append(BrainMeshSearchRankingField(text: boolValue ? "Ja" : "Nein", reason: "Detailwert", priority: .primaryLabel))
            fields.append(BrainMeshSearchRankingField(text: boolValue ? "true" : "false", reason: "Detailwert", priority: .metadata))
        }

        return fields
    }

    static func detailValueDisplayText(_ value: MetaDetailFieldValue) -> String? {
        if let stringValue = value.stringValue, stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return stringValue
        }
        if let intValue = value.intValue {
            return String(intValue)
        }
        if let doubleValue = value.doubleValue {
            return String(doubleValue)
        }
        if let dateValue = value.dateValue {
            return localizedDateText(dateValue)
        }
        if let boolValue = value.boolValue {
            return boolValue ? "Ja" : "Nein"
        }
        return nil
    }

    static func localizedDateText(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    static func isoDateText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

private extension AttachmentContentKind {
    var searchIconSymbolName: String {
        switch self {
        case .file:
            return "paperclip"
        case .video:
            return "video"
        case .galleryImage:
            return "photo"
        }
    }
}
