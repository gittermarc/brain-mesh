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
            try await sourceRepository.entity(id: entityID, in: scope.graphScope) == nil
        {
            return nil
        }

        let targetRevalidator = GraphChatAnswerArtifactNavigationTargetRevalidator(
            sourceRepository: sourceRepository
        )
        for target in artifact.allNavigationTargets {
            try Task.checkCancellation()
            guard
                try await targetRevalidator.revalidatedTarget(
                    target,
                    in: scope.graphScope
                ) != nil
            else {
                return nil
            }
        }

        return artifact
    }
}

nonisolated struct GraphChatAnswerArtifactNavigationTargetRevalidator: Sendable {
    private let sourceRepository: any GraphEvidenceSourceReading

    init(
        sourceRepository: any GraphEvidenceSourceReading = GraphReadRepository.shared
    ) {
        self.sourceRepository = sourceRepository
    }

    func revalidatedTarget(
        _ target: GraphChatAnswerArtifactNavigationTarget,
        in graphScope: GraphScope
    ) async throws -> GraphChatAnswerArtifactNavigationTarget? {
        try Task.checkCancellation()
        guard target.graphScope == graphScope else {
            return nil
        }

        switch target {
        case .openNode(_, let node):
            guard try await nodeExists(node, in: graphScope) else { return nil }
            return target

        case .focusNodeInGraph(_, let node):
            guard try await nodeExists(node, in: graphScope) else { return nil }
            return target

        case .openEntityList(_, let entityID, _):
            guard try await sourceRepository.entity(id: entityID, in: graphScope) != nil else {
                return nil
            }
            return target

        case .showResultNodes(_, let title, let nodes):
            let available = try await availableNodes(nodes, in: graphScope)
            guard available.isEmpty == false else { return nil }
            return .showResultNodes(graphScope: graphScope, title: title, nodes: available)

        case .openResultFilter(_, let entityID, let filters, let resultNodes):
            if let entityID,
                try await sourceRepository.entity(id: entityID, in: graphScope) == nil
            {
                return nil
            }
            let available = try await availableNodes(resultNodes, in: graphScope)
            guard available.isEmpty == false else { return nil }
            return .openResultFilter(
                graphScope: graphScope,
                entityID: entityID,
                filters: filters,
                resultNodes: available
            )

        case .highlightNodesInCanvas(_, let nodes):
            let available = try await availableNodes(nodes, in: graphScope)
            guard available.isEmpty == false else { return nil }
            return .highlightNodesInCanvas(graphScope: graphScope, nodes: available)

        case .clearCanvasHighlight:
            return target

        case .addNodesToCanvasSelection(_, let nodes):
            let available = try await availableNodes(nodes, in: graphScope)
            guard available.isEmpty == false else { return nil }
            return .addNodesToCanvasSelection(graphScope: graphScope, nodes: available)

        case .replaceCanvasSelection(_, let nodes):
            let available = try await availableNodes(nodes, in: graphScope)
            guard available.isEmpty == false else { return nil }
            return .replaceCanvasSelection(graphScope: graphScope, nodes: available)

        case .compareNodes(_, let nodes):
            let available = try await availableNodes(nodes, in: graphScope)
            guard available.count >= 2 else { return nil }
            return .compareNodes(graphScope: graphScope, nodes: available)
        }
    }

    private func availableNodes(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) async throws -> [NodeRefKey] {
        var seen = Set<NodeRefKey>()
        var available: [NodeRefKey] = []
        for node in nodes.prefix(GraphChatWorkspaceBudget.maximumActionNodes) {
            try Task.checkCancellation()
            guard seen.insert(node).inserted,
                try await nodeExists(node, in: graphScope)
            else {
                continue
            }
            available.append(node)
        }
        return available
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
