//
//  GraphReadRepository+NodeProfile.swift
//  BrainMesh
//
//  Authoritative, independently bounded node-profile reads.
//

import Foundation
import SwiftData

private nonisolated struct GraphNodeProfileIdentitySnapshot:
    Sendable
{
    let nodeKey: NodeRefKey
    let visibleName: String
    let displayName: String
    let ownerEntity: GraphNodeProfileOwner?
    let notes: String
    let attribute: GraphAttributeDTO?
}

extension GraphReadRepository: GraphNodeProfileReading {
    func nodeProfile(
        _ nodeKey: NodeRefKey,
        in scope: GraphScope,
        limits: GraphNodeProfileLimits
    ) async throws -> GraphNodeProfile? {
        let policy =
            GraphChatIntentLimitPolicy.default
        guard
            limits.detailValueLimit
                <= policy
                    .nodeProfileDetailValueCount,
            limits.incomingConnectionLimit
                <= policy
                    .nodeProfileIncomingConnectionCount,
            limits.outgoingConnectionLimit
                <= policy
                    .nodeProfileOutgoingConnectionCount,
            limits.attachmentLimit
                <= policy
                    .nodeProfileAttachmentCount
        else {
            throw GraphNodeProfileReadError
                .invalidLimits
        }
        let context = try await makeReadContext()
        try checkCancellation()

        guard
            let identity = try profileIdentity(
                for: nodeKey,
                in: scope,
                context: context
            )
        else {
            return nil
        }
        try checkCancellation()

        let allDetailValues = try profileDetailValues(
            for: identity,
            in: scope,
            context: context
        )
        try checkCancellation()

        let outgoingModels = try context.fetch(
            GraphScopedFetches.outgoingLinks(
                from: nodeKey,
                in: scope
            )
        )
        try checkCancellation()
        let incomingModels = try context.fetch(
            GraphScopedFetches.incomingLinks(
                to: nodeKey,
                in: scope
            )
        )
        try checkCancellation()

        let endpointMap = try profileEndpointMap(
            for: outgoingModels + incomingModels,
            center: identity,
            in: scope,
            context: context
        )
        try checkCancellation()

        let allOutgoingConnections = try profileConnections(
            outgoingModels,
            direction: .outgoing,
            center: nodeKey,
            endpoints: endpointMap,
            scope: scope
        )
        try checkCancellation()
        let allIncomingConnections = try profileConnections(
            incomingModels,
            direction: .incoming,
            center: nodeKey,
            endpoints: endpointMap,
            scope: scope
        )
        try checkCancellation()

        let attachmentModels = try context.fetch(
            GraphScopedFetches.attachments(
                owner: nodeKey,
                in: scope
            )
        )
        try checkCancellation()
        let allAttachments = try uniqueAttachments(
            fetchAttachmentMetadata(
                in: scope,
                context: context,
                models: attachmentModels
            ).filter {
                $0.ownerNodeKey == nodeKey
                    && $0.contentKind != nil
            }
        )
        try checkCancellation()

        let detailValues = Array(
            allDetailValues.prefix(
                limits.detailValueLimit
            )
        )
        let incomingConnections = Array(
            allIncomingConnections.prefix(
                limits.incomingConnectionLimit
            )
        )
        let outgoingConnections = Array(
            allOutgoingConnections.prefix(
                limits.outgoingConnectionLimit
            )
        )
        let attachments = Array(
            allAttachments.prefix(
                limits.attachmentLimit
            )
        )
        let directLinkCount = Set(
            allIncomingConnections.map(\.linkID)
                + allOutgoingConnections.map(\.linkID)
        ).count
        try checkCancellation()

        return GraphNodeProfile(
            scope: scope,
            nodeKey: nodeKey,
            visibleName: identity.visibleName,
            displayName: identity.displayName,
            ownerEntity: identity.ownerEntity,
            notes: identity.notes,
            detailValues: detailValues,
            incomingConnections: incomingConnections,
            outgoingConnections: outgoingConnections,
            attachments: attachments,
            directLinkCount: directLinkCount,
            detailValueWindow: GraphNodeProfileResultWindow(
                totalCount: allDetailValues.count,
                returnedCount: detailValues.count,
                limit: limits.detailValueLimit
            ),
            incomingConnectionWindow:
                GraphNodeProfileResultWindow(
                    totalCount:
                        allIncomingConnections.count,
                    returnedCount:
                        incomingConnections.count,
                    limit:
                        limits.incomingConnectionLimit
                ),
            outgoingConnectionWindow:
                GraphNodeProfileResultWindow(
                    totalCount:
                        allOutgoingConnections.count,
                    returnedCount:
                        outgoingConnections.count,
                    limit:
                        limits.outgoingConnectionLimit
                ),
            attachmentWindow:
                GraphNodeProfileResultWindow(
                    totalCount: allAttachments.count,
                    returnedCount: attachments.count,
                    limit: limits.attachmentLimit
                )
        )
    }

