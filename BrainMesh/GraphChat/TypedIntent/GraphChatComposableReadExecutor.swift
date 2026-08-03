//
//  GraphChatComposableReadExecutor.swift
//  BrainMesh
//
//  Bounded, provider-free execution of fully validated composable reads.
//

import Foundation

nonisolated enum GraphChatComposableReadExecutionError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case invalidPlan
    case graphScopeMismatch
    case sourceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPlan:
            return "Der validierte Composable-Read-Plan ist nicht ausführbar."
        case .graphScopeMismatch:
            return "Der Composable Read würde den aktiven Graphen oder Chat-Scope verlassen."
        case .sourceUnavailable:
            return "Der graphgescopte Read-Snapshot ist nicht vollständig verfügbar."
        }
    }
}

nonisolated enum GraphChatComposableReadExecutionStage:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case planValidation
    case snapshotRead
    case startSelection
    case traversal
    case linkInspection
    case evidenceValidation
    case resultAssembly
}

nonisolated struct GraphChatComposableReadResultLink:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let source: NodeRefKey
    let target: NodeRefKey
    let direction:
        GraphChatRelationshipConnectionDirection
    let note: String?
    let evidenceID: GraphEvidenceID
}

nonisolated struct GraphChatComposableReadResultPath:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let startNode: NodeRefKey
    let terminalNode: NodeRefKey
    let nodes: [NodeRefKey]
    let links: [GraphChatComposableReadResultLink]
    let evidenceIDs: [GraphEvidenceID]
}

nonisolated struct GraphChatComposableReadResultNode:
    Identifiable,
    Hashable,
    Sendable
{
    let node: NodeRefKey
    let label: String
    let ownerEntityID: UUID
    let evidenceIDs: [GraphEvidenceID]

    var id: NodeRefKey { node }
}

nonisolated struct GraphChatComposableReadExecutionMetrics:
    Hashable,
    Sendable
{
    let selectedStartNodeCount: Int
    let visitedNodeCount: Int
    let checkedLinkCount: Int
    let intermediateResultCounts: [Int]
}

nonisolated struct GraphChatComposableReadResultSet:
    Hashable,
    Sendable
{
    let rootEntity: GraphChatTypedEntityIdentity
    let resultEntity: GraphChatTypedEntityIdentity
    let resultTarget:
        GraphChatComposableReadTraversalResultTarget
    let nodes: [GraphChatComposableReadResultNode]
    let paths: [GraphChatComposableReadResultPath]
    let metrics: GraphChatComposableReadExecutionMetrics
    let resultWindow: GraphChatResultWindow
}

nonisolated struct GraphChatComposableReadExecutionOutput:
    Hashable,
    Sendable
{
    let resultSet: GraphChatComposableReadResultSet
    let queryResult: GraphChatQueryResult
    let continuationPlan: ValidatedGraphQueryPlan
    let continuationAction: GraphChatLocalQueryAction
}

