//
//  DetailValueMutationService.swift
//  BrainMesh
//
//  Atomic, validated detail-value writes with conflict consolidation.
//

import Foundation
import SwiftData

nonisolated enum DetailValueWritePayload: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case date(Date)
    case boolean(Bool)

    var typedStorage: DetailTypedStorageSnapshot {
        switch self {
        case .string(let value):
            return DetailTypedStorageSnapshot(
                stringValue: value,
                intValue: nil,
                doubleValue: nil,
                dateValue: nil,
                boolValue: nil
            )
        case .integer(let value):
            return DetailTypedStorageSnapshot(
                stringValue: nil,
                intValue: value,
                doubleValue: nil,
                dateValue: nil,
                boolValue: nil
            )
        case .double(let value):
            return DetailTypedStorageSnapshot(
                stringValue: nil,
                intValue: nil,
                doubleValue: value,
                dateValue: nil,
                boolValue: nil
            )
        case .date(let value):
            return DetailTypedStorageSnapshot(
                stringValue: nil,
                intValue: nil,
                doubleValue: nil,
                dateValue: value,
                boolValue: nil
            )
        case .boolean(let value):
            return DetailTypedStorageSnapshot(
                stringValue: nil,
                intValue: nil,
                doubleValue: nil,
                dateValue: nil,
                boolValue: value
            )
        }
    }

    func apply(to record: MetaDetailFieldValue) {
        record.clearTypedValues()
        switch self {
        case .string(let value):
            record.stringValue = value
        case .integer(let value):
            record.intValue = value
        case .double(let value):
            record.doubleValue = value
        case .date(let value):
            record.dateValue = value
        case .boolean(let value):
            record.boolValue = value
        }
    }
}

nonisolated enum DetailValueMutationOutcome: Equatable, Sendable {
    case noChange
    case saved(authoritativeRecordID: UUID, consolidatedRecordCount: Int)
    case deleted(recordCount: Int)
}

