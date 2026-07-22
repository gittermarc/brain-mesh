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
            )
        )
    }

    init(
        describeSchemaTool: DescribeGraphSchemaTool,
        searchGraphTool: SearchGraphTool,
        queryDetailValuesTool: QueryDetailValuesTool,
        getNodeTool: GetNodeTool,
        getNeighborsTool: GetNeighborsTool,
        graphStatsTool: GraphStatsTool
    ) {
        self.describeSchemaTool = describeSchemaTool
        self.searchGraphTool = searchGraphTool
        self.queryDetailValuesTool = queryDetailValuesTool
        self.getNodeTool = getNodeTool
        self.getNeighborsTool = getNeighborsTool
        self.graphStatsTool = graphStatsTool
    }

    func makeRunner(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        conversationTransaction: GraphChatConversationStateTransaction,
        conversationContext: GraphChatConversationContextSnapshot,
        referenceResolver: GraphChatConversationReferenceResolver,
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning {
        GraphChatModelToolRuntime(
            scope: scope,
            schemaContext: schemaContext,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
            conversationTransaction: conversationTransaction,
            conversationContext: conversationContext,
            referenceResolver: referenceResolver,
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
    private let scope: GraphChatScope
    private let schemaContext: GraphSchemaContext
    private let context: GraphChatToolContext
    private let evidenceRegistry: GraphChatEvidenceRegistry
    private let conversationTransaction: GraphChatConversationStateTransaction
    private let conversationContext: GraphChatConversationContextSnapshot
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let validator: GraphQueryPlanValidator
    private let describeSchemaTool: DescribeGraphSchemaTool
    private let searchGraphTool: SearchGraphTool
    private let queryDetailValuesTool: QueryDetailValuesTool
    private let getNodeTool: GetNodeTool
    private let getNeighborsTool: GetNeighborsTool
    private let graphStatsTool: GraphStatsTool

    private var nodeByAlias: [String: NodeRefKey]
    private var aliasByNode: [NodeRefKey: String]
    private var nextNodeAliasNumber: Int

    init(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        conversationTransaction: GraphChatConversationStateTransaction,
        conversationContext: GraphChatConversationContextSnapshot,
        referenceResolver: GraphChatConversationReferenceResolver,
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
        self.conversationTransaction = conversationTransaction
        self.conversationContext = conversationContext
        self.referenceResolver = referenceResolver
        self.validator = validator
        self.describeSchemaTool = describeSchemaTool
        self.searchGraphTool = searchGraphTool
        self.queryDetailValuesTool = queryDetailValuesTool
        self.getNodeTool = getNodeTool
        self.getNeighborsTool = getNeighborsTool
        self.graphStatsTool = graphStatsTool

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
        switch request {
        case .describeSchema(let exampleFieldAliases):
            return try await describeSchema(exampleFieldAliases: exampleFieldAliases)
        case .searchGraph(let query, let limit):
            return try await searchGraph(query: query, limit: limit)
        case .queryDetailValues(let queryRequest):
            return try await queryDetailValues(queryRequest)
        case .getNode(let nodeAlias, let relatedLimit):
            return try await getNode(alias: nodeAlias, relatedLimit: relatedLimit)
        case .getNeighbors(let nodeAlias, let limit):
            return try await getNeighbors(alias: nodeAlias, limit: limit)
        case .graphStats(let hubLimit):
            return try await graphStats(hubLimit: hubLimit)
        }
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
        return GraphChatModelToolResponse(
            tool: .describeGraphSchema,
            state: result.state,
            content: formatSchema(result.payload?.snapshot),
            evidenceIDs: result.evidence.map(\.id)
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
        return GraphChatModelToolResponse(
            tool: .searchGraph,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id)
        )
    }

    private func queryDetailValues(
        _ request: GraphChatModelQueryRequest
    ) async throws -> GraphChatModelToolResponse {
        let plan = try await makeQueryPlan(request)
        let validatedPlan = try validator.validate(plan, against: schemaContext)
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
        let content = result.payload.map { output in
            formatQueryResult(output.result)
        } ?? "Keine validierten Detailwerte im aktiven Scope."
        return GraphChatModelToolResponse(
            tool: .queryDetailValues,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id)
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
        let content = result.payload.map(formatNode) ?? "Node nicht im aktiven Scope gefunden."
        return GraphChatModelToolResponse(
            tool: .getNode,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id)
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
        let content = result.payload.map(formatNeighbors) ?? "Keine direkten Nachbarn im aktiven Scope."
        return GraphChatModelToolResponse(
            tool: .getNeighbors,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id)
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
        let content = result.payload.map(formatStats) ?? "Keine validierte Graph-Statistik verfügbar."
        return GraphChatModelToolResponse(
            tool: .graphStats,
            state: result.state,
            content: content,
            evidenceIDs: result.evidence.map(\.id)
        )
    }

    private func register(_ evidence: [GraphEvidence]) async throws {
        try await evidenceRegistry.register(evidence)
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
    ) async throws -> GraphQueryPlan {
        let entityAlias = GraphEntityAlias(normalizedAlias(request.entityAlias))
        guard let entity = schemaContext.aliases.entity(for: entityAlias) else {
            throw invalidInput("Unbekannter Entity-Alias: \(request.entityAlias)")
        }
        guard (1...QueryDetailValuesTool.maximumResultCount).contains(request.limit) else {
            throw GraphChatToolError(
                code: .budgetExceeded,
                message: "QueryDetailValues erlaubt höchstens \(QueryDetailValuesTool.maximumResultCount) Ergebnisse."
            )
        }

        let filters = try request.filters.map(makeFilter)
        let sorting = try makeSorting(request)
        let projection = try makeProjection(request.projectionFieldAliases)
        let aggregation = try makeAggregation(
            name: request.aggregation,
            fieldAlias: request.aggregationFieldAlias
        )
        let queryScope = try await resolvedQueryScope(
            alias: request.conversationReferenceAlias,
            expectedEntityID: entity.entityID
        )
        return GraphQueryPlan(
            entityAlias: entityAlias,
            scope: queryScope,
            filters: filters,
            sorting: sorting,
            projection: projection,
            aggregation: aggregation,
            limit: request.limit
        )
    }

    private func makeFilter(
        _ request: GraphChatModelQueryFilterRequest
    ) throws -> GraphQueryFilter {
        let fieldAlias = GraphFieldAlias(normalizedAlias(request.fieldAlias))
        guard let field = schemaContext.aliases.field(for: fieldAlias) else {
            throw invalidInput("Unbekannter Feld-Alias: \(request.fieldAlias)")
        }
        guard let operation = GraphQueryFilterOperator(rawValue: request.operation) else {
            throw invalidInput("Unbekannter Filter-Operator: \(request.operation)")
        }
        let value = try makeFilterValue(
            operation: operation,
            field: field,
            value: request.value,
            secondValue: request.secondValue,
            values: request.values
        )
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
        _ request: GraphChatModelQueryRequest
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
        guard schemaContext.aliases.field(for: alias) != nil else {
            throw invalidInput("Unbekannter Sortierfeld-Alias: \(rawKey)")
        }
        return [GraphQuerySort(key: .field(alias), direction: direction)]
    }

    private func makeProjection(
        _ rawAliases: [String]
    ) throws -> [GraphQueryProjection] {
        var result: [GraphQueryProjection] = [.nodeIdentity]
        var seen = Set<GraphFieldAlias>()
        for rawAlias in rawAliases {
            let alias = GraphFieldAlias(normalizedAlias(rawAlias))
            guard schemaContext.aliases.field(for: alias) != nil else {
                throw invalidInput("Unbekannter Projektionsfeld-Alias: \(rawAlias)")
            }
            if seen.insert(alias).inserted {
                result.append(.field(alias))
            }
        }
        return result
    }

    private func makeAggregation(
        name: String?,
        fieldAlias: String?
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
        guard schemaContext.aliases.field(for: alias) != nil else {
            throw invalidInput("Unbekannter Aggregationsfeld-Alias: \(rawFieldAlias)")
        }
        switch name {
        case "groupCount":
            return .groupCount(alias)
        case "minimum":
            return .minimum(alias)
        case "maximum":
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
            throw invalidInput("Der Conversation-Alias \(rawAlias) ist nicht eindeutig und aktuell auflösbar.")
        }
        nodeByAlias[alias] = node
        aliasByNode[node] = alias
        return node
    }

    private func resolvedQueryScope(
        alias rawAlias: String?,
        expectedEntityID: UUID
    ) async throws -> GraphChatScope {
        guard let rawAlias, rawAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return scope
        }
        let resolution = try await referenceResolver.resolve(
            .alias(normalizedAlias(rawAlias)),
            in: conversationContext,
            expectedGraphScope: scope.graphScope,
            expectedChatScope: scope,
            expectedEntityID: expectedEntityID
        )
        guard case .resolved(let reference) = resolution else {
            throw invalidInput("Der Conversation-Alias \(rawAlias) ist für diese Query nicht gültig.")
        }
        switch reference.kind {
        case .entity:
            guard let entityID = reference.entityID else {
                throw invalidInput("Der Conversation-Alias enthält keine gültige Entity.")
            }
            return .entity(entityID, in: scope.graphScope)
        case .node:
            guard let node = reference.singleNode else {
                throw invalidInput("Der Conversation-Alias enthält keinen einzelnen Node.")
            }
            return .node(node, in: scope.graphScope)
        case .resultSet, .resultSubset, .group, .comparison:
            guard reference.nodes.isEmpty == false else {
                throw invalidInput("Die referenzierte Ergebnismenge ist leer.")
            }
            return try .selection(reference.nodes, in: scope.graphScope)
        case .field:
            throw invalidInput("Ein Feld-Alias kann nicht als Query-Ergebnismenge verwendet werden.")
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
            maximumLength: 12_000
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
            lines.append("notes=\(boundedOutput(output.notes, maximumLength: 1_000))")
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
        maximumLength: Int = 600
    ) -> String {
        guard value.count > maximumLength else {
            return value
        }
        return String(value.prefix(maximumLength)) + " [gekürzt]"
    }

    private func boundedCollection(
        _ lines: [String],
        empty: String
    ) -> String {
        guard lines.isEmpty == false else {
            return empty
        }
        return boundedOutput(lines.joined(separator: "\n"), maximumLength: 16_000)
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
}
