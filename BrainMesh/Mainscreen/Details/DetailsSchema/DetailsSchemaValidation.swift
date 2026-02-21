//
//  DetailsSchemaValidation.swift
//  BrainMesh
//

import Foundation

enum DetailsSchemaValidation {
    static let maxPinnedFields: Int = 3

    static func canPinAnotherField(in entity: MetaEntity) -> Bool {
        let pinnedCount = entity.detailFieldsList.filter { $0.isPinned }.count
        return pinnedCount < maxPinnedFields
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