@MainActor
enum DetailValueMutationService {
    static func save(
        _ payload: DetailValueWritePayload,
        attribute: MetaAttribute,
        field: MetaDetailFieldDefinition,
        modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> DetailValueMutationOutcome {
        let graphID = try DetailDataWriteValidator.validateProposedValue(
            storage: payload.typedStorage,
            field: field,
            attribute: attribute
        )

        let candidates = try candidateRecords(
            attribute: attribute,
            field: field,
            modelContext: modelContext
        )
        let repairable = repairableRecords(
            candidates,
            attribute: attribute,
            field: field,
            graphID: graphID
        )
        let authority = DetailDataModelSnapshotMapper.authority(
            field: field,
            attribute: attribute,
            records: repairable
        )
        if case .authoritative(_, let currentValue, let removableIDs) = authority,
           removableIDs.isEmpty,
           currentValue == typedValue(for: payload, fieldType: field.type)
        {
            return .noChange
        }

        try Task.checkCancellation()

        let target: MetaDetailFieldValue
        if let authoritativeID = authority.authoritativeRecordID,
           let existing = repairable.first(where: { $0.id == authoritativeID })
        {
            target = existing
        } else if let existing = repairable.sorted(by: stableValueOrder).first {
            target = existing
        } else {
            target = MetaDetailFieldValue(attribute: attribute, fieldID: field.id)
            modelContext.insert(target)
            if attribute.detailValues == nil {
                attribute.detailValues = []
            }
            attribute.detailValues?.append(target)
        }

        target.attribute = attribute
        target.graphID = graphID
        target.attributeID = attribute.id
        target.fieldID = field.id
        payload.apply(to: target)

        let duplicates = repairable
            .filter { $0.id != target.id }
            .sorted(by: stableValueOrder)
        let deletedReferences = duplicates.map(reference)
        for duplicate in duplicates {
            attribute.detailValues?.removeAll { $0.id == duplicate.id }
            modelContext.delete(duplicate)
        }

        let authoritativeReference = reference(target)
        let batch = try GraphMutationBatchFactory.detailValueConsolidated(
            graphID: graphID,
            authoritativeValue: authoritativeReference,
            deletedValues: deletedReferences
        )
        _ = try await committer.commit(batch, in: modelContext)
        return .saved(
            authoritativeRecordID: target.id,
            consolidatedRecordCount: duplicates.count
        )
    }

    static func delete(
        attribute: MetaAttribute,
        field: MetaDetailFieldDefinition,
        modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> DetailValueMutationOutcome {
        let graphID = try DetailDataWriteValidator.validate(
            field: field,
            attribute: attribute
        )
        let candidates = try candidateRecords(
            attribute: attribute,
            field: field,
            modelContext: modelContext
        )
        let repairable = repairableRecords(
            candidates,
            attribute: attribute,
            field: field,
            graphID: graphID
        )
        guard repairable.isEmpty == false else {
            return .noChange
        }

        try Task.checkCancellation()
        let references = repairable.map(reference)
        for value in repairable {
            attribute.detailValues?.removeAll { $0.id == value.id }
            modelContext.delete(value)
        }

        let batch = try GraphMutationBatchFactory.detailValuesDeleted(
            graphID: graphID,
            values: references
        )
        _ = try await committer.commit(batch, in: modelContext)
        return .deleted(recordCount: repairable.count)
    }

    static func authority(
        attribute: MetaAttribute,
        field: MetaDetailFieldDefinition,
        modelContext: ModelContext
    ) throws -> (
        resolution: DetailValueAuthorityResolution,
        records: [MetaDetailFieldValue]
    ) {
        _ = try DetailDataWriteValidator.validate(
            field: field,
            attribute: attribute
        )
        let candidates = try candidateRecords(
            attribute: attribute,
            field: field,
            modelContext: modelContext
        )
        let graphID = try requireGraphID(attribute.graphID)
        let repairable = repairableRecords(
            candidates,
            attribute: attribute,
            field: field,
            graphID: graphID
        )
        return (
            DetailDataModelSnapshotMapper.authority(
                field: field,
                attribute: attribute,
                records: repairable
            ),
            repairable
        )
    }

    private static func candidateRecords(
        attribute: MetaAttribute,
        field: MetaDetailFieldDefinition,
        modelContext: ModelContext
    ) throws -> [MetaDetailFieldValue] {
        let attributeID = attribute.id
        let fieldID = field.id
        let fetched = try modelContext.fetch(
            FetchDescriptor<MetaDetailFieldValue>(
                predicate: #Predicate { value in
                    value.attributeID == attributeID
                        && value.fieldID == fieldID
                }
            )
        )
        var recordsByID: [UUID: MetaDetailFieldValue] = [:]
        for value in fetched + attribute.detailValuesList {
            guard value.fieldID == field.id else { continue }
            recordsByID[value.id] = value
        }
        return recordsByID.values.sorted(by: stableValueOrder)
    }

    private static func repairableRecords(
        _ records: [MetaDetailFieldValue],
        attribute: MetaAttribute,
        field: MetaDetailFieldDefinition,
        graphID: UUID
    ) -> [MetaDetailFieldValue] {
        records.filter { value in
            value.fieldID == field.id
                && value.attribute?.id == attribute.id
                && value.attribute?.owner?.id == field.owner?.id
                && value.attribute?.graphID == graphID
                && value.attribute?.owner?.graphID == graphID
                && (value.graphID == nil || value.graphID == graphID)
        }
        .sorted(by: stableValueOrder)
    }

    private static func typedValue(
        for payload: DetailValueWritePayload,
        fieldType: DetailFieldType
    ) -> DetailTypedValue? {
        guard case .valid(let value) = DetailDataIntegrityPolicy.typedValue(
            in: payload.typedStorage,
            for: fieldType
        ) else {
            return nil
        }
        return value
    }

    private static func reference(
        _ value: MetaDetailFieldValue
    ) -> GraphMutationDetailValueReference {
        GraphMutationDetailValueReference(
            id: value.id,
            ownerAttributeID: value.attributeID,
            fieldID: value.fieldID
        )
    }

    private static func stableValueOrder(
        _ lhs: MetaDetailFieldValue,
        _ rhs: MetaDetailFieldValue
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func requireGraphID(
        _ graphID: UUID?
    ) throws -> UUID {
        guard let graphID else {
            throw DetailDataWriteError.missingGraphScope
        }
        return graphID
    }
}
