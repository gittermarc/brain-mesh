//
//  GraphChatContextualSuggestions.swift
//  BrainMesh
//
//  Scope-aware, deterministic starter questions backed by productive tools.
//

import Foundation

nonisolated enum GraphChatSuggestionKind: String, CaseIterable, Hashable, Sendable {
    case list
    case detail
    case statistics
    case structure

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .detail:
            return "doc.text.magnifyingglass"
        case .statistics:
            return "chart.bar.xaxis"
        case .structure:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

nonisolated struct GraphChatEmptyStateSuggestion: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let kind: GraphChatSuggestionKind
    let accessibilityLabel: String
    let accessibilityHint: String

    init(
        id: String,
        title: String,
        prompt: String,
        kind: GraphChatSuggestionKind = .detail,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel ?? "\(title): \(prompt)"
        self.accessibilityHint = accessibilityHint ?? "Übernimmt diese Frage in das Eingabefeld."
    }
}

nonisolated struct GraphChatSuggestionContext: Sendable {
    let schema: GraphSchemaContext
    let scope: GraphChatScope
    let launchContext: GraphChatLaunchContext
    let availableTools: Set<GraphChatToolKind>
    let modelAvailability: GraphChatAvailabilityPresentationState
    let language: GraphChatResponseLanguage

    init(
        schema: GraphSchemaContext,
        scope: GraphChatScope,
        launchContext: GraphChatLaunchContext,
        availableTools: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        modelAvailability: GraphChatAvailabilityPresentationState = .available,
        language: GraphChatResponseLanguage = GraphChatResponseLanguageSelector.systemFallback()
    ) {
        self.schema = schema
        self.scope = scope
        self.launchContext = launchContext
        self.availableTools = availableTools
        self.modelAvailability = modelAvailability
        self.language = language
    }
}

