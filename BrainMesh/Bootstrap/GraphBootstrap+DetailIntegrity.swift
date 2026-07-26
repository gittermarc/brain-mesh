//
//  GraphBootstrap+DetailIntegrity.swift
//  BrainMesh
//
//  Owner-based detail scope migration and deterministic safe duplicate cleanup.
//

import Foundation
import SwiftData

extension GraphBootstrap {
    struct DetailFieldRepair {
        let field: MetaDetailFieldDefinition
        let graphID: UUID?
        let entityID: UUID?
    }

    struct DetailValueRepair {
        let value: MetaDetailFieldValue
        let graphID: UUID?
        let attributeID: UUID?
    }

    struct DetailIntegrityRepairPlan {
        let fieldRepairs: [DetailFieldRepair]
        let valueRepairs: [DetailValueRepair]
        let duplicateValuesToDelete: [MetaDetailFieldValue]
        let affectedGraphIDs: Set<UUID>
        let report: DetailDataIntegrityReport
    }

    static func makeDetailIntegrityRepairPlan(
        defaultGraphID: UUID,
        using modelContext: ModelContext
    ) throws -> DetailIntegrityRepairPlan {
        let definitions = try modelContext.fetch(
            FetchDescriptor<MetaDetailFieldDefinition>()
        )
        let values = try modelContext.fetch(
            FetchDescriptor<MetaDetailFieldValue>()
        )
        let knownGraphIDs = Set(
            try modelContext.fetch(FetchDescriptor<MetaGraph>()).map(\.id)
        )

        var report = DetailDataIntegrityReport()
        var fieldRepairs: [DetailFieldRepair] = []
        var valueRepairs: [DetailValueRepair] = []
        var affectedGraphIDs = Set<UUID>()
        var validFieldsByID: [UUID: [DetailFieldIntegritySnapshot]] = [:]

        for field in definitions.sorted(by: stableFieldOrder) {
            guard let owner = field.owner else {
                report.orphanedOrAmbiguousRecords += 1
                insertKnownGraphIDs(
                    [field.graphID],
                    into: &affectedGraphIDs
                )
                continue
            }
            let ownerGraphID = projectedEntityGraphID(
                owner,
                defaultGraphID: defaultGraphID
            )
            guard let ownerGraphID else {
                report.orphanedOrAmbiguousRecords += 1
                insertKnownGraphIDs(
                    [field.graphID],
                    into: &affectedGraphIDs
                )
                continue
            }
            if let currentGraphID = field.graphID,
               currentGraphID != ownerGraphID
            {
                report.rejectedCrossGraphRecords += 1
                insertKnownGraphIDs(
                    [currentGraphID, ownerGraphID],
                    into: &affectedGraphIDs
                )
                continue
            }

            let needsGraphRepair = field.graphID == nil
            let needsEntityRepair = field.entityID != owner.id
            if needsGraphRepair || needsEntityRepair {
                fieldRepairs.append(
                    DetailFieldRepair(
                        field: field,
                        graphID: needsGraphRepair ? ownerGraphID : nil,
                        entityID: needsEntityRepair ? owner.id : nil
                    )
                )
                affectedGraphIDs.insert(ownerGraphID)
                if needsGraphRepair {
                    report.migratedFieldDefinitions += 1
                }
                if needsEntityRepair {
                    report.repairedScalarOwnerIDs += 1
                }
            }

            let snapshot = DetailFieldIntegritySnapshot(
                id: field.id,
                graphID: ownerGraphID,
                entityID: owner.id,
                ownerID: owner.id,
                ownerGraphID: ownerGraphID,
                type: field.type
            )
            guard DetailDataIntegrityPolicy.fieldViolations(snapshot).isEmpty else {
                report.orphanedOrAmbiguousRecords += 1
                affectedGraphIDs.insert(ownerGraphID)
                continue
            }
            validFieldsByID[field.id, default: []].append(snapshot)
        }

        var validGroups: [DetailValueAuthorityKey: [DetailValueIntegritySnapshot]] = [:]
        var modelsByID: [UUID: MetaDetailFieldValue] = [:]
        var fieldByKey: [DetailValueAuthorityKey: DetailFieldIntegritySnapshot] = [:]
        var attributeByKey: [DetailValueAuthorityKey: DetailAttributeIntegritySnapshot] = [:]

        for value in values.sorted(by: stableValueOrder) {
            guard let attribute = value.attribute,
                  let owner = attribute.owner else {
                report.orphanedOrAmbiguousRecords += 1
                insertKnownGraphIDs(
                    [value.graphID, value.attribute?.graphID],
                    into: &affectedGraphIDs
                )
                continue
            }
            guard let ownerGraphID = projectedEntityGraphID(
                owner,
                defaultGraphID: defaultGraphID
            ) else {
                report.orphanedOrAmbiguousRecords += 1
                insertKnownGraphIDs(
                    [value.graphID, attribute.graphID],
                    into: &affectedGraphIDs
                )
                continue
            }
            if let attributeGraphID = attribute.graphID,
               attributeGraphID != ownerGraphID
            {
                report.rejectedCrossGraphRecords += 1
                insertKnownGraphIDs(
                    [value.graphID, attributeGraphID, ownerGraphID],
                    into: &affectedGraphIDs
                )
                continue
            }
            let projectedAttributeGraphID = attribute.graphID ?? ownerGraphID
            if let valueGraphID = value.graphID,
               valueGraphID != projectedAttributeGraphID
            {
                report.rejectedCrossGraphRecords += 1
                insertKnownGraphIDs(
                    [valueGraphID, projectedAttributeGraphID],
                    into: &affectedGraphIDs
                )
                continue
            }

            let matchingFields = (validFieldsByID[value.fieldID] ?? []).filter {
                $0.graphID == projectedAttributeGraphID
                    && $0.entityID == owner.id
            }
            guard matchingFields.count == 1,
                  let field = matchingFields.first else {
                report.orphanedOrAmbiguousRecords += 1
                affectedGraphIDs.insert(projectedAttributeGraphID)
                continue
            }

            let needsGraphRepair = value.graphID == nil
            let needsAttributeRepair = value.attributeID != attribute.id
            if needsGraphRepair || needsAttributeRepair {
                valueRepairs.append(
                    DetailValueRepair(
                        value: value,
                        graphID: needsGraphRepair ? projectedAttributeGraphID : nil,
                        attributeID: needsAttributeRepair ? attribute.id : nil
                    )
                )
                affectedGraphIDs.insert(projectedAttributeGraphID)
                if needsGraphRepair {
                    report.migratedDetailValues += 1
                }
                if needsAttributeRepair {
                    report.repairedScalarOwnerIDs += 1
                }
            }

            let attributeSnapshot = DetailAttributeIntegritySnapshot(
                id: attribute.id,
                graphID: projectedAttributeGraphID,
                ownerEntityID: owner.id,
                ownerGraphID: ownerGraphID
            )
            let snapshot = DetailValueIntegritySnapshot(
                id: value.id,
                graphID: projectedAttributeGraphID,
                attributeID: attribute.id,
                fieldID: value.fieldID,
                relationshipAttributeID: attribute.id,
                relationshipGraphID: projectedAttributeGraphID,
                relationshipEntityID: owner.id,
                relationshipEntityGraphID: ownerGraphID,
                storage: DetailDataModelSnapshotMapper.storage(value)
            )
            guard let key = DetailDataIntegrityPolicy.key(
                for: field,
                attribute: attributeSnapshot
            ) else {
                report.orphanedOrAmbiguousRecords += 1
                continue
            }

            validGroups[key, default: []].append(snapshot)
            modelsByID[value.id] = value
            fieldByKey[key] = field
            attributeByKey[key] = attributeSnapshot
        }

        var duplicateIDsToDelete = Set<UUID>()
        for key in validGroups.keys.sorted(by: stableKeyOrder) {
            guard let field = fieldByKey[key],
                  let attribute = attributeByKey[key] else {
                continue
            }
            let resolution = DetailDataIntegrityPolicy.resolveAuthority(
                field: field,
                attribute: attribute,
                records: validGroups[key] ?? []
            )
            switch resolution {
            case .missing:
                break
            case .authoritative(_, _, let safelyRemovableRecordIDs):
                duplicateIDsToDelete.formUnion(safelyRemovableRecordIDs)
            case .conflict(_, let safelyRemovableRecordIDs):
                report.conflictingDuplicateGroups += 1
                affectedGraphIDs.insert(key.graphID)
                duplicateIDsToDelete.formUnion(safelyRemovableRecordIDs)
            case .invalid(let recordIDs):
                report.orphanedOrAmbiguousRecords += recordIDs.count
                affectedGraphIDs.insert(key.graphID)
            }
        }

        let duplicatesToDelete = duplicateIDsToDelete
            .compactMap { modelsByID[$0] }
            .sorted(by: stableValueOrder)
        report.safelyRemovedDuplicates = duplicatesToDelete.count
        for value in duplicatesToDelete {
            if let graphID = value.graphID ?? value.attribute?.graphID {
                affectedGraphIDs.insert(graphID)
            }
        }

        return DetailIntegrityRepairPlan(
            fieldRepairs: fieldRepairs,
            valueRepairs: valueRepairs,
            duplicateValuesToDelete: duplicatesToDelete,
            affectedGraphIDs: affectedGraphIDs.intersection(knownGraphIDs),
            report: report
        )
    }

