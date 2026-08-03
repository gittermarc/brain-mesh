//
//  GraphChatComposableReadPlanValidation.swift
//  BrainMesh
//
//  Central normalization and live validation for app-compiled read plans.
//

import Foundation

nonisolated enum GraphChatComposableReadPlanValidationError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case unsupportedVersion
    case bindingMismatch
    case scopeMismatch
    case invalidLimits
    case invalidOperationOrder
    case duplicateStep
    case unboundStepReference
    case cyclicStepReference
    case invalidSelection
    case staleEntity
    case staleNode
    case staleField
    case invalidQuery
    case invalidProjectionAggregation
    case invalidStableSort
    case invalidTraversal
    case staleConversationResult
    case invalidResultContract
    case invalidEvidenceContract
    case invalidArtifactContract

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "Die Composable-Read-Plan-Version wird nicht unterstützt."
        case .bindingMismatch:
            return "Der Read-Plan ist nicht an den aktuellen Request und Turn gebunden."
        case .scopeMismatch:
            return "Der Read-Plan würde den autorisierten Graph-Chat-Scope verlassen."
        case .invalidLimits:
            return "Der Read-Plan enthält ungültige appseitige Ergebnis- oder Zwischenlimits."
        case .invalidOperationOrder:
            return "Die Operationen des Read-Plans besitzen keine eindeutige Reihenfolge."
        case .duplicateStep:
            return "Der Read-Plan enthält eine doppelte Step-ID."
        case .unboundStepReference:
            return "Der Read-Plan enthält eine ungebundene Step-Referenz."
        case .cyclicStepReference:
            return "Der Read-Plan enthält eine zyklische oder vorwärts gerichtete Step-Referenz."
        case .invalidSelection:
            return "Die Auswahl des Read-Plans passt nicht zur Intent-Familie."
        case .staleEntity:
            return "Eine Entity des Read-Plans ist im aktuellen Graphen nicht mehr gültig."
        case .staleNode:
            return "Ein Node des Read-Plans ist im aktuellen Graphen nicht mehr gültig."
        case .staleField:
            return "Ein Feld des Read-Plans ist im aktuellen Graphen nicht mehr gültig."
        case .invalidQuery:
            return "Der appseitige Query-Schritt des Read-Plans ist nicht mehr gültig."
        case .invalidProjectionAggregation:
            return "Projektion und Aggregation des Read-Plans sind nicht kompatibel."
        case .invalidStableSort:
            return "Die Sortierung des Read-Plans besitzt keinen gültigen stabilen Tie-Breaker."
        case .invalidTraversal:
            return "Die direkte Traversierung des Read-Plans ist nicht zulässig."
        case .staleConversationResult:
            return "Das referenzierte Conversation-Resultset ist nicht mehr frisch revalidierbar."
        case .invalidResultContract:
            return "Der Ergebnisvertrag des Read-Plans passt nicht zum Typed Intent."
        case .invalidEvidenceContract:
            return "Der Evidence-Vertrag des Read-Plans ist unvollständig."
        case .invalidArtifactContract:
            return "Der Artifact-Vertrag des Read-Plans passt nicht zum Ergebnis."
        }
    }
}

nonisolated struct ValidatedGraphChatComposableReadPlan:
    Hashable,
    Sendable
{
    let plan: GraphChatComposableReadPlan
    let action: GraphChatLocalIntentAction
    let validatedQueryPlan:
        ValidatedGraphQueryPlan?
    let validatedFilterStages:
        [GraphChatComposableReadValidatedFilterStage]
}

nonisolated struct GraphChatComposableReadValidatedFilterStage:
    Hashable,
    Sendable
{
    let operationID: GraphChatComposableReadStepID
    let entity: GraphChatTypedEntityIdentity
    let filters: [GraphValidatedQueryFilter]
}

nonisolated enum GraphChatComposableReadPlanNormalizer {
    static func normalize(
        _ plan: GraphChatComposableReadPlan
    ) throws -> GraphChatComposableReadPlan {
        guard plan.operations.isEmpty == false else {
            throw GraphChatComposableReadPlanValidationError
                .invalidOperationOrder
        }
        let allIDs = Set(
            plan.operations.map(\.id)
        )
        guard allIDs.count
                == plan.operations.count else {
            throw GraphChatComposableReadPlanValidationError
                .duplicateStep
        }

        var seen = Set<GraphChatComposableReadStepID>()
        var normalized:
            [GraphChatComposableReadOperation] = []
        normalized.reserveCapacity(
            plan.operations.count
        )
        for (index, operation) in
            plan.operations.enumerated()
        {
            if index == 0 {
                guard operation.input == nil else {
                    throw GraphChatComposableReadPlanValidationError
                        .cyclicStepReference
                }
            } else {
                guard let input = operation.input else {
                    throw GraphChatComposableReadPlanValidationError
                        .unboundStepReference
                }
                guard seen.contains(input) else {
                    if allIDs.contains(input) {
                        throw GraphChatComposableReadPlanValidationError
                            .cyclicStepReference
                    }
                    throw GraphChatComposableReadPlanValidationError
                        .unboundStepReference
                }
                guard input
                        == plan.operations[index - 1].id
                else {
                    throw GraphChatComposableReadPlanValidationError
                        .invalidOperationOrder
                }
            }
            seen.insert(operation.id)
            normalized.append(
                GraphChatComposableReadOperation(
                    id:
                        GraphChatComposableReadStepID(
                            rawValue: index
                        ),
                    input:
                        index == 0
                        ? nil
                        : GraphChatComposableReadStepID(
                            rawValue: index - 1
                        ),
                    payload:
                        normalizedPayload(
                            operation.payload
                        )
                )
            )
        }

        return GraphChatComposableReadPlan(
            version: plan.version,
            queryPlanVersion:
                plan.queryPlanVersion,
            graphScope: plan.graphScope,
            chatScope: plan.chatScope,
            queryScope: plan.queryScope,
            compiledScope: plan.compiledScope,
            binding: plan.binding,
            responseLanguage:
                plan.responseLanguage,
            intentKind: plan.intentKind,
            operations: normalized,
            resultContract:
                plan.resultContract,
            evidenceRequirements:
                stableUnique(
                    plan.evidenceRequirements
                ),
            artifactContract:
                plan.artifactContract,
            limits: plan.limits,
            queryReferenceDate:
                plan.queryReferenceDate
        )
    }

    private static func normalizedPayload(
        _ payload:
            GraphChatComposableReadOperationPayload
    ) -> GraphChatComposableReadOperationPayload {
        guard case .sort(let value) = payload else {
            return payload
        }
        let hasRelationshipKey =
            value.descriptors.contains {
                descriptor in
                switch descriptor.key {
                case .counterpartDisplayName,
                    .counterpartKind,
                    .counterpartNodeID,
                    .relationshipDirection,
                    .linkCreatedAt,
                    .stableLinkID:
                    return true
                case .nodeName, .field,
                    .stableNodeID:
                    return false
                }
            }
        let descriptors = value.descriptors
            .filter { descriptor in
                switch descriptor.key {
                case .stableNodeID, .stableLinkID:
                    return false
                case .nodeName, .field,
                    .counterpartDisplayName,
                    .counterpartKind,
                    .counterpartNodeID,
                    .relationshipDirection,
                    .linkCreatedAt:
                    return true
                }
            }
        let tieBreaker =
            GraphChatComposableReadSortDescriptor(
                key:
                    hasRelationshipKey
                    ? .stableLinkID
                    : .stableNodeID,
                direction: .ascending
            )
        return .sort(
            GraphChatComposableReadSort(
                descriptors:
                    stableUnique(descriptors)
                    + [tieBreaker]
            )
        )
    }

    private static func stableUnique<Value: Hashable>(
        _ values: [Value]
    ) -> [Value] {
        var seen = Set<Value>()
        return values.filter {
            seen.insert($0).inserted
        }
    }
}

