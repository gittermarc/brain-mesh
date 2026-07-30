//
//  GraphEvidenceValidator.swift
//  BrainMesh
//
//  Final graph, scope, and existence gate for evidence returned by chat tools.
//

import Foundation

nonisolated protocol GraphEvidenceSourceReading: Sendable {
    func graphMetadata(in scope: GraphScope) async throws -> GraphMetadataDTO?
    func entity(id: UUID, in scope: GraphScope) async throws -> GraphEntityDTO?
    func attribute(id: UUID, in scope: GraphScope) async throws -> GraphAttributeDTO?
    func detailFieldDefinition(id: UUID, in scope: GraphScope) async throws -> GraphDetailFieldDefinitionDTO?
    func detailValue(id: UUID, in scope: GraphScope) async throws -> GraphDetailValueDTO?
    func link(id: UUID, in scope: GraphScope) async throws -> GraphLinkDTO?
    func attachmentMetadata(id: UUID, in scope: GraphScope) async throws -> GraphAttachmentMetadataDTO?
}

extension GraphReadRepository: GraphEvidenceSourceReading {}

nonisolated protocol GraphEvidenceValidating: Sendable {
    func validatedEvidence(
        _ evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> [GraphEvidence]
}

actor GraphEvidenceSourceValidator: GraphEvidenceValidating {
    static let shared = GraphEvidenceSourceValidator(repository: GraphReadRepository.shared)

    private struct ResolvedSource: Sendable {
        let graphScope: GraphScope
        let sourceKind: GraphSourceKind
        let sourceID: UUID
        let fieldID: UUID?
        let attachmentID: UUID?
        let relatedNodes: Set<NodeRefKey>
        let ownerEntityIDs: Set<UUID>
        let authoritativeFieldValue: GraphEvidenceFieldValue?
        let authoritativeLink: GraphLinkDTO?
    }

    private let repository: any GraphEvidenceSourceReading

    init(repository: any GraphEvidenceSourceReading) {
        self.repository = repository
    }

    func validatedEvidence(
        _ evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> [GraphEvidence] {
        var result: [GraphEvidence] = []
        result.reserveCapacity(evidence.count)
        var seen = Set<GraphEvidenceID>()

        for (index, item) in evidence.enumerated() {
            if index.isMultiple(of: 32) {
                try Task.checkCancellation()
            }
            guard seen.insert(item.id).inserted else {
                continue
            }
            guard item.sourceReference.graphID == scope.graphScope.graphID else {
                continue
            }
            guard let resolved = try await resolve(item.sourceReference, in: scope.graphScope) else {
                continue
            }
            guard try await referenceMetadataIsConsistent(
                item.sourceReference,
                resolved: resolved,
                graphScope: scope.graphScope
            ) else {
                continue
            }
            guard evidenceContentIsConsistent(
                item,
                resolved: resolved
            ) else {
                continue
            }
            guard scopeAllows(resolved, scope: scope) else {
                continue
            }
            result.append(item)
        }
        try Task.checkCancellation()
        return result
    }

    private func resolve(
        _ reference: GraphSourceReference,
        in graphScope: GraphScope
    ) async throws -> ResolvedSource? {
        switch reference.sourceKind {
        case .graph:
            guard let graph = try await repository.graphMetadata(in: graphScope),
                  graph.id == reference.sourceID,
                  graph.scope == graphScope
            else {
                return nil
            }
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .graph,
                sourceID: graph.id,
                fieldID: nil,
                attachmentID: nil,
                relatedNodes: [],
                ownerEntityIDs: [],
                authoritativeFieldValue: nil,
                authoritativeLink: nil
            )

        case .entity:
            guard let entity = try await repository.entity(id: reference.sourceID, in: graphScope),
                  entity.scope == graphScope
            else {
                return nil
            }
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .entity,
                sourceID: entity.id,
                fieldID: nil,
                attachmentID: nil,
                relatedNodes: [entity.nodeKey],
                ownerEntityIDs: [entity.id],
                authoritativeFieldValue: nil,
                authoritativeLink: nil
            )

        case .attribute:
            guard let attribute = try await repository.attribute(id: reference.sourceID, in: graphScope),
                  attribute.scope == graphScope
            else {
                return nil
            }
            var nodes: Set<NodeRefKey> = [attribute.nodeKey]
            var owners = Set<UUID>()
            if let ownerEntityID = attribute.ownerEntityID {
                owners.insert(ownerEntityID)
                nodes.insert(NodeRefKey(kind: .entity, id: ownerEntityID))
            }
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .attribute,
                sourceID: attribute.id,
                fieldID: nil,
                attachmentID: nil,
                relatedNodes: nodes,
                ownerEntityIDs: owners,
                authoritativeFieldValue: nil,
                authoritativeLink: nil
            )

        case .detailField:
            guard let field = try await repository.detailFieldDefinition(
                id: reference.sourceID,
                in: graphScope
            ), field.scope == graphScope else {
                return nil
            }
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .detailField,
                sourceID: field.id,
                fieldID: field.id,
                attachmentID: nil,
                relatedNodes: [NodeRefKey(kind: .entity, id: field.entityID)],
                ownerEntityIDs: [field.entityID],
                authoritativeFieldValue: nil,
                authoritativeLink: nil
            )

        case .detailValue:
            guard let value = try await repository.detailValue(id: reference.sourceID, in: graphScope),
                  value.scope == graphScope,
                  let attribute = try await repository.attribute(id: value.attributeID, in: graphScope),
                  let ownerEntityID = attribute.ownerEntityID,
                  let field = try await repository.detailFieldDefinition(
                    id: value.fieldID,
                    in: graphScope
                  ),
                  field.scope == graphScope,
                  field.entityID == ownerEntityID
            else {
                return nil
            }
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .detailValue,
                sourceID: value.id,
                fieldID: value.fieldID,
                attachmentID: nil,
                relatedNodes: [
                    attribute.nodeKey,
                    NodeRefKey(kind: .entity, id: ownerEntityID)
                ],
                ownerEntityIDs: [ownerEntityID],
                authoritativeFieldValue: GraphEvidenceFieldValue(
                    fieldID: field.id,
                    fieldName: field.name,
                    value: value.value.graphEvidenceValue,
                    unit: field.unit
                ),
                authoritativeLink: nil
            )

        case .link:
            guard let link = try await repository.link(id: reference.sourceID, in: graphScope),
                  link.scope == graphScope
            else {
                return nil
            }
            guard let source = link.sourceNodeKey,
                  let target = link.targetNodeKey,
                  try await nodeExists(
                    source,
                    graphScope: graphScope
                  ),
                  try await nodeExists(
                    target,
                    graphScope: graphScope
                  )
            else {
                return nil
            }
            let nodes: Set<NodeRefKey> = [
                source,
                target,
            ]
            let owners = try await ownerEntityIDs(for: nodes, graphScope: graphScope)
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .link,
                sourceID: link.id,
                fieldID: nil,
                attachmentID: nil,
                relatedNodes: nodes,
                ownerEntityIDs: owners,
                authoritativeFieldValue: nil,
                authoritativeLink: link
            )

        case .attachment:
            guard let attachment = try await repository.attachmentMetadata(
                id: reference.sourceID,
                in: graphScope
            ), attachment.scope == graphScope,
            let ownerNode = attachment.ownerNodeKey else {
                return nil
            }
            let owners = try await ownerEntityIDs(for: [ownerNode], graphScope: graphScope)
            return ResolvedSource(
                graphScope: graphScope,
                sourceKind: .attachment,
                sourceID: attachment.id,
                fieldID: nil,
                attachmentID: attachment.id,
                relatedNodes: [ownerNode],
                ownerEntityIDs: owners,
                authoritativeFieldValue: nil,
                authoritativeLink: nil
            )
        }
    }

    private func evidenceContentIsConsistent(
        _ evidence: GraphEvidence,
        resolved: ResolvedSource
    ) -> Bool {
        let noteValues = evidence.fieldValues
            .filter {
                $0.fieldID == nil
                    && $0.fieldName
                        == "Link-Notiz"
            }
        if noteValues.isEmpty == false,
            evidence.sourceReference
                .linkBinding == nil
        {
            return false
        }
        if let binding =
            evidence.sourceReference.linkBinding
        {
            guard
                let link = resolved.authoritativeLink,
                link.id == binding.linkID,
                link.note == binding.note
            else {
                return false
            }
            if noteValues.isEmpty == false {
                guard
                    let note = binding.note,
                    noteValues.count == 1,
                    noteValues[0].value
                        == .text(note)
                else {
                    return false
                }
            }
        }
        guard let authoritative = resolved.authoritativeFieldValue else {
            return true
        }
        guard evidence.fieldValues.isEmpty == false else {
            return true
        }
        let matchingValues = evidence.fieldValues.filter {
            $0.fieldID == authoritative.fieldID
        }
        return matchingValues.count == 1
            && matchingValues[0] == authoritative
    }

    private func referenceMetadataIsConsistent(
        _ reference: GraphSourceReference,
        resolved: ResolvedSource,
        graphScope: GraphScope
    ) async throws -> Bool {
        guard resolved.graphScope == graphScope,
              resolved.sourceKind == reference.sourceKind,
              resolved.sourceID == reference.sourceID
        else {
            return false
        }

        if let node = reference.node, resolved.relatedNodes.contains(node.nodeKey) == false {
            return false
        }
        if let owner = reference.owner {
            let ownerKey = owner.nodeKey
            guard resolved.relatedNodes.contains(ownerKey)
                || (owner.kind == .entity && resolved.ownerEntityIDs.contains(owner.id))
            else {
                return false
            }
        }
        if let fieldID = reference.fieldID {
            if resolved.sourceKind == .attribute {
                guard let field = try await repository.detailFieldDefinition(
                    id: fieldID,
                    in: graphScope
                ), field.scope == graphScope,
                resolved.ownerEntityIDs.contains(field.entityID) else {
                    return false
                }
            } else if resolved.fieldID != fieldID {
                return false
            }
        }
        if let attachmentID = reference.attachmentID,
           resolved.attachmentID != attachmentID {
            return false
        }
        if let binding = reference.linkBinding {
            guard
                resolved.sourceKind == .link,
                let link = resolved.authoritativeLink,
                reference.sourceID == binding.linkID,
                reference.linkID == binding.linkID,
                link.id == binding.linkID,
                link.sourceNodeKey
                    == binding.source.nodeKey,
                link.targetNodeKey
                    == binding.target.nodeKey,
                link.note == binding.note
            else {
                return false
            }
            switch binding.direction {
            case .incoming:
                guard
                    reference.node?.nodeKey
                        == binding.target.nodeKey
                else {
                    return false
                }
            case .outgoing:
                guard
                    reference.node?.nodeKey
                        == binding.source.nodeKey
                else {
                    return false
                }
            }
        }
        if let linkID = reference.linkID {
            if resolved.sourceKind == .link, linkID != resolved.sourceID {
                return false
            }
            guard let link = try await repository.link(id: linkID, in: graphScope),
                  link.scope == graphScope
            else {
                return false
            }
            let linkNodes = Set([link.sourceNodeKey, link.targetNodeKey].compactMap { $0 })
            guard linkNodes.isDisjoint(with: resolved.relatedNodes) == false else {
                return false
            }
        }
        return true
    }

    private func scopeAllows(
        _ resolved: ResolvedSource,
        scope: GraphChatScope
    ) -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let entityID):
            return resolved.ownerEntityIDs.contains(entityID)
                || resolved.relatedNodes.contains(NodeRefKey(kind: .entity, id: entityID))
        case .node(let node):
            return scopeAllows(resolved, node: node)
        case .selection(let nodes):
            return nodes.contains { scopeAllows(resolved, node: $0) }
        }
    }

    private func scopeAllows(
        _ resolved: ResolvedSource,
        node: NodeRefKey
    ) -> Bool {
        if resolved.relatedNodes.contains(node) {
            return true
        }
        if node.kind == .entity, resolved.ownerEntityIDs.contains(node.id) {
            return true
        }
        return false
    }

    private func ownerEntityIDs(
        for nodes: Set<NodeRefKey>,
        graphScope: GraphScope
    ) async throws -> Set<UUID> {
        var result = Set<UUID>()
        for node in nodes {
            try Task.checkCancellation()
            switch node.kind {
            case .entity:
                if try await repository.entity(id: node.id, in: graphScope) != nil {
                    result.insert(node.id)
                }
            case .attribute:
                if let attribute = try await repository.attribute(id: node.id, in: graphScope),
                   let ownerEntityID = attribute.ownerEntityID {
                    result.insert(ownerEntityID)
                }
            }
        }
        return result
    }

    private func nodeExists(
        _ node: NodeRefKey,
        graphScope: GraphScope
    ) async throws -> Bool {
        switch node.kind {
        case .entity:
            return try await repository.entity(
                id: node.id,
                in: graphScope
            ) != nil
        case .attribute:
            return try await repository.attribute(
                id: node.id,
                in: graphScope
            ) != nil
        }
    }
}

nonisolated struct PassthroughGraphEvidenceValidator: GraphEvidenceValidating {
    func validatedEvidence(
        _ evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> [GraphEvidence] {
        evidence.filter { $0.sourceReference.graphID == scope.graphScope.graphID }
    }
}