nonisolated struct GraphChatComposableReadExecutor:
    GraphChatLocalIntentComposableReadExecuting
{
    private let repository:
        any GraphChatComposableReadSnapshotReading
    private let evidenceValidator:
        any GraphEvidenceValidating
    private let cancellationCheck:
        @Sendable (
            GraphChatComposableReadExecutionStage
        ) throws -> Void

    init(
        repository:
            any GraphChatComposableReadSnapshotReading =
                GraphReadRepository.shared,
        evidenceValidator:
            any GraphEvidenceValidating =
                GraphEvidenceSourceValidator.shared,
        cancellationCheck:
            @escaping @Sendable (
                GraphChatComposableReadExecutionStage
            ) throws -> Void = { _ in
                try Task.checkCancellation()
            }
    ) {
        self.repository = repository
        self.evidenceValidator = evidenceValidator
        self.cancellationCheck = cancellationCheck
    }

    func execute(
        _ validatedPlan:
            ValidatedGraphChatComposableReadPlan,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<GraphChatComposableReadExecutionOutput>
    {
        do {
            try cancellationCheck(.planValidation)
            let plan = validatedPlan.plan
            guard
                plan.resultContract
                    == .composableNodeCollection,
                context.scope == plan.queryScope,
                context.scope.graphScope
                    == plan.graphScope,
                plan.chatScope
                    == .entireGraph(plan.graphScope),
                case .entity(let rootReference) =
                    Self.selection(in: plan),
                let rootEntity = rootReference.identity,
                let projection =
                    Self.traversalProjection(in: plan),
                projection.deduplicatesNodes
            else {
                throw GraphChatComposableReadExecutionError
                    .invalidPlan
            }
            let stages = Self.traversalOperations(
                in: plan
            )
            guard
                stages.isEmpty == false,
                stages.count
                    <= plan.limits.maximumTraversalHopCount
            else {
                throw GraphChatComposableReadExecutionError
                    .invalidPlan
            }
            _ = try await context.budget.beginCall(
                tool: .getNeighbors,
                requestedResultCount:
                    plan.limits.resultLimit,
                toolMaximumResultCount:
                    plan.limits.maximumResultLimit
            )
            try cancellationCheck(.snapshotRead)
            let snapshot = try await repository
                .sourceSnapshot(in: plan.graphScope)
            try cancellationCheck(.snapshotRead)
            try Self.validate(
                snapshot: snapshot,
                plan: plan
            )

            let source = Source(snapshot: snapshot)
            let rootFilters = validatedPlan
                .validatedFilterStages.first {
                    $0.operationID
                        == Self.rootFilterOperationID(
                            in: plan
                        )
                }?.filters ?? []
            var wasAppLimited = false
            var wasSourceLimited = false
            var encounteredConflictKeys =
                Set<DetailValueAuthorityKey>()
            var intermediateCounts: [Int] = []

            var eligibleStarts: [StartCandidate] = []
            for (index, attribute) in
                source.attributes.enumerated()
            where attribute.ownerEntityID == rootEntity.id {
                if index.isMultiple(of: 32) {
                    try cancellationCheck(
                        .startSelection
                    )
                }
                let conflictKeys = source.conflictingKeys(
                    for: attribute,
                    filters: rootFilters
                )
                if conflictKeys.isEmpty == false {
                    encounteredConflictKeys.formUnion(
                        conflictKeys
                    )
                    wasSourceLimited = true
                    continue
                }
                guard let filterEvidence = source
                    .filterEvidence(
                        for: attribute,
                        filters: rootFilters
                    ) else {
                    continue
                }
                eligibleStarts.append(
                    StartCandidate(
                        attribute: attribute,
                        filterEvidence: filterEvidence
                    )
                )
                if eligibleStarts.count
                    > plan.limits.selectedStartNodeLimit + 1 {
                    eligibleStarts.sort(
                        by: Self.startCandidateSort
                    )
                    eligibleStarts.removeLast()
                }
            }
            eligibleStarts.sort(
                by: Self.startCandidateSort
            )

            var startPaths: [PathState] = []
            for (index, candidate) in
                eligibleStarts.enumerated()
            {
                if index.isMultiple(of: 32) {
                    try cancellationCheck(
                        .startSelection
                    )
                }
                guard startPaths.count
                        < plan.limits.selectedStartNodeLimit
                else {
                    wasAppLimited = true
                    break
                }
                let attribute = candidate.attribute
                let summary = attribute.nodeSummary
                startPaths.append(
                    PathState(
                        nodes: [summary],
                        traversedLinks: [],
                        evidence:
                            [Self.nodeEvidence(summary)]
                            + candidate.filterEvidence
                    )
                )
            }

            var visitedNodes = Set(
                startPaths.map { $0.start.nodeKey }
            )
            guard visitedNodes.count
                    <= plan.limits.visitedNodeLimit else {
                throw GraphChatComposableReadExecutionError
                    .invalidPlan
            }
            var checkedLinkCount = 0
            var paths = startPaths

            traversalStages: for traversal in stages {
                try cancellationCheck(.traversal)
                let stage = traversal.stage
                let stageFilters = validatedPlan
                    .validatedFilterStages.first {
                        $0.operationID == traversal.id
                    }?.filters ?? []
                var candidates: [PathState] = []
                var pathSignatures = Set<String>()

                pathLoop: for (pathIndex, path) in
                    paths.enumerated()
                {
                    if pathIndex.isMultiple(of: 16) {
                        try cancellationCheck(
                            .traversal
                        )
                    }
                    for link in source.links[
                        path.current.nodeKey
                    ] ?? [] {
                        if checkedLinkCount
                            >= plan.limits.checkedLinkLimit {
                            wasAppLimited = true
                            break pathLoop
                        }
                        checkedLinkCount += 1
                        try cancellationCheck(
                            .linkInspection
                        )
                        guard let observed = Self.observedLink(
                            link,
                            from: path.current.nodeKey,
                            requested: stage.direction
                        ),
                        let counterpart = source.nodes[
                            observed.counterpart
                        ],
                        counterpart.kind == .attribute,
                        Self.ownerEntityID(of: counterpart)
                            == stage.counterpartEntity.id,
                        stage.counterpartNode == nil
                            || stage.counterpartNode?.node
                                == counterpart.nodeKey,
                        Self.noteMatches(
                            link.note,
                            predicate:
                                stage.notePredicate
                        ),
                        let attribute = source
                            .attributesByID[
                                counterpart.nodeKey.id
                            ]
                        else {
                            continue
                        }
                        let conflictKeys = source
                            .conflictingKeys(
                                for: attribute,
                                filters: stageFilters
                            )
                        if conflictKeys.isEmpty == false {
                            encounteredConflictKeys.formUnion(
                                conflictKeys
                            )
                            wasSourceLimited = true
                            continue
                        }
                        guard let detailEvidence = source
                            .filterEvidence(
                                for: attribute,
                                filters: stageFilters
                            ),
                        path.visited.contains(
                            counterpart.nodeKey
                        ) == false
                        else {
                            continue
                        }

                        if visitedNodes.contains(
                            counterpart.nodeKey
                        ) == false {
                            guard visitedNodes.count
                                < plan.limits
                                    .visitedNodeLimit
                            else {
                                wasAppLimited = true
                                continue
                            }
                            visitedNodes.insert(
                                counterpart.nodeKey
                            )
                        }
                        let linkEvidence = Self.linkEvidence(
                            link,
                            current: path.current,
                            counterpart: counterpart,
                            direction: observed.direction
                        )
                        let next = path.appending(
                            counterpart,
                            link: TraversedLink(
                                link: link,
                                direction:
                                    observed.direction,
                                evidenceID:
                                    linkEvidence.id
                            ),
                            evidence:
                                [linkEvidence,
                                 Self.nodeEvidence(counterpart)]
                                + detailEvidence
                        )
                        let signature = next.signature
                        if pathSignatures.insert(
                            signature
                        ).inserted {
                            candidates.append(next)
                            if candidates.count
                                > plan.limits
                                    .intermediateResultLimit
                                    + 1 {
                                candidates.sort(
                                    by: Self.pathSort
                                )
                                candidates.removeLast()
                            }
                        }
                    }
                }
                candidates.sort(by: Self.pathSort)
                if candidates.count
                    > plan.limits.intermediateResultLimit {
                    wasAppLimited = true
                    candidates = Array(
                        candidates.prefix(
                            plan.limits
                                .intermediateResultLimit
                        )
                    )
                }
                intermediateCounts.append(
                    candidates.count
                )
                paths = candidates
                if paths.isEmpty {
                    break traversalStages
                }
            }
            try cancellationCheck(.resultAssembly)

            let projectedNode: (PathState) -> GraphNodeSummaryDTO = {
                path in
                projection.target == .startNodes
                    ? path.start
                    : path.current
            }
            let allProjectedNodes = Self.stableUniqueNodes(
                paths.map(projectedNode),
                direction: Self.nodeSortDirection(
                    in: plan
                )
            )
            let finalLimit = plan.limits.resultLimit
            var limitedNodes = allProjectedNodes
            if limitedNodes.count > finalLimit {
                wasAppLimited = true
                limitedNodes = Array(
                    limitedNodes.prefix(finalLimit)
                )
            }
            let limitedNodeKeys = Set(
                limitedNodes.map(\.nodeKey)
            )
            let relevantPaths = paths
                .filter {
                    limitedNodeKeys.contains(
                        projectedNode($0).nodeKey
                    )
                }
                .sorted(by: Self.pathSort)

            var evidenceByID = [
                GraphEvidenceID: GraphEvidence
            ]()
            var evidenceOrder: [GraphEvidenceID] = []
            var evidenceBoundPaths: [PathState] = []
            for path in relevantPaths {
                try cancellationCheck(
                    .evidenceValidation
                )
                let uniqueEvidence =
                    GraphEvidenceCollection(
                        path.evidence
                    ).values
                let newEvidence = uniqueEvidence.filter {
                    evidenceByID[$0.id] == nil
                }
                guard evidenceOrder.count
                    + newEvidence.count
                    <= plan.limits.maximumEvidenceCount
                else {
                    wasAppLimited = true
                    continue
                }
                for item in newEvidence {
                    evidenceByID[item.id] = item
                    evidenceOrder.append(item.id)
                }
                evidenceBoundPaths.append(path)
            }
            let requestedEvidence = evidenceOrder
                .compactMap { evidenceByID[$0] }
            try cancellationCheck(
                .evidenceValidation
            )
            let validatedEvidence = try await evidenceValidator
                .validatedEvidence(
                    requestedEvidence,
                    in: plan.chatScope
                )
            try cancellationCheck(
                .evidenceValidation
            )
            let validEvidenceIDs = Set(
                validatedEvidence.map(\.id)
            )
            let completePaths = evidenceBoundPaths.filter {
                path in
                GraphEvidenceCollection(path.evidence)
                    .ids.allSatisfy {
                        validEvidenceIDs.contains($0)
                    }
            }
            if completePaths.count
                != evidenceBoundPaths.count {
                wasSourceLimited = true
            }
            let completeNodeKeys = Set(
                completePaths.map {
                    projectedNode($0).nodeKey
                }
            )
            let finalNodes = limitedNodes.filter {
                completeNodeKeys.contains($0.nodeKey)
            }
            let finalNodeKeys = Set(
                finalNodes.map(\.nodeKey)
            )
            let finalPaths = completePaths.filter {
                finalNodeKeys.contains(
                    projectedNode($0).nodeKey
                )
            }
            let usedEvidenceIDs = Set(
                finalPaths.flatMap {
                    GraphEvidenceCollection($0.evidence).ids
                }
            )
            let finalEvidence = validatedEvidence.filter {
                usedEvidenceIDs.contains($0.id)
            }
            if wasAppLimited, finalNodes.isEmpty {
                throw GraphChatToolError(
                    code: .budgetExceeded,
                    message:
                        plan.responseLanguage == .german
                        ? "Der Composable Read wurde am app-eigenen Sicherheitsbudget geschlossen beendet."
                        : "The composable read was closed safely at the app-owned budget."
                )
            }
            try await context.budget.consumeEvidence(
                finalEvidence.count
            )

            let limitReached =
                wasAppLimited || wasSourceLimited
            let limitSources:
                [GraphChatResultLimitSource] =
                    (wasAppLimited ? [.appPolicy] : [])
                    + (wasSourceLimited ? [.source] : [])
            let window = GraphChatResultWindow(
                totalCount:
                    limitReached
                    ? nil
                    : allProjectedNodes.count,
                returnedCount: finalNodes.count,
                limit: finalLimit,
                limitReached: limitReached,
                limitSources: limitSources
            )
            let pathResults = finalPaths.map {
                Self.pathResult($0)
            }
            let resultNodes = finalNodes.map { node in
                let evidenceIDs = GraphEvidenceCollection(
                    finalPaths
                        .filter {
                            projectedNode($0).nodeKey
                                == node.nodeKey
                        }
                        .flatMap(\.evidence)
                ).ids
                return GraphChatComposableReadResultNode(
                    node: node.nodeKey,
                    label: node.visibleName,
                    ownerEntityID:
                        Self.ownerEntityID(of: node)
                        ?? node.nodeKey.id,
                    evidenceIDs: evidenceIDs
                )
            }
            let resultEntity =
                projection.target == .startNodes
                ? rootEntity
                : stages.last!.stage.counterpartEntity
            let resultSet = GraphChatComposableReadResultSet(
                rootEntity: rootEntity,
                resultEntity: resultEntity,
                resultTarget: projection.target,
                nodes: resultNodes,
                paths: pathResults,
                metrics:
                    GraphChatComposableReadExecutionMetrics(
                        selectedStartNodeCount:
                            startPaths.count,
                        visitedNodeCount:
                            visitedNodes.count,
                        checkedLinkCount:
                            checkedLinkCount,
                        intermediateResultCounts:
                            intermediateCounts
                    ),
                resultWindow: window
            )
            let appliedFilters = GraphChatQueryEngine
                .appliedFilters(
                    validatedPlan
                        .validatedFilterStages
                        .flatMap(\.filters),
                    fieldMap: source.fieldsByID
                )
            let rows = resultNodes.map {
                GraphChatQueryResultRow(
                    node: $0.node,
                    label: $0.label,
                    cells: [],
                    evidenceIDs: $0.evidenceIDs
                )
            }
            let resultState:
                GraphChatResultState
            if rows.isEmpty, wasSourceLimited {
                resultState = .noEvidence
            } else if allProjectedNodes.isEmpty {
                resultState = .noResults
            } else if rows.isEmpty {
                resultState = .noEvidence
            } else {
                resultState = .success
            }
            let queryResult = GraphChatQueryResult(
                state: resultState,
                rows: rows,
                aggregation: nil,
                appliedFilters: appliedFilters,
                evidence: finalEvidence,
                resultWindow: window,
                integrityConflictedValueKeys:
                    encounteredConflictKeys
            )
            let continuation = Self.continuation(
                resultEntity: resultEntity,
                nodes: resultNodes.map(\.node),
                plan: plan
            )
            let output = GraphChatComposableReadExecutionOutput(
                resultSet: resultSet,
                queryResult: queryResult,
                continuationPlan: continuation.validated,
                continuationAction: continuation.action
            )
            try cancellationCheck(.resultAssembly)
            let toolState:
                GraphChatToolResultState
            switch resultState {
            case .success:
                toolState = .success
            case .noResults:
                toolState = .noResults
            case .noEvidence:
                toolState = .noEvidence
            }
            return GraphChatToolResult(
                state: toolState,
                payload: output,
                evidence: finalEvidence
            )
        } catch is CancellationError {
            throw GraphChatToolError.cancelled()
        }
    }

    private struct TraversalOperation {
        let id: GraphChatComposableReadStepID
        let stage: GraphChatComposableReadTraversalStage
    }

    private struct StartCandidate {
        let attribute: GraphAttributeDTO
        let filterEvidence: [GraphEvidence]
    }

    private struct TraversedLink: Hashable {
        let link: GraphLinkDTO
        let direction:
            GraphChatRelationshipConnectionDirection
        let evidenceID: GraphEvidenceID
    }

    private struct PathState: Hashable {
        let nodes: [GraphNodeSummaryDTO]
        let traversedLinks: [TraversedLink]
        let evidence: [GraphEvidence]

        var start: GraphNodeSummaryDTO { nodes[0] }
        var current: GraphNodeSummaryDTO { nodes[nodes.count - 1] }
        var visited: Set<NodeRefKey> { Set(nodes.map(\.nodeKey)) }
        var signature: String {
            let nodeKey = nodes.map {
                "\($0.kind.rawValue):\($0.nodeKey.id.uuidString)"
            }.joined(separator: ">")
            let linkKey = traversedLinks.map {
                $0.link.id.uuidString
            }.joined(separator: ">")
            return "\(nodeKey)|\(linkKey)"
        }

        func appending(
            _ node: GraphNodeSummaryDTO,
            link: TraversedLink,
            evidence newEvidence: [GraphEvidence]
        ) -> PathState {
            PathState(
                nodes: nodes + [node],
                traversedLinks:
                    traversedLinks + [link],
                evidence: evidence + newEvidence
            )
        }
    }

    private struct ObservedLink {
        let counterpart: NodeRefKey
        let direction:
            GraphChatRelationshipConnectionDirection
    }

    private struct Source {
        let attributes: [GraphAttributeDTO]
        let attributesByID: [UUID: GraphAttributeDTO]
        let nodes: [NodeRefKey: GraphNodeSummaryDTO]
        let links: [NodeRefKey: [GraphLinkDTO]]
        let fieldsByID:
            [UUID: GraphDetailFieldDefinitionDTO]
        let valuesByAttribute:
            [UUID: [UUID: GraphDetailValueDTO]]
        let conflictingValueKeys:
            Set<DetailValueAuthorityKey>

        init(snapshot: GraphSourceSnapshotDTO) {
            attributes = snapshot.attributes
            attributesByID = Dictionary(
                uniqueKeysWithValues:
                    snapshot.attributes.map {
                        ($0.id, $0)
                    }
            )
            nodes = Dictionary(
                uniqueKeysWithValues:
                    snapshot.nodeSummaries.map {
                        ($0.nodeKey, $0)
                    }
            )
            fieldsByID = Dictionary(
                uniqueKeysWithValues:
                    snapshot.detailFieldDefinitions.map {
                        ($0.id, $0)
                    }
            )
            var adjacency = [
                NodeRefKey: [UUID: GraphLinkDTO]
            ]()
            for link in snapshot.links {
                if let source = link.sourceNodeKey {
                    adjacency[source, default: [:]][link.id]
                        = link
                }
                if let target = link.targetNodeKey {
                    adjacency[target, default: [:]][link.id]
                        = link
                }
            }
            links = adjacency.mapValues {
                $0.values.sorted(by: Self.linkSort)
            }

            var values = [
                UUID: [UUID: GraphDetailValueDTO]
            ]()
            var conflicts =
                snapshot.integrityConflictedValueKeys
            for value in snapshot.detailValues.sorted(
                by: { $0.id.uuidString < $1.id.uuidString }
            ) {
                let key = DetailValueAuthorityKey(
                    graphID: snapshot.scope.graphID,
                    attributeID: value.attributeID,
                    fieldID: value.fieldID
                )
                if values[value.attributeID]?[value.fieldID]
                    != nil {
                    conflicts.insert(key)
                    values[value.attributeID]?[value.fieldID]
                        = nil
                } else if conflicts.contains(key) == false {
                    values[value.attributeID, default: [:]][value.fieldID]
                        = value
                }
            }
            valuesByAttribute = values
            conflictingValueKeys = conflicts
        }

        func conflictingKeys(
            for attribute: GraphAttributeDTO,
            filters: [GraphValidatedQueryFilter]
        ) -> Set<DetailValueAuthorityKey> {
            Set(filters.compactMap { filter in
                let key = DetailValueAuthorityKey(
                    graphID: attribute.scope.graphID,
                    attributeID: attribute.id,
                    fieldID: filter.fieldID
                )
                return conflictingValueKeys.contains(key)
                    ? key
                    : nil
            })
        }

        func filterEvidence(
            for attribute: GraphAttributeDTO,
            filters: [GraphValidatedQueryFilter]
        ) -> [GraphEvidence]? {
            guard filters.allSatisfy({ filter in
                let conflictKey = DetailValueAuthorityKey(
                    graphID: attribute.scope.graphID,
                    attributeID: attribute.id,
                    fieldID: filter.fieldID
                )
                guard conflictingValueKeys
                    .contains(conflictKey) == false else {
                    return false
                }
                return GraphChatQueryEngine.matches(
                    valuesByAttribute[attribute.id]?[filter.fieldID]?.value,
                    filter: filter
                )
            }) else {
                return nil
            }
            let row = GraphChatPreparedQueryRow(
                attribute: attribute,
                valuesByFieldID:
                    valuesByAttribute[attribute.id] ?? [:]
            )
            var seen = Set<UUID>()
            let evidence: [GraphEvidence] = filters.compactMap {
                filter -> GraphEvidence? in
                guard seen.insert(filter.fieldID).inserted,
                      let field = fieldsByID[
                        filter.fieldID
                      ] else {
                    return nil
                }
                return GraphChatQueryEngine.makeFieldEvidence(
                    row: row,
                    field: field
                )
            }
            guard evidence.count
                    == Set(filters.map(\.fieldID)).count
            else {
                return nil
            }
            return evidence
        }

        private static func linkSort(
            _ lhs: GraphLinkDTO,
            _ rhs: GraphLinkDTO
        ) -> Bool {
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func validate(
        snapshot: GraphSourceSnapshotDTO,
        plan: GraphChatComposableReadPlan
    ) throws {
        guard
            snapshot.scope == plan.graphScope,
            snapshot.graph.scope == plan.graphScope,
            snapshot.graph.id
                == plan.graphScope.graphID,
            snapshot.entities.allSatisfy({
                $0.scope == plan.graphScope
            }),
            snapshot.attributes.allSatisfy({
                $0.scope == plan.graphScope
            }),
            snapshot.links.allSatisfy({
                $0.scope == plan.graphScope
            }),
            snapshot.detailFieldDefinitions.allSatisfy({
                $0.scope == plan.graphScope
            }),
            snapshot.detailValues.allSatisfy({
                $0.scope == plan.graphScope
            }),
            snapshot.attachments.allSatisfy({
                $0.scope == plan.graphScope
            })
        else {
            throw GraphChatComposableReadExecutionError
                .graphScopeMismatch
        }

        let entityIDs = Set(snapshot.entities.map(\.id))
        let attributeIDs = Set(snapshot.attributes.map(\.id))
        let nodeKeys = Set(snapshot.nodeSummaries.map(\.nodeKey))
        let fieldIDs = Set(
            snapshot.detailFieldDefinitions.map(\.id)
        )
        guard
            entityIDs.count == snapshot.entities.count,
            attributeIDs.count == snapshot.attributes.count,
            Set(snapshot.links.map(\.id)).count
                == snapshot.links.count,
            fieldIDs.count
                == snapshot.detailFieldDefinitions.count,
            Set(snapshot.detailValues.map(\.id)).count
                == snapshot.detailValues.count,
            Set(snapshot.attachments.map(\.id)).count
                == snapshot.attachments.count
        else {
            throw GraphChatComposableReadExecutionError
                .sourceUnavailable
        }
        let entitiesByID = Dictionary(
            uniqueKeysWithValues:
                snapshot.entities.map { ($0.id, $0) }
        )
        let attributesByID = Dictionary(
            uniqueKeysWithValues:
                snapshot.attributes.map { ($0.id, $0) }
        )
        let nodesByKey = Dictionary(
            uniqueKeysWithValues:
                snapshot.nodeSummaries.map {
                    ($0.nodeKey, $0)
                }
        )
        let fieldsByID = Dictionary(
            uniqueKeysWithValues:
                snapshot.detailFieldDefinitions.map {
                    ($0.id, $0)
                }
        )
        let planEntities = plan.operations.flatMap {
            operation -> [GraphChatTypedEntityIdentity] in
                switch operation.payload {
                case .select(.entity(let reference)):
                    return reference.identity.map { [$0] }
                        ?? []
                case .traverseRelationships(let stage):
                    return [stage.counterpartEntity]
                default:
                    return []
                }
            }
        let planFields = plan.operations.flatMap {
            operation -> [GraphChatTypedFieldIdentity] in
                switch operation.payload {
                case .filter(let filter):
                    return filter.predicates.compactMap {
                        $0.field.identity
                    }
                case .traverseRelationships(let stage):
                    return stage.nodePredicates.compactMap {
                        $0.field.identity
                    }
                default:
                    return []
                }
            }
        let planNodes = plan.operations.compactMap {
            operation -> GraphChatTypedNodeIdentity? in
            guard case .traverseRelationships(let stage) =
                    operation.payload else {
                return nil
            }
            return stage.counterpartNode
        }
        guard
            snapshot.attributes.allSatisfy({
                guard let ownerEntityID =
                        $0.ownerEntityID,
                      let owner = entitiesByID[
                        ownerEntityID
                      ] else {
                    return false
                }
                return $0.ownerLabel == owner.name
                    && $0.displayLabel
                        == "\(owner.name) · \($0.name)"
            }),
            snapshot.detailFieldDefinitions.allSatisfy({
                guard let owner = entitiesByID[$0.entityID]
                else { return false }
                return $0.entityLabel == owner.name
                    && DetailFieldType(
                        rawValue: $0.typeRaw
                    ) != nil
            }),
            snapshot.detailValues.allSatisfy({
                guard
                    let attribute = attributesByID[
                        $0.attributeID
                    ],
                    let field = fieldsByID[$0.fieldID]
                else { return false }
                return attribute.ownerEntityID
                        == field.entityID
                    && $0.attributeLabel
                        == attribute.displayLabel
                    && $0.fieldName == field.name
                    && $0.fieldTypeRaw == field.typeRaw
            }),
            snapshot.integrityConflictedValueKeys
                .allSatisfy({ key in
                    guard
                        key.graphID
                            == plan.graphScope.graphID,
                        let attribute = attributesByID[
                            key.attributeID
                        ],
                        let field = fieldsByID[
                            key.fieldID
                        ]
                    else {
                        return false
                    }
                    return attribute.ownerEntityID
                        == field.entityID
                }),
            snapshot.links.allSatisfy({
                guard let source = $0.sourceNodeKey,
                      let target = $0.targetNodeKey else {
                    return false
                }
                return nodeKeys.contains(source)
                    && nodeKeys.contains(target)
            }),
            snapshot.attachments.allSatisfy({
                guard let owner = $0.ownerNodeKey else {
                    return false
                }
                return nodeKeys.contains(owner)
                    && $0.contentKind != nil
            }),
            planEntities.allSatisfy({
                entitiesByID[$0.id]?.name
                    == $0.displayName
            }),
            planFields.allSatisfy({
                guard let current = fieldsByID[$0.id]
                else { return false }
                return current.entityID
                        == $0.ownerEntityID
                    && current.name == $0.displayName
                    && current.type == $0.type
                    && current.unit == $0.unit
            }),
            planNodes.allSatisfy({
                guard let current = nodesByKey[$0.node]
                else { return false }
                return current.kind == .attribute
                    && current.ownerEntityID
                        == $0.ownerEntityID
                    && current.visibleName
                        == $0.displayName
            })
        else {
            throw GraphChatComposableReadExecutionError
                .sourceUnavailable
        }
    }

    private static func selection(
        in plan: GraphChatComposableReadPlan
    ) -> GraphChatComposableReadSelection? {
        plan.operations.compactMap {
            operation -> GraphChatComposableReadSelection? in
            guard case .select(let selection) =
                    operation.payload else {
                return nil
            }
            return selection
        }.first
    }

    private static func rootFilterOperationID(
        in plan: GraphChatComposableReadPlan
    ) -> GraphChatComposableReadStepID? {
        plan.operations.first { operation in
            if case .filter = operation.payload {
                return true
            }
            return false
        }?.id
    }

    private static func traversalOperations(
        in plan: GraphChatComposableReadPlan
    ) -> [TraversalOperation] {
        plan.operations.compactMap { operation in
            guard case .traverseRelationships(
                let stage
            ) = operation.payload else {
                return nil
            }
            return TraversalOperation(
                id: operation.id,
                stage: stage
            )
        }
    }

    private static func traversalProjection(
        in plan: GraphChatComposableReadPlan
    ) -> GraphChatComposableReadTraversalProjection? {
        plan.operations.compactMap {
            operation -> GraphChatComposableReadTraversalProjection? in
            guard case .projectTraversalNodes(
                let projection
            ) = operation.payload else {
                return nil
            }
            return projection
        }.first
    }

    private static func observedLink(
        _ link: GraphLinkDTO,
        from node: NodeRefKey,
        requested: GraphChatRelationshipDirection
    ) -> ObservedLink? {
        guard let source = link.sourceNodeKey,
              let target = link.targetNodeKey else {
            return nil
        }
        if source == node, target == node {
            return ObservedLink(
                counterpart: node,
                direction: .selfLink
            )
        }
        if source == node,
           requested == .outgoing || requested == .both {
            return ObservedLink(
                counterpart: target,
                direction: .outgoing
            )
        }
        if target == node,
           requested == .incoming || requested == .both {
            return ObservedLink(
                counterpart: source,
                direction: .incoming
            )
        }
        return nil
    }

    private static func noteMatches(
        _ note: String?,
        predicate: GraphChatRelationshipNotePredicate?
    ) -> Bool {
        guard let predicate else { return true }
        let value = note?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        switch predicate {
        case .present:
            return value.isEmpty == false
        case .missing:
            return value.isEmpty
        case .contains(let term):
            return GraphChatComposableReadTextNormalizer
                .contains(value, term: term)
        }
    }

    private static func ownerEntityID(
        of node: GraphNodeSummaryDTO
    ) -> UUID? {
        switch node.kind {
        case .entity:
            return node.nodeKey.id
        case .attribute:
            return node.ownerEntityID
        }
    }

    private static func attributeSort(
        _ lhs: GraphAttributeDTO,
        _ rhs: GraphAttributeDTO
    ) -> Bool {
        let left = BMSearch.fold(lhs.displayLabel)
        let right = BMSearch.fold(rhs.displayLabel)
        if left != right { return left < right }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func startCandidateSort(
        _ lhs: StartCandidate,
        _ rhs: StartCandidate
    ) -> Bool {
        attributeSort(lhs.attribute, rhs.attribute)
    }

    private static func pathSort(
        _ lhs: PathState,
        _ rhs: PathState
    ) -> Bool {
        let leftNodes = lhs.nodes.map {
            "\(BMSearch.fold($0.visibleName))|\($0.nodeKey.id.uuidString)"
        }.joined(separator: ">")
        let rightNodes = rhs.nodes.map {
            "\(BMSearch.fold($0.visibleName))|\($0.nodeKey.id.uuidString)"
        }.joined(separator: ">")
        if leftNodes != rightNodes {
            return leftNodes < rightNodes
        }
        let leftLinks = lhs.traversedLinks.map {
            $0.link.id.uuidString
        }.joined(separator: ">")
        let rightLinks = rhs.traversedLinks.map {
            $0.link.id.uuidString
        }.joined(separator: ">")
        return leftLinks < rightLinks
    }

    private static func stableUniqueNodes(
        _ nodes: [GraphNodeSummaryDTO],
        direction: GraphQuerySortDirection
    ) -> [GraphNodeSummaryDTO] {
        var seen = Set<NodeRefKey>()
        let sortedNodes = nodes.sorted(
            by: { lhs, rhs in
                let left = BMSearch.fold(lhs.visibleName)
                let right = BMSearch.fold(rhs.visibleName)
                if left != right {
                    if direction == .ascending {
                        return left < right
                    }
                    return left > right
                }
                return lhs.nodeKey.id.uuidString < rhs.nodeKey.id.uuidString
            }
        )
        return sortedNodes.filter {
            seen.insert($0.nodeKey).inserted
        }
    }

    private static func nodeSortDirection(
        in plan: GraphChatComposableReadPlan
    ) -> GraphQuerySortDirection {
        for operation in plan.operations {
            guard case .sort(let sort) =
                    operation.payload else {
                continue
            }
            for descriptor in sort.descriptors {
                if descriptor.key == .nodeName {
                    return descriptor.direction
                }
            }
        }
        return .ascending
    }

    private static func nodeEvidence(
        _ node: GraphNodeSummaryDTO
    ) -> GraphEvidence {
        let sourceReference: GraphSourceReference
        var fieldValues = [
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Name",
                value: .text(node.visibleName),
                unit: nil
            ),
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Anzeigename",
                value: .text(node.label),
                unit: nil
            ),
        ]
        if let ownerLabel = node.ownerLabel {
            fieldValues.append(
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Owner",
                    value: .text(ownerLabel),
                    unit: nil
                )
            )
        }
        switch node.kind {
        case .entity:
            sourceReference = GraphSourceReference(
                graphID: node.scope.graphID,
                sourceKind: .entity,
                sourceID: node.nodeKey.id,
                node: GraphSourceNodeReference(
                    kind: .entity,
                    id: node.nodeKey.id
                )
            )
        case .attribute:
            sourceReference = GraphSourceReference(
                graphID: node.scope.graphID,
                sourceKind: .attribute,
                sourceID: node.nodeKey.id,
                node: GraphSourceNodeReference(
                    kind: .attribute,
                    id: node.nodeKey.id
                ),
                owner: node.ownerEntityID.map {
                    GraphSourceNodeReference(
                        kind: .entity,
                        id: $0
                    )
                }
            )
        }
        return GraphEvidence(
            sourceReference: sourceReference,
            summary: node.label,
            fieldValues: fieldValues,
            navigationTitle: node.label,
            nodeProfileArea: .identity,
            identitySuffix: "composable-read-node"
        )
    }

    private static func linkEvidence(
        _ link: GraphLinkDTO,
        current: GraphNodeSummaryDTO,
        counterpart: GraphNodeSummaryDTO,
        direction:
            GraphChatRelationshipConnectionDirection
    ) -> GraphEvidence {
        let source = link.sourceNodeKey
            ?? current.nodeKey
        let target = link.targetNodeKey
            ?? current.nodeKey
        let sourceLabel = source == current.nodeKey
            ? current.label
            : counterpart.label
        let targetLabel = target == current.nodeKey
            ? current.label
            : counterpart.label
        let bindingDirection:
            GraphSourceLinkDirection =
                direction == .incoming
                ? .incoming
                : .outgoing
        return GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: link.scope.graphID,
                sourceKind: .link,
                sourceID: link.id,
                node: GraphSourceNodeReference(
                    kind: current.kind,
                    id: current.nodeKey.id
                ),
                linkID: link.id,
                linkBinding: GraphSourceLinkBinding(
                    linkID: link.id,
                    source: GraphSourceNodeReference(
                        kind: source.kind,
                        id: source.id
                    ),
                    target: GraphSourceNodeReference(
                        kind: target.kind,
                        id: target.id
                    ),
                    direction: bindingDirection,
                    note: link.note
                )
            ),
            summary:
                "\(sourceLabel) → \(targetLabel)",
            fieldValues: link.note.map {
                [
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Link-Notiz",
                        value: .text($0),
                        unit: nil
                    ),
                ]
            } ?? [],
            navigationTitle: current.label,
            nodeProfileArea: .connection,
            identitySuffix: "composable-read-link"
        )
    }

    private static func pathResult(
        _ path: PathState
    ) -> GraphChatComposableReadResultPath {
        let identity = GraphEvidenceStableIdentity
            .deterministicUUID(
                for: path.signature
            )
        return GraphChatComposableReadResultPath(
            id: identity,
            startNode: path.start.nodeKey,
            terminalNode: path.current.nodeKey,
            nodes: path.nodes.map(\.nodeKey),
            links: path.traversedLinks.map {
                GraphChatComposableReadResultLink(
                    id: $0.link.id,
                    source:
                        $0.link.sourceNodeKey
                        ?? path.start.nodeKey,
                    target:
                        $0.link.targetNodeKey
                        ?? path.current.nodeKey,
                    direction: $0.direction,
                    note: $0.link.note,
                    evidenceID: $0.evidenceID
                )
            },
            evidenceIDs:
                GraphEvidenceCollection(
                    path.evidence
                ).ids
        )
    }

    private static func continuation(
        resultEntity: GraphChatTypedEntityIdentity,
        nodes: [NodeRefKey],
        plan: GraphChatComposableReadPlan
    ) -> (
        validated: ValidatedGraphQueryPlan,
        action: GraphChatLocalQueryAction
    ) {
        let sortDirection = nodeSortDirection(
            in: plan
        )
        let resolvedScope: GraphResolvedQueryScope =
            .selection(nodes)
        let queryScope: GraphChatScope = {
            guard nodes.isEmpty == false else {
                return .entity(
                    resultEntity.id,
                    in: plan.graphScope
                )
            }
            return (try? .selection(
                nodes,
                in: plan.graphScope
            )) ?? .entity(
                resultEntity.id,
                in: plan.graphScope
            )
        }()
        let raw = GraphQueryPlan(
            version: plan.queryPlanVersion,
            entityAlias: resultEntity.alias,
            scope: queryScope,
            filters: [],
            sorting: [
                GraphQuerySort(
                    key: .nodeName,
                    direction: sortDirection
                ),
            ],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: plan.limits.resultLimit
        )
        return (
            ValidatedGraphQueryPlan(
                version: plan.queryPlanVersion,
                graphScope: plan.graphScope,
                entityID: resultEntity.id,
                scope: resolvedScope,
                filters: [],
                sorting: [
                    GraphValidatedQuerySort(
                        key: .nodeName,
                        direction: sortDirection
                    ),
                ],
                projection: [.nodeIdentity],
                aggregation: nil,
                limit: plan.limits.resultLimit
            ),
            GraphChatLocalQueryAction(
                plan: raw,
                resultContract: .compiledCollection,
                compilationReferenceDate:
                    plan.queryReferenceDate
            )
        )
    }
}
