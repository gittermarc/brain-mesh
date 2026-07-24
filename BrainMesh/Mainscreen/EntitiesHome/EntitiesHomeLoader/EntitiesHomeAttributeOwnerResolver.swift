//
//  EntitiesHomeAttributeOwnerResolver.swift
//  BrainMesh
//
//  Graph-scoped, value-only resolution of attribute owners for indexed
//  Entities Home matches.
//

import Foundation
import SwiftData

nonisolated protocol EntitiesHomeAttributeOwnerResolving: Sendable {
    func ownerEntityIDs(
        graphID: UUID,
        attributeIDs: [UUID]
    ) async throws -> [UUID: UUID]
}

actor EntitiesHomeAttributeOwnerResolver: EntitiesHomeAttributeOwnerResolving {
    static let shared = EntitiesHomeAttributeOwnerResolver()

    private var container: AnyModelContainer?

    func configure(container: AnyModelContainer) {
        self.container = container
    }

    func ownerEntityIDs(
        graphID: UUID,
        attributeIDs: [UUID]
    ) async throws -> [UUID: UUID] {
        try Task.checkCancellation()
        guard let container else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeAttributeOwnerResolver",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "EntitiesHomeAttributeOwnerResolver not configured"
                ]
            )
        }

        let uniqueAttributeIDs = Array(Set(attributeIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        guard uniqueAttributeIDs.isEmpty == false else { return [:] }

        let context = ModelContext(container.container)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { attribute in
                attribute.graphID == graphID
                    && uniqueAttributeIDs.contains(attribute.id)
            }
        )
        let attributes = try context.fetch(descriptor)
        try Task.checkCancellation()

        var ownerEntityIDsByAttributeID: [UUID: UUID] = [:]
        ownerEntityIDsByAttributeID.reserveCapacity(attributes.count)
        for (index, attribute) in attributes.enumerated() {
            if index.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard let owner = attribute.owner,
                  owner.graphID == graphID
            else {
                continue
            }
            ownerEntityIDsByAttributeID[attribute.id] = owner.id
        }
        return ownerEntityIDsByAttributeID
    }
}
