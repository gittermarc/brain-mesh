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
            let integrity = DetailDataModelSnapshotMapper.field(field)
            guard DetailDataIntegrityPolicy.fieldViolations(integrity).isEmpty else {
                continue
            }

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
        let authoritativeValues = authoritativeValueModels(
            values: values,
            fieldMap: fieldMap,
            attributeMap: attributeMap
        )
        candidates.reserveCapacity(authoritativeValues.count)

        for value in authoritativeValues {
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
        var result: [UUID: MetaDetailFieldDefinition] = [:]
        for definition in definitions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let snapshot = DetailDataModelSnapshotMapper.field(definition)
            guard DetailDataIntegrityPolicy.fieldViolations(snapshot).isEmpty else {
                continue
            }
            if result[definition.id] == nil {
                result[definition.id] = definition
            }
        }
        return result
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
        var result: [UUID: MetaAttribute] = [:]
        for attribute in attributes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let snapshot = DetailDataModelSnapshotMapper.attribute(attribute)
            guard DetailDataIntegrityPolicy.attributeViolations(snapshot).isEmpty else {
                continue
            }
            if result[attribute.id] == nil {
                result[attribute.id] = attribute
            }
        }
        return result
    }

    private func authoritativeValueModels(
        values: [MetaDetailFieldValue],
        fieldMap: [UUID: MetaDetailFieldDefinition],
        attributeMap: [UUID: MetaAttribute]
    ) -> [MetaDetailFieldValue] {
        var grouped: [DetailValueAuthorityKey: [MetaDetailFieldValue]] = [:]
        var fieldByKey: [DetailValueAuthorityKey: MetaDetailFieldDefinition] = [:]
        var attributeByKey: [DetailValueAuthorityKey: MetaAttribute] = [:]

        for value in values {
            guard let field = fieldMap[value.fieldID],
                  let attribute = attributeMap[value.attributeID],
                  let key = DetailDataIntegrityPolicy.key(
                    for: DetailDataModelSnapshotMapper.field(field),
                    attribute: DetailDataModelSnapshotMapper.attribute(attribute)
                  ) else {
                continue
            }
            grouped[key, default: []].append(value)
            fieldByKey[key] = field
            attributeByKey[key] = attribute
        }

        var result: [MetaDetailFieldValue] = []
        let keys = grouped.keys.sorted { lhs, rhs in
            if lhs.graphID != rhs.graphID {
                return lhs.graphID.uuidString < rhs.graphID.uuidString
            }
            if lhs.attributeID != rhs.attributeID {
                return lhs.attributeID.uuidString < rhs.attributeID.uuidString
            }
            return lhs.fieldID.uuidString < rhs.fieldID.uuidString
        }
        for key in keys {
            guard let field = fieldByKey[key],
                  let attribute = attributeByKey[key] else {
                continue
            }
            let records = grouped[key] ?? []
            let resolution = DetailDataModelSnapshotMapper.authority(
                field: field,
                attribute: attribute,
                records: records
            )
            guard let recordID = resolution.authoritativeRecordID,
                  let value = records.first(where: { $0.id == recordID }) else {
                continue
            }
            result.append(value)
        }
        return result
    }
}
