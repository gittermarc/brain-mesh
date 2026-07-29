//
//  GraphChatModelToolRuntime.swift
//  BrainMesh
//
//  Compact, provider-independent adapters around the deterministic read-only tools.
//

import Foundation
import SwiftData

nonisolated struct GraphChatModelToolRuntimeFactory: GraphChatModelToolRunnerFactory {
    private let describeSchemaTool: DescribeGraphSchemaTool
    private let searchGraphTool: SearchGraphTool
    private let queryDetailValuesTool: QueryDetailValuesTool
    private let getNodeTool: GetNodeTool
    private let getNeighborsTool: GetNeighborsTool
    private let graphStatsTool: GraphStatsTool
    private let outputBudget: GraphChatModelToolOutputBudget

    @MainActor
    init(modelContainer: ModelContainer) {
        self.init(
            describeSchemaTool: DescribeGraphSchemaTool(),
            searchGraphTool: SearchGraphTool(),
            queryDetailValuesTool: QueryDetailValuesTool(),
            getNodeTool: GetNodeTool(),
            getNeighborsTool: GetNeighborsTool(),
            graphStatsTool: GraphStatsTool(
                reader: GraphStatsServiceReader(
                    container: AnyModelContainer(modelContainer)
                )
            ),
            outputBudget: .default
        )
    }

    init(
        describeSchemaTool: DescribeGraphSchemaTool,
        searchGraphTool: SearchGraphTool,
        queryDetailValuesTool: QueryDetailValuesTool,
        getNodeTool: GetNodeTool,
        getNeighborsTool: GetNeighborsTool,
        graphStatsTool: GraphStatsTool,
        outputBudget: GraphChatModelToolOutputBudget = .default
    ) {
        self.describeSchemaTool = describeSchemaTool
        self.searchGraphTool = searchGraphTool
        self.queryDetailValuesTool = queryDetailValuesTool
        self.getNodeTool = getNodeTool
        self.getNeighborsTool = getNeighborsTool
        self.graphStatsTool = graphStatsTool
        self.outputBudget = outputBudget
    }

    func makeRunner(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry: GraphChatPresentationRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry,
        artifactTransactionID: GraphChatAnswerArtifactTransactionID,
        conversationTransaction: GraphChatConversationStateTransaction,
        conversationContext: GraphChatConversationContextSnapshot,
        referenceResolver: GraphChatConversationReferenceResolver,
        recoveryCoordinator: GraphChatProviderRecoveryCoordinator,
        responseLanguage: GraphChatResponseLanguage,
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning {
        GraphChatModelToolRuntime(
            scope: scope,
            schemaContext: schemaContext,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
            presentationRegistry: presentationRegistry,
            artifactRegistry: artifactRegistry,
            artifactTransactionID: artifactTransactionID,
            conversationTransaction: conversationTransaction,
            conversationContext: conversationContext,
            referenceResolver: referenceResolver,
            recoveryCoordinator: recoveryCoordinator,
            responseLanguage: responseLanguage,
            outputBudget: outputBudget,
            validator: GraphQueryPlanValidator(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate,
                defaultLimit: min(
                    GraphQueryPlanLimits.defaultResultLimit,
                    QueryDetailValuesTool.maximumResultCount
                ),
                maximumLimit: QueryDetailValuesTool.maximumResultCount
            ),
            describeSchemaTool: describeSchemaTool,
            searchGraphTool: searchGraphTool,
            queryDetailValuesTool: queryDetailValuesTool,
            getNodeTool: getNodeTool,
            getNeighborsTool: getNeighborsTool,
            graphStatsTool: graphStatsTool
        )
    }
}

actor GraphChatModelToolRuntime: GraphChatModelToolRunning {
    private struct ResolvedQueryTarget: Sendable {
        let entity: GraphSchemaEntityResolution
        let scope: GraphChatScope
        let validatedCurrent: GraphChatToolRepairCurrentContext?
    }

    private let scope: GraphChatScope
    private let schemaContext: GraphSchemaContext
    private let context: GraphChatToolContext
    private let evidenceRegistry: GraphChatEvidenceRegistry
    private let presentationRegistry: GraphChatPresentationRegistry
    private let artifactRegistry: GraphChatAnswerArtifactRegistry
    private let artifactTransactionID: GraphChatAnswerArtifactTransactionID
    private let conversationTransaction: GraphChatConversationStateTransaction
    private let conversationContext: GraphChatConversationContextSnapshot
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let recoveryCoordinator: GraphChatProviderRecoveryCoordinator
    private let responseLanguage: GraphChatResponseLanguage
    private let outputBudget: GraphChatModelToolOutputBudget
    private let validator: GraphQueryPlanValidator
    private let describeSchemaTool: DescribeGraphSchemaTool
    private let searchGraphTool: SearchGraphTool
    private let queryDetailValuesTool: QueryDetailValuesTool
    private let getNodeTool: GetNodeTool
    private let getNeighborsTool: GetNeighborsTool
    private let graphStatsTool: GraphStatsTool
    private let repairHintBuilder: GraphChatToolRepairHintBuilder

    private var nodeByAlias: [String: NodeRefKey]
    private var aliasByNode: [NodeRefKey: String]
    private var nextNodeAliasNumber: Int

    init(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry: GraphChatPresentationRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry,
        artifactTransactionID: GraphChatAnswerArtifactTransactionID,
        conversationTransaction: GraphChatConversationStateTransaction,
        conversationContext: GraphChatConversationContextSnapshot,
        referenceResolver: GraphChatConversationReferenceResolver,
        recoveryCoordinator: GraphChatProviderRecoveryCoordinator,
        responseLanguage: GraphChatResponseLanguage,
        outputBudget: GraphChatModelToolOutputBudget = .default,
        validator: GraphQueryPlanValidator,
        describeSchemaTool: DescribeGraphSchemaTool,
        searchGraphTool: SearchGraphTool,
        queryDetailValuesTool: QueryDetailValuesTool,
        getNodeTool: GetNodeTool,
        getNeighborsTool: GetNeighborsTool,
        graphStatsTool: GraphStatsTool
    ) {
        self.scope = scope
        self.schemaContext = schemaContext
        self.context = GraphChatToolContext(scope: scope, budget: budget)
        self.evidenceRegistry = evidenceRegistry
        self.presentationRegistry = presentationRegistry
        self.artifactRegistry = artifactRegistry
        self.artifactTransactionID = artifactTransactionID
        self.conversationTransaction = conversationTransaction
        self.conversationContext = conversationContext
        self.referenceResolver = referenceResolver
        self.recoveryCoordinator = recoveryCoordinator
        self.responseLanguage = responseLanguage
        self.outputBudget = outputBudget
        self.validator = validator
        self.describeSchemaTool = describeSchemaTool
        self.searchGraphTool = searchGraphTool
        self.queryDetailValuesTool = queryDetailValuesTool
        self.getNodeTool = getNodeTool
        self.getNeighborsTool = getNeighborsTool
        self.graphStatsTool = graphStatsTool
        self.repairHintBuilder = GraphChatToolRepairHintBuilder(
            schemaContext: schemaContext,
            scope: scope
        )

        var initialNodeByAlias: [String: NodeRefKey] = [:]
        var initialAliasByNode: [NodeRefKey: String] = [:]
        for resolution in schemaContext.aliases.entitiesByAlias.values {
            let alias = resolution.alias.rawValue.uppercased()
            let node = NodeRefKey(kind: .entity, id: resolution.entityID)
            initialNodeByAlias[alias] = node
            initialAliasByNode[node] = alias
        }
        self.nodeByAlias = initialNodeByAlias
        self.aliasByNode = initialAliasByNode
        self.nextNodeAliasNumber = 1
    }

    func registeredToolKinds() -> Set<GraphChatToolKind> {
        Set(GraphChatToolKind.allCases)
    }

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse {
        try Task.checkCancellation()
        let isRepairAttempt =
            await recoveryCoordinator.beginRepairAttempt(
                for: request.kind
            ) != nil
        do {
            let response = try await execute(request)
            if isRepairAttempt {
                await recoveryCoordinator.completeRepairAttempt(
                    succeeded: true,
                    tool: request.kind
                )
            }
            return response
        } catch is CancellationError {
            if isRepairAttempt {
                await recoveryCoordinator.completeRepairAttempt(
                    succeeded: false,
                    tool: request.kind
                )
            } else {
                await recoveryCoordinator.recordRepairNotAllowed(
                    tool: request.kind,
                    reason: .cancellation
                )
            }
            throw CancellationError()
        } catch let error as GraphChatToolError
            where error.code == .cancelled
        {
            if isRepairAttempt {
                await recoveryCoordinator.completeRepairAttempt(
                    succeeded: false,
                    tool: request.kind
                )
            } else {
                await recoveryCoordinator.recordRepairNotAllowed(
                    tool: request.kind,
                    reason: .cancellation
                )
            }
            throw error
        } catch let error as GraphChatToolNonRepairableError {
            if isRepairAttempt {
                await recoveryCoordinator.completeRepairAttempt(
                    succeeded: false,
                    tool: request.kind
                )
            } else {
                await recoveryCoordinator.recordRepairNotAllowed(
                    tool: request.kind,
                    reason: error.reason
                )
            }
            throw error.publicError
        } catch let error as GraphChatToolRepairableError {
            if isRepairAttempt {
                await recoveryCoordinator.completeRepairAttempt(
                    succeeded: false,
                    tool: request.kind
                )
                return repairTerminalResponse(
                    tool: request.kind,
                    state: .failed
                )
            }
            if await recoveryCoordinator.offerRepair(
                error.result,
                for: request.kind
            ) {
                return repairResponse(
                    tool: request.kind,
                    result: error.result
                )
            }
            return repairTerminalResponse(
                tool: request.kind,
                state: .budgetExhausted
            )
        } catch {
            if isRepairAttempt {
                await recoveryCoordinator.completeRepairAttempt(
                    succeeded: false,
                    tool: request.kind
                )
            } else {
                await recoveryCoordinator.recordRepairNotAllowed(
                    tool: request.kind,
                    reason:
                        GraphChatToolFailureTaxonomy.nonRepairableReason(
                            for: error
                        )
                )
            }
            throw error
        }
    }

    private func execute(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse {
        switch request {
        case .describeSchema(let exampleFieldAliases):
            return try await describeSchema(
                exampleFieldAliases: exampleFieldAliases
            )
        case .searchGraph(let query, let limit):
            return try await searchGraph(query: query, limit: limit)
        case .queryDetailValues(let queryRequest):
            return try await queryDetailValues(queryRequest)
        case .getNode(let nodeAlias, let relatedLimit):
            return try await getNode(
                alias: nodeAlias,
                relatedLimit: relatedLimit
            )
        case .getNeighbors(let nodeAlias, let limit):
            return try await getNeighbors(alias: nodeAlias, limit: limit)
        case .graphStats(let hubLimit):
            return try await graphStats(hubLimit: hubLimit)
        }
    }

    private func repairResponse(
        tool: GraphChatToolKind,
        result: GraphChatToolRepairResult
    ) -> GraphChatModelToolResponse {
        GraphChatModelToolResponse(
            tool: tool,
            state: .noEvidence,
            content: result.modelContent,
            evidenceIDs: [],
            repairResult: result
        )
    }

    private func repairTerminalResponse(
        tool: GraphChatToolKind,
        state: GraphChatToolRepairTerminalState
    ) -> GraphChatModelToolResponse {
        GraphChatModelToolResponse(
            tool: tool,
            state: .noEvidence,
            content: state.modelContent,
            evidenceIDs: []
        )
    }

    private func describeSchema(
        exampleFieldAliases: [String]
    ) async throws -> GraphChatModelToolResponse {
        let fieldIDs = Set(
            try exampleFieldAliases.map { aliasValue in
                let alias = GraphFieldAlias(normalizedAlias(aliasValue))
                guard let field = schemaContext.aliases.field(for: alias) else {
                    throw invalidInput("Unbekannter Feld-Alias: \(aliasValue)")
                }
                return field.fieldID
            }
        )
        let result = try await describeSchemaTool.execute(
            DescribeGraphSchemaInput(exampleFieldIDs: fieldIDs),
            context: context
        )
        try await register(result.evidence)
        if let snapshot = result.payload?.snapshot {
            try await record(
                .schemaResolved(
                    schemaContext: GraphSchemaContext(
                        graphScope: schemaContext.graphScope,
                        snapshot: snapshot,
                        aliases: schemaContext.aliases
                    ),
                    state: result.state,
                    evidence: result.evidence
                )
            )
        }
        let artifactIDs = try await stageArtifacts(
            result.payload.flatMap {
                GraphChatAnswerArtifactFactory.schemaOverview(
                    output: $0,
                    schemaContext: GraphSchemaContext(
                        graphScope: schemaContext.graphScope,
                        snapshot: $0.snapshot,
                        aliases: schemaContext.aliases
                    ),
                    evidenceIDs: result.evidence.map(\.id),
                    language: responseLanguage
                )
            }.map { [$0] } ?? []
        )
        return GraphChatModelToolResponse(
            tool: .describeGraphSchema,
            state: result.state,
            content: formatSchema(result.payload?.snapshot),
            evidenceIDs: result.evidence.map(\.id),
            artifactIDs: artifactIDs
        )
    }

    private func searchGraph(
        query: String,
        limit: Int
    ) async throws -> GraphChatModelToolResponse {
        let result = try await searchGraphTool.execute(
            SearchGraphInput(query: boundedInput(query), limit: limit),
            context: context
        )
        try await register(result.evidence)
        if let output = result.payload {
            try await record(
                .searchResolved(
                    output: output,
                    state: result.state,
                    evidence: result.evidence
                )
            )
        }
        let artifactID = try await stageArtifact(
            result.payload.flatMap {
                GraphChatAnswerArtifactFactory.searchResults(
                    output: $0,
                    graphScope: scope.graphScope,
                    requestedLimit: limit,
                    language: responseLanguage
                )
            }
        )
        let content = result.payload.map { output in
            let lines = output.hits.map { hit in
                let nodeAlias = aliasForReference(hit.sourceReference)
                return [
                    "nodeAlias=\(nodeAlias ?? "none")",
                    "kind=\(hit.kind.rawValue)",
                    "title=\(boundedOutput(hit.title))",
                    "subtitle=\(boundedOutput(hit.subtitle))",
                    "match=\(boundedOutput(hit.matchReason))",
                    "evidenceID=\(hit.evidenceID.rawValue.uuidString)"
                ].joined(separator: " | ")
            }
            return boundedCollection(lines, empty: "Keine Treffer im aktiven Scope.")
        } ?? "Keine Treffer im aktiven Scope."
        if let output = result.payload {
            for hit in output.hits {
                guard let node = presentationNode(
                    for: hit.sourceReference
                ),
                    let nodeAlias = aliasForReference(
                        hit.sourceReference
                    )
                else {
                    continue
                }
                await presentationRegistry.registerValidatedNode(
                    alias: nodeAlias,
                    node: node,
                    displayName: hit.title
                )
            }
        }
        return GraphChatModelToolResponse(
            tool: .searchGraph,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id),
            artifactID: artifactID
        )
    }

    private func queryDetailValues(
        _ request: GraphChatModelQueryRequest
    ) async throws -> GraphChatModelToolResponse {
        let preparedQuery = try await makeQueryPlan(request)
        let validatedPlan: ValidatedGraphQueryPlan
        do {
            validatedPlan = try validator.validate(
                preparedQuery.plan,
                against: schemaContext
            )
        } catch let error as GraphQueryPlanValidationError {
            if let repairResult = repairResult(
                for: error,
                request: request,
                target: preparedQuery.target
            ) {
                throw GraphChatToolRepairableError(result: repairResult)
            }
            throw error
        }
        let result = try await queryDetailValuesTool.execute(
            QueryDetailValuesInput(plan: validatedPlan),
            context: context
        )
        try await register(result.evidence)
        if let output = result.payload {
            try await evidenceRegistry.registerAppliedFilters(
                output.result.appliedFilters
            )
            try await record(
                .queryResolved(
                    plan: validatedPlan,
                    result: output.result,
                    schemaContext: schemaContext
                )
            )
        }
        let artifactID = try await stageArtifact(
            result.payload.flatMap {
                GraphChatAnswerArtifactFactory.queryResult(
                    $0.result,
                    plan: validatedPlan,
                    schemaContext: schemaContext,
                    language: responseLanguage
                )
            }
        )
        let content = result.payload.map { output in
            formatQueryResult(output.result)
        } ?? "Keine validierten Detailwerte im aktiven Scope."
        if let output = result.payload {
            for row in output.result.rows {
                await presentationRegistry.registerValidatedNode(
                    alias: alias(for: row.node),
                    node: row.node,
                    displayName: row.label
                )
            }
        }
        return GraphChatModelToolResponse(
            tool: .queryDetailValues,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id),
            artifactID: artifactID
        )
    }

    private func getNode(
        alias: String,
        relatedLimit: Int
    ) async throws -> GraphChatModelToolResponse {
        let node = try await resolveNodeAlias(alias)
        let result = try await getNodeTool.execute(
            GetNodeInput(node: node, relatedLimit: relatedLimit),
            context: context
        )
        try await register(result.evidence)
        if let output = result.payload {
            try await record(
                .nodeResolved(
                    output: output,
                    state: result.state,
                    evidence: result.evidence
                )
            )
        }
        let artifactID = try await stageArtifact(
            result.payload.flatMap {
                GraphChatAnswerArtifactFactory.nodeDetails(
                    output: $0,
                    graphScope: scope.graphScope,
                    language: responseLanguage
                )
            }
        )
        let content = result.payload.map(formatNode) ?? "Node nicht im aktiven Scope gefunden."
        if let output = result.payload {
            await registerNodePresentations(output)
        }
        return GraphChatModelToolResponse(
            tool: .getNode,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id),
            artifactID: artifactID
        )
    }

    private func getNeighbors(
        alias: String,
        limit: Int
    ) async throws -> GraphChatModelToolResponse {
        let node = try await resolveNodeAlias(alias)
        let result = try await getNeighborsTool.execute(
            GetNeighborsInput(node: node, limit: limit),
            context: context
        )
        try await register(result.evidence)
        if let output = result.payload {
            try await record(
                .neighborsResolved(
                    output: output,
                    state: result.state,
                    evidence: result.evidence
                )
            )
        }
        let artifactID = try await stageArtifact(
            result.payload.flatMap {
                GraphChatAnswerArtifactFactory.neighbors(
                    output: $0,
                    graphScope: scope.graphScope,
                    requestedLimit: limit,
                    language: responseLanguage
                )
            }
        )
        let content = result.payload.map(formatNeighbors) ?? "Keine direkten Nachbarn im aktiven Scope."
        if let output = result.payload {
            await registerNodePresentations(output)
        }
        return GraphChatModelToolResponse(
            tool: .getNeighbors,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id),
            artifactID: artifactID
        )
    }

    private func graphStats(
        hubLimit: Int
    ) async throws -> GraphChatModelToolResponse {
        let result = try await graphStatsTool.execute(
            GraphStatsInput(hubLimit: hubLimit),
            context: context
        )
        try await register(result.evidence)
        if let output = result.payload {
            try await record(
                .statsResolved(
                    output: output,
                    state: result.state,
                    evidence: result.evidence
                )
            )
        }
        let artifactIDs = try await stageArtifacts(
            result.payload.map {
                GraphChatAnswerArtifactFactory.statistics(
                    output: $0,
                    graphScope: scope.graphScope,
                    requestedHubLimit: hubLimit,
                    language: responseLanguage
                )
            } ?? []
        )
        let content = result.payload.map(formatStats) ?? "Keine validierte Graph-Statistik verfügbar."
        if let output = result.payload {
            for hub in output.hubs {
                await presentationRegistry.registerValidatedNode(
                    alias: alias(for: hub.node),
                    node: hub.node,
                    displayName: hub.label
                )
            }
        }
        return GraphChatModelToolResponse(
            tool: .graphStats,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id),
            artifactIDs: artifactIDs
        )
    }

    private func register(_ evidence: [GraphEvidence]) async throws {
        try await evidenceRegistry.register(evidence)
        await presentationRegistry.registerValidatedEvidence(evidence)
    }

    private func stageArtifact(
        _ draft: GraphChatAnswerArtifactDraft?
    ) async throws -> GraphChatAnswerArtifactID? {
        guard let draft else {
            return nil
        }
        return try await stageArtifacts([draft]).first
    }

    private func stageArtifacts(
        _ drafts: [GraphChatAnswerArtifactDraft]
    ) async throws -> [GraphChatAnswerArtifactID] {
        var artifactIDs: [GraphChatAnswerArtifactID] = []
        artifactIDs.reserveCapacity(drafts.count)
        for draft in drafts {
            do {
                let artifactID = try await artifactRegistry.stage(
                    draft,
                    transactionID: artifactTransactionID,
                    evidenceRegistry: evidenceRegistry
                )
                artifactIDs.append(artifactID)
                await presentationRegistry.registerValidatedArtifact(
                    id: artifactID,
                    title: draft.title
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return artifactIDs
    }

    private func record(
        _ payload: GraphChatConversationTrustedPayload
    ) async throws {
        try await conversationTransaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: scope.graphScope,
                chatScope: scope,
                payload: payload
            )
        )
    }

    private func makeQueryPlan(
        _ request: GraphChatModelQueryRequest
    ) async throws -> (
        plan: GraphQueryPlan,
        target: ResolvedQueryTarget
    ) {
        guard (1...QueryDetailValuesTool.maximumResultCount).contains(request.limit) else {
            throw GraphChatToolError(
                code: .budgetExceeded,
                message: "QueryDetailValues erlaubt höchstens \(QueryDetailValuesTool.maximumResultCount) Ergebnisse."
            )
        }

        let target = try await resolvedQueryTarget(for: request)
        let filters = try request.filters.enumerated().map {
            try makeFilter(
                $0.element,
                index: $0.offset,
                target: target
            )
        }
        let sorting = try makeSorting(request, target: target)
        let projection = try makeProjection(
            request.projectionFieldAliases,
            target: target
        )
        let aggregation = try makeAggregation(
            name: request.aggregation,
            fieldAlias: request.aggregationFieldAlias,
            target: target
        )
        return (
            plan: GraphQueryPlan(
                entityAlias: target.entity.alias,
                scope: target.scope,
                filters: filters,
                sorting: sorting,
                projection: projection,
                aggregation: aggregation,
                limit: request.limit
            ),
            target: target
        )
    }

    private func repairResult(
        for error: GraphQueryPlanValidationError,
        request: GraphChatModelQueryRequest,
        target: ResolvedQueryTarget
    ) -> GraphChatToolRepairResult? {
        guard let issue = error.issues.first else {
            return nil
        }
        switch issue.code {
        case .invalidOperator:
            guard let index = filterIndex(from: issue.path),
                  request.filters.indices.contains(index),
                  let field = schemaContext.aliases.field(
                    for: GraphFieldAlias(
                        normalizedAlias(
                            request.filters[index].fieldAlias
                        )
                    )
                  ) else {
                return nil
            }
            return repairHintBuilder.invalidOperator(
                path: issue.path,
                field: field,
                current: target.validatedCurrent
            )

        case .invalidValueType,
            .emptyValue,
            .invalidRange,
            .invalidChoiceValue,
            .ambiguousChoiceValue:
            guard let index = filterIndex(from: issue.path),
                  request.filters.indices.contains(index),
                  let field = schemaContext.aliases.field(
                    for: GraphFieldAlias(
                        normalizedAlias(
                            request.filters[index].fieldAlias
                        )
                    )
                  ),
                  let operation = GraphQueryFilterOperator(
                    rawValue: request.filters[index].operation
                  ) else {
                return nil
            }
            return repairHintBuilder.invalidValue(
                path: issue.path,
                field: field,
                operation: operation,
                current: target.validatedCurrent
            )

        case .invalidAggregation:
            guard let rawAlias = request.aggregationFieldAlias else {
                return nil
            }
            return repairHintBuilder.fieldIssue(
                rawValue: rawAlias,
                path: issue.path,
                expectedCategory: .aggregationField,
                entity: target.entity,
                reason: .schemaIncompatibility,
                current: target.validatedCurrent
            )

        case .unsupportedVersion,
            .unknownEntityAlias,
            .unknownFieldAlias,
            .fieldEntityMismatch,
            .invalidLimit,
            .invalidFilterCount,
            .invalidProjectionCount,
            .graphScopeMismatch,
            .unknownScopeEntity,
            .unknownScopeNode,
            .scopeEntityMismatch,
            .duplicateProjection:
            return nil
        }
    }

    private func filterIndex(
        from path: String
    ) -> Int? {
        guard path.hasPrefix("filters["),
              let closingBracket = path.firstIndex(of: "]") else {
            return nil
        }
        let start = path.index(path.startIndex, offsetBy: "filters[".count)
        return Int(path[start..<closingBracket])
    }

    private func resolvedQueryTarget(
        for request: GraphChatModelQueryRequest
    ) async throws -> ResolvedQueryTarget {
        guard
            let rawReferenceAlias = request.conversationReferenceAlias?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            rawReferenceAlias.isEmpty == false
        else {
            let entityAlias = GraphEntityAlias(
                normalizedAlias(request.entityAlias)
            )
            guard
                let entity = schemaContext.aliases.entity(for: entityAlias)
            else {
                if looksLikeTechnicalIdentifier(request.entityAlias) {
                    throw nonRepairable(
                        .manipulatedTechnicalIdentifier,
                        message:
                            "Technische IDs sind in Entity-Alias-Argumenten nicht zulässig."
                    )
                }
                throw GraphChatToolRepairableError(
                    result: repairHintBuilder.unknownEntity(
                        rawValue: request.entityAlias
                    )
                )
            }
            guard isEntityAllowedByRequestScope(entity.entityID) else {
                throw nonRepairable(
                    .unauthorizedNodeOrSelectionScope,
                    message:
                        "Die gewählte Entity liegt außerhalb des freigegebenen Chat-Scopes."
                )
            }
            return ResolvedQueryTarget(
                entity: entity,
                scope: scope,
                validatedCurrent: nil
            )
        }

        let referenceAlias = normalizedAlias(rawReferenceAlias)
        let resolution: GraphChatResolvedConversationScopeResolution
        if let currentAlias = conversationContext.currentReferenceAlias,
            normalizedAlias(currentAlias) == referenceAlias,
            let currentScope = conversationContext.currentResolvedScope
        {
            resolution = try await referenceResolver.resolveScope(
                .validatedScope(currentScope),
                in: conversationContext,
                expectedGraphScope: scope.graphScope,
                expectedChatScope: scope
            )
        } else {
            resolution = try await referenceResolver.resolveScope(
                .alias(referenceAlias),
                in: conversationContext,
                expectedGraphScope: scope.graphScope,
                expectedChatScope: scope
            )
        }

        guard case .resolved(let resolvedScope) = resolution else {
            switch resolution {
            case .clarification(let clarification)
            where clarification.issue == .mixedEntities:
                throw nonRepairable(
                    .staleConversationReference,
                    message:
                        "Die referenzierte Ergebnismenge muss zuerst fachlich geklärt werden."
                )
            case .resolved:
                preconditionFailure("Unreachable resolved scope branch.")
            case .clarification, .noResults, .rejected:
                throw nonRepairable(
                    looksLikeTechnicalIdentifier(rawReferenceAlias)
                        ? .manipulatedTechnicalIdentifier
                        : .staleConversationReference,
                    message:
                        "Die Conversation-Referenz ist für diese Query nicht mehr gültig."
                )
            }
        }
        guard
            let entity = schemaContext.aliases.entitiesByAlias.values
                .filter({ $0.entityID == resolvedScope.entityID })
                .sorted(by: { $0.alias.rawValue < $1.alias.rawValue })
                .first
        else {
            throw nonRepairable(
                .staleConversationReference,
                message:
                    "Die validierte Conversation-Referenz ist im aktuellen Schema nicht mehr verfügbar."
            )
        }
        return ResolvedQueryTarget(
            entity: entity,
            scope: try queryScope(for: resolvedScope),
            validatedCurrent: repairHintBuilder.currentContext(
                for: resolvedScope,
                entity: entity
            )
        )
    }

    private func makeFilter(
        _ request: GraphChatModelQueryFilterRequest,
        index: Int,
        target: ResolvedQueryTarget
    ) throws -> GraphQueryFilter {
        let fieldAlias = GraphFieldAlias(normalizedAlias(request.fieldAlias))
        guard let field = schemaContext.aliases.field(for: fieldAlias) else {
            if looksLikeTechnicalIdentifier(request.fieldAlias) {
                throw nonRepairable(
                    .manipulatedTechnicalIdentifier,
                    message:
                        "Technische IDs sind in Feld-Alias-Argumenten nicht zulässig."
                )
            }
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.fieldIssue(
                    rawValue: request.fieldAlias,
                    path: "filters[\(index)].fieldAlias",
                    expectedCategory: .fieldAlias,
                    entity: target.entity,
                    reason: target.validatedCurrent == nil
                        ? .schemaIncompatibility
                        : .conversationReferenceMismatch,
                    current: target.validatedCurrent
                )
            )
        }
        guard field.entityID == target.entity.entityID else {
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.fieldIssue(
                    rawValue: request.fieldAlias,
                    path: "filters[\(index)].fieldAlias",
                    expectedCategory: .fieldAlias,
                    entity: target.entity,
                    reason: target.validatedCurrent == nil
                        ? .fieldEntityMismatch
                        : .conversationReferenceMismatch,
                    current: target.validatedCurrent
                )
            )
        }
        guard let operation = GraphQueryFilterOperator(rawValue: request.operation) else {
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.invalidOperator(
                    path: "filters[\(index)].operation",
                    field: field,
                    current: target.validatedCurrent
                )
            )
        }
        guard GraphChatQueryOperatorCompatibility
            .allowedOperators(for: field.type)
            .contains(operation) else {
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.invalidOperator(
                    path: "filters[\(index)].operation",
                    field: field,
                    current: target.validatedCurrent
                )
            )
        }
        let value: GraphQueryFilterValue
        do {
            value = try makeFilterValue(
                operation: operation,
                field: field,
                value: request.value,
                secondValue: request.secondValue,
                values: request.values
            )
        } catch let error as GraphChatToolError
            where error.code == .invalidInput
        {
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.invalidValue(
                    path: "filters[\(index)].value",
                    field: field,
                    operation: operation,
                    current: target.validatedCurrent
                )
            )
        }
        return GraphQueryFilter(
            fieldAlias: fieldAlias,
            operation: operation,
            value: value
        )
    }

    private func makeFilterValue(
        operation: GraphQueryFilterOperator,
        field: GraphSchemaFieldResolution,
        value: String?,
        secondValue: String?,
        values: [String]
    ) throws -> GraphQueryFilterValue {
        switch operation {
        case .isPresent, .isMissing, .isOverdue:
            return .none
        case .inYear:
            guard let raw = value, let year = Int(raw) else {
                throw invalidInput("inYear benötigt eine vierstellige Jahreszahl.")
            }
            return .year(year)
        case .inMonth:
            guard let raw = value else {
                throw invalidInput("inMonth benötigt einen Wert im Format YYYY-MM.")
            }
            let components = raw.split(separator: "-")
            guard components.count == 2,
                  let year = Int(components[0]),
                  let month = Int(components[1]) else {
                throw invalidInput("inMonth benötigt einen Wert im Format YYYY-MM.")
            }
            return .month(GraphQueryYearMonth(year: year, month: month))
        case .oneOf:
            guard values.isEmpty == false else {
                throw invalidInput("oneOf benötigt mindestens einen Auswahlwert.")
            }
            return .choices(values.map { boundedInput($0) })
        case .between:
            guard let first = value, let second = secondValue else {
                throw invalidInput("between benötigt zwei Grenzwerte.")
            }
            switch field.type {
            case .numberInt:
                guard let lower = Int(first), let upper = Int(second) else {
                    throw invalidInput("between benötigt zwei Ganzzahlen.")
                }
                return .integerRange(
                    GraphQueryIntegerRange(lowerBound: lower, upperBound: upper)
                )
            case .numberDouble:
                guard let lower = Double(first), let upper = Double(second) else {
                    throw invalidInput("between benötigt zwei Dezimalzahlen.")
                }
                return .decimalRange(
                    GraphQueryDoubleRange(lowerBound: lower, upperBound: upper)
                )
            case .date:
                let lower = try parseDate(first)
                let upper = try parseDate(second)
                return .dateInterval(
                    GraphQueryDateInterval(
                        lowerBound: lower,
                        upperBoundExclusive: upper
                    )
                )
            case .singleLineText, .multiLineText, .toggle, .singleChoice:
                throw invalidInput("between ist für diesen Feldtyp nicht zulässig.")
            }
        case .contains, .startsWith:
            return .text(try requiredValue(value))
        case .equals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual, .before, .after:
            return try typedScalarValue(value, fieldType: field.type)
        }
    }

    private func typedScalarValue(
        _ value: String?,
        fieldType: DetailFieldType
    ) throws -> GraphQueryFilterValue {
        let raw = try requiredValue(value)
        switch fieldType {
        case .singleLineText, .multiLineText:
            return .text(raw)
        case .numberInt:
            guard let parsed = Int(raw) else {
                throw invalidInput("Der Filterwert muss eine Ganzzahl sein.")
            }
            return .integer(parsed)
        case .numberDouble:
            guard let parsed = Double(raw) else {
                throw invalidInput("Der Filterwert muss eine Dezimalzahl sein.")
            }
            return .decimal(parsed)
        case .date:
            return .date(try parseDate(raw))
        case .toggle:
            switch raw.lowercased() {
            case "true", "yes", "ja", "1":
                return .boolean(true)
            case "false", "no", "nein", "0":
                return .boolean(false)
            default:
                throw invalidInput("Der Filterwert muss true oder false sein.")
            }
        case .singleChoice:
            return .choice(raw)
        }
    }

    private func makeSorting(
        _ request: GraphChatModelQueryRequest,
        target: ResolvedQueryTarget
    ) throws -> [GraphQuerySort] {
        guard let rawKey = request.sortFieldAlias else {
            return []
        }
        let direction: GraphQuerySortDirection
        if let rawDirection = request.sortDirection {
            guard let parsed = GraphQuerySortDirection(rawValue: rawDirection) else {
                throw invalidInput("Unbekannte Sortierrichtung: \(rawDirection)")
            }
            direction = parsed
        } else {
            direction = .ascending
        }
        if rawKey == "nodeName" {
            return [GraphQuerySort(key: .nodeName, direction: direction)]
        }
        let alias = GraphFieldAlias(normalizedAlias(rawKey))
        guard let field = schemaContext.aliases.field(for: alias) else {
            if looksLikeTechnicalIdentifier(rawKey) {
                throw nonRepairable(
                    .manipulatedTechnicalIdentifier,
                    message:
                        "Technische IDs sind in Sortierfeld-Alias-Argumenten nicht zulässig."
                )
            }
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.fieldIssue(
                    rawValue: rawKey,
                    path: "sortFieldAlias",
                    expectedCategory: .sortField,
                    entity: target.entity,
                    reason: .schemaIncompatibility,
                    current: target.validatedCurrent
                )
            )
        }
        guard field.entityID == target.entity.entityID else {
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.fieldIssue(
                    rawValue: rawKey,
                    path: "sortFieldAlias",
                    expectedCategory: .sortField,
                    entity: target.entity,
                    reason: target.validatedCurrent == nil
                        ? .fieldEntityMismatch
                        : .conversationReferenceMismatch,
                    current: target.validatedCurrent
                )
            )
        }
        return [GraphQuerySort(key: .field(alias), direction: direction)]
    }

    private func makeProjection(
        _ rawAliases: [String],
        target: ResolvedQueryTarget
    ) throws -> [GraphQueryProjection] {
        var result: [GraphQueryProjection] = [.nodeIdentity]
        var seen = Set<GraphFieldAlias>()
        for (index, rawAlias) in rawAliases.enumerated() {
            let alias = GraphFieldAlias(normalizedAlias(rawAlias))
            guard let field = schemaContext.aliases.field(for: alias) else {
                if looksLikeTechnicalIdentifier(rawAlias) {
                    throw nonRepairable(
                        .manipulatedTechnicalIdentifier,
                        message:
                            "Technische IDs sind in Projektionsfeld-Alias-Argumenten nicht zulässig."
                    )
                }
                throw GraphChatToolRepairableError(
                    result: repairHintBuilder.fieldIssue(
                        rawValue: rawAlias,
                        path: "projectionFieldAliases[\(index)]",
                        expectedCategory: .projectionField,
                        entity: target.entity,
                        reason: .schemaIncompatibility,
                        current: target.validatedCurrent
                    )
                )
            }
            guard field.entityID == target.entity.entityID else {
                throw GraphChatToolRepairableError(
                    result: repairHintBuilder.fieldIssue(
                        rawValue: rawAlias,
                        path: "projectionFieldAliases[\(index)]",
                        expectedCategory: .projectionField,
                        entity: target.entity,
                        reason: target.validatedCurrent == nil
                            ? .fieldEntityMismatch
                            : .conversationReferenceMismatch,
                        current: target.validatedCurrent
                    )
                )
            }
            if seen.insert(alias).inserted {
                result.append(.field(alias))
            }
        }
        return result
    }

    private func makeAggregation(
        name: String?,
        fieldAlias: String?,
        target: ResolvedQueryTarget
    ) throws -> GraphQueryAggregation? {
        guard let name, name.isEmpty == false else {
            return nil
        }
        if name == "count" {
            return .count
        }
        guard let rawFieldAlias = fieldAlias else {
            throw invalidInput("Die Aggregation \(name) benötigt einen Feld-Alias.")
        }
        let alias = GraphFieldAlias(normalizedAlias(rawFieldAlias))
        guard let field = schemaContext.aliases.field(for: alias) else {
            if looksLikeTechnicalIdentifier(rawFieldAlias) {
                throw nonRepairable(
                    .manipulatedTechnicalIdentifier,
                    message:
                        "Technische IDs sind in Aggregationsfeld-Alias-Argumenten nicht zulässig."
                )
            }
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.fieldIssue(
                    rawValue: rawFieldAlias,
                    path: "aggregationFieldAlias",
                    expectedCategory: .aggregationField,
                    entity: target.entity,
                    reason: .schemaIncompatibility,
                    current: target.validatedCurrent
                )
            )
        }
        guard field.entityID == target.entity.entityID else {
            throw GraphChatToolRepairableError(
                result: repairHintBuilder.fieldIssue(
                    rawValue: rawFieldAlias,
                    path: "aggregationFieldAlias",
                    expectedCategory: .aggregationField,
                    entity: target.entity,
                    reason: target.validatedCurrent == nil
                        ? .fieldEntityMismatch
                        : .conversationReferenceMismatch,
                    current: target.validatedCurrent
                )
            )
        }
        switch name {
        case "groupCount":
            return .groupCount(alias)
        case "minimum":
            guard GraphChatQueryOperatorCompatibility
                .supportsMinimumMaximum(field.type) else {
                throw GraphChatToolRepairableError(
                    result: repairHintBuilder.fieldIssue(
                        rawValue: rawFieldAlias,
                        path: "aggregationFieldAlias",
                        expectedCategory: .aggregationField,
                        entity: target.entity,
                        reason: .schemaIncompatibility,
                        current: target.validatedCurrent
                    )
                )
            }
            return .minimum(alias)
        case "maximum":
            guard GraphChatQueryOperatorCompatibility
                .supportsMinimumMaximum(field.type) else {
                throw GraphChatToolRepairableError(
                    result: repairHintBuilder.fieldIssue(
                        rawValue: rawFieldAlias,
                        path: "aggregationFieldAlias",
                        expectedCategory: .aggregationField,
                        entity: target.entity,
                        reason: .schemaIncompatibility,
                        current: target.validatedCurrent
                    )
                )
            }
            return .maximum(alias)
        default:
            throw invalidInput("Unbekannte Aggregation: \(name)")
        }
    }

    private func resolveNodeAlias(_ rawAlias: String) async throws -> NodeRefKey {
        let alias = normalizedAlias(rawAlias)
        if let node = nodeByAlias[alias] {
            return node
        }
        let resolution = try await referenceResolver.resolve(
            .alias(alias),
            in: conversationContext,
            expectedGraphScope: scope.graphScope,
            expectedChatScope: scope
        )
        guard case .resolved(let reference) = resolution,
              let node = reference.singleNode else {
            throw nonRepairable(
                looksLikeTechnicalIdentifier(rawAlias)
                    ? .manipulatedTechnicalIdentifier
                    : .staleConversationReference,
                message:
                    "Die Conversation-Referenz ist nicht eindeutig und aktuell auflösbar."
            )
        }
        nodeByAlias[alias] = node
        aliasByNode[node] = alias
        return node
    }

    private func queryScope(
        for resolvedScope: GraphChatResolvedConversationScope
    ) throws -> GraphChatScope {
        let reference = resolvedScope.reference
        switch reference.kind {
        case .entity:
            return .entity(
                resolvedScope.entityID,
                in: resolvedScope.graphScope
            )
        case .node:
            guard let node = reference.singleNode else {
                throw nonRepairable(
                    .staleConversationReference,
                    message:
                        "Die validierte Conversation-Referenz enthält keinen einzelnen Node."
                )
            }
            return .node(node, in: resolvedScope.graphScope)
        case .resultSet, .resultSubset, .group, .comparison:
            guard resolvedScope.nodes.isEmpty == false else {
                throw nonRepairable(
                    .staleConversationReference,
                    message:
                        "Die validierte Conversation-Ergebnismenge ist leer."
                )
            }
            return try .selection(
                resolvedScope.nodes,
                in: resolvedScope.graphScope
            )
        case .field:
            throw nonRepairable(
                .staleConversationReference,
                message:
                    "Eine Feldreferenz kann nicht als Query-Ergebnismenge verwendet werden."
            )
        }
    }

    private func aliasForReference(
        _ reference: GraphSourceReference
    ) -> String? {
        if let node = reference.node?.nodeKey {
            return alias(for: node)
        }
        if let owner = reference.owner?.nodeKey {
            return alias(for: owner)
        }
        switch reference.sourceKind {
        case .entity:
            return alias(for: NodeRefKey(kind: .entity, id: reference.sourceID))
        case .attribute:
            return alias(for: NodeRefKey(kind: .attribute, id: reference.sourceID))
        case .graph, .detailField, .detailValue, .link, .attachment:
            return nil
        }
    }

    private func presentationNode(
        for reference: GraphSourceReference
    ) -> NodeRefKey? {
        if let node = reference.node?.nodeKey {
            return node
        }
        if let owner = reference.owner?.nodeKey {
            return owner
        }
        switch reference.sourceKind {
        case .entity:
            return NodeRefKey(
                kind: .entity,
                id: reference.sourceID
            )
        case .attribute:
            return NodeRefKey(
                kind: .attribute,
                id: reference.sourceID
            )
        case .graph, .detailField, .detailValue, .link, .attachment:
            return nil
        }
    }

    private func registerNodePresentations(
        _ output: GetNodeOutput
    ) async {
        await presentationRegistry.registerValidatedNode(
            alias: alias(for: output.node),
            node: output.node,
            displayName: output.label
        )
        for link in output.links {
            let otherNode =
                link.direction == .outgoing
                ? link.target
                : link.source
            let otherLabel =
                link.direction == .outgoing
                ? link.targetLabel
                : link.sourceLabel
            await presentationRegistry.registerValidatedNode(
                alias: alias(for: otherNode),
                node: otherNode,
                displayName: otherLabel
            )
        }
    }

    private func registerNodePresentations(
        _ output: GetNeighborsOutput
    ) async {
        await presentationRegistry.registerValidatedNode(
            alias: alias(for: output.center.nodeKey),
            node: output.center.nodeKey,
            displayName: output.center.label
        )
        for connection in output.connections {
            await presentationRegistry.registerValidatedNode(
                alias: alias(for: connection.neighbor),
                node: connection.neighbor,
                displayName: connection.neighborLabel
            )
        }
    }

    private func alias(for node: NodeRefKey) -> String {
        if let existing = aliasByNode[node] {
            return existing
        }
        var candidate: String
        repeat {
            candidate = "N\(nextNodeAliasNumber)"
            nextNodeAliasNumber += 1
        } while nodeByAlias[candidate] != nil
        nodeByAlias[candidate] = node
        aliasByNode[node] = candidate
        return candidate
    }

    private func allows(_ node: NodeRefKey) -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let entityID):
            return node == NodeRefKey(kind: .entity, id: entityID)
                || schemaContext.aliases.owningEntityID(for: node) == entityID
        case .node(let expected):
            return node == expected
        case .selection(let nodes):
            return Set(nodes).contains(node)
        }
    }

    private func formatSchema(_ snapshot: GraphSchemaSnapshot?) -> String {
        guard let snapshot else {
            return "Kein validiertes Schema verfügbar."
        }
        let entityLines = snapshot.entities.map { entity in
            let fieldLines = entity.fields.map { field in
                var parts = [
                    "\(field.alias.rawValue)=\(boundedOutput(field.name))",
                    "type=\(field.type.title)"
                ]
                if let unit = field.unit, unit.isEmpty == false {
                    parts.append("unit=\(boundedOutput(unit))")
                }
                if field.choiceOptions.isEmpty == false {
                    parts.append(
                        "choices=\(field.choiceOptions.map { boundedOutput($0) }.joined(separator: ", "))"
                    )
                }
                return parts.joined(separator: " | ")
            }
            return "\(entity.alias.rawValue)=\(boundedOutput(entity.name))\n\(fieldLines.joined(separator: "\n"))"
        }
        let truncation = snapshot.truncation.isTruncated ? "Schema ist begrenzt." : "Schema ist vollständig im Snapshot."
        return boundedOutput(
            "Graph=\(snapshot.graphName)\n\(entityLines.joined(separator: "\n"))\n\(truncation)",
            maximumLength: outputBudget.maximumSchemaCharacters
        )
    }

    private func formatQueryResult(_ result: GraphChatQueryResult) -> String {
        var lines: [String] = []
        if let aggregation = result.aggregation {
            lines.append(formatAggregation(aggregation))
        }
        for row in result.rows {
            let nodeAlias = alias(for: row.node)
            let cells = row.cells.map { cell in
                let unit = cell.unit.map { " \($0)" } ?? ""
                return "\(cell.fieldName)=\(formatCell(cell.value))\(unit) [\(cell.evidenceID.rawValue.uuidString)]"
            }
            lines.append(
                "nodeAlias=\(nodeAlias) | label=\(boundedOutput(row.label)) | \(cells.joined(separator: " | "))"
            )
        }
        if result.appliedFilters.isEmpty == false {
            let filters = result.appliedFilters.map { filter in
                [filter.fieldName, filter.operationDescription, filter.valueDescription]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            lines.append("Angewendete Filter: \(filters.joined(separator: "; "))")
        }
        return boundedCollection(lines, empty: "Keine validierten Detailwerte im aktiven Scope.")
    }

    private func formatAggregation(_ aggregation: GraphChatAggregationResult) -> String {
        var parts = ["aggregation=\(aggregation.kind.rawValue)"]
        if let fieldName = aggregation.fieldName {
            parts.append("field=\(boundedOutput(fieldName))")
        }
        if let count = aggregation.count {
            parts.append("count=\(count)")
        }
        if let value = aggregation.value {
            parts.append("value=\(formatCell(value))")
        }
        if aggregation.groups.isEmpty == false {
            let groups = aggregation.groups.map { group in
                "\(formatCell(group.value))=\(group.count) evidenceIDs=\(idList(group.evidenceIDs))"
            }
            parts.append("groups=\(groups.joined(separator: "; "))")
        }
        parts.append("evidenceIDs=\(idList(aggregation.evidenceIDs))")
        return parts.joined(separator: " | ")
    }

    private func formatNode(_ output: GetNodeOutput) -> String {
        let nodeAlias = alias(for: output.node)
        var lines = [
            "nodeAlias=\(nodeAlias) | label=\(boundedOutput(output.label)) | evidenceIDs=\(idList(output.evidenceIDs))"
        ]
        if output.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append(
                "notes=\(boundedOutput(output.notes, maximumLength: outputBudget.maximumNotesCharacters))"
            )
        }
        for detail in output.detailValues {
            let unit = detail.unit.map { " \($0)" } ?? ""
            lines.append(
                "field=\(boundedOutput(detail.fieldName)) | value=\(formatCell(detail.value))\(unit) | evidenceID=\(detail.evidenceID.rawValue.uuidString)"
            )
        }
        for link in output.links {
            let otherNode = link.direction == .outgoing ? link.target : link.source
            let otherLabel = link.direction == .outgoing ? link.targetLabel : link.sourceLabel
            lines.append(
                "link=\(link.direction.rawValue) | nodeAlias=\(alias(for: otherNode)) | label=\(boundedOutput(otherLabel)) | note=\(boundedOutput(link.note ?? "none")) | evidenceID=\(link.evidenceID.rawValue.uuidString)"
            )
        }
        for attachment in output.attachments {
            lines.append(
                "attachmentMetadata | title=\(boundedOutput(attachment.title)) | filename=\(boundedOutput(attachment.originalFilename)) | contentType=\(boundedOutput(attachment.contentTypeIdentifier)) | bytes=\(attachment.byteCount) | contentNotRead=true | evidenceID=\(attachment.evidenceID.rawValue.uuidString)"
            )
        }
        return boundedCollection(lines, empty: "Node ohne validierte Details.")
    }

    private func formatNeighbors(_ output: GetNeighborsOutput) -> String {
        var lines = [
            "centerAlias=\(alias(for: output.center.nodeKey)) | label=\(boundedOutput(output.center.label)) | evidenceIDs=\(idList(output.evidenceIDs))"
        ]
        lines.append(contentsOf: output.connections.map { connection in
            "direction=\(connection.direction.rawValue) | nodeAlias=\(alias(for: connection.neighbor)) | label=\(boundedOutput(connection.neighborLabel)) | note=\(boundedOutput(connection.note ?? "none")) | evidenceID=\(connection.evidenceID.rawValue.uuidString)"
        })
        return boundedCollection(lines, empty: "Keine direkten Nachbarn im aktiven Scope.")
    }

    private func formatStats(_ output: GraphStatsOutput) -> String {
        var lines = [
            "entities=\(output.counts.entities) | attributes=\(output.counts.attributes) | links=\(output.counts.links) | notes=\(output.counts.notes) | attachments=\(output.counts.attachments) | images=\(output.counts.images) | attachmentBytes=\(output.counts.attachmentBytes)",
            "nodeCount=\(output.nodeCount) | linkCount=\(output.linkCount) | isolatedNodeCount=\(output.isolatedNodeCount) | healthScore=\(output.healthScore) | healthIssueCount=\(output.healthIssueCount) | evidenceIDs=\(idList(output.evidenceIDs))"
        ]
        lines.append(contentsOf: output.hubs.map { hub in
            "hubAlias=\(alias(for: hub.node)) | label=\(boundedOutput(hub.label)) | degree=\(hub.degree) | evidenceID=\(hub.evidenceID.rawValue.uuidString)"
        })
        return boundedCollection(lines, empty: "Keine validierte Graph-Statistik verfügbar.")
    }

    private func formatCell(_ value: GraphChatQueryCellValue) -> String {
        switch value {
        case .text(let value):
            return boundedOutput(value)
        case .integer(let value):
            return String(value)
        case .decimal(let value):
            return String(value)
        case .date(let value):
            return ISO8601DateFormatter().string(from: value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .choice(let value):
            return boundedOutput(value)
        case .missing:
            return "missing"
        }
    }

    private func idList(_ ids: [GraphEvidenceID]) -> String {
        ids.map { $0.rawValue.uuidString }.joined(separator: ",")
    }

    private func normalizedAlias(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func boundedInput(_ value: String) -> String {
        boundedOutput(value.trimmingCharacters(in: .whitespacesAndNewlines), maximumLength: 500)
    }

    private func boundedOutput(
        _ value: String,
        maximumLength: Int? = nil
    ) -> String {
        let maximumLength = maximumLength ?? outputBudget.maximumValueCharacters
        guard value.count > maximumLength else {
            return value
        }
        let truncationMarker = " [gekürzt]"
        guard truncationMarker.count < maximumLength else {
            return String(value.prefix(maximumLength))
        }
        return String(
            value.prefix(maximumLength - truncationMarker.count)
        ) + truncationMarker
    }

    private func boundedCollection(
        _ lines: [String],
        empty: String
    ) -> String {
        guard lines.isEmpty == false else {
            return empty
        }
        return boundedOutput(
            lines.joined(separator: "\n"),
            maximumLength: outputBudget.maximumCollectionCharacters
        )
    }

    private func requiredValue(_ value: String?) throws -> String {
        guard let value else {
            throw invalidInput("Der Filter benötigt einen Wert.")
        }
        let bounded = boundedInput(value)
        guard bounded.isEmpty == false else {
            throw invalidInput("Der Filterwert darf nicht leer sein.")
        }
        return bounded
    }

    private func parseDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        let components = value.split(separator: "-").compactMap { Int($0) }
        if components.count == 3 {
            var dateComponents = DateComponents()
            dateComponents.calendar = Calendar(identifier: .gregorian)
            dateComponents.timeZone = TimeZone(secondsFromGMT: 0)
            dateComponents.year = components[0]
            dateComponents.month = components[1]
            dateComponents.day = components[2]
            if let date = dateComponents.date {
                return date
            }
        }
        throw invalidInput("Datum benötigt ISO-8601 oder YYYY-MM-DD.")
    }

    private func invalidInput(_ message: String) -> GraphChatToolError {
        GraphChatToolError(code: .invalidInput, message: message)
    }

    private func nonRepairable(
        _ reason: GraphChatToolNonRepairableReason,
        message: String
    ) -> GraphChatToolNonRepairableError {
        GraphChatToolNonRepairableError(
            reason: reason,
            publicError: GraphChatToolError(
                code: .invalidInput,
                message: message
            )
        )
    }

    private func looksLikeTechnicalIdentifier(
        _ value: String
    ) -> Bool {
        UUID(
            uuidString: value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ) != nil
    }

    private func isEntityAllowedByRequestScope(
        _ entityID: UUID
    ) -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let scopedEntityID):
            return entityID == scopedEntityID
        case .node(let node):
            return schemaContext.aliases.owningEntityID(for: node) == entityID
        case .selection(let nodes):
            return nodes.isEmpty == false
                && nodes.allSatisfy {
                    schemaContext.aliases.owningEntityID(for: $0)
                        == entityID
                }
        }
    }
}
