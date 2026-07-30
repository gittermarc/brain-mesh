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
        if case .nodeProfile =
            artifact.payload
        {
            return GraphChatNodeProfileArtifactEvidenceProjector
                .revalidatedArtifact(
                    artifact,
                    availableEvidenceIDs:
                        availableEvidenceIDs
                )
        }
        if case .relationship =
            artifact.payload {
            return GraphChatRelationshipArtifactEvidenceProjector
                .revalidatedArtifact(
                    artifact,
                    availableEvidenceIDs:
                        availableEvidenceIDs
                )
        }
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
        if case .nodeProfile =
            artifact.payload
        {
            guard
                let profile =
                    GraphChatNodeProfileArtifactEvidenceProjector
                    .revalidatedArtifact(
                        artifact,
                        availableEvidenceIDs:
                            validatedEvidenceIDs
                    )
            else {
                return nil
            }
            return try await
                revalidatedNodeProfileNavigation(
                    profile,
                    scope: scope
                )
        }
        if case .relationship =
            artifact.payload {
            guard
                let relationship =
                    GraphChatRelationshipArtifactEvidenceProjector
                    .revalidatedArtifact(
                        artifact,
                        availableEvidenceIDs:
                            validatedEvidenceIDs
                    )
            else {
                return nil
            }
            return try await revalidatedNavigation(
                relationship,
                scope: scope
            )
        }
        if case .comparison = artifact.payload {
            guard let comparison =
                    revalidatedComparison(
                    artifact,
                    availableEvidenceIDs:
                        validatedEvidenceIDs
                ) else {
                return nil
            }
            return try await revalidatedNavigation(
                comparison,
                scope: scope
            )
        }
        guard Set(artifact.allEvidenceIDs).isSubset(of: validatedEvidenceIDs) else {
            return nil
        }

        if let entityID = artifact.querySummary?.entityID,
            try await sourceRepository.entity(id: entityID, in: scope.graphScope) == nil
        {
            return nil
        }

        return try await revalidatedNavigation(
            artifact,
            scope: scope
        )
    }

    private func revalidatedNodeProfileNavigation(
        _ artifact: GraphChatAnswerArtifact,
        scope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact? {
        guard
            case .nodeProfile(let source) =
                artifact.payload
        else {
            return nil
        }
        let revalidator =
            GraphChatAnswerArtifactNavigationTargetRevalidator(
                sourceRepository:
                    sourceRepository
            )
        guard
            let sourceNodeTarget =
                source.nodeNavigationTarget,
            let nodeTarget =
                try await revalidator
                .revalidatedTarget(
                    sourceNodeTarget,
                    in: scope.graphScope
                )
        else {
            return nil
        }

        let owner:
            GraphChatAnswerArtifactNodeProfileOwner?
        if let sourceOwner = source.owner {
            let target:
                GraphChatAnswerArtifactNavigationTarget?
            if let sourceTarget =
                sourceOwner
                    .navigationTarget
            {
                target =
                    try await revalidator
                    .revalidatedTarget(
                        sourceTarget,
                        in:
                            scope.graphScope
                    )
            } else {
                target = nil
            }
            owner =
                GraphChatAnswerArtifactNodeProfileOwner(
                    label:
                        sourceOwner.label,
                    navigationTarget:
                        target
                )
        } else {
            owner = nil
        }

        let incoming =
            try await revalidatedConnections(
                source.incomingConnections,
                revalidator:
                    revalidator,
                graphScope:
                    scope.graphScope
            )
        let outgoing =
            try await revalidatedConnections(
                source.outgoingConnections,
                revalidator:
                    revalidator,
                graphScope:
                    scope.graphScope
            )
        var navigationTargets: [
            GraphChatAnswerArtifactNavigationTarget
        ] = []
        for target in artifact.navigationTargets {
            try Task.checkCancellation()
            let validated =
                try await revalidator
                .revalidatedTarget(
                    target,
                    in: scope.graphScope
                )
            if let validated {
                navigationTargets.append(
                    validated
                )
            }
        }
        let payload =
            GraphChatAnswerArtifactNodeProfilePayload(
                node: source.node,
                visibleName:
                    source.visibleName,
                displayName:
                    source.displayName,
                owner: owner,
                notes: source.notes,
                detailValues:
                    source.detailValues,
                incomingConnections:
                    incoming,
                outgoingConnections:
                    outgoing,
                attachments:
                    source.attachments,
                detailValueMetadata:
                    source
                        .detailValueMetadata,
                incomingConnectionMetadata:
                    source
                        .incomingConnectionMetadata,
                outgoingConnectionMetadata:
                    source
                        .outgoingConnectionMetadata,
                attachmentMetadata:
                    source
                        .attachmentMetadata,
                nodeNavigationTarget:
                    nodeTarget,
                identityEvidence:
                    source.identityEvidence,
                evidence:
                    source.evidence
            )
        return GraphChatAnswerArtifact(
            id: artifact.id,
            sessionID:
                artifact.sessionID,
            graphScope:
                artifact.graphScope,
            title: artifact.title,
            payload:
                .nodeProfile(payload),
            evidence:
                artifact.evidence,
            navigationTargets:
                navigationTargets,
            querySummary:
                artifact.querySummary
        )
    }

    private func revalidatedConnections(
        _ values: [
            GraphChatAnswerArtifactNodeProfileConnection
        ],
        revalidator:
            GraphChatAnswerArtifactNavigationTargetRevalidator,
        graphScope: GraphScope
    ) async throws -> [
        GraphChatAnswerArtifactNodeProfileConnection
    ] {
        var result: [
            GraphChatAnswerArtifactNodeProfileConnection
        ] = []
        result.reserveCapacity(values.count)
        for value in values {
            try Task.checkCancellation()
            let target:
                GraphChatAnswerArtifactNavigationTarget?
            if let sourceTarget =
                value.counterpartNavigationTarget
            {
                target =
                    try await revalidator
                    .revalidatedTarget(
                        sourceTarget,
                        in: graphScope
                    )
            } else {
                target = nil
            }
            result.append(
                GraphChatAnswerArtifactNodeProfileConnection(
                    id: value.id,
                    direction:
                        value.direction,
                    sourceLabel:
                        value.sourceLabel,
                    targetLabel:
                        value.targetLabel,
                    counterpartLabel:
                        value.counterpartLabel,
                    counterpartNavigationTarget:
                        target,
                    note: value.note,
                    evidence:
                        value.evidence
                )
            )
        }
        return result
    }

    private func revalidatedNavigation(
        _ artifact: GraphChatAnswerArtifact,
        scope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact? {
        let targetRevalidator =
            GraphChatAnswerArtifactNavigationTargetRevalidator(
                sourceRepository:
                    sourceRepository
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

    private func revalidatedComparison(
        _ artifact: GraphChatAnswerArtifact,
        availableEvidenceIDs:
            Set<GraphEvidenceID>
    ) -> GraphChatAnswerArtifact? {
        guard case .comparison(let source) =
                artifact.payload
        else {
            return nil
        }
        let subjects = source.subjects.filter {
            $0.evidence.evidenceIDs.isEmpty == false
                && Set(
                    $0.evidence.evidenceIDs
                ).isSubset(
                    of: availableEvidenceIDs
                )
        }
        let preliminarySubjectIDs = Set(
            subjects.map(\.id)
        )
        let preliminaryFeatures =
            source.features.filter {
                Set(
                    $0.evidence.evidenceIDs
                ).isSubset(
                    of: availableEvidenceIDs
                )
            }
        let preliminaryFeatureIDs = Set(
            preliminaryFeatures.map(\.id)
        )
        let values = source.values.filter {
            guard
                preliminarySubjectIDs
                    .contains($0.subjectID),
                preliminaryFeatureIDs
                    .contains($0.featureID),
                let evidence = $0.evidence,
                evidence.evidenceIDs
                    .isEmpty == false
            else {
                return false
            }
            return Set(
                evidence.evidenceIDs
            ).isSubset(
                of: availableEvidenceIDs
            )
        }
        let usedSubjectIDs = Set(
            values.map(\.subjectID)
        )
        let usedFeatureIDs = Set(
            values.map(\.featureID)
        )
        let retainedSubjects =
            subjects.filter {
                usedSubjectIDs.contains($0.id)
            }
        let retainedFeatures =
            preliminaryFeatures.filter {
                usedFeatureIDs.contains($0.id)
            }
        guard retainedSubjects.count >= 2,
              retainedFeatures.isEmpty == false
        else {
            return nil
        }
        let subjectsWereReduced =
            retainedSubjects.count < source.subjects.count
        let featuresWereReduced =
            retainedFeatures.count < source.features.count
        let valuesWereReduced =
            values.count < source.values.count
        var truncationReasons =
            source.resultMetadata
                .truncation.reasons
        if subjectsWereReduced ||
            featuresWereReduced ||
            valuesWereReduced
        {
            truncationReasons.insert(
                .sourceLimited,
                at: 0
            )
        }
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    retainedSubjects.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + retainedFeatures.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + values.flatMap {
                        $0.evidence?
                            .evidenceIDs ?? []
                    }
            )
        let comparison =
            GraphChatAnswerArtifactComparisonPayload(
                title: source.title,
                subjects: retainedSubjects,
                features: retainedFeatures,
                values: values,
                resultMetadata:
                    GraphChatAnswerArtifactResultMetadata(
                        resultCount:
                            source
                                .resultMetadata
                                .totalCount,
                        returnedCount:
                            retainedSubjects
                                .count,
                        truncation:
                            GraphChatAnswerArtifactTruncation(
                                reasons:
                                    truncationReasons,
                                omittedCount:
                                    source
                                        .resultMetadata
                                        .totalCount
                                        .map {
                                            max(
                                                0,
                                                $0
                                                    - retainedSubjects
                                                        .count
                                            )
                                        }
                            )
                    ),
                evidence: evidence
            )
        let retainedNodes =
            retainedSubjects.compactMap {
                subject -> NodeRefKey? in
                guard
                    case .openNode(
                        _,
                        let node
                    ) =
                        subject
                            .navigationTarget
                else {
                    return nil
                }
                return node
            }
        let navigationTargets =
            retainedNodes.count >= 2
            ? [
                GraphChatAnswerArtifactNavigationTarget
                    .compareNodes(
                        graphScope:
                            artifact.graphScope,
                        nodes:
                            retainedNodes
                    ),
            ]
            : []
        return GraphChatAnswerArtifact(
            id: artifact.id,
            sessionID: artifact.sessionID,
            graphScope: artifact.graphScope,
            title: artifact.title,
            payload: .comparison(comparison),
            evidence: evidence,
            navigationTargets:
                navigationTargets,
            querySummary:
                artifact.querySummary
        )
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
