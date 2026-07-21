//
//  DescribeGraphSchemaTool.swift
//  BrainMesh
//
//  Read-only access to the compact graph schema snapshot.
//

import Foundation

nonisolated protocol GraphSchemaSnapshotProviding: Sendable {
    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) async throws -> GraphSchemaContext
}

extension GraphSchemaService: GraphSchemaSnapshotProviding {}

nonisolated struct DescribeGraphSchemaInput: Sendable {
    let exampleFieldIDs: Set<UUID>

    init(exampleFieldIDs: Set<UUID> = []) {
        self.exampleFieldIDs = exampleFieldIDs
    }
}

nonisolated struct DescribeGraphSchemaOutput: Sendable {
    let snapshot: GraphSchemaSnapshot
}

nonisolated struct DescribeGraphSchemaTool: GraphChatTool {
    let kind = GraphChatToolKind.describeGraphSchema

    private let schemaService: any GraphSchemaSnapshotProviding
    private let evidenceValidator: any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        schemaService: any GraphSchemaSnapshotProviding = GraphSchemaService.shared,
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        logger: any GraphChatToolLogging = GraphChatTechnicalLogger()
    ) {
        self.schemaService = schemaService
        self.evidenceValidator = evidenceValidator
        self.logger = logger
    }

    func execute(
        _ input: DescribeGraphSchemaInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<DescribeGraphSchemaOutput> {
        let timer = GraphChatToolTimer()
        do {
            _ = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: 1,
                toolMaximumResultCount: 1
            )
            try Task.checkCancellation()
            let schemaContext = try await schemaService.makeSnapshot(
                in: context.scope.graphScope,
                exampleFieldIDs: input.exampleFieldIDs
            )
            guard schemaContext.graphScope == context.scope.graphScope else {
                throw GraphChatToolError(
                    code: .graphScopeMismatch,
                    message: "Das Schema gehört nicht zum aktiven Graphen."
                )
            }

            let graphEvidence = GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: context.scope.graphScope.graphID,
                    sourceKind: .graph,
                    sourceID: context.scope.graphScope.graphID
                ),
                summary: "Schema von \(schemaContext.snapshot.graphName)",
                identitySuffix: "schema-v\(schemaContext.snapshot.version)"
            )
            let evidence = try await evidenceValidator.validatedEvidence(
                [graphEvidence],
                in: context.scope
            )
            try await context.budget.consumeEvidence(evidence.count)
            logger.record(
                timer.metric(
                    tool: kind,
                    resultCount: schemaContext.snapshot.entities.count,
                    wasCancelled: false
                )
            )
            guard evidence.isEmpty == false else {
                return .noEvidence()
            }
            return .success(
                DescribeGraphSchemaOutput(snapshot: schemaContext.snapshot),
                evidence: evidence
            )
        } catch is CancellationError {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: true))
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
            throw error
        }
    }
}
