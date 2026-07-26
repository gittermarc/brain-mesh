//
//  GraphChatConversationContext.swift
//  BrainMesh
//
//  Strictly bounded provider snapshot built only from app-validated conversation facts.
//

import Foundation

nonisolated enum GraphChatConversationContextAliasTarget: Hashable, Sendable {
    case node(NodeRefKey, ownerEntityID: UUID?)
    case entity(UUID)
    case field(UUID, entityID: UUID)
    case resultSet(UUID, nodes: [NodeRefKey], entityID: UUID?)
    case group(String, nodes: [NodeRefKey], fieldID: UUID?, count: Int)
    case comparison([GraphChatConversationReference])
}

nonisolated struct GraphChatConversationContextAlias: Hashable, Sendable, Identifiable {
    let alias: String
    let label: String
    let target: GraphChatConversationContextAliasTarget
    let ordinal: Int?

    var id: String {
        alias
    }
}

nonisolated struct GraphChatConversationContextResult: Hashable, Sendable, Identifiable {
    let id: UUID
    let alias: String
    let kind: GraphChatConversationResultKind
    let state: GraphChatToolResultState
    let entityAlias: String?
    let itemAliases: [String]
    let groupAliases: [String]
    let sourceReferenceCount: Int
    let appliedFilters: [GraphChatAppliedFilter]
    let technicalDescription: String
}

nonisolated struct GraphChatConversationContextTurn: Hashable, Sendable, Identifiable {
    let id: UUID
    let completedAt: Date
    let toolKinds: [GraphChatToolKind]
    let resultAliases: [String]
    let technicalDescription: String
}

nonisolated struct GraphChatConversationContextQueryFilter: Hashable, Sendable {
    let fieldAlias: String
    let operation: String
    let valueDescription: String?
}

nonisolated struct GraphChatConversationContextQuerySort: Hashable, Sendable {
    let keyAlias: String
    let direction: GraphQuerySortDirection
}

nonisolated struct GraphChatConversationContextQuery: Hashable, Sendable {
    let version: Int
    let entityAlias: String
    let scopeAliases: [String]
    let filters: [GraphChatConversationContextQueryFilter]
    let sorting: [GraphChatConversationContextQuerySort]
    let projectionAliases: [String]
    let aggregation: String?
    let limit: Int
}

nonisolated struct GraphChatConversationContextResultRevalidation: Hashable, Sendable {
    let resultAlias: String
    let itemAliases: [String]
    let groupAliases: [String]
    let sourceReferenceCount: Int
    let plan: ValidatedGraphQueryPlan

    func contains(alias: String) -> Bool {
        resultAlias == alias || itemAliases.contains(alias) || groupAliases.contains(alias)
    }
}

nonisolated struct GraphChatConversationContextBudget: Hashable, Sendable {
    let maximumAliases: Int
    let maximumResults: Int
    let maximumResultItems: Int
    let maximumGroups: Int
    let maximumTurns: Int
    let maximumFormattedCharacters: Int

    static let `default` = GraphChatConversationContextBudget(
        maximumAliases: 256,
        maximumResults: 4,
        maximumResultItems: 48,
        maximumGroups: 16,
        maximumTurns: 6,
        maximumFormattedCharacters: 8_000
    )
}

nonisolated struct GraphChatConversationContextSnapshot: Hashable, Sendable {
    let conversationID: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let aliases: [GraphChatConversationContextAlias]
    let results: [GraphChatConversationContextResult]
    let turns: [GraphChatConversationContextTurn]
    let latestResultAlias: String?
    let lastEntityAlias: String?
    let lastFieldAlias: String?
    let lastGroupAlias: String?
    let lastNodeAlias: String?
    let lastComparisonAlias: String?
    let currentReferenceAlias: String?
    let currentResolvedScope: GraphChatResolvedConversationScope?
    let lastValidatedQuery: GraphChatConversationContextQuery?
    let resultRevalidations: [GraphChatConversationContextResultRevalidation]
    let pendingClarificationID: UUID?

    init(
        conversationID: UUID,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        aliases: [GraphChatConversationContextAlias],
        results: [GraphChatConversationContextResult],
        turns: [GraphChatConversationContextTurn],
        latestResultAlias: String?,
        lastEntityAlias: String?,
        lastFieldAlias: String?,
        lastGroupAlias: String?,
        lastNodeAlias: String?,
        lastComparisonAlias: String?,
        currentReferenceAlias: String?,
        currentResolvedScope: GraphChatResolvedConversationScope? = nil,
        lastValidatedQuery: GraphChatConversationContextQuery?,
        resultRevalidations: [GraphChatConversationContextResultRevalidation],
        pendingClarificationID: UUID?
    ) {
        self.conversationID = conversationID
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.aliases = aliases
        self.results = results
        self.turns = turns
        self.latestResultAlias = latestResultAlias
        self.lastEntityAlias = lastEntityAlias
        self.lastFieldAlias = lastFieldAlias
        self.lastGroupAlias = lastGroupAlias
        self.lastNodeAlias = lastNodeAlias
        self.lastComparisonAlias = lastComparisonAlias
        self.currentReferenceAlias = currentReferenceAlias
        self.currentResolvedScope = currentResolvedScope
        self.lastValidatedQuery = lastValidatedQuery
        self.resultRevalidations = resultRevalidations
        self.pendingClarificationID = pendingClarificationID
    }

    func alias(_ rawValue: String) -> GraphChatConversationContextAlias? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return aliases.first { $0.alias.uppercased() == normalized }
    }
}