nonisolated struct GraphChatComposableReadPlanValidator:
    Sendable
{
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let referenceDate:
        @Sendable () -> Date
    private let policy:
        GraphChatIntentLimitPolicy

    init(
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate:
            @escaping @Sendable () -> Date,
        policy:
            GraphChatIntentLimitPolicy = .default
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
        self.referenceDate = referenceDate
        self.policy = policy
    }

    func validate(
        _ source: GraphChatComposableReadPlan,
        for intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext,
        providerPlan: GraphChatProviderTurnPlan
    ) throws -> ValidatedGraphChatComposableReadPlan {
        guard source.version == .current,
              source.queryPlanVersion
                == GraphQueryPlan.currentVersion
        else {
            throw GraphChatComposableReadPlanValidationError
                .unsupportedVersion
        }
        let plan = try GraphChatComposableReadPlanNormalizer
            .normalize(source)
        try validateBinding(
            plan,
            intent: intent,
            providerPlan: providerPlan
        )
        try validateLimits(
            plan,
            intent: intent
        )
        let inventory = try OperationInventory(
            plan.operations
        )
        try validateOperationOrder(
            inventory,
            plan: plan
        )
        try validateIdentities(
            inventory,
            intent: intent,
            schemaContext:
                schemaContext
        )
        try validateSelection(
            inventory.selection,
            plan: plan,
            intent: intent,
            schemaContext:
                schemaContext,
            providerPlan: providerPlan
        )
        try validateStableSort(
            inventory.sort,
            resultContract:
                plan.resultContract
        )
        try validateContracts(
            inventory,
            plan: plan,
            intent: intent,
            providerPlan: providerPlan
        )

        let action: GraphChatLocalIntentAction
        do {
            action =
                try GraphChatComposableReadPlanLegacyActionAdapter
                    .validatedAction(from: plan)
        } catch {
            throw GraphChatComposableReadPlanValidationError
                .invalidResultContract
        }
        let validatedQueryPlan =
            try validateQueryIfNeeded(
                action,
                plan: plan,
                schemaContext:
                    schemaContext
            )
        let validatedFilterStages =
            try validateComposableFiltersIfNeeded(
                inventory,
                plan: plan,
                schemaContext: schemaContext
            )
        return ValidatedGraphChatComposableReadPlan(
            plan: plan,
            action: action,
            validatedQueryPlan:
                validatedQueryPlan,
            validatedFilterStages:
                validatedFilterStages
        )
    }

    private func validateBinding(
        _ plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent,
        providerPlan: GraphChatProviderTurnPlan
    ) throws {
        guard
            plan.binding == intent.binding,
            plan.binding.requestID
                == plan.binding.turnID,
            plan.binding.conversationID
                == providerPlan
                    .requestBaseState
                    .conversationID,
            plan.intentKind == intent.kind,
            plan.responseLanguage
                == intent.responseLanguage
        else {
            throw GraphChatComposableReadPlanValidationError
                .bindingMismatch
        }
        guard
            plan.graphScope
                == intent.scope.graphScope,
            plan.chatScope
                == intent.scope.chatScope,
            plan.queryScope
                == intent.scope.queryScope,
            plan.compiledScope
                == plan.queryScope,
            plan.graphScope
                == plan.chatScope.graphScope,
            plan.graphScope
                == plan.queryScope.graphScope,
            providerPlan.scopeKey.graphScope
                == plan.graphScope,
            providerPlan.scopeKey.chatScope
                == plan.chatScope
        else {
            throw GraphChatComposableReadPlanValidationError
                .scopeMismatch
        }
    }

    private func validateLimits(
        _ plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent
    ) throws {
        guard
            plan.limits.resultLimit
                == intent.limits.resultLimit,
            plan.limits.maximumResultLimit
                == intent.limits.maximumResultLimit,
            plan.limits.maximumEvidenceCount
                == intent.limits.maximumEvidenceCount,
            plan.limits.maximumArtifactCount
                == intent.limits.maximumArtifactCount,
            plan.limits.maximumOperationCount
                == policy
                    .maximumComposableReadOperationCount,
            plan.limits.maximumTraversalHopCount
                == policy
                    .maximumComposableReadTraversalHopCount,
            plan.limits.selectedStartNodeLimit
                == policy
                    .maximumComposableReadSelectedStartNodeCount,
            plan.limits.visitedNodeLimit
                == policy
                    .maximumComposableReadVisitedNodeCount,
            plan.limits.checkedLinkLimit
                == policy
                    .maximumComposableReadCheckedLinkCount,
            plan.resultContract
                != .composableNodeCollection
                || (
                    plan.limits.maximumResultLimit
                        == GraphQueryPlanLimits
                            .maximumResultLimit
                    && plan.limits
                        .maximumEvidenceCount
                        == policy
                            .maximumQueryEvidenceCount
                    && plan.limits
                        .maximumArtifactCount == 1
                ),
            plan.operations.count
                <= plan.limits
                    .maximumOperationCount,
            plan.limits.resultLimit > 0,
            plan.limits.resultLimit
                <= plan.limits
                    .maximumResultLimit,
            plan.limits.intermediateResultLimit > 0,
            plan.limits.intermediateResultLimit
                <= policy
                    .maximumComposableReadIntermediateCount,
            plan.limits.selectedStartNodeLimit > 0,
            plan.limits.visitedNodeLimit
                >= plan.limits.selectedStartNodeLimit,
            plan.limits.checkedLinkLimit > 0,
            plan.limits.maximumEvidenceCount > 0,
            plan.evidenceRequirements.isEmpty
                == false,
            plan.evidenceRequirements.count
                <= plan.limits
                    .maximumEvidenceCount,
            plan.limits.maximumArtifactCount > 0
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidLimits
        }
    }

    private func validateOperationOrder(
        _ inventory: OperationInventory,
        plan: GraphChatComposableReadPlan
    ) throws {
        let kinds = plan.operations.map {
            OperationKind($0.payload)
        }
        let validKinds:
            Set<[OperationKind]>
        switch plan.resultContract {
        case .authoritativeSingleField:
            validKinds = [
                [.select, .project, .limit],
                [
                    .select,
                    .project,
                    .sort,
                    .limit,
                ],
            ]
        case .entityCollection,
            .compiledCollection,
            .refinement:
            validKinds = [
                [
                    .select,
                    .project,
                    .sort,
                    .limit,
                ],
                [
                    .select,
                    .filter,
                    .project,
                    .sort,
                    .limit,
                ],
            ]
        case .count, .groupCount:
            validKinds = [
                [
                    .select,
                    .project,
                    .aggregate,
                    .limit,
                ],
                [
                    .select,
                    .filter,
                    .project,
                    .aggregate,
                    .limit,
                ],
            ]
        case .search:
            validKinds = [
                [.select, .search, .limit],
            ]
        case .nodeProfile:
            validKinds = [
                [
                    .select,
                    .describeNode,
                    .limit,
                ],
            ]
        case .comparison:
            validKinds = [
                [
                    .select,
                    .compareNodes,
                    .limit,
                ],
                [
                    .select,
                    .project,
                    .sort,
                    .compareNodes,
                    .limit,
                ],
            ]
        case .graphState:
            validKinds = [
                [
                    .select,
                    .inspectGraphState,
                    .limit,
                ],
            ]
        case .relationships:
            validKinds = [
                [
                    .select,
                    .traverseDirectRelationships,
                    .projectRelationships,
                    .sort,
                    .limit,
                ],
            ]
        case .composableNodeCollection:
            validKinds = [
                [
                    .select,
                    .traverseRelationships,
                    .projectTraversalNodes,
                    .sort,
                    .limit,
                ],
                [
                    .select,
                    .filter,
                    .traverseRelationships,
                    .projectTraversalNodes,
                    .sort,
                    .limit,
                ],
                [
                    .select,
                    .traverseRelationships,
                    .traverseRelationships,
                    .projectTraversalNodes,
                    .sort,
                    .limit,
                ],
                [
                    .select,
                    .filter,
                    .traverseRelationships,
                    .traverseRelationships,
                    .projectTraversalNodes,
                    .sort,
                    .limit,
                ],
            ]
        }
        guard
            plan.operations.first.map({
                if case .select = $0.payload {
                    return true
                }
                return false
            }) == true,
            plan.operations.last.map({
                if case .limit = $0.payload {
                    return true
                }
                return false
            }) == true,
            inventory.selectionCount == 1,
            inventory.limitCount == 1,
            validKinds.contains(kinds)
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidOperationOrder
        }
    }

    private enum OperationKind:
        Hashable,
        Sendable
    {
        case select
        case search
        case filter
        case project
        case sort
        case aggregate
        case describeNode
        case compareNodes
        case inspectGraphState
        case traverseDirectRelationships
        case traverseRelationships
        case projectTraversalNodes
        case projectRelationships
        case limit

        init(
            _ payload:
                GraphChatComposableReadOperationPayload
        ) {
            switch payload {
            case .select:
                self = .select
            case .search:
                self = .search
            case .filter:
                self = .filter
            case .project:
                self = .project
            case .sort:
                self = .sort
            case .aggregate:
                self = .aggregate
            case .describeNode:
                self = .describeNode
            case .compareNodes:
                self = .compareNodes
            case .inspectGraphState:
                self = .inspectGraphState
            case .traverseDirectRelationships:
                self =
                    .traverseDirectRelationships
            case .traverseRelationships:
                self = .traverseRelationships
            case .projectTraversalNodes:
                self = .projectTraversalNodes
            case .projectRelationships:
                self = .projectRelationships
            case .limit:
                self = .limit
            }
        }
    }

    private func validateIdentities(
        _ inventory: OperationInventory,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext
    ) throws {
        guard
            schemaContext.graphScope
                == intent.scope.graphScope,
            schemaContext.foundationalAliases
                .graphScope
                == intent.scope.graphScope
        else {
            throw GraphChatComposableReadPlanValidationError
                .scopeMismatch
        }
        for entity in inventory.entities {
            try validateEntity(
                entity,
                schemaContext:
                    schemaContext
            )
        }
        for node in inventory.nodes {
            try validateNode(
                node,
                schemaContext:
                    schemaContext
            )
        }
        for field in inventory.fields {
            try validateField(
                field,
                schemaContext:
                    schemaContext
            )
        }
    }

    private func validateEntity(
        _ reference:
            GraphChatComposableReadEntityReference,
        schemaContext: GraphSchemaContext
    ) throws {
        guard let identity =
                reference.identity,
              identity.alias == reference.alias,
              let current =
                schemaContext
                    .foundationalAliases
                    .entity(
                        for:
                            reference.alias
                    ),
              current.entityID == identity.id,
              current.name
                == identity.displayName
        else {
            throw GraphChatComposableReadPlanValidationError
                .staleEntity
        }
    }

    private func validateEntity(
        _ identity:
            GraphChatTypedEntityIdentity,
        schemaContext: GraphSchemaContext
    ) throws {
        try validateEntity(
            GraphChatComposableReadEntityReference(
                alias: identity.alias,
                identity: identity
            ),
            schemaContext: schemaContext
        )
    }

    private func validateNode(
        _ node: GraphChatTypedNodeIdentity,
        schemaContext: GraphSchemaContext
    ) throws {
        guard let current =
                schemaContext
                    .foundationalAliases
                    .nodesByKey[node.node],
              current.ownerEntityID
                == node.ownerEntityID,
              current.displayName
                == node.displayName
        else {
            throw GraphChatComposableReadPlanValidationError
                .staleNode
        }
    }

    private func validateField(
        _ reference:
            GraphChatComposableReadFieldReference,
        schemaContext: GraphSchemaContext
    ) throws {
        guard let identity =
                reference.identity,
              identity.alias
                == reference.alias,
              let current =
                schemaContext
                    .foundationalAliases
                    .field(
                        for:
                            reference.alias
                    ),
              current.fieldID
                == identity.id,
              current.entityID
                == identity.ownerEntityID,
              current.name
                == identity.displayName,
              current.type == identity.type,
              current.unit == identity.unit
        else {
            throw GraphChatComposableReadPlanValidationError
                .staleField
        }
    }

    private func validateSelection(
        _ selection: GraphChatComposableReadSelection,
        plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext,
        providerPlan: GraphChatProviderTurnPlan
    ) throws {
        guard GraphChatScopeAuthorization.allows(
            scope: plan.compiledScope,
            within: plan.chatScope,
            aliases:
                schemaContext
                    .foundationalAliases
        ) else {
            throw GraphChatComposableReadPlanValidationError
                .scopeMismatch
        }
        switch selection {
        case .scope(let scope):
            guard scope == plan.compiledScope else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidSelection
            }
        case .entity(let entity):
            guard let identity = entity.identity,
                  intent.payload.entities
                    .contains(identity) else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidSelection
            }
        case .node(let entity, let node):
            guard node.ownerEntityID
                    == entity.id,
                  intent.payload.entities
                    .contains(entity),
                  intent.payload.nodes
                    .contains(node),
                  plan.compiledScope
                    == .node(
                        node.node,
                        in: plan.graphScope
                    )
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidSelection
            }
        case .nodes(let entities, let nodes):
            guard
                entities.isEmpty == false,
                nodes.count >= 2,
                Set(nodes.map(\.node)).count
                    == nodes.count,
                Set(nodes.map(\.ownerEntityID))
                    .isSubset(
                        of:
                            Set(
                                entities.map(\.id)
                            )
                    ),
                nodes == intent.payload.nodes,
                entities == intent.payload.entities,
                plan.compiledScope
                    == (try GraphChatScope.selection(
                        nodes.map(\.node),
                        in: plan.graphScope
                    ))
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidSelection
            }
        case .conversationResult(let value):
            try validateConversationSelection(
                value,
                intent: intent,
                providerPlan: providerPlan,
                schemaContext:
                    schemaContext
            )
        }
    }

    private func validateConversationSelection(
        _ selection:
            GraphChatComposableReadConversationSelection,
        intent: GraphChatTypedIntent,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws {
        let source = selection.source
        let sourceNodesBelongToSelectedEntity =
            source.nodes.allSatisfy { node in
                schemaContext
                    .foundationalAliases
                    .owningEntityID(for: node)
                    == source.entityID
            }
        guard
            providerPlan.currentResolvedScope
                == source,
            providerPlan.conversationContext
                .currentResolvedScope == source,
            source.graphScope
                == intent.scope.graphScope,
            source.chatScope
                == intent.scope.chatScope,
            source.conversationID
                == intent.binding.conversationID,
            source.entityID
                == selection.entity.identity?.id,
            source.nodes
                == selection.nodes.map(\.node),
            sourceNodesBelongToSelectedEntity,
            source.revision.sourceResultID
                == selection
                    .sourceResultContextID,
            let sourceTurnID =
                source.revision.sourceTurnID,
            providerPlan.requestBaseState
                .turnContexts.contains(
                    where: {
                        $0.id == sourceTurnID
                    }
                ),
            providerPlan.requestBaseState
                .resultContexts.contains(
                    where: {
                        $0.id
                            == selection
                                .sourceResultContextID
                    }
                )
        else {
            throw GraphChatComposableReadPlanValidationError
                .staleConversationResult
        }
    }

    private func validateStableSort(
        _ sort: GraphChatComposableReadSort?,
        resultContract:
            GraphChatComposableReadResultContract
    ) throws {
        guard let sort else {
            switch resultContract {
            case .entityCollection,
                .compiledCollection,
                .refinement,
                .composableNodeCollection:
                throw GraphChatComposableReadPlanValidationError
                    .invalidStableSort
            case .authoritativeSingleField,
                .count, .groupCount, .search,
                .nodeProfile, .comparison,
                .graphState, .relationships:
                return
            }
        }
        guard
            sort.descriptors.isEmpty == false,
            Set(sort.descriptors).count
                == sort.descriptors.count,
            Set(sort.descriptors.map(\.key)).count
                == sort.descriptors.count
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidStableSort
        }
        let expectedTieBreaker:
            GraphChatComposableReadSortKey =
                resultContract == .relationships
                ? .stableLinkID
                : .stableNodeID
        guard
            sort.descriptors.last?.key
                == expectedTieBreaker,
            sort.descriptors.last?.direction
                == .ascending,
            sort.descriptors.filter({
                $0.key == expectedTieBreaker
            }).count == 1
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidStableSort
        }
    }

    private func validateContracts(
        _ inventory: OperationInventory,
        plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent,
        providerPlan: GraphChatProviderTurnPlan
    ) throws {
        guard
            inventory.limit.resultLimit
                == plan.limits.resultLimit,
            inventory.limit
                .intermediateResultLimit
                == plan.limits
                    .intermediateResultLimit
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidLimits
        }
        let expectedIntermediateLimit: Int
        switch plan.resultContract {
        case .refinement:
            expectedIntermediateLimit = max(
                plan.limits.resultLimit,
                selectedNodeKeys(
                    inventory.selection
                ).count
            )
        case .nodeProfile:
            expectedIntermediateLimit = 1
        case .comparison:
            expectedIntermediateLimit =
                selectedNodeKeys(
                    inventory.selection
                ).count
        case .graphState:
            expectedIntermediateLimit =
                inventory.graphState.map {
                    max(1, $0.hubLimit)
                } ?? 0
        case .relationships:
            expectedIntermediateLimit =
                plan.limits.maximumResultLimit
        case .composableNodeCollection:
            expectedIntermediateLimit =
                policy
                    .maximumComposableReadIntermediateCount
        case .authoritativeSingleField,
            .entityCollection,
            .compiledCollection,
            .count,
            .groupCount,
            .search:
            expectedIntermediateLimit =
                plan.limits.resultLimit
        }
        guard plan.limits.intermediateResultLimit
                == expectedIntermediateLimit
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidLimits
        }

        switch plan.resultContract {
        case .authoritativeSingleField(
            let node,
            let field
        ):
            guard
                intent.kind == .nodeDetails,
                intent.factExpectation
                    == .authoritativeSingleField,
                inventory.search == nil,
                inventory.description == nil,
                inventory.comparison == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                inventory.filter == nil,
                inventory.aggregation == nil,
                inventory.projection?
                    .includesNodeIdentity == true,
                inventory.projection?
                    .fields == [
                        GraphChatComposableReadFieldReference(
                            alias: field.alias,
                            identity: field
                        ),
                    ],
                case .nodeDetails(let details) =
                    intent.payload,
                details.node == node,
                details.fields == [field],
                inventory.selection
                    == .node(
                        entity:
                            details.entity,
                        node: details.node
                    ),
                plan.artifactContract
                    == .queryResult,
                Set(plan.evidenceRequirements)
                    == [
                        .nodeIdentity,
                        .authoritativeDetailValue,
                    ],
                plan.limits.resultLimit == 1
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidResultContract
            }

        case .entityCollection:
            guard
                intent.kind == .entityCollection,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .zeroOrMore,
                case .entityCollection(
                    let collection
                ) = intent.payload,
                collection.relatedEntities.isEmpty,
                collection.relatedNodes.isEmpty,
                collection.projectedFields
                    .isEmpty,
                collection.referencedFields
                    .isEmpty,
                inventory.projection
                    == GraphChatComposableReadProjection(
                        includesNodeIdentity: true,
                        fields: []
                    ),
                inventory.filter == nil,
                inventory.aggregation == nil,
                inventory.search == nil,
                inventory.description == nil,
                inventory.comparison == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                plan.artifactContract
                    == .queryResult,
                Set(plan.evidenceRequirements)
                    == [.nodeIdentity],
                selectedEntityID(
                    inventory.selection
                ) == collection.entity.id
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidProjectionAggregation
            }

        case .compiledCollection:
            guard
                intent.kind == .entityCollection,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .zeroOrMore,
                case .entityCollection(
                    let collection
                ) = intent.payload,
                collection.relatedEntities.isEmpty,
                collection.relatedNodes.isEmpty,
                inventory.projection?
                    .includesNodeIdentity == true,
                inventory.aggregation == nil,
                inventory.search == nil,
                inventory.description == nil,
                inventory.comparison == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                plan.artifactContract
                    == .queryResult,
                Set(plan.evidenceRequirements)
                    == [.nodeIdentity],
                selectedEntityID(
                    inventory.selection
                ) == collection.entity.id,
                projectedFieldIDs(
                    inventory
                ) == Set(
                    collection
                        .projectedFields
                        .map(\.id)
                ),
                referencedFieldIDs(
                    inventory
                ) == Set(
                    collection
                        .referencedFields
                        .map(\.id)
                )
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidProjectionAggregation
            }

        case .refinement:
            guard
                intent.kind == .narrowResultSet,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .zeroOrMore,
                case .narrowResultSet(
                    let refinement
                ) = intent.payload,
                case .conversationResult =
                    inventory.selection,
                inventory.projection?
                    .includesNodeIdentity == true,
                inventory.aggregation == nil,
                inventory.search == nil,
                inventory.description == nil,
                inventory.comparison == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                plan.artifactContract
                    == .queryResult,
                Set(plan.evidenceRequirements)
                    == [.nodeIdentity],
                selectedEntityID(
                    inventory.selection
                ) == refinement.entity.id,
                projectedFieldIDs(
                    inventory
                ) == Set(
                    refinement
                        .projectedFields
                        .map(\.id)
                ),
                referencedFieldIDs(
                    inventory
                ) == Set(
                    refinement
                        .fields
                        .map(\.id)
                ),
                selectedNodeKeys(
                    inventory.selection
                ) == refinement.nodes.map(\.node)
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidProjectionAggregation
            }

        case .count:
            try validateAggregationContract(
                inventory,
                plan: plan,
                intent: intent,
                expected: .count
            )

        case .groupCount:
            guard case .groupCount? =
                    inventory.aggregation else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidProjectionAggregation
            }
            try validateAggregationContract(
                inventory,
                plan: plan,
                intent: intent,
                expected: inventory.aggregation
            )

        case .search:
            guard
                intent.kind == .findNodes,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .zeroOrMore,
                case .findNodes(let find) =
                    intent.payload,
                find.fields.isEmpty,
                let search = inventory.search,
                search.query
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ).isEmpty == false,
                search.entityID
                    == find.entity?.id,
                search.target != .entityNodes
                    || search.entityID != nil,
                inventory.projection == nil,
                inventory.filter == nil,
                inventory.sort == nil,
                inventory.aggregation == nil,
                inventory.description == nil,
                inventory.comparison == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                plan.artifactContract
                    == .searchResults,
                Set(plan.evidenceRequirements)
                    == [.searchIdentity],
                plan.limits.resultLimit
                    <= policy
                        .maximumSearchResultCount,
                plan.limits.maximumResultLimit
                    == policy
                        .maximumSearchResultCount,
                plan.limits.maximumEvidenceCount
                    == plan.limits.resultLimit,
                plan.limits.maximumArtifactCount
                    == 1
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidResultContract
            }

        case .nodeProfile:
            guard
                intent.kind == .nodeDetails,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .zeroOrOne,
                case .nodeDetails(let details) =
                    intent.payload,
                inventory.description != nil,
                inventory.search == nil,
                inventory.projection == nil,
                inventory.filter == nil,
                inventory.sort == nil,
                inventory.aggregation == nil,
                inventory.comparison == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                plan.artifactContract
                    == .nodeProfile,
                Set(plan.evidenceRequirements)
                    == [
                        .nodeIdentity,
                        .nodeProfileAreas,
                    ],
                let description =
                    inventory.description,
                description.node
                    == details.node,
                inventory.selection
                    == .node(
                        entity:
                            details.entity,
                        node:
                            details.node
                    ),
                description.compatibilityLimit
                    == GraphChatAdvancedIntentPolicy
                        .default
                        .nodeDetailRelatedLimit,
                description.profileLimits
                    == policy.nodeProfileLimits(
                        compatibilityLimit:
                            description
                                .compatibilityLimit
                    ),
                plan.limits.resultLimit == 1
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidResultContract
            }

        case .comparison:
            guard
                intent.kind == .compareNodes,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .twoOrMore,
                case .compareNodes(let details) =
                    intent.payload,
                inventory.comparison != nil,
                inventory.search == nil,
                inventory.filter == nil,
                inventory.aggregation == nil,
                inventory.description == nil,
                inventory.graphState == nil,
                inventory.traversal == nil,
                plan.artifactContract
                    == .comparison,
                Set(plan.evidenceRequirements)
                    == [
                        .nodeIdentity,
                        .comparisonFeatureValues,
                    ],
                let comparison =
                    inventory.comparison,
                comparison.policy
                    == GraphChatAdvancedIntentPolicy
                        .default,
                comparison.features.isEmpty == false,
                Set(comparison.features).count
                    == comparison.features.count,
                case .nodes(
                    _,
                    let nodes
                ) = inventory.selection,
                nodes.count >= 2,
                nodes == details.nodes,
                plan.limits.resultLimit
                    == nodes.count,
                nodes.count
                    <= policy
                        .maximumComparisonNodeCount,
                comparison.features.count
                    <= policy
                        .maximumComparisonFeatureCount
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidResultContract
            }
            switch comparison.kind {
            case .sameEntityAttributes:
                let expectedFeatures:
                    [GraphChatComparisonFeature] =
                    details.fields.map { field in
                        .field(field)
                    }
                let containsOnlyFieldFeatures =
                    comparison.features.allSatisfy {
                        feature in
                        if case .field = feature {
                            return true
                        }
                        return false
                    }
                guard
                    inventory.projection?
                        .includesNodeIdentity == true,
                    inventory.sort != nil,
                    comparison.relatedLimit == 0,
                    comparison.features
                        == expectedFeatures,
                    containsOnlyFieldFeatures
                else {
                    throw GraphChatComposableReadPlanValidationError
                        .invalidProjectionAggregation
                }
            case .structural:
                let containsOnlyStructuralFeatures =
                    comparison.features.allSatisfy {
                        feature in
                        if case .structure = feature {
                            return true
                        }
                        return false
                    }
                guard
                    details.fields.isEmpty,
                    inventory.projection == nil,
                    inventory.sort == nil,
                    comparison.relatedLimit
                        == comparison.policy
                            .structuralRelatedLimit,
                    containsOnlyStructuralFeatures
                else {
                    throw GraphChatComposableReadPlanValidationError
                        .invalidProjectionAggregation
                }
            }

        case .graphState:
            guard
                intent.kind == .inspectGraphState,
                intent.factExpectation == .none,
                intent.expectedCardinality
                    == .exactlyOne,
                case .inspectGraphState(
                    let graphStateIntent
                ) = intent.payload,
                graphStateIntent.entity == nil,
                inventory.graphState != nil,
                inventory.search == nil,
                inventory.filter == nil,
                inventory.projection == nil,
                inventory.sort == nil,
                inventory.aggregation == nil,
                inventory.description == nil,
                inventory.comparison == nil,
                inventory.traversal == nil,
                plan.chatScope
                    == .entireGraph(
                        plan.graphScope
                    ),
                plan.artifactContract
                    == .graphState,
                Set(plan.evidenceRequirements)
                    == [.graphStateSnapshot],
                inventory.graphState?.hubLimit
                    == policy.graphHubCount,
                inventory.graphState?.aspect
                    == graphStateIntent.aspect,
                plan.limits.resultLimit
                    == max(
                        1,
                        policy.graphHubCount
                    )
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidResultContract
            }

        case .relationships:
            try validateRelationshipContract(
                inventory,
                plan: plan,
                intent: intent,
                providerPlan: providerPlan
            )
        case .composableNodeCollection:
            try validateComposableNodeCollectionContract(
                inventory,
                plan: plan,
                intent: intent
            )
        }
    }

    private func validateComposableNodeCollectionContract(
        _ inventory: OperationInventory,
        plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent
    ) throws {
        guard
            intent.kind == .entityCollection,
            intent.factExpectation == .none,
            intent.expectedCardinality == .zeroOrMore,
            case .entityCollection(let collection) =
                intent.payload,
            collection.relatedEntities.isEmpty == false,
            collection.relatedEntities.count
                == inventory.composableTraversals.count,
            inventory.composableTraversals.count
                <= plan.limits.maximumTraversalHopCount,
            inventory.search == nil,
            inventory.projection == nil,
            inventory.aggregation == nil,
            inventory.description == nil,
            inventory.comparison == nil,
            inventory.graphState == nil,
            inventory.traversal == nil,
            inventory.relationshipProjection == nil,
            inventory.traversalProjection != nil,
            inventory.traversalProjection?
                .deduplicatesNodes == true,
            inventory.sort?.descriptors.count == 2,
            inventory.sort?.descriptors.first?.key
                == .nodeName,
            inventory.sort?.descriptors.allSatisfy({
                descriptor in
                switch descriptor.key {
                case .nodeName, .stableNodeID:
                    return true
                case .field, .counterpartDisplayName,
                    .counterpartKind,
                    .counterpartNodeID,
                    .relationshipDirection,
                    .linkCreatedAt,
                    .stableLinkID:
                    return false
                }
            }) == true,
            plan.artifactContract == .queryResult,
            selectedEntityID(inventory.selection)
                == collection.entity.id,
            plan.chatScope
                == .entireGraph(plan.graphScope),
            plan.compiledScope
                == .entity(
                    collection.entity.id,
                    in: plan.graphScope
                ),
            collection.relatedEntities.map(\.id)
                == inventory.composableTraversals.map({
                    $0.stage.counterpartEntity.id
                }),
            collection.relatedNodes
                == inventory.composableTraversals
                    .compactMap({
                        $0.stage.counterpartNode
                    }),
            collection.projectedFields.isEmpty,
            Set(collection.referencedFields.map(\.id))
                == Set(inventory.fields.compactMap {
                    $0.identity?.id
                }),
            rootPredicatesBelongToRootEntity(
                inventory,
                rootEntityID: collection.entity.id
            ),
            traversalPredicatesBelongToTheirEntities(
                inventory.composableTraversals
            )
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidTraversal
        }

        let hasDetailPredicates =
            inventory.filter?.predicates.isEmpty == false
            || inventory.composableTraversals.contains {
                $0.stage.nodePredicates.isEmpty == false
            }
        let expectedEvidence:
            Set<GraphChatComposableReadEvidenceRequirement> =
                hasDetailPredicates
                ? [
                    .nodeIdentity,
                    .authoritativeDetailValue,
                    .composableTraversalPath,
                ]
                : [
                    .nodeIdentity,
                    .composableTraversalPath,
                ]
        guard Set(plan.evidenceRequirements)
                == expectedEvidence else {
            throw GraphChatComposableReadPlanValidationError
                .invalidEvidenceContract
        }

        for traversal in inventory.composableTraversals {
            let stage = traversal.stage
            guard
                stage.counterpartNode == nil
                    || (
                        stage.counterpartNode?
                            .node.kind == .attribute
                        && stage.counterpartNode?
                            .ownerEntityID
                            == stage.counterpartEntity.id
                    )
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidTraversal
            }
            if case .contains(let term)? =
                    stage.notePredicate {
                let normalized = term.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard
                    normalized.isEmpty == false,
                    normalized.count
                        <= policy.maximumFilterValueLength,
                    GraphChatSemanticSafety
                        .containsTechnicalIdentifier(
                            normalized
                        ) == false,
                    GraphChatComposableReadTextNormalizer
                        .normalized(normalized)
                        .isEmpty == false
                else {
                    throw GraphChatComposableReadPlanValidationError
                        .invalidTraversal
                }
            }
        }
    }

    private func rootPredicatesBelongToRootEntity(
        _ inventory: OperationInventory,
        rootEntityID: UUID
    ) -> Bool {
        inventory.filter?.predicates.allSatisfy {
            $0.field.identity?.ownerEntityID
                == rootEntityID
        } ?? true
    }

    private func traversalPredicatesBelongToTheirEntities(
        _ traversals:
            [OperationInventory.TraversalOperation]
    ) -> Bool {
        traversals.allSatisfy { traversal in
            traversal.stage.nodePredicates.allSatisfy {
                $0.field.identity?.ownerEntityID
                    == traversal.stage
                        .counterpartEntity.id
            }
        }
    }

    private func validateAggregationContract(
        _ inventory: OperationInventory,
        plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent,
        expected:
            GraphChatComposableReadAggregation?
    ) throws {
        let expectedOperation:
            GraphChatTypedCountOrGroupOperation
        switch expected {
        case .count?:
            expectedOperation = .count
        case .groupCount(let field)?:
            guard let identity = field.identity else {
                throw GraphChatComposableReadPlanValidationError
                    .staleField
            }
            expectedOperation =
                .group(field: identity)
        case .unsupportedMinimum?,
            .unsupportedMaximum?, nil:
            throw GraphChatComposableReadPlanValidationError
                .invalidProjectionAggregation
        }
        guard
            intent.kind == .countOrGroup,
            intent.factExpectation == .none,
            inventory.aggregation == expected,
            inventory.projection
                == GraphChatComposableReadProjection(
                    includesNodeIdentity: true,
                    fields: []
                ),
            inventory.sort == nil,
            inventory.search == nil,
            inventory.description == nil,
            inventory.comparison == nil,
            inventory.graphState == nil,
            inventory.traversal == nil,
            plan.artifactContract
                == .queryResult,
            Set(plan.evidenceRequirements)
                == [.nodeIdentity],
            case .countOrGroup(
                let countOrGroup
            ) = intent.payload,
            countOrGroup.operation
                == expectedOperation,
            selectedEntityID(
                inventory.selection
            ) == countOrGroup.entity.id,
            referencedFieldIDs(
                inventory
            ) == Set(
                countOrGroup
                    .referencedFields
                    .map(\.id)
            ),
            intent.expectedCardinality
                == (
                    expectedOperation == .count
                    ? .exactlyOne
                    : .zeroOrMore
                )
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidProjectionAggregation
        }
    }

    private func validateRelationshipContract(
        _ inventory: OperationInventory,
        plan: GraphChatComposableReadPlan,
        intent: GraphChatTypedIntent,
        providerPlan: GraphChatProviderTurnPlan
    ) throws {
        guard
            intent.kind == .relationships,
            intent.version == .v2,
            intent.factExpectation == .none,
            intent.expectedCardinality
                == .zeroOrMore,
            case .relationships(
                let relationship
            ) = intent.payload,
            let traversal =
                inventory.traversal,
            traversal.request
                == relationship.request,
            traversal.centerEntity
                == relationship.centerEntity,
            traversal.centerNode
                == relationship.centerNode,
            traversal.direction
                == relationship.direction,
            traversal.counterpartEntity
                == relationship.counterpartEntity,
            traversal.counterpartNode
                == relationship.counterpartNode,
            traversal.notePredicate
                == relationship.notePredicate,
            traversal.sourceRelationshipContextID
                == relationship
                    .sourceRelationshipContextID,
            traversal.hopCount == 1,
            traversal.hopCount
                <= plan.limits
                    .maximumTraversalHopCount,
            inventory.relationshipProjection
                == GraphChatComposableReadRelationshipProjection(
                    includesCounterpartNode: true,
                    includesDirection: true,
                    includesLinkNote: true
                ),
            inventory.sort
                == GraphChatComposableReadSort(
                    descriptors: [
                        GraphChatComposableReadSortDescriptor(
                            key:
                                .counterpartDisplayName,
                            direction:
                                .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key:
                                .counterpartKind,
                            direction:
                                .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key:
                                .counterpartNodeID,
                            direction:
                                .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key:
                                .relationshipDirection,
                            direction:
                                .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key:
                                .linkCreatedAt,
                            direction:
                                .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key:
                                .stableLinkID,
                            direction:
                                .ascending
                        ),
                    ]
                ),
            inventory.search == nil,
            inventory.filter == nil,
            inventory.projection == nil,
            inventory.aggregation == nil,
            inventory.description == nil,
            inventory.comparison == nil,
            inventory.graphState == nil,
            plan.artifactContract
                == .relationships,
            Set(plan.evidenceRequirements)
                == [
                    .nodeIdentity,
                    .directRelationshipBinding,
                ],
            plan.limits.maximumResultLimit
                == policy.maximumNeighborCount,
            relationship.limits
                == GraphChatTypedIntentLimits(
                    resultLimit:
                        plan.limits
                            .resultLimit,
                    maximumResultLimit:
                        plan.limits
                            .maximumResultLimit,
                    maximumEvidenceCount:
                        plan.limits
                            .maximumEvidenceCount,
                    maximumArtifactCount:
                        plan.limits
                            .maximumArtifactCount
                ),
            case .node(
                let entity,
                let node
            ) = inventory.selection,
            entity == traversal.centerEntity,
            node == traversal.centerNode,
            plan.compiledScope
                == .node(
                    node.node,
                    in: plan.graphScope
                ),
            traversal.centerNode
                .ownerEntityID
                == traversal.centerEntity.id,
            traversal.counterpartNode == nil
                || (
                    traversal.counterpartEntity != nil
                    && traversal.counterpartNode?
                        .ownerEntityID
                        == traversal.counterpartEntity?
                            .id
                )
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidTraversal
        }
        if traversal.request
            == .linkNotesBetweenNodes
        {
            guard
                traversal.counterpartNode != nil,
                traversal.direction == .both,
                traversal.notePredicate == nil
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidTraversal
            }
        }
        if case .contains(let term)? =
                traversal.notePredicate {
            let normalized =
                term.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            guard
                normalized.isEmpty == false,
                normalized.count
                    <= policy
                        .maximumFilterValueLength,
                GraphChatSemanticSafety
                    .containsTechnicalIdentifier(
                        normalized
                    ) == false
            else {
                throw GraphChatComposableReadPlanValidationError
                .invalidTraversal
            }
        }
        if let sourceContextID =
                traversal
                    .sourceRelationshipContextID {
            guard
                let previous =
                    providerPlan
                        .requestBaseState
                        .lastRelationship,
                previous.resultContextID
                    == sourceContextID,
                previous.sourceTurnID
                    == plan.binding
                        .sourceTurnID,
                previous.plan.graphScope
                    == plan.graphScope,
                previous.plan.chatScope
                    == plan.chatScope,
                previous.plan.centerEntity.id
                    == traversal.centerEntity.id,
                previous.plan.centerNode.node
                    == traversal.centerNode.node,
                previous.plan.counterpartEntity?
                    .id
                    == traversal
                        .counterpartEntity?
                        .id,
                previous.plan.counterpartNode?
                    .node
                    == traversal
                        .counterpartNode?
                        .node,
                providerPlan
                    .requestBaseState
                    .turnContexts.contains(
                        where: {
                            $0.id
                                == previous
                                    .sourceTurnID
                        }
                    ),
                providerPlan
                    .requestBaseState
                    .resultContexts.contains(
                        where: {
                            $0.id
                                == sourceContextID
                            && $0.kind
                                == .relationship
                        }
                    )
            else {
                throw GraphChatComposableReadPlanValidationError
                    .staleConversationResult
            }
        }
    }

    private func validateQueryIfNeeded(
        _ action: GraphChatLocalIntentAction,
        plan: GraphChatComposableReadPlan,
        schemaContext: GraphSchemaContext
    ) throws -> ValidatedGraphQueryPlan? {
        let source: GraphQueryPlan
        switch action {
        case .queryDetailValues(let query):
            source = query.plan
        case .compareNodes(let comparison):
            guard let selectionQuery =
                    comparison.selectionQuery else {
                return nil
            }
            source = selectionQuery
        case .searchGraph, .nodeDetails,
            .inspectGraphState, .relationships,
            .composableRead:
            return nil
        }
        let executionSchema =
            GraphSchemaContext(
                graphScope:
                    schemaContext.graphScope,
                snapshot:
                    schemaContext.snapshot,
                aliases:
                    schemaContext
                        .foundationalAliases,
                foundationalAliases:
                    schemaContext
                        .foundationalAliases
            )
        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate:
                plan.queryReferenceDate
                ?? referenceDate()
        )
        do {
            let validated = try validator
                .validate(
                    source,
                    against:
                        executionSchema
                )
            guard
                validated.graphScope
                    == plan.graphScope,
                validated.limit
                    == plan.limits.resultLimit,
                GraphChatScopeAuthorization
                    .allows(
                        plan: validated,
                        within:
                            plan.chatScope
                    )
            else {
                throw GraphChatComposableReadPlanValidationError
                    .scopeMismatch
            }
            return validated
        } catch let error
            as GraphChatComposableReadPlanValidationError {
            throw error
        } catch {
            throw GraphChatComposableReadPlanValidationError
                .invalidQuery
        }
    }

    private func validateComposableFiltersIfNeeded(
        _ inventory: OperationInventory,
        plan: GraphChatComposableReadPlan,
        schemaContext: GraphSchemaContext
    ) throws
        -> [GraphChatComposableReadValidatedFilterStage]
    {
        guard plan.resultContract
                == .composableNodeCollection else {
            return []
        }
        guard
            case .entity(let rootReference) =
                inventory.selection,
            let rootEntity = rootReference.identity
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidSelection
        }
        var result:
            [GraphChatComposableReadValidatedFilterStage] = []
        if let filter = inventory.filter,
           let operationID = inventory.filterOperationID {
            result.append(
                try validatedFilterStage(
                    operationID: operationID,
                    entity: rootEntity,
                    predicates: filter.predicates,
                    plan: plan,
                    schemaContext: schemaContext
                )
            )
        }
        for traversal in inventory.composableTraversals
        where traversal.stage.nodePredicates.isEmpty == false {
            result.append(
                try validatedFilterStage(
                    operationID: traversal.id,
                    entity:
                        traversal.stage
                            .counterpartEntity,
                    predicates:
                        traversal.stage
                            .nodePredicates,
                    plan: plan,
                    schemaContext: schemaContext
                )
            )
        }
        return result
    }

    private func validatedFilterStage(
        operationID: GraphChatComposableReadStepID,
        entity: GraphChatTypedEntityIdentity,
        predicates: [GraphChatComposableReadPredicate],
        plan: GraphChatComposableReadPlan,
        schemaContext: GraphSchemaContext
    ) throws -> GraphChatComposableReadValidatedFilterStage {
        guard
            predicates.isEmpty == false,
            predicates.count <= policy.maximumFilterCount,
            predicates.allSatisfy({
                $0.field.identity?.ownerEntityID
                    == entity.id
            })
        else {
            throw GraphChatComposableReadPlanValidationError
                .invalidQuery
        }
        let source = GraphQueryPlan(
            version: plan.queryPlanVersion,
            entityAlias: entity.alias,
            scope: .entity(
                entity.id,
                in: plan.graphScope
            ),
            filters: predicates.map {
                GraphQueryFilter(
                    fieldAlias: $0.field.alias,
                    operation: $0.operation,
                    value: $0.value
                )
            },
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: 1
        )
        let executionSchema = GraphSchemaContext(
            graphScope: schemaContext.graphScope,
            snapshot: schemaContext.snapshot,
            aliases:
                schemaContext.foundationalAliases,
            foundationalAliases:
                schemaContext.foundationalAliases
        )
        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate:
                plan.queryReferenceDate
                ?? referenceDate()
        )
        do {
            let validated = try validator.validate(
                source,
                against: executionSchema
            )
            guard
                validated.graphScope == plan.graphScope,
                validated.entityID == entity.id,
                validated.filters.count
                    == predicates.count
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidQuery
            }
            return GraphChatComposableReadValidatedFilterStage(
                operationID: operationID,
                entity: entity,
                filters: validated.filters
            )
        } catch let error
            as GraphChatComposableReadPlanValidationError {
            throw error
        } catch {
            throw GraphChatComposableReadPlanValidationError
                .invalidQuery
        }
    }

    private func selectedEntityID(
        _ selection:
            GraphChatComposableReadSelection
    ) -> UUID? {
        switch selection {
        case .scope:
            return nil
        case .entity(let entity):
            return entity.identity?.id
        case .node(let entity, _):
            return entity.id
        case .nodes(let entities, _):
            return entities.count == 1
                ? entities[0].id
                : nil
        case .conversationResult(let value):
            return value.entity.identity?.id
        }
    }

    private func selectedNodeKeys(
        _ selection:
            GraphChatComposableReadSelection
    ) -> [NodeRefKey] {
        switch selection {
        case .scope, .entity:
            return []
        case .node(_, let node):
            return [node.node]
        case .nodes(_, let nodes):
            return nodes.map(\.node)
        case .conversationResult(let value):
            return value.nodes.map(\.node)
        }
    }

    private func projectedFieldIDs(
        _ inventory: OperationInventory
    ) -> Set<UUID> {
        Set(
            inventory.projection?
                .fields.compactMap {
                    $0.identity?.id
                } ?? []
        )
    }

    private func referencedFieldIDs(
        _ inventory: OperationInventory
    ) -> Set<UUID> {
        Set(
            inventory.fields.compactMap {
                $0.identity?.id
            }
        )
    }

    private struct OperationInventory {
        struct TraversalOperation {
            let id: GraphChatComposableReadStepID
            let stage: GraphChatComposableReadTraversalStage
        }

        let selection:
            GraphChatComposableReadSelection
        let selectionCount: Int
        let search:
            GraphChatComposableReadSearch?
        let filter:
            GraphChatComposableReadFilter?
        let filterOperationID:
            GraphChatComposableReadStepID?
        let projection:
            GraphChatComposableReadProjection?
        let sort:
            GraphChatComposableReadSort?
        let aggregation:
            GraphChatComposableReadAggregation?
        let description:
            GraphChatComposableReadNodeDescription?
        let comparison:
            GraphChatComposableReadComparison?
        let graphState:
            GraphChatComposableReadGraphState?
        let traversal:
            GraphChatComposableReadTraversal?
        let composableTraversals:
            [TraversalOperation]
        let traversalProjection:
            GraphChatComposableReadTraversalProjection?
        let relationshipProjection:
            GraphChatComposableReadRelationshipProjection?
        let limit:
            GraphChatComposableReadLimit
        let limitCount: Int
        let entities:
            [GraphChatComposableReadEntityReference]
        let nodes:
            [GraphChatTypedNodeIdentity]
        let fields:
            [GraphChatComposableReadFieldReference]

        init(
            _ operations:
                [GraphChatComposableReadOperation]
        ) throws {
            var selections:
                [GraphChatComposableReadSelection] = []
            var searches:
                [GraphChatComposableReadSearch] = []
            var filters:
                [(GraphChatComposableReadStepID, GraphChatComposableReadFilter)] = []
            var projections:
                [GraphChatComposableReadProjection] = []
            var sorts:
                [GraphChatComposableReadSort] = []
            var aggregations:
                [GraphChatComposableReadAggregation] = []
            var descriptions:
                [GraphChatComposableReadNodeDescription] = []
            var comparisons:
                [GraphChatComposableReadComparison] = []
            var graphStates:
                [GraphChatComposableReadGraphState] = []
            var traversals:
                [GraphChatComposableReadTraversal] = []
            var composableTraversals:
                [TraversalOperation] = []
            var traversalProjections:
                [GraphChatComposableReadTraversalProjection] = []
            var relationshipProjections:
                [GraphChatComposableReadRelationshipProjection] = []
            var limits:
                [GraphChatComposableReadLimit] = []

            for operation in operations {
                switch operation.payload {
                case .select(let value):
                    selections.append(value)
                case .search(let value):
                    searches.append(value)
                case .filter(let value):
                    filters.append((operation.id, value))
                case .project(let value):
                    projections.append(value)
                case .sort(let value):
                    sorts.append(value)
                case .aggregate(let value):
                    aggregations.append(value)
                case .describeNode(let value):
                    descriptions.append(value)
                case .compareNodes(let value):
                    comparisons.append(value)
                case .inspectGraphState(let value):
                    graphStates.append(value)
                case .traverseDirectRelationships(
                    let value
                ):
                    traversals.append(value)
                case .traverseRelationships(let value):
                    composableTraversals.append(
                        TraversalOperation(
                            id: operation.id,
                            stage: value
                        )
                    )
                case .projectTraversalNodes(let value):
                    traversalProjections.append(value)
                case .projectRelationships(
                    let value
                ):
                    relationshipProjections
                        .append(value)
                case .limit(let value):
                    limits.append(value)
                }
            }
            guard
                selections.count == 1,
                limits.count == 1,
                searches.count <= 1,
                filters.count <= 1,
                projections.count <= 1,
                sorts.count <= 1,
                aggregations.count <= 1,
                descriptions.count <= 1,
                comparisons.count <= 1,
                graphStates.count <= 1,
                traversals.count <= 1,
                composableTraversals.count <= 2,
                traversalProjections.count <= 1,
                relationshipProjections.count
                    <= 1
            else {
                throw GraphChatComposableReadPlanValidationError
                    .invalidOperationOrder
            }
            selection = selections[0]
            selectionCount = selections.count
            search = searches.first
            filter = filters.first?.1
            filterOperationID = filters.first?.0
            projection = projections.first
            sort = sorts.first
            aggregation = aggregations.first
            description = descriptions.first
            comparison = comparisons.first
            graphState = graphStates.first
            traversal = traversals.first
            self.composableTraversals =
                composableTraversals
            traversalProjection =
                traversalProjections.first
            relationshipProjection =
                relationshipProjections.first
            limit = limits[0]
            limitCount = limits.count

            var entityValues:
                [GraphChatComposableReadEntityReference] = []
            var nodeValues:
                [GraphChatTypedNodeIdentity] = []
            switch selection {
            case .scope:
                break
            case .entity(let entity):
                entityValues.append(entity)
            case .node(let entity, let node):
                entityValues.append(
                    GraphChatComposableReadEntityReference(
                        alias: entity.alias,
                        identity: entity
                    )
                )
                nodeValues.append(node)
            case .nodes(let entities, let nodes):
                entityValues.append(
                    contentsOf:
                        entities.map {
                            GraphChatComposableReadEntityReference(
                                alias: $0.alias,
                                identity: $0
                            )
                        }
                )
                nodeValues.append(
                    contentsOf: nodes
                )
            case .conversationResult(let value):
                entityValues.append(value.entity)
                nodeValues.append(
                    contentsOf:
                        value.nodes
                )
            }
            if let description {
                nodeValues.append(
                    description.node
                )
            }
            if let traversal {
                entityValues.append(
                    GraphChatComposableReadEntityReference(
                        alias:
                            traversal
                                .centerEntity.alias,
                        identity:
                            traversal
                                .centerEntity
                    )
                )
                nodeValues.append(
                    traversal.centerNode
                )
                if let counterpart =
                        traversal
                            .counterpartEntity {
                    entityValues.append(
                        GraphChatComposableReadEntityReference(
                            alias:
                                counterpart.alias,
                            identity:
                                counterpart
                        )
                    )
                }
                if let counterpart =
                        traversal
                            .counterpartNode {
                    nodeValues.append(
                        counterpart
                    )
                }
            }
            for traversal in composableTraversals {
                let stage = traversal.stage
                entityValues.append(
                    GraphChatComposableReadEntityReference(
                        alias:
                            stage.counterpartEntity.alias,
                        identity:
                            stage.counterpartEntity
                    )
                )
                if let counterpart =
                        stage.counterpartNode {
                    nodeValues.append(counterpart)
                }
            }

            var fieldValues:
                [GraphChatComposableReadFieldReference] = []
            fieldValues.append(
                contentsOf:
                    filters.flatMap { $0.1.predicates }
                        .map(\.field)
            )
            fieldValues.append(
                contentsOf:
                    composableTraversals
                        .flatMap {
                            $0.stage.nodePredicates
                        }
                        .map(\.field)
            )
            fieldValues.append(
                contentsOf:
                    projections
                        .flatMap(\.fields)
            )
            fieldValues.append(
                contentsOf:
                    sorts.flatMap(
                        \.descriptors
                    ).compactMap {
                        descriptor in
                        guard case .field(
                            let field
                        ) = descriptor.key
                        else {
                            return nil
                        }
                        return field
                    }
            )
            for aggregation in aggregations {
                switch aggregation {
                case .count:
                    break
                case .groupCount(let field),
                    .unsupportedMinimum(let field),
                    .unsupportedMaximum(let field):
                    fieldValues.append(field)
                }
            }
            for comparison in comparisons {
                fieldValues.append(
                    contentsOf:
                        comparison.features
                            .compactMap {
                                feature in
                                guard case .field(
                                    let field
                                ) = feature
                                else {
                                    return nil
                                }
                                return GraphChatComposableReadFieldReference(
                                    alias:
                                        field.alias,
                                    identity: field
                                )
                            }
                )
            }
            entities = OperationInventory
                .stableUnique(entityValues)
            nodes = OperationInventory
                .stableUnique(nodeValues)
            fields = OperationInventory
                .stableUnique(fieldValues)
        }

        private static func stableUnique<Value: Hashable>(
            _ values: [Value]
        ) -> [Value] {
            var seen = Set<Value>()
            return values.filter {
                seen.insert($0).inserted
            }
        }
    }
}
