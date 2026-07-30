//
//  GetNeighborsTool.swift
//  BrainMesh
//
//  Direct incoming and outgoing graph neighbors only.
//

import Foundation

nonisolated protocol GraphChatNeighborhoodReading: Sendable {
    func directNeighborhood(
        of nodeKey: NodeRefKey,
        in scope: GraphScope
    ) async throws -> GraphDirectNeighborhoodDTO?
}

extension NodeRepository: GraphChatNeighborhoodReading {}

nonisolated struct GetNeighborsInput: Sendable {
    let node: NodeRefKey
    let limit: Int

    init(
        node: NodeRefKey,
        limit: Int =
            GraphChatIntentLimitPolicy
                .default.nodeDetailRelatedItemCount
    ) {
        self.node = node
        self.limit = limit
    }
}

nonisolated struct GraphChatNeighborConnection: Hashable, Sendable, Identifiable {
    let id: UUID
    let direction: GraphChatLinkDirection
    let neighbor: NodeRefKey
    let neighborLabel: String
    let note: String?
    let evidenceID: GraphEvidenceID
}

nonisolated struct GetNeighborsOutput: Sendable {
    let center: GraphNodeSummaryDTO
    let connections: [GraphChatNeighborConnection]
    let evidenceIDs: [GraphEvidenceID]
    let resultWindow: GraphChatResultWindow

    init(
        center: GraphNodeSummaryDTO,
        connections: [GraphChatNeighborConnection],
        evidenceIDs: [GraphEvidenceID],
        resultWindow: GraphChatResultWindow? = nil
    ) {
        self.center = center
        self.connections = connections
        self.evidenceIDs = evidenceIDs
        self.resultWindow = resultWindow ?? .complete(totalCount: connections.count)
    }
}

