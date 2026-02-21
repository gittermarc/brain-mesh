//
//  EntityAttributesAllListModel+Lookups.swift
//  BrainMesh
//
//  P0.1: SwiftData fetch helpers extracted from EntityAttributesAllListModel.swift
//

import Foundation
import SwiftData

extension EntityAttributesAllListModel {
    func fetchAttributeOwnersWithMedia(
        context: ModelContext,
        attributeIDs: Set<UUID>,
        graphID: UUID?
    ) -> Set<UUID> {
        guard !attributeIDs.isEmpty else { return [] }

        let ownerKindRaw = NodeKind.attribute.rawValue

        let attachments: [MetaAttachment]
        if let graphID {
            let gid: UUID? = graphID
            let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == ownerKindRaw && a.graphID == gid
            })
            attachments = (try? context.fetch(fd)) ?? []
        } else {
            let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == ownerKindRaw
            })
            attachments = (try? context.fetch(fd)) ?? []
        }

        var owners = Set<UUID>()
        owners.reserveCapacity(min(attachments.count, 256))
        for a in attachments {
            if attributeIDs.contains(a.ownerID) {
                owners.insert(a.ownerID)
            }
        }
        return owners
    }

    func fetchPinnedValuesLookup(
        context: ModelContext,
        pinnedFields: [MetaDetailFieldDefinition]
    ) -> [UUID: [UUID: MetaDetailFieldValue]] {
        guard !pinnedFields.isEmpty else { return [:] }

        var result: [UUID: [UUID: MetaDetailFieldValue]] = [:]
        result.reserveCapacity(256)

        for field in pinnedFields {
            // SwiftData #Predicate can't reliably compare against a captured model object's property
            // (e.g. `field.id`). Capture the UUID as a constant instead.
            let fieldID: UUID = field.id
            let fd = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate<MetaDetailFieldValue> { v in
                v.fieldID == fieldID
            })
            let values = (try? context.fetch(fd)) ?? []

            for v in values {
                result[v.attributeID, default: [:]][field.id] = v
            }
        }

        return result
    }
}