    static func applyDetailIntegrityRepairPlan(
        _ plan: DetailIntegrityRepairPlan,
        using modelContext: ModelContext
    ) {
        for repair in plan.fieldRepairs {
            if let graphID = repair.graphID {
                repair.field.graphID = graphID
            }
            if let entityID = repair.entityID {
                repair.field.entityID = entityID
            }
        }
        for repair in plan.valueRepairs {
            if let graphID = repair.graphID {
                repair.value.graphID = graphID
            }
            if let attributeID = repair.attributeID {
                repair.value.attributeID = attributeID
            }
        }
        for value in plan.duplicateValuesToDelete {
            value.attribute?.detailValues?.removeAll { $0.id == value.id }
            modelContext.delete(value)
        }
    }

    private static func projectedEntityGraphID(
        _ entity: MetaEntity,
        defaultGraphID: UUID
    ) -> UUID? {
        entity.graphID ?? defaultGraphID
    }

    private static func stableFieldOrder(
        _ lhs: MetaDetailFieldDefinition,
        _ rhs: MetaDetailFieldDefinition
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func stableValueOrder(
        _ lhs: MetaDetailFieldValue,
        _ rhs: MetaDetailFieldValue
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func stableKeyOrder(
        _ lhs: DetailValueAuthorityKey,
        _ rhs: DetailValueAuthorityKey
    ) -> Bool {
        if lhs.graphID != rhs.graphID {
            return lhs.graphID.uuidString < rhs.graphID.uuidString
        }
        if lhs.attributeID != rhs.attributeID {
            return lhs.attributeID.uuidString < rhs.attributeID.uuidString
        }
        return lhs.fieldID.uuidString < rhs.fieldID.uuidString
    }

    private static func insertKnownGraphIDs(
        _ graphIDs: [UUID?],
        into affectedGraphIDs: inout Set<UUID>
    ) {
        for graphID in graphIDs {
            if let graphID {
                affectedGraphIDs.insert(graphID)
            }
        }
    }
}
