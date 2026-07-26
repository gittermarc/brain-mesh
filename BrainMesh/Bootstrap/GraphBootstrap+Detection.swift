//
//  GraphBootstrap+Detection.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphBootstrap {

    /// Returns true if there are any legacy records still missing a `graphID`.
    /// Uses `fetchLimit = 1` to keep this check very cheap.
    static func hasLegacyRecords(using modelContext: ModelContext) -> Bool {
        hasRecords(matching: FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
            entity.graphID == nil
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
            attribute.graphID == nil
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { link in
            link.graphID == nil
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaDetailsTemplate>(predicate: #Predicate<MetaDetailsTemplate> { template in
            template.graphID == nil
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaDetailFieldDefinition>(predicate: #Predicate<MetaDetailFieldDefinition> { field in
            field.graphID == nil
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate<MetaDetailFieldValue> { value in
            value.graphID == nil
        }), using: modelContext)
    }

    /// Returns true if there are any records with non-empty notes but missing the stored `notesFolded` index.
    /// Uses `fetchLimit = 1` to keep this check very cheap.
    static func hasFoldedNotesBackfillNeeded(using modelContext: ModelContext) -> Bool {
        hasRecords(matching: FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
            entity.notes != "" && entity.notesFolded == ""
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
            attribute.notes != "" && attribute.notesFolded == ""
        }), using: modelContext)
        || hasRecords(matching: FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { link in
            link.note != nil && link.noteFolded == ""
        }), using: modelContext)
    }

    private static func hasRecords<Model: PersistentModel>(
        matching descriptor: FetchDescriptor<Model>,
        using modelContext: ModelContext
    ) -> Bool {
        do {
            var descriptor = descriptor
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).isEmpty == false
        } catch {
            return false
        }
    }
}
