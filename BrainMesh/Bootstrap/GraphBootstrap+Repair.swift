//
//  GraphBootstrap+Repair.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphBootstrap {

    static func ensureAtLeastOneGraph(using modelContext: ModelContext) -> MetaGraph {
        // ältester Graph = "default"
        let descriptor = FetchDescriptor<MetaGraph>(sortBy: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
        if let graph = try? modelContext.fetch(descriptor).first {
            return graph
        }

        let graph = MetaGraph(name: "Default")
        modelContext.insert(graph)
        try? modelContext.save()
        return graph
    }

    static func migrateLegacyRecordsIfNeeded(defaultGraphID: UUID, using modelContext: ModelContext) {
        guard hasLegacyRecords(using: modelContext) else { return }

        var changed = false
        changed = migrateLegacyEntities(defaultGraphID: defaultGraphID, using: modelContext) || changed
        changed = migrateLegacyAttributes(defaultGraphID: defaultGraphID, using: modelContext) || changed
        changed = migrateLegacyLinks(defaultGraphID: defaultGraphID, using: modelContext) || changed

        saveIfChanged(changed, using: modelContext)
    }

    private static func migrateLegacyEntities(defaultGraphID: UUID, using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entity.graphID == nil
            })
            let entities = try modelContext.fetch(descriptor)
            for entity in entities {
                entity.graphID = defaultGraphID
            }
            return entities.isEmpty == false
        } catch {
            return false
        }
    }

    private static func migrateLegacyAttributes(defaultGraphID: UUID, using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == nil
            })
            let attributes = try modelContext.fetch(descriptor)
            for attribute in attributes {
                if let owner = attribute.owner, let ownerGraphID = owner.graphID {
                    attribute.graphID = ownerGraphID
                } else {
                    attribute.graphID = defaultGraphID
                }
            }
            return attributes.isEmpty == false
        } catch {
            return false
        }
    }

    private static func migrateLegacyLinks(defaultGraphID: UUID, using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { link in
                link.graphID == nil
            })
            let links = try modelContext.fetch(descriptor)
            for link in links {
                link.graphID = defaultGraphID
            }
            return links.isEmpty == false
        } catch {
            return false
        }
    }
}