    private func profileIdentity(
        for nodeKey: NodeRefKey,
        in scope: GraphScope,
        context: ModelContext
    ) throws -> GraphNodeProfileIdentitySnapshot? {
        switch nodeKey.kind {
        case .entity:
            guard
                let model = try context.fetch(
                    GraphScopedFetches.entity(
                        id: nodeKey.id,
                        in: scope
                    )
                ).first
            else {
                return nil
            }
            let entity = GraphReadDTOMapper.entity(
                model,
                scope: scope
            )
            return GraphNodeProfileIdentitySnapshot(
                nodeKey: entity.nodeKey,
                visibleName: entity.name,
                displayName: entity.name,
                ownerEntity: nil,
                notes: entity.notes,
                attribute: nil
            )

        case .attribute:
            guard
                let model = try context.fetch(
                    GraphScopedFetches.attribute(
                        id: nodeKey.id,
                        in: scope
                    )
                ).first
            else {
                return nil
            }
            let attribute = GraphReadDTOMapper.attribute(
                model,
                scope: scope
            )
            let owner: GraphNodeProfileOwner?
            if
                let ownerEntityID =
                    attribute.ownerEntityID,
                let ownerLabel =
                    attribute.ownerLabel
            {
                owner = GraphNodeProfileOwner(
                    entityID: ownerEntityID,
                    visibleName: ownerLabel
                )
            } else {
                owner = nil
            }
            return GraphNodeProfileIdentitySnapshot(
                nodeKey: attribute.nodeKey,
                visibleName: attribute.name,
                displayName: attribute.displayLabel,
                ownerEntity: owner,
                notes: attribute.notes,
                attribute: attribute
            )
        }
    }

    private func profileDetailValues(
        for identity: GraphNodeProfileIdentitySnapshot,
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [GraphNodeProfileDetailValue] {
        guard
            let attribute = identity.attribute,
            let ownerEntityID =
                attribute.ownerEntityID
        else {
            return []
        }
        try checkCancellation()

        let definitionModels = try context.fetch(
            GraphScopedFetches.detailFieldDefinitions(
                entityID: ownerEntityID,
                in: scope
            )
        )
        let definitions = try mapDetailFieldDefinitions(
            definitionModels,
            scope: scope
        )
        try checkCancellation()

        let valueModels = try context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attribute.id,
                in: scope
            )
        )
        let values = try fetchDetailValues(
            in: scope,
            context: context,
            models: valueModels,
            prefetchedDefinitions: definitions,
            prefetchedAttributes: [attribute]
        )
        try checkCancellation()

