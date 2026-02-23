//
//  DetailsSchemaValidation.swift
//  BrainMesh
//
//  NOTE:
//  Historically this file was called "Validation", but it only contains pinning rules.
//  The public API is now DetailsSchemaPinning. A thin deprecated wrapper remains
//  for any older call sites.
//

import Foundation

enum DetailsSchemaPinning {
    static let maxPinnedFields: Int = 3

    static func pinnedCount(in entity: MetaEntity) -> Int {
        entity.detailFieldsList.filter { $0.isPinned }.count
    }

    static func canPinAnotherField(in entity: MetaEntity) -> Bool {
        pinnedCount(in: entity) < maxPinnedFields
    }

    /// Returns `false` only when a new pin would exceed the max.
    /// - Parameters:
    ///   - from: the previous pinned state of the edited field (or `false` for a new field)
    ///   - to: the desired pinned state
    static func allowsPinChange(in entity: MetaEntity, from wasPinned: Bool, to wantsPinned: Bool) -> Bool {
        if wantsPinned == false { return true }
        if wasPinned == true { return true }
        return canPinAnotherField(in: entity)
    }

    static func enforcePinnedLimitIfNeeded(on entity: MetaEntity) {
        let pinned = entity.detailFieldsList
            .filter { $0.isPinned }
            .sorted(by: { $0.sortIndex < $1.sortIndex })

        if pinned.count <= maxPinnedFields { return }

        for field in pinned.dropFirst(maxPinnedFields) {
            field.isPinned = false
        }
    }
}

@available(*, deprecated, message: "Use DetailsSchemaPinning")
enum DetailsSchemaValidation {
    static let maxPinnedFields: Int = DetailsSchemaPinning.maxPinnedFields

    static func canPinAnotherField(in entity: MetaEntity) -> Bool {
        DetailsSchemaPinning.canPinAnotherField(in: entity)
    }

    static func enforcePinnedLimitIfNeeded(on entity: MetaEntity) {
        DetailsSchemaPinning.enforcePinnedLimitIfNeeded(on: entity)
    }
}
