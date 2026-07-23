//
//  GraphChatAnswerArtifactRevalidator.swift
//  BrainMesh
//
//  Revalidates committed artifacts against the active graph and chat scope.
//

import Foundation

nonisolated protocol GraphChatAnswerArtifactRevalidating: Sendable {
    func revalidatedArtifact(
        _ artifact: GraphChatAnswerArtifact,
        evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact?
}

nonisolated struct GraphChatRegistryAnswerArtifactRevalidator: GraphChatAnswerArtifactRevalidating {
    func revalidatedArtifact(
        _ artifact: GraphChatAnswerArtifact,
        evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact? {
        guard artifact.graphScope == scope.graphScope else {
            return nil
        }
        let availableEvidenceIDs = Set(evidence.map(\.id))
        guard Set(artifact.allEvidenceIDs).isSubset(of: availableEvidenceIDs) else {
            return nil
        }
        return artifact
    }
}

nonisolated struct GraphChatLiveAnswerArtifactRevalidator: GraphChatAnswerArtifactRevalidating {
    private let evidenceValidator: any GraphEvidenceValidating
    private let sourceRepository: any GraphEvidenceSourceReading

    init(
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        sourceRepository: any GraphEvidenceSourceReading = GraphReadRepository.shared
    ) {
        self.evidenceValidator = evidenceValidator
        self.sourceRepository = sourceRepository
    }

    func revalidatedArtifact(
        _ artifact: GraphChatAnswerArtifact,
        evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact? {
        try Task.checkCancellation()
        guard artifact.graphScope == scope.graphScope else {
            return nil
        }

        let validatedEvidence = try await evidenceValidator.validatedEvidence(
            evidence,
            in: scope
        )
        let validatedEvidenceIDs = Set(validatedEvidence.map(\.id))
        guard Set(artifact.allEvidenceIDs).isSubset(of: validatedEvidenceIDs) else {
            return nil
        }

        if let entityID = artifact.querySummary?.entityID,
           try await sourceRepository.entity(id: entityID, in: scope.graphScope) == nil {
            return nil
        }

        for target in artifact.allNavigationTargets {
            try Task.checkCancellation()
            guard try await navigationTargetExists(target, in: scope.graphScope) else {
                return nil
            }
        }

        return artifact
    }

    private func navigationTargetExists(
        _ target: GraphChatAnswerArtifactNavigationTarget,
        in graphScope: GraphScope
    ) async throws -> Bool {
        guard target.graphScope == graphScope else {
            return false
        }

        switch target {
        case .openNode(_, let node),
             .focusNodeInGraph(_, let node):
            return try await nodeExists(node, in: graphScope)

        case .openEntityList(_, let entityID, _):
            return try await sourceRepository.entity(id: entityID, in: graphScope) != nil

        case .openResultFilter(_, let entityID, _, let resultNodes):
            if let entityID,
               try await sourceRepository.entity(id: entityID, in: graphScope) == nil {
                return false
            }
            return try await allNodesExist(resultNodes, in: graphScope)

        case .addNodesToCanvasSelection(_, let nodes):
            guard nodes.isEmpty == false else {
                return false
            }
            return try await allNodesExist(nodes, in: graphScope)

        case .compareNodes(_, let nodes):
            guard nodes.count >= 2 else {
                return false
            }
            return try await allNodesExist(nodes, in: graphScope)
        }
    }

    private func allNodesExist(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) async throws -> Bool {
        for node in nodes {
            try Task.checkCancellation()
            guard try await nodeExists(node, in: graphScope) else {
                return false
            }
        }
        return true
    }

    private func nodeExists(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) async throws -> Bool {
        switch node.kind {
        case .entity:
            return try await sourceRepository.entity(id: node.id, in: graphScope) != nil
        case .attribute:
            return try await sourceRepository.attribute(id: node.id, in: graphScope) != nil
        }
    }
}