nonisolated struct GetNeighborsTool: GraphChatTool {
    let kind = GraphChatToolKind.getNeighbors
    static let maximumNeighborCount =
        GraphChatIntentLimitPolicy
            .default.maximumNeighborCount

    private let repository: any GraphChatNeighborhoodReading
    private let evidenceValidator: any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        repository: any GraphChatNeighborhoodReading = NodeRepository.shared,
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        logger: any GraphChatToolLogging = GraphChatTechnicalLogger()
    ) {
        self.repository = repository
        self.evidenceValidator = evidenceValidator
        self.logger = logger
    }

    func execute(
        _ input: GetNeighborsInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GetNeighborsOutput> {
        let timer = GraphChatToolTimer()
        do {
            guard (0...Self.maximumNeighborCount).contains(input.limit) else {
                throw GraphChatToolError(
                    code: .budgetExceeded,
                    message: "GetNeighbors erlaubt höchstens \(Self.maximumNeighborCount) Detailergebnisse."
                )
            }
            let totalResultLimit = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: input.limit + 1,
                toolMaximumResultCount: Self.maximumNeighborCount + 1
            )
            let limit = totalResultLimit - 1
            try Task.checkCancellation()
            guard let neighborhood = try await repository.directNeighborhood(
                of: input.node,
                in: context.scope.graphScope
            ), neighborhood.scope == context.scope.graphScope else {
                logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
                return .noResults()
            }

            let centerEvidence = GraphEvidence(
                sourceReference: Self.nodeSourceReference(neighborhood.center),
                summary: neighborhood.center.label,
                navigationTitle: neighborhood.center.label,
                identitySuffix: "neighbor-center"
            )
            var evidence = [centerEvidence]
            var connections: [GraphChatNeighborConnection] = []

            let outgoing = neighborhood.outgoingLinks.sorted(by: Self.linkSort)
            let incoming = neighborhood.incomingLinks.sorted(by: Self.linkSort)
            let eligibleConnectionCount = outgoing.reduce(into: 0) { count, link in
                if let target = link.targetNodeKey, target != input.node {
                    count += 1
                }
            } + incoming.reduce(into: 0) { count, link in
                if let source = link.sourceNodeKey, source != input.node {
                    count += 1
                }
            }
            for link in outgoing {
                try Task.checkCancellation()
                guard connections.count < limit,
                      let source = link.sourceNodeKey,
                      let target = link.targetNodeKey,
                      source == input.node,
                      target != input.node else {
                    continue
                }
                let itemEvidence = Self.linkEvidence(
                    link,
                    center: input.node,
                    centerLabel: neighborhood.center.label,
                    direction: .outgoing
                )
                evidence.append(itemEvidence)
                connections.append(
                    GraphChatNeighborConnection(
                        id: link.id,
                        direction: .outgoing,
                        neighbor: target,
                        neighborLabel: link.targetLabel,
                        note: link.note,
                        evidenceID: itemEvidence.id
                    )
                )
            }

            if connections.count < limit {
                for link in incoming {
                    try Task.checkCancellation()
                    guard connections.count < limit,
                          let source = link.sourceNodeKey,
                          let target = link.targetNodeKey,
                          target == input.node,
                          source != input.node else {
                        continue
                    }
                    let itemEvidence = Self.linkEvidence(
                        link,
                        center: input.node,
                        centerLabel: neighborhood.center.label,
                        direction: .incoming
                    )
                    evidence.append(itemEvidence)
                    connections.append(
                        GraphChatNeighborConnection(
                            id: link.id,
                            direction: .incoming,
                            neighbor: source,
                            neighborLabel: link.sourceLabel,
                            note: link.note,
                            evidenceID: itemEvidence.id
                        )
                    )
                }
            }

            let validatedEvidence = try await evidenceValidator.validatedEvidence(
                evidence,
                in: context.scope
            )
            let validIDs = Set(validatedEvidence.map(\.id))
            guard validIDs.contains(centerEvidence.id) else {
                logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
                return .noEvidence()
            }
            let validatedConnections = connections.filter {
                validIDs.contains($0.evidenceID)
            }
            try await context.budget.consumeEvidence(validatedEvidence.count)
            logger.record(
                timer.metric(
                    tool: kind,
                    resultCount: validatedConnections.count,
                    wasCancelled: false
                )
            )
            let output = GetNeighborsOutput(
                center: neighborhood.center,
                connections: validatedConnections,
                evidenceIDs: validatedEvidence.map(\.id),
                resultWindow: GraphChatResultWindow(
                    totalCount: validatedConnections.count == connections.count
                        ? eligibleConnectionCount
                        : nil,
                    returnedCount: validatedConnections.count,
                    limit: limit,
                    limitReached: eligibleConnectionCount > limit
                        || validatedConnections.count < connections.count,
                    limitSources: (eligibleConnectionCount > limit ? [.tool] : [])
                        + (validatedConnections.count < connections.count ? [.source] : [])
                )
            )
            if validatedConnections.isEmpty {
                return GraphChatToolResult(
                    state: .noResults,
                    payload: output,
                    evidence: validatedEvidence
                )
            }
            return .success(output, evidence: validatedEvidence)
        } catch is CancellationError {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: true))
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
            throw error
        }
    }

    private static func nodeSourceReference(
        _ node: GraphNodeSummaryDTO
    ) -> GraphSourceReference {
        switch node.kind {
        case .entity:
            return GraphSourceReference(
                graphID: node.scope.graphID,
                sourceKind: .entity,
                sourceID: node.nodeKey.id,
                node: GraphSourceNodeReference(kind: .entity, id: node.nodeKey.id)
            )
        case .attribute:
            return GraphSourceReference(
                graphID: node.scope.graphID,
                sourceKind: .attribute,
                sourceID: node.nodeKey.id,
                node: GraphSourceNodeReference(kind: .attribute, id: node.nodeKey.id),
                owner: node.ownerEntityID.map {
                    GraphSourceNodeReference(kind: .entity, id: $0)
                }
            )
        }
    }

    private static func linkEvidence(
        _ link: GraphLinkDTO,
        center: NodeRefKey,
        centerLabel: String,
        direction: GraphChatLinkDirection
    ) -> GraphEvidence {
        let source = link.sourceNodeKey
            ?? center
        let target = link.targetNodeKey
            ?? center
        return GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: link.scope.graphID,
                sourceKind: .link,
                sourceID: link.id,
                node: GraphSourceNodeReference(kind: center.kind, id: center.id),
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
                            direction == .outgoing
                            ? .outgoing
                            : .incoming,
                        note: link.note
                    )
            ),
            summary: "\(link.sourceLabel) → \(link.targetLabel)",
            fieldValues: link.note.map {
                [
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Link-Notiz",
                        value: .text($0),
                        unit: nil
                    )
                ]
            } ?? [],
            navigationTitle: centerLabel,
            identitySuffix: "direct-neighbor"
        )
    }

    private static func linkSort(
        _ lhs: GraphLinkDTO,
        _ rhs: GraphLinkDTO
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
