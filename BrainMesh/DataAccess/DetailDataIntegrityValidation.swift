//
//  DetailDataIntegrityValidation.swift
//  BrainMesh
//
//  SwiftData-facing validation and privacy-neutral detail-integrity diagnostics.
//

import Foundation

#if canImport(os)
import os
#endif

nonisolated enum DetailDataWriteError: LocalizedError, Equatable, Sendable {
    case missingGraphScope
    case invalidFieldDefinition
    case invalidAttributeOwner
    case mismatchedEntity
    case crossGraphAssignment
    case invalidTypedValue

    var errorDescription: String? {
        switch self {
        case .missingGraphScope:
            return "Für dieses Detail ist kein Graph zugeordnet."
        case .invalidFieldDefinition:
            return "Das Detailfeld ist nicht eindeutig seiner Entität zugeordnet."
        case .invalidAttributeOwner:
            return "Das Attribut ist nicht eindeutig seiner Entität zugeordnet."
        case .mismatchedEntity:
            return "Das Detailfeld gehört nicht zur Entität dieses Attributes."
        case .crossGraphAssignment:
            return "Detailfeld und Attribut gehören nicht zum selben Graphen."
        case .invalidTypedValue:
            return "Der Detailwert besitzt keine gültige typisierte Speicherung."
        }
    }
}

nonisolated struct DetailDataIntegrityReport: Equatable, Sendable {
    var migratedFieldDefinitions: Int = 0
    var migratedDetailValues: Int = 0
    var repairedScalarOwnerIDs: Int = 0
    var safelyRemovedDuplicates: Int = 0
    var conflictingDuplicateGroups: Int = 0
    var rejectedCrossGraphRecords: Int = 0
    var orphanedOrAmbiguousRecords: Int = 0

    var hasMutations: Bool {
        migratedFieldDefinitions > 0
            || migratedDetailValues > 0
            || repairedScalarOwnerIDs > 0
            || safelyRemovedDuplicates > 0
    }
}

nonisolated enum DetailDataWriteValidator {
    static func validate(
        field: MetaDetailFieldDefinition,
        attribute: MetaAttribute
    ) throws -> UUID {
        let fieldSnapshot = DetailDataModelSnapshotMapper.field(field)
        let attributeSnapshot = DetailDataModelSnapshotMapper.attribute(attribute)
        let violations = DetailDataIntegrityPolicy.associationViolations(
            field: fieldSnapshot,
            attribute: attributeSnapshot
        )
        guard violations.isEmpty else {
            let error = publicError(for: violations)
            DetailDataIntegrityObservability.logRejectedWrite(error)
            throw error
        }
        guard let graphID = attributeSnapshot.graphID else {
            DetailDataIntegrityObservability.logRejectedWrite(.missingGraphScope)
            throw DetailDataWriteError.missingGraphScope
        }
        return graphID
    }

    static func validate(
        field: MetaDetailFieldDefinition,
        owner: MetaEntity
    ) throws -> UUID {
        let snapshot = DetailDataModelSnapshotMapper.field(field)
        let violations = DetailDataIntegrityPolicy.fieldViolations(snapshot)
        guard violations.isEmpty else {
            let error = publicError(for: violations)
            DetailDataIntegrityObservability.logRejectedWrite(error)
            throw error
        }
        guard snapshot.ownerGraphID == owner.graphID else {
            DetailDataIntegrityObservability.logRejectedWrite(
                .crossGraphAssignment
            )
            throw DetailDataWriteError.crossGraphAssignment
        }
        guard snapshot.ownerID == owner.id else {
            DetailDataIntegrityObservability.logRejectedWrite(
                .mismatchedEntity
            )
            throw DetailDataWriteError.mismatchedEntity
        }
        guard let graphID = owner.graphID else {
            DetailDataIntegrityObservability.logRejectedWrite(.missingGraphScope)
            throw DetailDataWriteError.missingGraphScope
        }
        return graphID
    }

    static func validateNewFieldOwner(
        owner: MetaEntity
    ) throws -> UUID {
        guard let graphID = owner.graphID else {
            DetailDataIntegrityObservability.logRejectedWrite(.missingGraphScope)
            throw DetailDataWriteError.missingGraphScope
        }
        return graphID
    }

    static func validate(
        storage: DetailTypedStorageSnapshot,
        fieldType: DetailFieldType
    ) throws {
        guard case .valid = DetailDataIntegrityPolicy.typedValue(
            in: storage,
            for: fieldType
        ) else {
            DetailDataIntegrityObservability.logRejectedWrite(.invalidTypedValue)
            throw DetailDataWriteError.invalidTypedValue
        }
    }

    static func validateProposedValue(
        storage: DetailTypedStorageSnapshot,
        field: MetaDetailFieldDefinition,
        attribute: MetaAttribute
    ) throws -> UUID {
        let graphID = try validate(field: field, attribute: attribute)
        let fieldSnapshot = DetailDataModelSnapshotMapper.field(field)
        let attributeSnapshot = DetailDataModelSnapshotMapper.attribute(attribute)
        let proposedValue = DetailValueIntegritySnapshot(
            id: attribute.id,
            graphID: graphID,
            attributeID: attribute.id,
            fieldID: field.id,
            relationshipAttributeID: attribute.id,
            relationshipGraphID: attribute.graphID,
            relationshipEntityID: attribute.owner?.id,
            relationshipEntityGraphID: attribute.owner?.graphID,
            storage: storage
        )
        let violations = DetailDataIntegrityPolicy.valueViolations(
            proposedValue,
            field: fieldSnapshot,
            attribute: attributeSnapshot
        )
        guard violations.isEmpty else {
            let error = publicError(for: violations)
            DetailDataIntegrityObservability.logRejectedWrite(error)
            throw error
        }
        return graphID
    }

    private static func publicError(
        for violations: Set<DetailDataIntegrityViolation>
    ) -> DetailDataWriteError {
        if violations.contains(where: { $0.isCrossGraph }) {
            return .crossGraphAssignment
        }
        if violations.contains(.valueEntityMismatch)
            || violations.contains(.fieldEntityMismatch)
        {
            return .mismatchedEntity
        }
        if violations.contains(.missingAttributeOwner)
            || violations.contains(.missingAttributeGraph)
        {
            return .invalidAttributeOwner
        }
        if violations.contains(.invalidTypedStorage) {
            return .invalidTypedValue
        }
        if violations.contains(.missingFieldGraph) {
            return .missingGraphScope
        }
        return .invalidFieldDefinition
    }
}

nonisolated enum DetailDataIntegrityObservability {
    static func logBootstrap(_ report: DetailDataIntegrityReport) {
        #if canImport(os)
        BMLog.detailIntegrity.info(
            """
            detail_integrity_bootstrap migrated_fields=\(report.migratedFieldDefinitions, privacy: .public) \
            migrated_values=\(report.migratedDetailValues, privacy: .public) \
            repaired_owner_ids=\(report.repairedScalarOwnerIDs, privacy: .public) \
            removed_duplicates=\(report.safelyRemovedDuplicates, privacy: .public) \
            conflicting_groups=\(report.conflictingDuplicateGroups, privacy: .public) \
            rejected_cross_graph=\(report.rejectedCrossGraphRecords, privacy: .public) \
            orphaned_or_ambiguous=\(report.orphanedOrAmbiguousRecords, privacy: .public)
            """
        )
        #endif
    }

    static func logRejectedWrite(_ error: DetailDataWriteError) {
        #if canImport(os)
        BMLog.detailIntegrity.notice(
            "detail_integrity_write_rejected reason=\(String(describing: error), privacy: .public)"
        )
        #endif
    }
}
