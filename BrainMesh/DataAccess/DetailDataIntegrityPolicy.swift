//
//  DetailDataIntegrityPolicy.swift
//  BrainMesh
//
//  Central value-only integrity and authority rules for detail schema and values.
//

import Foundation

nonisolated struct DetailFieldIntegritySnapshot: Hashable, Sendable {
    let id: UUID
    let graphID: UUID?
    let entityID: UUID
    let ownerID: UUID?
    let ownerGraphID: UUID?
    let type: DetailFieldType
}

nonisolated struct DetailAttributeIntegritySnapshot: Hashable, Sendable {
    let id: UUID
    let graphID: UUID?
    let ownerEntityID: UUID?
    let ownerGraphID: UUID?
}

nonisolated struct DetailTypedStorageSnapshot: Hashable, Sendable {
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let dateValue: Date?
    let boolValue: Bool?

    init(
        stringValue: String?,
        intValue: Int?,
        doubleValue: Double?,
        dateValue: Date?,
        boolValue: Bool?
    ) {
        self.stringValue = stringValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }
}

nonisolated struct DetailValueIntegritySnapshot: Hashable, Sendable {
    let id: UUID
    let graphID: UUID?
    let attributeID: UUID
    let fieldID: UUID
    let relationshipAttributeID: UUID?
    let relationshipGraphID: UUID?
    let relationshipEntityID: UUID?
    let relationshipEntityGraphID: UUID?
    let storage: DetailTypedStorageSnapshot
}

nonisolated struct DetailValueAuthorityKey: Hashable, Sendable {
    let graphID: UUID
    let attributeID: UUID
    let fieldID: UUID
}

nonisolated enum DetailTypedValue: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case date(Date)
    case boolean(Bool)
    case choice(String)
    case empty

    var isEmpty: Bool {
        self == .empty
    }
}

nonisolated enum DetailDataIntegrityViolation: String, Hashable, Sendable {
    case missingFieldOwner
    case missingFieldGraph
    case fieldGraphMismatch
    case fieldEntityMismatch
    case missingAttributeOwner
    case missingAttributeGraph
    case attributeGraphMismatch
    case missingValueAttribute
    case valueGraphMismatch
    case valueAttributeMismatch
    case valueFieldMismatch
    case valueEntityMismatch
    case invalidTypedStorage

    var isCrossGraph: Bool {
        switch self {
        case .fieldGraphMismatch,
             .attributeGraphMismatch,
             .valueGraphMismatch:
            return true
        default:
            return false
        }
    }
}

nonisolated enum DetailTypedStorageResolution: Hashable, Sendable {
    case valid(DetailTypedValue)
    case invalid
}

nonisolated enum DetailValueAuthorityResolution: Hashable, Sendable {
    case missing
    case authoritative(
        recordID: UUID,
        value: DetailTypedValue,
        safelyRemovableRecordIDs: [UUID]
    )
    case conflict(
        recordIDs: [UUID],
        safelyRemovableRecordIDs: [UUID]
    )
    case invalid(recordIDs: [UUID])

    var authoritativeRecordID: UUID? {
        guard case .authoritative(let recordID, _, _) = self else {
            return nil
        }
        return recordID
    }

    var authoritativeValue: DetailTypedValue? {
        guard case .authoritative(_, let value, _) = self else {
            return nil
        }
        return value
    }

    var hasConflict: Bool {
        switch self {
        case .conflict, .invalid:
            return true
        case .missing, .authoritative:
            return false
        }
    }
}

