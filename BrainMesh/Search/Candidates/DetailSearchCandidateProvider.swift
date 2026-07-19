//
//  DetailSearchCandidateProvider.swift
//  BrainMesh
//
//  Builds value-only candidates from detail definitions and typed detail values.
//

import Foundation
import SwiftData

nonisolated struct DetailSearchCandidateProvider: BrainMeshSearchCandidateProvider {
    let source: BrainMeshSearchCandidateSource = .detail

    func candidates(for request: BrainMeshSearchCandidateRequest) throws -> [BrainMeshSearchCandidate] {
        try request.checkCancellation()

        var candidates = try definitionCandidates(for: request)
        try request.checkCancellation()
        candidates.append(contentsOf: try valueCandidates(for: request))
        try request.checkCancellation()
        return candidates
    }

    private func definitionCandidates(
        for request: BrainMeshSearchCandidateRequest
    ) throws -> [BrainMeshSearchCandidate] {
        let foldedQuery = request.foldedQuery
        let descriptor: FetchDescriptor<MetaDetailFieldDefinition>
        if let graphID = request.graphID {
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

        let definitions = try request.modelContext.fetch(descriptor)
        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(definitions.count)

        for field in definitions {
            try request.checkCancellation()

            let ownerName = field.owner?.name ?? "Details-Schema"
            let fields = [
                BrainMeshSearchRankingField(
                    text: field.name,
                    reason: "Detailfeld",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: ownerName,
                    reason: "Entität",
                    priority: .secondaryLabel
                )
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(
                foldedQuery: foldedQuery,
                fields: fields
            ) else {
                continue
            }

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
            candidates.append(BrainMeshSearchCandidate(result: result, score: match.score))
        }

        return candidates
    }

    private func valueCandidates(
        for request: BrainMeshSearchCandidateRequest
    ) throws -> [BrainMeshSearchCandidate] {
        let valuesDescriptor: FetchDescriptor<MetaDetailFieldValue>
        if let graphID = request.graphID {
            valuesDescriptor = FetchDescriptor<MetaDetailFieldValue>(
                predicate: #Predicate<MetaDetailFieldValue> { value in
                    value.graphID == graphID
                }
            )
        } else {
            valuesDescriptor = FetchDescriptor<MetaDetailFieldValue>()
        }

        let values = try request.modelContext.fetch(valuesDescriptor)
        guard values.isEmpty == false else { return [] }
        try request.checkCancellation()

        let fieldIDs = Array(Set(values.map(\.fieldID)))
        let attributeIDs = Array(Set(values.map(\.attributeID)))
        let fieldMap = try fetchDetailDefinitionsByID(
            request: request,
            ids: fieldIDs
        )
        try request.checkCancellation()
        let attributeMap = try fetchAttributesByID(
            request: request,
            ids: attributeIDs
        )

        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(values.count)

        for value in values {
            try request.checkCancellation()

            let components = BrainMeshSearchDetailValueContent(
                stringValue: value.stringValue,
                intValue: value.intValue,
                doubleValue: value.doubleValue,
                dateValue: value.dateValue,
                boolValue: value.boolValue
            )
            let valueFields = BrainMeshSearchDetailValueFormatter.rankingFields(for: components)
            guard valueFields.isEmpty == false else { continue }

            let field = fieldMap[value.fieldID]
            let attribute = attributeMap[value.attributeID] ?? value.attribute
            let fieldName = field?.name ?? "Detailwert"
            let attributeLabel = attribute?.displayName ?? "Attribut"
            let displayValue = BrainMeshSearchDetailValueFormatter.displayText(for: components) ?? "Wert"

            let fields = valueFields + [
                BrainMeshSearchRankingField(
                    text: fieldName,
                    reason: "Detailfeld",
                    priority: .secondaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: attributeLabel,
                    reason: "Attribut",
                    priority: .secondaryLabel
                )
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(
                foldedQuery: request.foldedQuery,
                fields: fields
            ) else {
                continue
            }

            let result = BrainMeshSearchResult(
                kind: .detail,
                id: value.id,
                graphID: value.graphID,
                title: "\(fieldName): \(displayValue)",
                subtitle: attributeLabel,
                iconSymbolName: field?.type.systemImage
                    ?? BrainMeshSearchResultKind.detail.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: NodeKind.attribute.rawValue,
                ownerID: attribute?.id ?? value.attributeID
            )
            candidates.append(BrainMeshSearchCandidate(result: result, score: match.score))
        }

        return candidates
    }

    private func fetchDetailDefinitionsByID(
        request: BrainMeshSearchCandidateRequest,
        ids: [UUID]
    ) throws -> [UUID: MetaDetailFieldDefinition] {
        guard ids.isEmpty == false else { return [:] }
        try request.checkCancellation()

        let descriptor: FetchDescriptor<MetaDetailFieldDefinition>
        if let graphID = request.graphID {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(
                predicate: #Predicate<MetaDetailFieldDefinition> { field in
                    ids.contains(field.id) && field.graphID == graphID
                }
            )
        } else {
            descriptor = FetchDescriptor<MetaDetailFieldDefinition>(
                predicate: #Predicate<MetaDetailFieldDefinition> { field in
                    ids.contains(field.id)
                }
            )
        }

        let definitions = try request.modelContext.fetch(descriptor)
        try request.checkCancellation()
        return Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
    }

    private func fetchAttributesByID(
        request: BrainMeshSearchCandidateRequest,
        ids: [UUID]
    ) throws -> [UUID: MetaAttribute] {
        guard ids.isEmpty == false else { return [:] }
        try request.checkCancellation()

        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID = request.graphID {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    ids.contains(attribute.id) && attribute.graphID == graphID
                }
            )
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    ids.contains(attribute.id)
                }
            )
        }

        let attributes = try request.modelContext.fetch(descriptor)
        try request.checkCancellation()
        return Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    }
}
