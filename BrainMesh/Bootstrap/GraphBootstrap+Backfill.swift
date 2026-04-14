//
//  GraphBootstrap+Backfill.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphBootstrap {

    static func backfillFoldedNotesIfNeeded(using modelContext: ModelContext) {
        guard hasFoldedNotesBackfillNeeded(using: modelContext) else { return }

        var changed = false
        changed = backfillEntityFoldedNotes(using: modelContext) || changed
        changed = backfillAttributeFoldedNotes(using: modelContext) || changed
        changed = backfillLinkFoldedNotes(using: modelContext) || changed

        saveIfChanged(changed, using: modelContext)
    }

    private static func backfillEntityFoldedNotes(using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entity.notes != "" && entity.notesFolded == ""
            })
            let entities = try modelContext.fetch(descriptor)
            for entity in entities {
                entity.notesFolded = BMSearch.fold(entity.notes)
            }
            return entities.isEmpty == false
        } catch {
            return false
        }
    }

    private static func backfillAttributeFoldedNotes(using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attribute.notes != "" && attribute.notesFolded == ""
            })
            let attributes = try modelContext.fetch(descriptor)
            for attribute in attributes {
                attribute.notesFolded = BMSearch.fold(attribute.notes)
            }
            return attributes.isEmpty == false
        } catch {
            return false
        }
    }

    private static func backfillLinkFoldedNotes(using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { link in
                link.note != nil && link.noteFolded == ""
            })
            let links = try modelContext.fetch(descriptor)
            for link in links {
                let note = link.note ?? ""
                if note.isEmpty {
                    // Normalize "empty string" to nil to avoid re-triggering the backfill forever.
                    link.note = nil
                } else {
                    link.noteFolded = BMSearch.fold(note)
                }
            }
            return links.isEmpty == false
        } catch {
            return false
        }
    }
}
