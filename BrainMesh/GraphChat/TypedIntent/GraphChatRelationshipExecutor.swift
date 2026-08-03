//
//  GraphChatRelationshipExecutor.swift
//  BrainMesh
//
//  Provider-free execution of direct graph relationships. All semantic
//  filters are applied to the complete direct neighborhood before limiting.
//

import Foundation

nonisolated enum GraphChatRelationshipConnectionDirection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case incoming
    case outgoing
    case selfLink
}

nonisolated struct GraphChatRelationshipConnection:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let createdAt: Date
    let direction:
        GraphChatRelationshipConnectionDirection
    let source: NodeRefKey
    let sourceLabel: String
    let target: NodeRefKey
    let targetLabel: String
    let counterpart: GraphNodeSummaryDTO
    let note: String?
    let evidenceID: GraphEvidenceID
}

nonisolated struct GraphChatRelationshipOutput:
    Hashable,
    Sendable
{
    let center: GraphNodeSummaryDTO
    let centerEvidenceID: GraphEvidenceID
    let connections: [GraphChatRelationshipConnection]
    let evidenceIDs: [GraphEvidenceID]
    let resultWindow: GraphChatResultWindow
}

nonisolated struct GraphChatRelationshipExecutor:
    GraphChatLocalIntentRelationshipExecuting
{
    private let repository:
        any GraphChatNeighborhoodReading
    private let evidenceValidator:
        any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        repository:
            any GraphChatNeighborhoodReading =
                NodeRepository.shared,
        evidenceValidator:
            any GraphEvidenceValidating =
                GraphEvidenceSourceValidator.shared,
        logger:
            any GraphChatToolLogging =
                GraphChatTechnicalLogger()
    ) {
        self.repository = repository
        self.evidenceValidator = evidenceValidator
        self.logger = logger
    }

    func execute(
        _ plan: GraphChatRelationshipPlan,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<GraphChatRelationshipOutput>
    {
        let timer = GraphChatToolTimer()
        do {
            guard context.scope == plan.queryScope,
                  context.scope.graphScope
                    == plan.graphScope else {
                throw GraphChatToolError(
                    code: .graphScopeMismatch,
                    message:
                        "Der Relationship-Executor wurde mit einem abweichenden Scope aufgerufen."
                )
            }
            let requestedEvidenceCount =
                plan.limits.resultLimit + 1
            let totalResultLimit =
                try await context.budget.beginCall(
                tool: .getNeighbors,
                requestedResultCount:
                    requestedEvidenceCount,
                toolMaximumResultCount:
                    plan.limits.maximumResultLimit + 1
            )
            let effectiveResultLimit = max(
                0,
                min(
                    plan.limits.resultLimit,
                    totalResultLimit - 1
                )
            )
            try Task.checkCancellation()
            guard let neighborhood =
                    try await repository
                        .directNeighborhood(
                            of:
                                plan.centerNode.node,
                            in: plan.graphScope
                        ),
                  neighborhood.scope
                    == plan.graphScope,
                  neighborhood.center.nodeKey
                    == plan.centerNode.node,
                  Self.ownerEntityID(
                    of: neighborhood.center
                  ) == plan.centerEntity.id
            else {
                logger.record(
                    timer.metric(
                        tool: .getNeighbors,
                        resultCount: 0,
                        wasCancelled: false
                    )
                )
                return .noResults()
            }

            let centerEvidence =
                Self.nodeEvidence(
                    neighborhood.center
                )
            let eligible = try Self
                .eligibleConnections(
                    in: neighborhood,
                    plan: plan
                )
            let limited = Array(
                eligible.prefix(
                    effectiveResultLimit
                )
            )
            let provisional = limited.map {
                candidate in
                let evidence = Self.linkEvidence(
                    candidate.link,
                    center:
                        neighborhood.center,
                    direction:
                        candidate.direction
                )
                return (
                    connection:
                        GraphChatRelationshipConnection(
                            id: candidate.link.id,
                            createdAt:
                                candidate.link.createdAt,
                            direction:
                                candidate.direction,
                            source: candidate.source,
                            sourceLabel:
                                candidate.link.sourceLabel,
                            target: candidate.target,
                            targetLabel:
                                candidate.link.targetLabel,
                            counterpart:
                                candidate.counterpart,
                            note: candidate.link.note,
                            evidenceID: evidence.id
                        ),
                    evidence: evidence
                )
            }
            let requestedEvidence =
                [centerEvidence]
                + provisional.map(\.evidence)
            let validatedEvidence =
                try await evidenceValidator
                    .validatedEvidence(
                        requestedEvidence,
                        in: plan.queryScope
                    )
            let validEvidenceIDs = Set(
                validatedEvidence.map(\.id)
            )
            guard validEvidenceIDs.contains(
                centerEvidence.id
            ) else {
                logger.record(
                    timer.metric(
                        tool: .getNeighbors,
                        resultCount: 0,
                        wasCancelled: false
                    )
                )
                return .noEvidence()
            }
            let connections = provisional
                .filter {
                    validEvidenceIDs.contains(
                        $0.connection.evidenceID
                    )
                }
                .map(\.connection)
            try await context.budget.consumeEvidence(
                validatedEvidence.count
            )
            let lostEvidence =
                connections.count
                    != provisional.count
            let wasLimited =
                eligible.count > effectiveResultLimit
            let resultWindow =
                GraphChatResultWindow(
                    totalCount:
                        lostEvidence
                        ? nil
                        : eligible.count,
                    returnedCount:
                        connections.count,
                    limit:
                        effectiveResultLimit,
                    limitReached:
                        wasLimited
                        || lostEvidence,
                    limitSources:
                        (wasLimited
                            ? [.tool]
                            : [])
                        + (lostEvidence
                            ? [.source]
                            : [])
                )
            let output =
                GraphChatRelationshipOutput(
                    center:
                        neighborhood.center,
                    centerEvidenceID:
                        centerEvidence.id,
                    connections: connections,
                    evidenceIDs:
                        validatedEvidence.map(\.id),
                    resultWindow:
                        resultWindow
                )
            logger.record(
                timer.metric(
                    tool: .getNeighbors,
                    resultCount:
                        connections.count,
                    wasCancelled: false
                )
            )
            if connections.isEmpty {
                return GraphChatToolResult(
                    state: .noResults,
                    payload: output,
                    evidence: validatedEvidence
                )
            }
            return .success(
                output,
                evidence: validatedEvidence
            )
        } catch is CancellationError {
            logger.record(
                timer.metric(
                    tool: .getNeighbors,
                    resultCount: 0,
                    wasCancelled: true
                )
            )
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(
                timer.metric(
                    tool: .getNeighbors,
                    resultCount: 0,
                    wasCancelled: false
                )
            )
            throw error
        }
    }

    private struct Candidate: Hashable {
        let link: GraphLinkDTO
        let source: NodeRefKey
        let target: NodeRefKey
        let direction:
            GraphChatRelationshipConnectionDirection
        let counterpart: GraphNodeSummaryDTO
    }

    private static func eligibleConnections(
        in neighborhood: GraphDirectNeighborhoodDTO,
        plan: GraphChatRelationshipPlan
    ) throws -> [Candidate] {
        try Task.checkCancellation()
        let center = neighborhood.center.nodeKey
        let summaries = (
            neighborhood.neighbors
            + [neighborhood.center]
        ).reduce(
            into: [NodeRefKey: GraphNodeSummaryDTO]()
        ) { partial, node in
            partial[node.nodeKey] = node
        }
        var byLinkID = [UUID: Candidate]()

        func consider(
            _ link: GraphLinkDTO,
            observedDirection:
                GraphChatRelationshipConnectionDirection
        ) {
            guard link.scope == plan.graphScope,
                  let source = link.sourceNodeKey,
                  let target = link.targetNodeKey else {
                return
            }
            let isOutgoing = source == center
            let isIncoming = target == center
            guard isOutgoing || isIncoming else {
                return
            }
            let direction:
                GraphChatRelationshipConnectionDirection
            let counterpartKey: NodeRefKey
            if source == center, target == center {
                direction = .selfLink
                counterpartKey = center
            } else if observedDirection == .outgoing,
                      isOutgoing {
                direction = .outgoing
                counterpartKey = target
            } else if observedDirection == .incoming,
                      isIncoming {
                direction = .incoming
                counterpartKey = source
            } else {
                return
            }
            guard let counterpart =
                    summaries[counterpartKey],
                  counterpart.scope
                    == plan.graphScope,
                  counterpart.nodeKey
                    == counterpartKey,
                  ownerEntityID(
                    of: counterpart
                  ) != nil,
                  directionMatches(
                    direction,
                    requested: plan.direction
                  ),
                  counterpartMatches(
                    counterpart,
                    plan: plan
                  ),
                  noteMatches(
                    link.note,
                    predicate:
                        plan.notePredicate
                  )
            else {
                return
            }
            let candidate = Candidate(
                link: link,
                source: source,
                target: target,
                direction: direction,
                counterpart: counterpart
            )
            if let existing = byLinkID[link.id] {
                if existing.direction
                    != .selfLink,
                   direction == .selfLink {
                    byLinkID[link.id] = candidate
                }
            } else {
                byLinkID[link.id] = candidate
            }
        }

        for link in neighborhood.outgoingLinks {
            try Task.checkCancellation()
            consider(
                link,
                observedDirection: .outgoing
            )
        }
        for link in neighborhood.incomingLinks {
            try Task.checkCancellation()
            consider(
                link,
                observedDirection: .incoming
            )
        }
        return byLinkID.values.sorted(
            by: candidateSort
        )
    }

    private static func directionMatches(
        _ direction:
            GraphChatRelationshipConnectionDirection,
        requested:
            GraphChatRelationshipDirection
    ) -> Bool {
        if direction == .selfLink {
            return true
        }
        switch requested {
        case .incoming:
            return direction == .incoming
        case .outgoing:
            return direction == .outgoing
        case .both:
            return true
        }
    }

    private static func counterpartMatches(
        _ counterpart: GraphNodeSummaryDTO,
        plan: GraphChatRelationshipPlan
    ) -> Bool {
        if let counterpartNode =
                plan.counterpartNode,
           counterpart.nodeKey
                != counterpartNode.node {
            return false
        }
        if let counterpartEntity =
                plan.counterpartEntity,
           ownerEntityID(of: counterpart)
                != counterpartEntity.id {
            return false
        }
        return true
    }

    private static func noteMatches(
        _ note: String?,
        predicate:
            GraphChatRelationshipNotePredicate?
    ) -> Bool {
        guard let predicate else {
            return true
        }
        let normalized = note?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
        switch predicate {
        case .present:
            return normalized.isEmpty == false
        case .missing:
            return normalized.isEmpty
        case .contains(let term):
            return GraphChatComposableReadTextNormalizer
                .contains(
                    normalized,
                    term: term
                )
        }
    }

    private static func candidateSort(
        _ lhs: Candidate,
        _ rhs: Candidate
    ) -> Bool {
        let leftLabel = folded(
            lhs.counterpart.label
        )
        let rightLabel = folded(
            rhs.counterpart.label
        )
        if leftLabel != rightLabel {
            return leftLabel < rightLabel
        }
        if lhs.counterpart.kind.rawValue
            != rhs.counterpart.kind.rawValue {
            return lhs.counterpart.kind.rawValue < rhs.counterpart.kind.rawValue
        }
        if lhs.counterpart.nodeKey.id
            != rhs.counterpart.nodeKey.id {
            return lhs.counterpart.nodeKey.id.uuidString < rhs.counterpart.nodeKey.id.uuidString
        }
        if lhs.direction.rawValue
            != rhs.direction.rawValue {
            return lhs.direction.rawValue < rhs.direction.rawValue
        }
        if lhs.link.createdAt
            != rhs.link.createdAt {
            return lhs.link.createdAt < rhs.link.createdAt
        }
        return lhs.link.id.uuidString < rhs.link.id.uuidString
    }

    private static func folded(
        _ value: String
    ) -> String {
        value.folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive,
            ],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
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

    private static func nodeEvidence(
        _ node: GraphNodeSummaryDTO
    ) -> GraphEvidence {
        let sourceReference: GraphSourceReference
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
            navigationTitle: node.label,
            identitySuffix:
                "relationship-center"
        )
    }

    private static func linkEvidence(
        _ link: GraphLinkDTO,
        center: GraphNodeSummaryDTO,
        direction:
            GraphChatRelationshipConnectionDirection
    ) -> GraphEvidence {
        let source = link.sourceNodeKey
            ?? center.nodeKey
        let target = link.targetNodeKey
            ?? center.nodeKey
        let bindingDirection:
            GraphSourceLinkDirection =
            direction == .incoming
            ? .incoming
            : .outgoing
        return GraphEvidence(
            sourceReference:
                GraphSourceReference(
                    graphID: link.scope.graphID,
                    sourceKind: .link,
                    sourceID: link.id,
                    node:
                        GraphSourceNodeReference(
                            kind:
                                center.nodeKey.kind,
                            id:
                                center.nodeKey.id
                        ),
                    linkID: link.id,
                    linkBinding:
                        GraphSourceLinkBinding(
                            linkID: link.id,
                            source:
                                GraphSourceNodeReference(
                                    kind: source.kind,
                                    id: source.id
                                ),
                            target:
                                GraphSourceNodeReference(
                                    kind: target.kind,
                                    id: target.id
                                ),
                            direction:
                                bindingDirection,
                            note: link.note
                        )
                ),
            summary:
                "\(link.sourceLabel) → \(link.targetLabel)",
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
            navigationTitle:
                center.label,
            identitySuffix:
                "relationship-direct-link"
        )
    }
}