nonisolated struct GraphChatConversationContextBuilder: Sendable {
    let budget: GraphChatConversationContextBudget

    init(budget: GraphChatConversationContextBudget = .default) {
        self.budget = budget
    }

    func makeSnapshot(
        from state: GraphChatConversationStateSnapshot,
        currentReference: GraphChatResolvedConversationReference? = nil,
        currentResolvedScope: GraphChatResolvedConversationScope? = nil
    ) -> GraphChatConversationContextSnapshot {
        if let currentResolvedScope {
            precondition(currentResolvedScope.graphScope == state.graphScope)
            precondition(currentResolvedScope.chatScope == state.chatScope)
            precondition(
                currentResolvedScope.conversationID
                    == state.conversationID
            )
        }
        var aliases: [GraphChatConversationContextAlias] = []
        var usedAliases = Set<String>()
        var stableAliasByReference: [String: String] = [:]

        func appendAlias(
            preferredAlias: String? = nil,
            prefix: String,
            stableKey: String,
            label: String,
            target: GraphChatConversationContextAliasTarget,
            ordinal: Int? = nil
        ) -> String? {
            guard aliases.count < budget.maximumAliases else {
                return nil
            }
            if let existing = stableAliasByReference[stableKey] {
                return existing
            }
            let base =
                preferredAlias.map(Self.normalizedAlias)
                ?? "\(prefix)_\(Self.stableToken(stableKey))"
            var candidate = base
            var suffix = 2
            while usedAliases.contains(candidate) {
                candidate = "\(base)_\(suffix)"
                suffix += 1
            }
            usedAliases.insert(candidate)
            stableAliasByReference[stableKey] = candidate
            aliases.append(
                GraphChatConversationContextAlias(
                    alias: candidate,
                    label: Self.bounded(label, limit: 160),
                    target: target,
                    ordinal: ordinal
                )
            )
            return candidate
        }

        for entity in state.entityReferences.reversed() {
            _ = appendAlias(
                preferredAlias: entity.alias?.rawValue,
                prefix: "CE",
                stableKey: GraphChatConversationReference.entity(entity.entityID).stableKey,
                label: entity.name,
                target: .entity(entity.entityID)
            )
        }
        for field in state.fieldReferences.reversed() {
            _ = appendAlias(
                preferredAlias: field.alias?.rawValue,
                prefix: "CF",
                stableKey: GraphChatConversationReference.field(field.fieldID).stableKey,
                label: field.name,
                target: .field(field.fieldID, entityID: field.entityID)
            )
        }
        for node in state.nodeReferences.reversed() {
            _ = appendAlias(
                prefix: "CN",
                stableKey: GraphChatConversationReference.node(node.node).stableKey,
                label: node.label,
                target: .node(node.node, ownerEntityID: node.ownerEntityID)
            )
        }

        let retainedResults = Array(state.resultContexts.suffix(budget.maximumResults))
        var reversedContextResults: [GraphChatConversationContextResult] = []
        var remainingItems = budget.maximumResultItems
        var remainingGroups = budget.maximumGroups

        for result in retainedResults.reversed() {
            let retainedReferences = Array(result.references.prefix(remainingItems))
            let retainedGroups = Array(result.groupReferences.prefix(remainingGroups))
            let resultAlias = appendAlias(
                prefix: "CR",
                stableKey: GraphChatConversationReference.result(result.id).stableKey,
                label: result.technicalDescription,
                target: .resultSet(
                    result.id,
                    nodes: retainedReferences.compactMap(Self.node(from:)),
                    entityID: result.entityID
                )
            )

            var itemAliases: [String] = []
            for reference in retainedReferences {
                guard
                    let target = Self.aliasTarget(
                        for: reference.reference,
                        state: state
                    )
                else {
                    continue
                }
                let alias = appendAlias(
                    prefix: "CI",
                    stableKey: reference.reference.stableKey,
                    label: reference.label,
                    target: target,
                    ordinal: reference.ordinal
                )
                if let alias {
                    itemAliases.append(alias)
                    remainingItems -= 1
                }
                if remainingItems == 0 {
                    break
                }
            }

            var groupAliases: [String] = []
            for group in retainedGroups {
                let alias = appendAlias(
                    prefix: "CG",
                    stableKey: GraphChatConversationReference.group(group.id).stableKey,
                    label: group.valueDescription,
                    target: .group(
                        group.id,
                        nodes: Array(group.memberNodes.prefix(budget.maximumResultItems)),
                        fieldID: group.fieldID,
                        count: group.count
                    )
                )
                if let alias {
                    groupAliases.append(alias)
                    remainingGroups -= 1
                }
                if remainingGroups == 0 {
                    break
                }
            }

            let entityAlias = result.entityID.flatMap { entityID in
                stableAliasByReference[GraphChatConversationReference.entity(entityID).stableKey]
            }
            if let resultAlias {
                reversedContextResults.append(
                    GraphChatConversationContextResult(
                        id: result.id,
                        alias: resultAlias,
                        kind: result.kind,
                        state: result.state,
                        entityAlias: entityAlias,
                        itemAliases: itemAliases,
                        groupAliases: groupAliases,
                        sourceReferenceCount: result.references.count,
                        appliedFilters: result.appliedFilters,
                        technicalDescription: Self.bounded(
                            result.technicalDescription,
                            limit: 180
                        )
                    )
                )
            }
        }
        let contextResults = Array(reversedContextResults.reversed())

        let comparisonAlias: String?
        if let comparison = state.lastComparison {
            comparisonAlias = appendAlias(
                preferredAlias: "LAST_COMPARISON",
                prefix: "CC",
                stableKey: "comparison:\(comparison.references.map(\.stableKey).joined(separator: "|"))",
                label: comparison.technicalDescription,
                target: .comparison(comparison.references)
            )
        } else {
            comparisonAlias = nil
        }

        let currentAlias: String?
        let resolvedCurrentReference =
            currentResolvedScope?.reference
            ?? currentReference
        if let resolvedCurrentReference,
            let currentTarget = target(from: resolvedCurrentReference)
        {
            currentAlias = appendAlias(
                preferredAlias: "CURRENT",
                prefix: "CURRENT",
                stableKey:
                    "current:\(resolvedCurrentReference.alias):\(resolvedCurrentReference.kind.rawValue)",
                label: resolvedCurrentReference.label,
                target: currentTarget
            )
        } else {
            currentAlias = nil
        }

        let resultAliasByID = Dictionary(
            uniqueKeysWithValues: contextResults.map { ($0.id, $0.alias) }
        )
        let turns = state.turnContexts.suffix(budget.maximumTurns).map { turn in
            GraphChatConversationContextTurn(
                id: turn.id,
                completedAt: turn.completedAt,
                toolKinds: turn.toolKinds,
                resultAliases: turn.resultContextIDs.compactMap { resultAliasByID[$0] },
                technicalDescription: Self.bounded(
                    turn.technicalDescription,
                    limit: 180
                )
            )
        }

        let latestResultAlias = contextResults.last?.alias
        let lastEntityAlias = state.entityReferences.last.flatMap {
            stableAliasByReference[GraphChatConversationReference.entity($0.entityID).stableKey]
        }
        let lastFieldAlias = state.fieldReferences.last.flatMap {
            stableAliasByReference[GraphChatConversationReference.field($0.fieldID).stableKey]
        }
        let lastNodeAlias: String?
        if case .node(let node)? = state.referenceTargets.singular {
            lastNodeAlias =
                stableAliasByReference[
                    GraphChatConversationReference.node(node).stableKey
                ]
        } else {
            lastNodeAlias = nil
        }
        let lastGroupAlias: String?
        if case .group(let groupID)? = state.referenceTargets.group {
            lastGroupAlias =
                stableAliasByReference[
                    GraphChatConversationReference.group(groupID).stableKey
                ]
        } else {
            lastGroupAlias = nil
        }

        let lastValidatedQuery = state.lastValidatedQueryPlan.flatMap { plan in
            querySummary(
                from: plan,
                stableAliasByReference: stableAliasByReference
            )
        }
        let latestQueryResultID = state.resultContexts.last(where: { $0.kind == .query })?.id
        let resultRevalidations: [GraphChatConversationContextResultRevalidation]
        if let plan = state.lastValidatedQueryPlan,
            let latestQueryResultID,
            let result = contextResults.first(where: { $0.id == latestQueryResultID })
        {
            resultRevalidations = [
                GraphChatConversationContextResultRevalidation(
                    resultAlias: result.alias,
                    itemAliases: result.itemAliases,
                    groupAliases: result.groupAliases,
                    sourceReferenceCount: result.sourceReferenceCount,
                    plan: plan
                )
            ]
        } else {
            resultRevalidations = []
        }

        return GraphChatConversationContextSnapshot(
            conversationID: state.conversationID,
            graphScope: state.graphScope,
            chatScope: state.chatScope,
            aliases: aliases,
            results: contextResults,
            turns: turns,
            latestResultAlias: latestResultAlias,
            lastEntityAlias: lastEntityAlias,
            lastFieldAlias: lastFieldAlias,
            lastGroupAlias: lastGroupAlias,
            lastNodeAlias: lastNodeAlias,
            lastComparisonAlias: comparisonAlias,
            currentReferenceAlias: currentAlias,
            currentResolvedScope: currentResolvedScope,
            lastValidatedQuery: lastValidatedQuery,
            resultRevalidations: resultRevalidations,
            pendingClarificationID: state.pendingClarification?.id
        )
    }

    private static func aliasTarget(
        for reference: GraphChatConversationReference,
        state: GraphChatConversationStateSnapshot
    ) -> GraphChatConversationContextAliasTarget? {
        switch reference {
        case .node(let node):
            let owner = state.nodeReferences.first(where: { $0.node == node })?.ownerEntityID
            return .node(node, ownerEntityID: owner)
        case .entity(let entityID):
            return .entity(entityID)
        case .field(let fieldID):
            guard let field = state.fieldReferences.first(where: { $0.fieldID == fieldID }) else {
                return nil
            }
            return .field(fieldID, entityID: field.entityID)
        case .result(let resultID):
            guard let result = state.resultContexts.first(where: { $0.id == resultID }) else {
                return nil
            }
            return .resultSet(
                resultID,
                nodes: result.references.compactMap(node(from:)),
                entityID: result.entityID
            )
        case .group(let groupID):
            guard let group = state.groupReferences.first(where: { $0.id == groupID }) else {
                return nil
            }
            return .group(
                groupID,
                nodes: group.memberNodes,
                fieldID: group.fieldID,
                count: group.count
            )
        }
    }

    private func target(
        from reference: GraphChatResolvedConversationReference
    ) -> GraphChatConversationContextAliasTarget? {
        switch reference.kind {
        case .node:
            guard let node = reference.singleNode else {
                return nil
            }
            return .node(node, ownerEntityID: reference.entityID)
        case .entity:
            guard let entityID = reference.entityID else {
                return nil
            }
            return .entity(entityID)
        case .field:
            guard let fieldID = reference.fieldID,
                let entityID = reference.entityID
            else {
                return nil
            }
            return .field(fieldID, entityID: entityID)
        case .group:
            guard let groupID = reference.groupID else {
                return nil
            }
            return .group(
                groupID,
                nodes: Array(reference.nodes.prefix(budget.maximumResultItems)),
                fieldID: reference.fieldID,
                count: reference.nodes.count
            )
        case .comparison:
            return .comparison(reference.nodes.map(GraphChatConversationReference.node))
        case .resultSet, .resultSubset:
            return .resultSet(
                Self.stableUUID(reference.alias),
                nodes: Array(reference.nodes.prefix(budget.maximumResultItems)),
                entityID: reference.entityID
            )
        }
    }

    private func querySummary(
        from plan: ValidatedGraphQueryPlan,
        stableAliasByReference: [String: String]
    ) -> GraphChatConversationContextQuery? {
        guard
            let entityAlias = stableAliasByReference[
                GraphChatConversationReference.entity(plan.entityID).stableKey
            ]
        else {
            return nil
        }
        let filters = plan.filters.compactMap { filter -> GraphChatConversationContextQueryFilter? in
            guard
                let fieldAlias = stableAliasByReference[
                    GraphChatConversationReference.field(filter.fieldID).stableKey
                ]
            else {
                return nil
            }
            return GraphChatConversationContextQueryFilter(
                fieldAlias: fieldAlias,
                operation: filter.operation.rawValue,
                valueDescription: filter.valueDescription.map {
                    Self.bounded($0, limit: 160)
                }
            )
        }
        let sorting = plan.sorting.compactMap { sort -> GraphChatConversationContextQuerySort? in
            switch sort.key {
            case .nodeName:
                return GraphChatConversationContextQuerySort(
                    keyAlias: "nodeName",
                    direction: sort.direction
                )
            case .field(let fieldID):
                guard
                    let fieldAlias = stableAliasByReference[
                        GraphChatConversationReference.field(fieldID).stableKey
                    ]
                else {
                    return nil
                }
                return GraphChatConversationContextQuerySort(
                    keyAlias: fieldAlias,
                    direction: sort.direction
                )
            }
        }
        let projections = plan.projection.compactMap { projection -> String? in
            switch projection {
            case .nodeIdentity:
                return "nodeIdentity"
            case .field(let fieldID):
                return stableAliasByReference[
                    GraphChatConversationReference.field(fieldID).stableKey
                ]
            }
        }
        let aggregation: String?
        switch plan.aggregation {
        case .none:
            aggregation = nil
        case .count:
            aggregation = "count"
        case .groupCount(let fieldID):
            aggregation = stableAliasByReference[
                GraphChatConversationReference.field(fieldID).stableKey
            ].map { "groupCount:\($0)" }
        case .minimum(let fieldID):
            aggregation = stableAliasByReference[
                GraphChatConversationReference.field(fieldID).stableKey
            ].map { "minimum:\($0)" }
        case .maximum(let fieldID):
            aggregation = stableAliasByReference[
                GraphChatConversationReference.field(fieldID).stableKey
            ].map { "maximum:\($0)" }
        }
        return GraphChatConversationContextQuery(
            version: plan.version,
            entityAlias: entityAlias,
            scopeAliases: scopeAliases(
                for: plan.scope,
                stableAliasByReference: stableAliasByReference
            ),
            filters: filters,
            sorting: sorting,
            projectionAliases: projections,
            aggregation: aggregation,
            limit: plan.limit
        )
    }

    private func scopeAliases(
        for scope: GraphResolvedQueryScope,
        stableAliasByReference: [String: String]
    ) -> [String] {
        switch scope {
        case .graph:
            return ["GRAPH"]
        case .entity(let entityID):
            return stableAliasByReference[
                GraphChatConversationReference.entity(entityID).stableKey
            ].map { [$0] } ?? ["ENTITY"]
        case .node(let node):
            return stableAliasByReference[
                GraphChatConversationReference.node(node).stableKey
            ].map { [$0] } ?? ["NODE"]
        case .selection(let nodes):
            return Array(
                nodes.compactMap { node in
                    stableAliasByReference[
                        GraphChatConversationReference.node(node).stableKey
                    ]
                }.prefix(budget.maximumResultItems))
        }
    }

    private static func node(
        from reference: GraphChatConversationResultReference
    ) -> NodeRefKey? {
        guard case .node(let node) = reference.reference else {
            return nil
        }
        return node
    }

    private static func normalizedAlias(_ value: String) -> String {
        let allowed = value.uppercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "_" ? character : "_"
        }
        return String(allowed.prefix(40))
    }

    private static func stableToken(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 36, uppercase: true).suffix(8).description
    }

    private static func stableUUID(_ value: String) -> UUID {
        let first = stableToken("first:\(value)").padding(
            toLength: 16,
            withPad: "0",
            startingAt: 0
        )
        let second = stableToken("second:\(value)").padding(
            toLength: 16,
            withPad: "0",
            startingAt: 0
        )
        let hexadecimalCharacters = Array("0123456789abcdef")
        let hex = (first + second).unicodeScalars.map { scalar -> Character in
            hexadecimalCharacters[Int(scalar.value) % hexadecimalCharacters.count]
        }
        let compact = String(hex.prefix(32))
        let formatted = [
            compact.prefix(8),
            compact.dropFirst(8).prefix(4),
            compact.dropFirst(12).prefix(4),
            compact.dropFirst(16).prefix(4),
            compact.dropFirst(20).prefix(12),
        ].map(String.init).joined(separator: "-")
        return UUID(uuidString: formatted)!
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit))
    }
}