nonisolated enum GraphChatEmptyStateSuggestionBuilder {
    static let maximumSuggestions = 4
    private static let maximumDirectNodeInspections = GraphChatToolBudgetPolicy.default.maximumCalls

    static func suggestions(
        for context: GraphChatSuggestionContext
    ) -> [GraphChatEmptyStateSuggestion] {
        guard context.modelAvailability.isAvailable else {
            return []
        }

        let candidates: [Candidate]
        switch context.launchContext {
        case .graph:
            candidates = graphCandidates(context)
        case .entity(let entityReference):
            candidates = entityCandidates(context, reference: entityReference)
        case .detailField(let fieldReference):
            candidates = fieldCandidates(context, reference: fieldReference)
        case .node(let nodeReference):
            candidates = nodeCandidates(context, reference: nodeReference)
        case .selection(let nodeReferences):
            candidates = selectionCandidates(context, references: nodeReferences)
        case .healthFinding(let finding):
            candidates = healthCandidates(context, finding: finding)
        }

        return ranked(candidates, context: context)
    }

    /// Compatibility entry used by previews and older callers that only own a snapshot.
    /// Contextual production callers should pass a full `GraphChatSuggestionContext`.
    static func suggestions(
        for snapshot: GraphSchemaSnapshot,
        scope: GraphChatScope
    ) -> [GraphChatEmptyStateSuggestion] {
        let aliases = GraphSchemaAliasMap(
            graphScope: scope.graphScope,
            entitiesByAlias: [:],
            fieldsByAlias: [:],
            nodeEntityIDs: [:]
        )
        return suggestions(
            for: GraphChatSuggestionContext(
                schema: GraphSchemaContext(
                    graphScope: scope.graphScope,
                    snapshot: snapshot,
                    aliases: aliases
                ),
                scope: scope,
                launchContext: .inferred(from: scope)
            )
        )
    }

    private static func graphCandidates(
        _ context: GraphChatSuggestionContext
    ) -> [Candidate] {
        var result: [Candidate] = []
        let text = Texts(context.language)

        if tool(.graphStats, isAvailableIn: context),
           case .graph = context.scope.target {
            result.append(
                Candidate(
                    id: "graph-overview",
                    semanticKey: "graph-overview",
                    priority: 10,
                    kind: .detail,
                    requiredTools: [.graphStats],
                    title: text.graphOverviewTitle,
                    prompt: text.graphOverviewPrompt(context.schema.snapshot.graphName)
                )
            )
            result.append(
                Candidate(
                    id: "graph-links",
                    semanticKey: "graph-links",
                    priority: 30,
                    kind: .structure,
                    requiredTools: [.graphStats],
                    title: text.strongestLinksTitle,
                    prompt: text.strongestLinksPrompt
                )
            )
        }

        if let entity = context.schema.snapshot.entities
            .filter({ $0.attributeCount > 0 })
            .sorted(by: entitySort)
            .first,
           tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-entity-list-\(entity.alias.rawValue)",
                    semanticKey: "entity-list-\(entity.alias.rawValue)",
                    priority: 20,
                    kind: .list,
                    requiredTools: [.queryDetailValues],
                    title: text.entityListTitle,
                    prompt: text.graphEntityListPrompt(entity.name)
                )
            )
        }

        if let pair = preferredChoiceField(in: context.schema.snapshot),
           tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-choice-\(pair.field.alias.rawValue)",
                    semanticKey: "choice-distribution-\(pair.field.alias.rawValue)",
                    priority: 15,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.distributionPrompt(
                        entity: pair.entity.name,
                        field: pair.field.name
                    )
                )
            )
        } else if let pair = firstField(
            in: context.schema.snapshot,
            matching: { $0.type == .date }
        ), tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-date-\(pair.field.alias.rawValue)",
                    semanticKey: "date-overdue-\(pair.field.alias.rawValue)",
                    priority: 15,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.overdueTitle,
                    prompt: text.overduePrompt(
                        entity: pair.entity.name,
                        field: pair.field.name
                    )
                )
            )
        }

        if let pair = firstField(
            in: context.schema.snapshot,
            matching: { _ in true }
        ), tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-missing-\(pair.field.alias.rawValue)",
                    semanticKey: "missing-\(pair.field.alias.rawValue)",
                    priority: 40,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.missingValuesTitle,
                    prompt: text.missingValuesPrompt(
                        entity: pair.entity.name,
                        field: pair.field.name
                    )
                )
            )
        }

        return result
    }

    private static func entityCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatEntityContextReference
    ) -> [Candidate] {
        guard let entity = entity(
            id: reference.id,
            in: context.schema
        ), scopeAllows(entityID: reference.id, context: context),
        tool(.queryDetailValues, isAvailableIn: context) else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = [
            Candidate(
                id: "entity-list-\(entity.alias.rawValue)",
                semanticKey: "entity-list-\(entity.alias.rawValue)",
                priority: 10,
                kind: .list,
                requiredTools: [.queryDetailValues],
                title: text.entityListTitle,
                prompt: text.entityListPrompt(entity.name)
            )
        ]

        if let field = preferredChoiceField(in: entity) {
            result.append(
                Candidate(
                    id: "entity-choice-\(field.alias.rawValue)",
                    semanticKey: "choice-distribution-\(field.alias.rawValue)",
                    priority: 20,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.distributionPrompt(entity: entity.name, field: field.name)
                )
            )
        }

        if let dateField = entity.fields.first(where: { $0.type == .date }) {
            result.append(
                Candidate(
                    id: "entity-newest-\(dateField.alias.rawValue)",
                    semanticKey: "newest-\(dateField.alias.rawValue)",
                    priority: 30,
                    kind: .list,
                    requiredTools: [.queryDetailValues],
                    title: text.newestTitle,
                    prompt: text.newestPrompt(entity: entity.name, field: dateField.name)
                )
            )
        }

        if let field = entity.fields.first {
            result.append(
                Candidate(
                    id: "entity-missing-\(field.alias.rawValue)",
                    semanticKey: "missing-\(field.alias.rawValue)",
                    priority: 40,
                    kind: .detail,
                    requiredTools: [.queryDetailValues],
                    title: text.missingValuesTitle,
                    prompt: text.missingValuesPrompt(entity: entity.name, field: field.name)
                )
            )
        }

        if let field = entity.fields.first(where: supportsMinimumMaximum) {
            result.append(
                Candidate(
                    id: "entity-range-\(field.alias.rawValue)",
                    semanticKey: "range-\(field.alias.rawValue)",
                    priority: 35,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.rangeTitle,
                    prompt: text.rangePrompt(entity: entity.name, field: field.name)
                )
            )
        }

        return result
    }

    private static func fieldCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatFieldContextReference
    ) -> [Candidate] {
        guard let pair = field(id: reference.id, in: context.schema),
              pair.entityID == reference.entity.id,
              scopeAllows(entityID: reference.entity.id, context: context),
              tool(.queryDetailValues, isAvailableIn: context) else {
            return []
        }

        let entity = pair.entity
        let field = pair.field
        let text = Texts(context.language)
        var result: [Candidate] = []

        if supportsDistribution(field) {
            result.append(
                Candidate(
                    id: "field-distribution-\(field.alias.rawValue)",
                    semanticKey: "field-frequency-\(field.alias.rawValue)",
                    priority: 10,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.distributionPrompt(entity: entity.name, field: field.name)
                )
            )
        } else if supportsCommonValues(field) {
            result.append(
                Candidate(
                    id: "field-common-\(field.alias.rawValue)",
                    semanticKey: "field-frequency-\(field.alias.rawValue)",
                    priority: 10,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.commonValuesTitle,
                    prompt: text.commonValuesPrompt(entity: entity.name, field: field.name)
                )
            )
        }

        result.append(
            Candidate(
                id: "field-missing-\(field.alias.rawValue)",
                semanticKey: "missing-\(field.alias.rawValue)",
                priority: 15,
                kind: .detail,
                requiredTools: [.queryDetailValues],
                title: text.missingValuesTitle,
                prompt: text.missingValuesPrompt(entity: entity.name, field: field.name)
            )
        )
        result.append(
            Candidate(
                id: "field-nodes-\(field.alias.rawValue)",
                semanticKey: "field-nodes-\(field.alias.rawValue)",
                priority: 30,
                kind: .list,
                requiredTools: [.queryDetailValues],
                title: text.affectedNodesTitle,
                prompt: text.fieldNodesPrompt(entity: entity.name, field: field.name)
            )
        )

        if supportsMinimumMaximum(field) {
            result.append(
                Candidate(
                    id: "field-range-\(field.alias.rawValue)",
                    semanticKey: "range-\(field.alias.rawValue)",
                    priority: 25,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.rangeTitle,
                    prompt: text.rangePrompt(entity: entity.name, field: field.name)
                )
            )
        }

        return result
    }

    private static func nodeCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatNodeContextReference
    ) -> [Candidate] {
        guard case .node(let scopedNode) = context.scope.target,
              scopedNode == reference.node else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []

        if tool(.getNode, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "node-describe-\(reference.node.id.uuidString)",
                    semanticKey: "node-describe",
                    priority: 10,
                    kind: .detail,
                    requiredTools: [.getNode],
                    title: text.describeNodeTitle,
                    prompt: text.describeNodePrompt(reference.label)
                )
            )
            result.append(
                Candidate(
                    id: "node-details-\(reference.node.id.uuidString)",
                    semanticKey: "node-details",
                    priority: 30,
                    kind: .list,
                    requiredTools: [.getNode],
                    title: text.nodeDetailsTitle,
                    prompt: text.nodeDetailsPrompt(reference.label)
                )
            )
        }

        if tool(.getNeighbors, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "node-neighbors-\(reference.node.id.uuidString)",
                    semanticKey: "node-neighbors",
                    priority: 20,
                    kind: .structure,
                    requiredTools: [.getNeighbors],
                    title: text.neighborsTitle,
                    prompt: text.neighborsPrompt(reference.label)
                )
            )
            result.append(
                Candidate(
                    id: "node-directions-\(reference.node.id.uuidString)",
                    semanticKey: "node-directions",
                    priority: 25,
                    kind: .statistics,
                    requiredTools: [.getNeighbors],
                    title: text.connectionDirectionsTitle,
                    prompt: text.connectionDirectionsPrompt(reference.label)
                )
            )
        }

        return result
    }

    private static func selectionCandidates(
        _ context: GraphChatSuggestionContext,
        references: [GraphChatNodeContextReference]
    ) -> [Candidate] {
        guard case .selection(let scopedNodes) = context.scope.target else {
            return []
        }
        let selected = references.filter { scopedNodes.contains($0.node) }
        guard selected.isEmpty == false else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = []
        let canInspectEverySelectedNode = selected.count <= maximumDirectNodeInspections
            && tool(.getNode, isAvailableIn: context)

        if canInspectEverySelectedNode {
            result.append(
                Candidate(
                    id: "selection-summary",
                    semanticKey: "selection-summary",
                    priority: 10,
                    kind: .detail,
                    requiredTools: [.getNode],
                    title: text.selectionSummaryTitle,
                    prompt: text.selectionSummaryPrompt(selected.count)
                )
            )
            result.append(
                Candidate(
                    id: "selection-entities",
                    semanticKey: "selection-entities",
                    priority: 20,
                    kind: .statistics,
                    requiredTools: [.getNode],
                    title: text.groupSelectionTitle,
                    prompt: text.groupSelectionByEntityPrompt(selected.count)
                )
            )
        }

        if selected.count > 1, canInspectEverySelectedNode {
            result.append(
                Candidate(
                    id: "selection-compare",
                    semanticKey: "selection-compare",
                    priority: 30,
                    kind: .list,
                    requiredTools: [.getNode],
                    title: text.compareSelectionTitle,
                    prompt: text.compareSelectionPrompt(selected.count)
                )
            )
        }

        if let entityID = commonEntityID(selected),
           let entity = entity(id: entityID, in: context.schema),
           let field = preferredChoiceField(in: entity),
           tool(.queryDetailValues, isAvailableIn: context),
           scopeAllows(entityID: entityID, context: context) {
            result.append(
                Candidate(
                    id: "selection-choice-\(field.alias.rawValue)",
                    semanticKey: "selection-choice-\(field.alias.rawValue)",
                    priority: 15,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.selectionDistributionPrompt(
                        count: selected.count,
                        field: field.name
                    )
                )
            )
        }

        if selected.count <= maximumDirectNodeInspections,
           tool(.getNeighbors, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "selection-connections",
                    semanticKey: "selection-connections",
                    priority: 40,
                    kind: .structure,
                    requiredTools: [.getNeighbors],
                    title: text.selectionConnectionsTitle,
                    prompt: text.selectionConnectionsPrompt(selected.count)
                )
            )
        }

        return result
    }

    private static func healthCandidates(
        _ context: GraphChatSuggestionContext,
        finding: GraphChatHealthFindingContext
    ) -> [Candidate] {
        let text = Texts(context.language)
        var result: [Candidate] = []
        let canInspectNodes = finding.affectedNodes.isEmpty == false
            && finding.affectedNodes.count <= maximumDirectNodeInspections
            && tool(.getNode, isAvailableIn: context)
        let canUseGraphStats: Bool = {
            guard case .graph = context.scope.target else {
                return false
            }
            return tool(.graphStats, isAvailableIn: context)
        }()

        if canInspectNodes || canUseGraphStats {
            result.append(
                Candidate(
                    id: "health-explain-\(finding.id)",
                    semanticKey: "health-explain-\(finding.id)",
                    priority: 10,
                    kind: .detail,
                    requiredTools: canInspectNodes ? [.getNode] : [.graphStats],
                    title: text.explainFindingTitle,
                    prompt: text.explainFindingPrompt(finding)
                )
            )
        }

        if canInspectNodes {
            result.append(
                Candidate(
                    id: "health-list-\(finding.id)",
                    semanticKey: "health-list-\(finding.id)",
                    priority: 20,
                    kind: .list,
                    requiredTools: [.getNode],
                    title: text.affectedNodesTitle,
                    prompt: text.findingNodesPrompt(finding)
                )
            )
            result.append(
                Candidate(
                    id: "health-group-\(finding.id)",
                    semanticKey: "health-group-\(finding.id)",
                    priority: 30,
                    kind: .statistics,
                    requiredTools: [.getNode],
                    title: text.groupSelectionTitle,
                    prompt: text.findingGroupPrompt(finding)
                )
            )
            result.append(
                Candidate(
                    id: "health-details-\(finding.id)",
                    semanticKey: "health-details-\(finding.id)",
                    priority: 40,
                    kind: .structure,
                    requiredTools: [.getNode],
                    title: text.nodeDetailsTitle,
                    prompt: text.findingDetailsPrompt(finding)
                )
            )
        }

        return result
    }

    private static func ranked(
        _ candidates: [Candidate],
        context: GraphChatSuggestionContext
    ) -> [GraphChatEmptyStateSuggestion] {
        let sorted = candidates
            .filter { candidate in
                candidate.requiredTools.isSubset(of: context.availableTools)
            }
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority < $1.priority
                }
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.id < $1.id
            }

        var seenSemanticKeys = Set<String>()
        var seenPrompts = Set<String>()
        var unique: [Candidate] = []
        for candidate in sorted {
            let promptKey = BMSearch.fold(candidate.prompt)
            guard seenSemanticKeys.insert(candidate.semanticKey).inserted,
                  seenPrompts.insert(promptKey).inserted else {
                continue
            }
            unique.append(candidate)
        }

        var selected: [Candidate] = []
        var selectedKinds = Set<GraphChatSuggestionKind>()
        for candidate in unique where selected.count < maximumSuggestions {
            guard selectedKinds.insert(candidate.kind).inserted else {
                continue
            }
            selected.append(candidate)
        }
        for candidate in unique where selected.count < maximumSuggestions {
            guard selected.contains(where: { $0.id == candidate.id }) == false else {
                continue
            }
            selected.append(candidate)
        }

        let text = Texts(context.language)
        return selected.map {
            GraphChatEmptyStateSuggestion(
                id: $0.id,
                title: $0.title,
                prompt: $0.prompt,
                kind: $0.kind,
                accessibilityLabel: "\($0.title): \($0.prompt)",
                accessibilityHint: text.suggestionAccessibilityHint
            )
        }
    }

    private static func tool(
        _ tool: GraphChatToolKind,
        isAvailableIn context: GraphChatSuggestionContext
    ) -> Bool {
        context.availableTools.contains(tool)
    }

    private static func scopeAllows(
        entityID: UUID,
        context: GraphChatSuggestionContext
    ) -> Bool {
        switch context.scope.target {
        case .graph:
            return true
        case .entity(let scopedEntityID):
            return scopedEntityID == entityID
        case .node(let node):
            return context.schema.aliases.owningEntityID(for: node) == entityID
                || (node.kind == .entity && node.id == entityID)
        case .selection(let nodes):
            return nodes.allSatisfy {
                context.schema.aliases.owningEntityID(for: $0) == entityID
                    || ($0.kind == .entity && $0.id == entityID)
            }
        }
    }

    private static func entity(
        id: UUID,
        in schema: GraphSchemaContext
    ) -> GraphSchemaEntity? {
        guard let resolution = schema.aliases.entitiesByAlias.values.first(
            where: { $0.entityID == id }
        ) else {
            return nil
        }
        return schema.snapshot.entities.first { $0.alias == resolution.alias }
    }

    private static func field(
        id: UUID,
        in schema: GraphSchemaContext
    ) -> (entity: GraphSchemaEntity, field: GraphSchemaField, entityID: UUID)? {
        guard let resolution = schema.aliases.fieldsByAlias.values.first(
            where: { $0.fieldID == id }
        ), let entity = schema.snapshot.entities.first(
            where: { $0.alias == resolution.entityAlias }
        ), let field = entity.fields.first(
            where: { $0.alias == resolution.alias }
        ) else {
            return nil
        }
        return (entity, field, resolution.entityID)
    }

    private static func firstField(
        in snapshot: GraphSchemaSnapshot,
        matching predicate: (GraphSchemaField) -> Bool
    ) -> (entity: GraphSchemaEntity, field: GraphSchemaField)? {
        for entity in snapshot.entities.sorted(by: entitySort) {
            if let field = entity.fields.first(where: predicate) {
                return (entity, field)
            }
        }
        return nil
    }

    private static func preferredChoiceField(
        in snapshot: GraphSchemaSnapshot
    ) -> (entity: GraphSchemaEntity, field: GraphSchemaField)? {
        let entities = snapshot.entities.sorted(by: entitySort)
        for entity in entities {
            if let field = preferredChoiceField(in: entity) {
                return (entity, field)
            }
        }
        return nil
    }

    private static func preferredChoiceField(
        in entity: GraphSchemaEntity
    ) -> GraphSchemaField? {
        let choiceFields = entity.fields.filter { $0.type == .singleChoice }
        return choiceFields.first {
            BMSearch.fold($0.name).contains("status")
        } ?? choiceFields.first
    }

    private static func supportsDistribution(_ field: GraphSchemaField) -> Bool {
        switch field.type {
        case .singleChoice, .toggle:
            return true
        case .singleLineText, .multiLineText, .numberInt, .numberDouble, .date:
            return false
        }
    }

    private static func supportsCommonValues(_ field: GraphSchemaField) -> Bool {
        field.type == .singleLineText
    }

    private static func supportsMinimumMaximum(_ field: GraphSchemaField) -> Bool {
        switch field.type {
        case .numberInt, .numberDouble, .date:
            return true
        case .singleLineText, .multiLineText, .toggle, .singleChoice:
            return false
        }
    }

    private static func commonEntityID(
        _ references: [GraphChatNodeContextReference]
    ) -> UUID? {
        let ids = Set(references.compactMap(\GraphChatNodeContextReference.entityID))
        guard ids.count == 1,
              references.allSatisfy({ $0.entityID != nil }) else {
            return nil
        }
        return ids.first
    }

    private static func entitySort(
        _ lhs: GraphSchemaEntity,
        _ rhs: GraphSchemaEntity
    ) -> Bool {
        if lhs.attributeCount != rhs.attributeCount {
            return lhs.attributeCount > rhs.attributeCount
        }
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.alias.rawValue < rhs.alias.rawValue
    }

    private struct Candidate: Sendable {
        let id: String
        let semanticKey: String
        let priority: Int
        let kind: GraphChatSuggestionKind
        let requiredTools: Set<GraphChatToolKind>
        let title: String
        let prompt: String
    }

    private struct Texts: Sendable {
        let language: GraphChatResponseLanguage

        init(_ language: GraphChatResponseLanguage) {
            self.language = language
        }

        var graphOverviewTitle: String { localized("Graph überblicken", "Review graph") }
        var strongestLinksTitle: String { localized("Stärkste Verknüpfungen", "Strongest links") }
        var entityListTitle: String { localized("Einträge auflisten", "List entries") }
        var distributionTitle: String { localized("Werte verteilen", "Show distribution") }
        var overdueTitle: String { localized("Überfälliges prüfen", "Check overdue items") }
        var missingValuesTitle: String { localized("Fehlende Werte", "Missing values") }
        var newestTitle: String { localized("Neueste Einträge", "Newest entries") }
        var rangeTitle: String { localized("Min und Max", "Minimum and maximum") }
        var commonValuesTitle: String { localized("Häufigste Werte", "Most common values") }
        var affectedNodesTitle: String { localized("Betroffene Nodes", "Affected nodes") }
        var describeNodeTitle: String { localized("Node beschreiben", "Describe node") }
        var nodeDetailsTitle: String { localized("Relevante Details", "Relevant details") }
        var neighborsTitle: String { localized("Direkte Nachbarn", "Direct neighbors") }
        var connectionDirectionsTitle: String { localized("Verbindungsrichtungen", "Connection directions") }
        var selectionSummaryTitle: String { localized("Auswahl zusammenfassen", "Summarize selection") }
        var groupSelectionTitle: String { localized("Nach Entity gruppieren", "Group by entity") }
        var compareSelectionTitle: String { localized("Auswahl vergleichen", "Compare selection") }
        var selectionConnectionsTitle: String { localized("Gemeinsame Verbindungen", "Shared connections") }
        var explainFindingTitle: String { localized("Befund erklären", "Explain finding") }
        var suggestionAccessibilityHint: String {
            localized(
                "Übernimmt diese ausführbare Frage in das Eingabefeld.",
                "Places this supported question in the composer."
            )
        }

        func graphOverviewPrompt(_ graphName: String) -> String {
            localized(
                "Gib mir einen Überblick über „\(graphName)“ mit Anzahl der Entities, Attribute und direkten Verbindungen.",
                "Give me an overview of “\(graphName)” with counts of entities, attributes, and direct links."
            )
        }

        var strongestLinksPrompt: String {
            localized(
                "Welche Nodes haben im gesamten Graphen die meisten direkten Verbindungen?",
                "Which nodes have the most direct links in the entire graph?"
            )
        }

        func graphEntityListPrompt(_ entity: String) -> String {
            localized(
                "Liste die ersten Einträge der Entity „\(entity)“ mit ihren verfügbaren Details auf.",
                "List the first entries of the “\(entity)” entity with their available details."
            )
        }

        func entityListPrompt(_ entity: String) -> String {
            localized(
                "Liste Einträge aus „\(entity)“ mit ihren verfügbaren Details auf.",
                "List entries from “\(entity)” with their available details."
            )
        }

        func distributionPrompt(entity: String, field: String) -> String {
            localized(
                "Wie verteilen sich die Werte von „\(field)“ bei „\(entity)“?",
                "How are the values of “\(field)” distributed across “\(entity)”?"
            )
        }

        func overduePrompt(entity: String, field: String) -> String {
            localized(
                "Welche Einträge in „\(entity)“ sind anhand von „\(field)“ überfällig?",
                "Which entries in “\(entity)” are overdue based on “\(field)”?"
            )
        }

        func missingValuesPrompt(entity: String, field: String) -> String {
            localized(
                "Welche Einträge in „\(entity)“ haben keinen Wert für „\(field)“?",
                "Which entries in “\(entity)” have no value for “\(field)”?"
            )
        }

        func newestPrompt(entity: String, field: String) -> String {
            localized(
                "Zeige die neuesten Einträge in „\(entity)“, sortiert nach „\(field)“.",
                "Show the newest entries in “\(entity)”, sorted by “\(field)”."
            )
        }

        func rangePrompt(entity: String, field: String) -> String {
            localized(
                "Was sind Minimum und Maximum von „\(field)“ bei „\(entity)“?",
                "What are the minimum and maximum values of “\(field)” in “\(entity)”?"
            )
        }

        func commonValuesPrompt(entity: String, field: String) -> String {
            localized(
                "Welche Werte kommen bei „\(field)“ in „\(entity)“ am häufigsten vor?",
                "Which values occur most often for “\(field)” in “\(entity)”?"
            )
        }

        func fieldNodesPrompt(entity: String, field: String) -> String {
            localized(
                "Liste die Nodes in „\(entity)“ auf, die einen Wert für „\(field)“ besitzen.",
                "List the nodes in “\(entity)” that have a value for “\(field)”."
            )
        }

        func describeNodePrompt(_ node: String) -> String {
            localized(
                "Beschreibe „\(node)“ anhand der vorhandenen Graphdaten.",
                "Describe “\(node)” using the available graph data."
            )
        }

        func nodeDetailsPrompt(_ node: String) -> String {
            localized(
                "Welche relevanten Details sind für „\(node)“ vorhanden?",
                "Which relevant details are available for “\(node)”?"
            )
        }

        func neighborsPrompt(_ node: String) -> String {
            localized(
                "Zeige die direkten Nachbarn von „\(node)“ und erkläre die Verbindungen.",
                "Show the direct neighbors of “\(node)” and explain the links."
            )
        }

        func connectionDirectionsPrompt(_ node: String) -> String {
            localized(
                "Welche eingehenden und ausgehenden direkten Verbindungen hat „\(node)“?",
                "Which incoming and outgoing direct links does “\(node)” have?"
            )
        }

        func selectionSummaryPrompt(_ count: Int) -> String {
            localized(
                "Fasse die \(count) ausgewählten Nodes anhand ihrer vorhandenen Details zusammen.",
                "Summarize the \(count) selected nodes using their available details."
            )
        }

        func groupSelectionByEntityPrompt(_ count: Int) -> String {
            localized(
                "Gruppiere die \(count) ausgewählten Nodes nach ihrer Entity.",
                "Group the \(count) selected nodes by entity."
            )
        }

        func compareSelectionPrompt(_ count: Int) -> String {
            localized(
                "Vergleiche die \(count) ausgewählten Nodes und zeige Gemeinsamkeiten sowie Unterschiede in vorhandenen Details.",
                "Compare the \(count) selected nodes and show similarities and differences in available details."
            )
        }

        func selectionDistributionPrompt(count: Int, field: String) -> String {
            localized(
                "Wie verteilen sich die \(count) ausgewählten Nodes nach „\(field)“?",
                "How are the \(count) selected nodes distributed by “\(field)”?"
            )
        }

        func selectionConnectionsPrompt(_ count: Int) -> String {
            localized(
                "Welche direkten Verbindungen bestehen bei den \(count) ausgewählten Nodes?",
                "Which direct links exist for the \(count) selected nodes?"
            )
        }

        func explainFindingPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Erkläre den Health-Befund „\(finding.title)“ mit \(finding.count) Treffer(n): \(finding.message)",
                "Explain the health finding “\(finding.title)” with \(finding.count) match(es): \(finding.message)"
            )
        }

        func findingNodesPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Liste die betroffenen Nodes für den Befund „\(finding.title)“ mit direkten Quellen auf.",
                "List the nodes affected by the “\(finding.title)” finding with direct sources."
            )
        }

        func findingGroupPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Gruppiere die betroffenen Nodes des Befunds „\(finding.title)“ nach Entity.",
                "Group the nodes affected by the “\(finding.title)” finding by entity."
            )
        }

        func findingDetailsPrompt(_ finding: GraphChatHealthFindingContext) -> String {
            localized(
                "Zeige die relevanten Details der Nodes, die vom Befund „\(finding.title)“ betroffen sind.",
                "Show the relevant details of the nodes affected by the “\(finding.title)” finding."
            )
        }

        private func localized(_ german: String, _ english: String) -> String {
            language == .german ? german : english
        }
    }
}