        let definitionsByID =
            Self.detailFieldMap(definitions)
        var result: [GraphNodeProfileDetailValue] = []
        result.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            try checkCancellation(at: index)
            guard
                let field =
                    definitionsByID[value.fieldID],
                value.fieldType == field.type
            else {
                continue
            }
            result.append(
                GraphNodeProfileDetailValue(
                    valueID: value.id,
                    fieldID: field.id,
                    fieldName: field.name,
                    fieldType: field.type,
                    unit: field.unit,
                    value: value.value
                )
            )
        }
        try checkCancellation()
        return result.sorted { lhs, rhs in
            guard
                let lhsField =
                    definitionsByID[lhs.fieldID],
                let rhsField =
                    definitionsByID[rhs.fieldID]
            else {
                return lhs.fieldID.uuidString < rhs.fieldID.uuidString
            }
            if lhsField.sortIndex
                != rhsField.sortIndex {
                return lhsField.sortIndex < rhsField.sortIndex
            }
            let lhsName = BMSearch.fold(
                lhsField.name
            )
            let rhsName = BMSearch.fold(
                rhsField.name
            )
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            if lhs.fieldID != rhs.fieldID {
                return lhs.fieldID.uuidString < rhs.fieldID.uuidString
            }
            return lhs.valueID.uuidString < rhs.valueID.uuidString
        }
    }

    private func profileEndpointMap(
        for links: [MetaLink],
        center: GraphNodeProfileIdentitySnapshot,
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [NodeRefKey: GraphNodeProfileEndpoint] {
        var nodeKeys = Set<NodeRefKey>()
        nodeKeys.insert(center.nodeKey)
        for (index, link) in links.enumerated() {
            try checkCancellation(at: index)
            if let source = GraphReadDTOMapper
                .link(link, scope: scope)
                .sourceNodeKey {
                nodeKeys.insert(source)
            }
            if let target = GraphReadDTOMapper
                .link(link, scope: scope)
                .targetNodeKey {
                nodeKeys.insert(target)
            }
        }
        try checkCancellation()

        let entityIDs = nodeKeys.compactMap {
            $0.kind == .entity ? $0.id : nil
        }
        let attributeIDs = nodeKeys.compactMap {
            $0.kind == .attribute ? $0.id : nil
        }
        var result: [
            NodeRefKey: GraphNodeProfileEndpoint
        ] = [:]
        result.reserveCapacity(nodeKeys.count)

        if entityIDs.isEmpty == false {
            let models = try context.fetch(
                GraphScopedFetches.entities(
                    ids: entityIDs,
                    in: scope
                )
            )
            let values = try mapEntities(
                models,
                scope: scope
            ).sorted(by: Self.entitySort)
            for entity in values
                where result[entity.nodeKey] == nil {
                result[entity.nodeKey] =
                    GraphNodeProfileEndpoint(
                        nodeKey: entity.nodeKey,
                        visibleName: entity.name,
                        displayName: entity.name,
                        ownerEntity: nil
                    )
            }
        }
        try checkCancellation()

        if attributeIDs.isEmpty == false {
            let models = try context.fetch(
                GraphScopedFetches.attributes(
                    ids: attributeIDs,
                    in: scope
                )
            )
            let values = try mapAttributes(
                models,
                scope: scope
            ).sorted(by: Self.attributeSort)
            for attribute in values
                where result[attribute.nodeKey] == nil {
                let owner: GraphNodeProfileOwner?
                if
                    let ownerEntityID =
                        attribute.ownerEntityID,
                    let ownerLabel =
                        attribute.ownerLabel
                {
                    owner = GraphNodeProfileOwner(
                        entityID: ownerEntityID,
                        visibleName: ownerLabel
                    )
                } else {
                    owner = nil
                }
                result[attribute.nodeKey] =
                    GraphNodeProfileEndpoint(
                        nodeKey: attribute.nodeKey,
                        visibleName: attribute.name,
                        displayName:
                            attribute.displayLabel,
                        ownerEntity: owner
                    )
            }
        }
        try checkCancellation()

        if result[center.nodeKey] == nil {
            result[center.nodeKey] =
                GraphNodeProfileEndpoint(
                    nodeKey: center.nodeKey,
                    visibleName: center.visibleName,
                    displayName: center.displayName,
                    ownerEntity: center.ownerEntity
                )
        }
        return result
    }

    private func profileConnections(
        _ models: [MetaLink],
        direction:
            GraphNodeProfileConnectionDirection,
        center: NodeRefKey,
        endpoints: [
            NodeRefKey: GraphNodeProfileEndpoint
        ],
        scope: GraphScope
    ) throws -> [GraphNodeProfileConnection] {
        var result: [GraphNodeProfileConnection] = []
        result.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            let link = GraphReadDTOMapper.link(
                model,
                scope: scope
            )
            guard
                let sourceKey = link.sourceNodeKey,
                let targetKey = link.targetNodeKey,
                let source = endpoints[sourceKey],
                let target = endpoints[targetKey]
            else {
                continue
            }
            switch direction {
            case .incoming:
                guard targetKey == center else {
                    continue
                }
            case .outgoing:
                guard sourceKey == center else {
                    continue
                }
            }
            result.append(
                GraphNodeProfileConnection(
                    linkID: link.id,
                    createdAt: link.createdAt,
                    direction: direction,
                    source: source,
                    target: target,
                    note: link.note
                )
            )
        }
        try checkCancellation()

        let sorted = result.sorted(
            by: Self.profileConnectionSort
        )
        var seen = Set<UUID>()
        return sorted.filter {
            seen.insert($0.linkID).inserted
        }
    }

    private func uniqueAttachments(
        _ values: [GraphAttachmentMetadataDTO]
    ) -> [GraphAttachmentMetadataDTO] {
        var seen = Set<UUID>()
        return values.filter {
            seen.insert($0.id).inserted
        }
    }

    private nonisolated static func profileConnectionSort(
        lhs: GraphNodeProfileConnection,
        rhs: GraphNodeProfileConnection
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        if lhs.linkID != rhs.linkID {
            return lhs.linkID.uuidString < rhs.linkID.uuidString
        }
        if lhs.sourceReference != rhs.sourceReference {
            let lhsKind = lhs.sourceReference.kind.rawValue
            let rhsKind = rhs.sourceReference.kind.rawValue
            if lhsKind != rhsKind {
                return lhsKind < rhsKind
            }
            let lhsID = lhs.sourceReference.id.uuidString
            let rhsID = rhs.sourceReference.id.uuidString
            return lhsID < rhsID
        }
        let lhsTargetKind =
            lhs.targetReference.kind.rawValue
        let rhsTargetKind =
            rhs.targetReference.kind.rawValue
        if lhsTargetKind != rhsTargetKind {
            return lhsTargetKind < rhsTargetKind
        }
        if lhs.targetReference.id != rhs.targetReference.id {
            let lhsID =
                lhs.targetReference.id.uuidString
            let rhsID =
                rhs.targetReference.id.uuidString
            return lhsID < rhsID
        }
        return (lhs.note ?? "") < (rhs.note ?? "")
    }
}