nonisolated struct GraphChatConversationContextFormatter: Sendable {
    let budget: GraphChatConversationContextBudget

    init(budget: GraphChatConversationContextBudget = .default) {
        self.budget = budget
    }

    func format(
        _ snapshot: GraphChatConversationContextSnapshot,
        language: GraphChatResponseLanguage,
        maximumCharacters: Int? = nil
    ) -> String {
        var lines: [String] = []
        switch language {
        case .german:
            lines.append("VERTRAUENSWÜRDIGER CONVERSATION-KONTEXT")
            lines.append(
                "Nur diese appseitig validierten Aliase dürfen für Folgefragen verwendet werden.")
        case .english:
            lines.append("TRUSTED CONVERSATION CONTEXT")
            lines.append("Only these app-validated aliases may be used for follow-up references.")
        }

        if let current = snapshot.currentReferenceAlias {
            lines.append("currentReference=\(current)")
        }
        if let latest = snapshot.latestResultAlias {
            lines.append("latestResults=\(latest)")
        }
        if let value = snapshot.lastNodeAlias { lines.append("lastNode=\(value)") }
        if let value = snapshot.lastEntityAlias { lines.append("lastEntity=\(value)") }
        if let value = snapshot.lastFieldAlias { lines.append("lastField=\(value)") }
        if let value = snapshot.lastGroupAlias { lines.append("lastGroup=\(value)") }
        if let value = snapshot.lastComparisonAlias { lines.append("lastComparison=\(value)") }

        if snapshot.aliases.isEmpty == false {
            lines.append("ALIASES")
            for alias in snapshot.aliases {
                let ordinal = alias.ordinal.map { " ordinal=\($0)" } ?? ""
                lines.append(
                    "\(alias.alias) | \(kind(alias.target)) | \(bounded(alias.label, 160))\(ordinal)")
            }
        }

        if let query = snapshot.lastValidatedQuery {
            lines.append("LAST VALIDATED QUERY")
            let filters = query.filters.map { filter in
                [filter.fieldAlias, filter.operation, filter.valueDescription]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: "; ")
            let sorting = query.sorting.map {
                "\($0.keyAlias):\($0.direction.rawValue)"
            }.joined(separator: ",")
            lines.append(
                "version=\(query.version) | entity=\(query.entityAlias) | scope=\(query.scopeAliases.joined(separator: ",")) | filters=\(bounded(filters, 500)) | sorting=\(sorting) | projection=\(query.projectionAliases.joined(separator: ",")) | aggregation=\(query.aggregation ?? "none") | limit=\(query.limit)"
            )
        }

        if snapshot.results.isEmpty == false {
            lines.append("RESULTS")
            for result in snapshot.results {
                let filters = result.appliedFilters.map { filter in
                    [filter.fieldName, filter.operationDescription, filter.valueDescription]
                        .compactMap { $0 }
                        .joined(separator: " ")
                }.joined(separator: "; ")
                lines.append(
                    "\(result.alias) | kind=\(result.kind.rawValue) | state=\(result.state.rawValue) | items=\(result.itemAliases.joined(separator: ",")) | groups=\(result.groupAliases.joined(separator: ",")) | filters=\(bounded(filters, 400))"
                )
            }
        }

        if snapshot.turns.isEmpty == false {
            lines.append("TRUSTED TURN SUMMARIES")
            for turn in snapshot.turns {
                lines.append(
                    "tools=\(turn.toolKinds.map(\.rawValue).joined(separator: ",")) | results=\(turn.resultAliases.joined(separator: ",")) | \(bounded(turn.technicalDescription, 180))"
                )
            }
        }

        let formatted = lines.joined(separator: "\n")
        return bounded(
            formatted,
            maximumCharacters ?? budget.maximumFormattedCharacters
        )
    }

    private func kind(_ target: GraphChatConversationContextAliasTarget) -> String {
        switch target {
        case .node:
            return "node"
        case .entity:
            return "entity"
        case .field:
            return "field"
        case .resultSet:
            return "resultSet"
        case .group:
            return "group"
        case .comparison:
            return "comparison"
        }
    }

    private func bounded(_ value: String, _ limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit))
    }
}
