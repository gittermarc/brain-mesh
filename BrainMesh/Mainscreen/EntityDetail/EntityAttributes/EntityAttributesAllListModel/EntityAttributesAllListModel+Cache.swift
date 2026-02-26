//
//  EntityAttributesAllListModel+Cache.swift
//  BrainMesh
//
//  P0.1: Cache state extracted from EntityAttributesAllListModel.swift
//

import Foundation
import SwiftData

extension EntityAttributesAllListModel {
    struct Cache {
        var entityID: UUID? = nil
        var graphID: UUID? = nil
        var attributeIDs: [UUID] = []

        var pinnedFieldIDs: [UUID] = []
        var pinnedValuesByAttribute: [UUID: [UUID: MetaDetailFieldValue]] = [:]

        var ownersWithMedia: Set<UUID> = []
        var rowsByID: [UUID: Row] = [:]

        var lastShowPinnedDetails: Bool = false
        var lastIncludeNotesPreview: Bool = false
        var lastGrouping: AttributesAllGrouping = .none
    }
}
