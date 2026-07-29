//
//  GraphStatsTool.swift
//  BrainMesh
//
//  Read-only chat projection of the existing GraphStatsService results.
//

import Foundation
import SwiftData

nonisolated struct GraphChatStatsSnapshot: Sendable {
    let counts: GraphCounts
    let structure: GraphStructureSnapshot
    let health: GraphHealthSnapshot
}

nonisolated protocol GraphChatStatsReading: Sendable {
    func snapshot(in scope: GraphScope) async throws -> GraphChatStatsSnapshot
}

nonisolated struct GraphStatsServiceReader: GraphChatStatsReading {
    private let container: AnyModelContainer

    init(container: AnyModelContainer) {
        self.container = container
    }

    func snapshot(in scope: GraphScope) async throws -> GraphChatStatsSnapshot {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) { [container, scope] in
            let context = ModelContext(container.container)
            context.autosaveEnabled = false
            let service = GraphStatsService(context: context)
            let counts = try service.counts(for: scope.graphID)
            try Task.checkCancellation()
            let structure = try service.structureSnapshot(for: scope.graphID)
            try Task.checkCancellation()
            let media = try service.mediaSnapshot(for: scope.graphID)
            try Task.checkCancellation()
            let health = try service.healthSnapshot(
                for: scope.graphID,
                counts: counts,
                structure: structure,
                media: media
            )
            return GraphChatStatsSnapshot(
                counts: counts,
                structure: structure,
                health: health
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated struct GraphStatsInput: Sendable {
    let hubLimit: Int

    init(
        hubLimit: Int =
            GraphChatIntentLimitPolicy
                .default.graphHubCount
    ) {
        self.hubLimit = hubLimit
    }
}

nonisolated struct GraphChatStatsCounts: Hashable, Sendable {
    let entities: Int
    let attributes: Int
    let links: Int
    let notes: Int
    let attachments: Int
    let images: Int
    let attachmentBytes: Int64
}

nonisolated struct GraphChatStatsHub: Hashable, Sendable, Identifiable {
    let node: NodeRefKey
    let label: String
    let degree: Int
    let evidenceID: GraphEvidenceID

    var id: NodeRefKey {
        node
    }
}

nonisolated struct GraphStatsOutput: Sendable {
    let counts: GraphChatStatsCounts
    let nodeCount: Int
    let linkCount: Int
    let isolatedNodeCount: Int
    let hubs: [GraphChatStatsHub]
    let healthScore: Int
    let healthIssueCount: Int
    let evidenceIDs: [GraphEvidenceID]
    let hubWindow: GraphChatResultWindow

    init(
        counts: GraphChatStatsCounts,
        nodeCount: Int,
        linkCount: Int,
        isolatedNodeCount: Int,
        hubs: [GraphChatStatsHub],
        healthScore: Int,
        healthIssueCount: Int,
        evidenceIDs: [GraphEvidenceID],
        hubWindow: GraphChatResultWindow? = nil
    ) {
        self.counts = counts
        self.nodeCount = nodeCount
        self.linkCount = linkCount
        self.isolatedNodeCount = isolatedNodeCount
        self.hubs = hubs
        self.healthScore = healthScore
        self.healthIssueCount = healthIssueCount
        self.evidenceIDs = evidenceIDs
        self.hubWindow = hubWindow ?? .complete(totalCount: hubs.count)
    }
}

nonisolated struct GraphStatsTool: GraphChatTool {
    let kind = GraphChatToolKind.graphStats
    static let maximumHubCount =
        GraphChatIntentLimitPolicy
            .default.maximumGraphHubCount

    private let reader: any GraphChatStatsReading
    private let evidenceValidator: any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        reader: any GraphChatStatsReading,
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        logger: any GraphChatToolLogging = GraphChatTechnicalLogger()
    ) {
        self.reader = reader
        self.evidenceValidator = evidenceValidator
        self.logger = logger
    }

    func execute(
        _ input: GraphStatsInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GraphStatsOutput> {
        let timer = GraphChatToolTimer()
        do {
            guard (0...Self.maximumHubCount).contains(input.hubLimit) else {
                throw GraphChatToolError(
                    code: .budgetExceeded,
                    message: "GraphStats erlaubt höchstens \(Self.maximumHubCount) Detailergebnisse."
                )
            }
            guard context.scope
                    == GraphChatScope.entireGraph(
                        context.scope.graphScope
                    )
            else {
                throw GraphChatToolError(
                    code: .invalidInput,
                    message: "GraphStats kann nur für den gesamten aktiven Graphen ausgeführt werden."
                )
            }
            let totalResultLimit = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: input.hubLimit + 1,
                toolMaximumResultCount: Self.maximumHubCount + 1
            )
            let hubLimit = totalResultLimit - 1
            try Task.checkCancellation()
            let snapshot = try await reader.snapshot(in: context.scope.graphScope)
            try Task.checkCancellation()
            guard snapshot.health.graphID == context.scope.graphScope.graphID else {
                throw GraphChatToolError(
                    code: .graphScopeMismatch,
                    message: "Die Statistikdaten gehören nicht zum aktiven Graphen."
                )
            }

            let graphEvidence = makeGraphEvidence(
                graphID: context.scope.graphScope.graphID,
                snapshot: snapshot
            )
            var evidence = [graphEvidence]
            var hubs: [GraphChatStatsHub] = []
            for hub in snapshot.structure.topHubs.prefix(hubLimit) {
                try Task.checkCancellation()
                let node = NodeRefKey(kind: hub.kind, id: hub.id)
                let itemEvidence = GraphEvidence(
                    sourceReference: GraphSourceReference(
                        graphID: context.scope.graphScope.graphID,
                        sourceKind: hub.kind == .entity ? .entity : .attribute,
                        sourceID: hub.id,
                        node: GraphSourceNodeReference(kind: hub.kind, id: hub.id)
                    ),
                    summary: "\(hub.label): \(hub.degree) direkte Verbindungen",
                    fieldValues: [
                        GraphEvidenceFieldValue(
                            fieldID: nil,
                            fieldName: "Direkte Verbindungen",
                            value: .integer(hub.degree),
                            unit: nil
                        )
                    ],
                    navigationTitle: hub.label,
                    identitySuffix: "stats-hub"
                )
                evidence.append(itemEvidence)
                hubs.append(
                    GraphChatStatsHub(
                        node: node,
                        label: hub.label,
                        degree: hub.degree,
                        evidenceID: itemEvidence.id
                    )
                )
            }

            let validatedEvidence = try await evidenceValidator.validatedEvidence(
                GraphEvidenceCollection(evidence).values,
                in: context.scope
            )
            let validIDs = Set(validatedEvidence.map(\.id))
            guard validIDs.contains(graphEvidence.id) else {
                logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
                return .noEvidence()
            }
            let validHubs = hubs.filter { validIDs.contains($0.evidenceID) }
            let totalHubCount = max(
                0,
                snapshot.structure.nodeCount - snapshot.structure.isolatedNodeCount
            )
            let evidenceLimited = validHubs.count < hubs.count
            let toolLimitReached = totalHubCount > hubLimit
            let sourceLimitReached =
                snapshot.structure.topHubs.count < min(totalHubCount, hubLimit)
            let output = GraphStatsOutput(
                counts: GraphChatStatsCounts(
                    entities: snapshot.counts.entities,
                    attributes: snapshot.counts.attributes,
                    links: snapshot.counts.links,
                    notes: snapshot.counts.notes,
                    attachments: snapshot.counts.attachments,
                    images: snapshot.counts.images,
                    attachmentBytes: snapshot.counts.attachmentBytes
                ),
                nodeCount: snapshot.structure.nodeCount,
                linkCount: snapshot.structure.linkCount,
                isolatedNodeCount: snapshot.structure.isolatedNodeCount,
                hubs: validHubs,
                healthScore: snapshot.health.score.value,
                healthIssueCount: snapshot.health.issues.count,
                evidenceIDs: [graphEvidence.id] + validHubs.map(\.evidenceID),
                hubWindow: GraphChatResultWindow(
                    totalCount: evidenceLimited ? nil : totalHubCount,
                    returnedCount: validHubs.count,
                    limit: hubLimit,
                    limitReached: toolLimitReached || sourceLimitReached || evidenceLimited,
                    limitSources: (toolLimitReached ? [.tool] : [])
                        + (sourceLimitReached || evidenceLimited ? [.source] : [])
                )
            )
            try await context.budget.consumeEvidence(validatedEvidence.count)
            let resultCount = 1 + validHubs.count
            logger.record(timer.metric(tool: kind, resultCount: resultCount, wasCancelled: false))
            return .success(output, evidence: validatedEvidence)
        } catch is CancellationError {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: true))
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
            throw error
        }
    }

    private func makeGraphEvidence(
        graphID: UUID,
        snapshot: GraphChatStatsSnapshot
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: .graph,
                sourceID: graphID
            ),
            summary: "Graph-Statistik",
            fieldValues: [
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Entities", value: .integer(snapshot.counts.entities), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Attributes", value: .integer(snapshot.counts.attributes), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Links", value: .integer(snapshot.counts.links), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Notizen", value: .integer(snapshot.counts.notes), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Attachments", value: .integer(snapshot.counts.attachments), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Bilder", value: .integer(snapshot.counts.images), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Attachment-Größe", value: .integer(Int(clamping: snapshot.counts.attachmentBytes)), unit: "Bytes"),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Nodes", value: .integer(snapshot.structure.nodeCount), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Struktur-Links", value: .integer(snapshot.structure.linkCount), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Isolierte Nodes", value: .integer(snapshot.structure.isolatedNodeCount), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Health Score", value: .integer(snapshot.health.score.value), unit: nil),
                GraphEvidenceFieldValue(fieldID: nil, fieldName: "Health Issues", value: .integer(snapshot.health.issues.count), unit: nil)
            ],
            navigationTitle: "Graph",
            identitySuffix: "graph-stats"
        )
    }
}