nonisolated enum DetailDataIntegrityPolicy {
    static func fieldViolations(
        _ field: DetailFieldIntegritySnapshot
    ) -> Set<DetailDataIntegrityViolation> {
        var violations = Set<DetailDataIntegrityViolation>()

        guard let ownerID = field.ownerID else {
            violations.insert(.missingFieldOwner)
            return violations
        }
        guard let ownerGraphID = field.ownerGraphID else {
            violations.insert(.missingFieldGraph)
            return violations
        }
        guard let graphID = field.graphID else {
            violations.insert(.missingFieldGraph)
            return violations
        }

        if graphID != ownerGraphID {
            violations.insert(.fieldGraphMismatch)
        }
        if field.entityID != ownerID {
            violations.insert(.fieldEntityMismatch)
        }
        return violations
    }

    static func attributeViolations(
        _ attribute: DetailAttributeIntegritySnapshot
    ) -> Set<DetailDataIntegrityViolation> {
        var violations = Set<DetailDataIntegrityViolation>()

        guard attribute.ownerEntityID != nil else {
            violations.insert(.missingAttributeOwner)
            return violations
        }
        guard let ownerGraphID = attribute.ownerGraphID else {
            violations.insert(.missingAttributeGraph)
            return violations
        }
        guard let graphID = attribute.graphID else {
            violations.insert(.missingAttributeGraph)
            return violations
        }

        if graphID != ownerGraphID {
            violations.insert(.attributeGraphMismatch)
        }
        return violations
    }

    static func associationViolations(
        field: DetailFieldIntegritySnapshot,
        attribute: DetailAttributeIntegritySnapshot
    ) -> Set<DetailDataIntegrityViolation> {
        var violations = fieldViolations(field)
        violations.formUnion(attributeViolations(attribute))

        guard let fieldGraphID = field.graphID,
              let attributeGraphID = attribute.graphID,
              let attributeEntityID = attribute.ownerEntityID else {
            return violations
        }

        if fieldGraphID != attributeGraphID {
            violations.insert(.fieldGraphMismatch)
        }
        if field.entityID != attributeEntityID {
            violations.insert(.valueEntityMismatch)
        }
        return violations
    }

    static func valueViolations(
        _ value: DetailValueIntegritySnapshot,
        field: DetailFieldIntegritySnapshot,
        attribute: DetailAttributeIntegritySnapshot
    ) -> Set<DetailDataIntegrityViolation> {
        var violations = associationViolations(
            field: field,
            attribute: attribute
        )

        guard let expectedGraphID = attribute.graphID else {
            return violations
        }
        guard let relationshipAttributeID = value.relationshipAttributeID else {
            violations.insert(.missingValueAttribute)
            return violations
        }

        if value.graphID != expectedGraphID
            || value.relationshipGraphID != expectedGraphID
            || value.relationshipEntityGraphID != expectedGraphID
        {
            violations.insert(.valueGraphMismatch)
        }
        if value.attributeID != attribute.id
            || relationshipAttributeID != attribute.id
        {
            violations.insert(.valueAttributeMismatch)
        }
        if value.fieldID != field.id {
            violations.insert(.valueFieldMismatch)
        }
        if value.relationshipEntityID != field.entityID {
            violations.insert(.valueEntityMismatch)
        }
        if typedValue(
            in: value.storage,
            for: field.type
        ) == .invalid {
            violations.insert(.invalidTypedStorage)
        }
        return violations
    }

    static func typedValue(
        in storage: DetailTypedStorageSnapshot,
        for fieldType: DetailFieldType
    ) -> DetailTypedStorageResolution {
        let filledSlotCount = [
            storage.stringValue != nil,
            storage.intValue != nil,
            storage.doubleValue != nil,
            storage.dateValue != nil,
            storage.boolValue != nil
        ]
        .filter { $0 }
        .count

        guard filledSlotCount <= 1 else {
            return .invalid
        }

        switch fieldType {
        case .singleLineText, .multiLineText:
            guard storage.intValue == nil,
                  storage.doubleValue == nil,
                  storage.dateValue == nil,
                  storage.boolValue == nil else {
                return .invalid
            }
            return normalizedString(storage.stringValue).map {
                .valid(.text($0))
            } ?? .valid(.empty)

        case .numberInt:
            guard storage.stringValue == nil,
                  storage.doubleValue == nil,
                  storage.dateValue == nil,
                  storage.boolValue == nil else {
                return .invalid
            }
            return storage.intValue.map {
                .valid(.integer($0))
            } ?? .valid(.empty)

        case .numberDouble:
            guard storage.stringValue == nil,
                  storage.intValue == nil,
                  storage.dateValue == nil,
                  storage.boolValue == nil else {
                return .invalid
            }
            guard let value = storage.doubleValue else {
                return .valid(.empty)
            }
            return value.isFinite ? .valid(.decimal(value)) : .invalid

        case .date:
            guard storage.stringValue == nil,
                  storage.intValue == nil,
                  storage.doubleValue == nil,
                  storage.boolValue == nil else {
                return .invalid
            }
            return storage.dateValue.map {
                .valid(.date($0))
            } ?? .valid(.empty)

        case .toggle:
            guard storage.stringValue == nil,
                  storage.intValue == nil,
                  storage.doubleValue == nil,
                  storage.dateValue == nil else {
                return .invalid
            }
            return storage.boolValue.map {
                .valid(.boolean($0))
            } ?? .valid(.empty)

        case .singleChoice:
            guard storage.intValue == nil,
                  storage.doubleValue == nil,
                  storage.dateValue == nil,
                  storage.boolValue == nil else {
                return .invalid
            }
            return normalizedString(storage.stringValue).map {
                .valid(.choice($0))
            } ?? .valid(.empty)
        }
    }

    static func resolveAuthority(
        field: DetailFieldIntegritySnapshot,
        attribute: DetailAttributeIntegritySnapshot,
        records: [DetailValueIntegritySnapshot]
    ) -> DetailValueAuthorityResolution {
        let orderedRecords = stableRecords(records)
        guard orderedRecords.isEmpty == false else {
            return .missing
        }
        guard associationViolations(
            field: field,
            attribute: attribute
        ).isEmpty else {
            return .invalid(recordIDs: orderedRecords.map(\.id))
        }

        var validRecords: [(record: DetailValueIntegritySnapshot, value: DetailTypedValue)] = []
        var invalidRecordIDs: [UUID] = []
        validRecords.reserveCapacity(orderedRecords.count)

        for record in orderedRecords {
            let violations = valueViolations(
                record,
                field: field,
                attribute: attribute
            )
            guard violations.isEmpty else {
                invalidRecordIDs.append(record.id)
                continue
            }
            guard case .valid(let typedValue) = typedValue(
                in: record.storage,
                for: field.type
            ) else {
                invalidRecordIDs.append(record.id)
                continue
            }
            validRecords.append((record, typedValue))
        }

        guard invalidRecordIDs.isEmpty else {
            return .invalid(
                recordIDs: stableIDs(
                    invalidRecordIDs + validRecords.map { $0.record.id }
                )
            )
        }
        guard validRecords.isEmpty == false else {
            return .invalid(recordIDs: orderedRecords.map(\.id))
        }

        let emptyRecordIDs = validRecords
            .filter { $0.value.isEmpty }
            .map { $0.record.id }
        let filledRecords = validRecords.filter { $0.value.isEmpty == false }

        guard filledRecords.isEmpty == false else {
            let keeper = validRecords[0]
            return .authoritative(
                recordID: keeper.record.id,
                value: .empty,
                safelyRemovableRecordIDs: stableIDs(
                    validRecords.dropFirst().map { $0.record.id }
                )
            )
        }

        let grouped = Dictionary(grouping: filledRecords) {
            equivalenceKey(for: $0.value)
        }
        guard grouped.count == 1 else {
            return .conflict(
                recordIDs: stableIDs(filledRecords.map { $0.record.id }),
                safelyRemovableRecordIDs: stableIDs(emptyRecordIDs)
            )
        }

        let keeper = filledRecords[0]
        let removable = validRecords
            .map { $0.record.id }
            .filter { $0 != keeper.record.id }
        return .authoritative(
            recordID: keeper.record.id,
            value: keeper.value,
            safelyRemovableRecordIDs: stableIDs(removable)
        )
    }

    static func key(
        for field: DetailFieldIntegritySnapshot,
        attribute: DetailAttributeIntegritySnapshot
    ) -> DetailValueAuthorityKey? {
        guard associationViolations(
            field: field,
            attribute: attribute
        ).isEmpty,
        let graphID = attribute.graphID else {
            return nil
        }
        return DetailValueAuthorityKey(
            graphID: graphID,
            attributeID: attribute.id,
            fieldID: field.id
        )
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func stableRecords(
        _ records: [DetailValueIntegritySnapshot]
    ) -> [DetailValueIntegritySnapshot] {
        var byID: [UUID: DetailValueIntegritySnapshot] = [:]
        for record in records {
            byID[record.id] = record
        }
        return byID.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func stableIDs(_ ids: [UUID]) -> [UUID] {
        Array(Set(ids)).sorted {
            $0.uuidString < $1.uuidString
        }
    }

    private static func equivalenceKey(
        for value: DetailTypedValue
    ) -> String {
        switch value {
        case .text(let text):
            return "text:\(normalizedComparisonString(text))"
        case .integer(let integer):
            return "integer:\(integer)"
        case .decimal(let decimal):
            return "decimal:\(decimal.bitPattern)"
        case .date(let date):
            return "date:\(date.timeIntervalSinceReferenceDate.bitPattern)"
        case .boolean(let boolean):
            return "boolean:\(boolean ? 1 : 0)"
        case .choice(let choice):
            return "choice:\(normalizedComparisonString(choice))"
        case .empty:
            return "empty"
        }
    }

    private static func normalizedComparisonString(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }
}

nonisolated enum DetailDataModelSnapshotMapper {
    static func field(
        _ field: MetaDetailFieldDefinition
    ) -> DetailFieldIntegritySnapshot {
        DetailFieldIntegritySnapshot(
            id: field.id,
            graphID: field.graphID,
            entityID: field.entityID,
            ownerID: field.owner?.id,
            ownerGraphID: field.owner?.graphID,
            type: field.type
        )
    }

    static func attribute(
        _ attribute: MetaAttribute
    ) -> DetailAttributeIntegritySnapshot {
        DetailAttributeIntegritySnapshot(
            id: attribute.id,
            graphID: attribute.graphID,
            ownerEntityID: attribute.owner?.id,
            ownerGraphID: attribute.owner?.graphID
        )
    }

    static func value(
        _ value: MetaDetailFieldValue
    ) -> DetailValueIntegritySnapshot {
        DetailValueIntegritySnapshot(
            id: value.id,
            graphID: value.graphID,
            attributeID: value.attributeID,
            fieldID: value.fieldID,
            relationshipAttributeID: value.attribute?.id,
            relationshipGraphID: value.attribute?.graphID,
            relationshipEntityID: value.attribute?.owner?.id,
            relationshipEntityGraphID: value.attribute?.owner?.graphID,
            storage: storage(value)
        )
    }

    static func storage(
        _ value: MetaDetailFieldValue
    ) -> DetailTypedStorageSnapshot {
        DetailTypedStorageSnapshot(
            stringValue: value.stringValue,
            intValue: value.intValue,
            doubleValue: value.doubleValue,
            dateValue: value.dateValue,
            boolValue: value.boolValue
        )
    }

    static func authority(
        field: MetaDetailFieldDefinition,
        attribute: MetaAttribute,
        records: [MetaDetailFieldValue]
    ) -> DetailValueAuthorityResolution {
        let fieldSnapshot = self.field(field)
        let attributeSnapshot = self.attribute(attribute)
        guard let key = DetailDataIntegrityPolicy.key(
            for: fieldSnapshot,
            attribute: attributeSnapshot
        ) else {
            return .invalid(recordIDs: records.map(\.id))
        }
        let scopedRecords = records
            .map { self.value($0) }
            .filter { record in
                record.graphID == key.graphID
                    && record.attributeID == key.attributeID
                    && record.fieldID == key.fieldID
            }
        return DetailDataIntegrityPolicy.resolveAuthority(
            field: fieldSnapshot,
            attribute: attributeSnapshot,
            records: scopedRecords
        )
    }
}
