import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat composable read plan")
struct GraphChatComposableReadPlanTests {
    @Test
    func domainVersionHashabilitySendabilityAndArtifactGate()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let mapped = try fixture.collection()
        let plan = mapped.adaptation.readPlan

        requireHashableSendable(
            GraphChatComposableReadPlanVersion.v1
        )
        requireHashableSendable(
            GraphChatComposableReadPlanVersion.v2
        )
        requireHashableSendable(
            GraphChatComposableReadPlanVersion.allCases
        )
        requireHashableSendable(plan)
        requireHashableSendable(plan.operations)
        requireHashableSendable(plan.limits)
        #expect(
            GraphChatComposableReadPlanVersion.current
                == .v2
        )
        #expect(plan.version == .current)
        #expect(
            plan.queryPlanVersion
                == GraphQueryPlan.currentVersion
        )
        #expect(Set([plan, plan]).count == 1)

        let unsupportedQueryVersion =
            plan.replacingQueryPlanVersion(
                GraphQueryPlan.currentVersion + 1
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .unsupportedVersion
        ) {
            _ = try fixture.validator.validate(
                unsupportedQueryVersion,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let oldContext =
            GraphChatArtifactCommitContext(
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                sessionID:
                    fixture.artifactSessionID,
                transactionID:
                    fixture.transactionID
            )
        let currentContext =
            GraphChatArtifactCommitContext(
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                sessionID:
                    fixture.artifactSessionID,
                transactionID:
                    fixture.transactionID,
                readPlanVersion: .current
            )
        #expect(oldContext.readPlanVersion == nil)
        #expect(
            currentContext.readPlanVersion
                == .current
        )
        #expect(oldContext != currentContext)
    }

    @Test
    func normalizationIsStableAndAddsExactlyOneTieBreaker()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let source = try fixture.filtered(
            fieldAlias: GraphFieldAlias("F1"),
            operation: .contains,
            value: .text("Atlas")
        ).adaptation.readPlan
        let withoutTieBreaker =
            source.replacingOperations(
                source.operations.map {
                    operation in
                    guard case .sort(let sort) =
                            operation.payload
                    else {
                        return operation
                    }
                    return operation.replacingPayload(
                        .sort(
                            GraphChatComposableReadSort(
                                descriptors:
                                    sort.descriptors.filter {
                                        $0.key
                                            != .stableNodeID
                                    }
                            )
                        )
                    )
                }
            )

        let normalized =
            try GraphChatComposableReadPlanNormalizer
                .normalize(withoutTieBreaker)
        let normalizedAgain =
            try GraphChatComposableReadPlanNormalizer
                .normalize(normalized)
        let sort = try #require(
            normalized.operations.compactMap {
                operation
                -> GraphChatComposableReadSort? in
                guard case .sort(let value) =
                        operation.payload
                else {
                    return nil
                }
                return value
            }.first
        )

        #expect(normalized == normalizedAgain)
        #expect(
            normalized.operations.map(\.id)
                == normalized.operations.indices.map {
                    GraphChatComposableReadStepID(
                        rawValue: $0
                    )
                }
        )
        #expect(
            sort.descriptors.last
                == GraphChatComposableReadSortDescriptor(
                    key: .stableNodeID,
                    direction: .ascending
                )
        )
        #expect(
            sort.descriptors.filter {
                $0.key == .stableNodeID
            }.count == 1
        )
    }

    @Test
    func normalizerRejectsDuplicateUnboundAndCyclicReferences()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let plan = try fixture.collection()
            .adaptation.readPlan

        var duplicate = plan.operations
        duplicate[1] =
            GraphChatComposableReadOperation(
                id: duplicate[0].id,
                input: duplicate[1].input,
                payload: duplicate[1].payload
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .duplicateStep
        ) {
            _ = try GraphChatComposableReadPlanNormalizer
                .normalize(
                    plan.replacingOperations(
                        duplicate
                    )
                )
        }

        var unbound = plan.operations
        unbound[1] =
            GraphChatComposableReadOperation(
                id: unbound[1].id,
                input:
                    GraphChatComposableReadStepID(
                        rawValue: 99
                    ),
                payload: unbound[1].payload
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .unboundStepReference
        ) {
            _ = try GraphChatComposableReadPlanNormalizer
                .normalize(
                    plan.replacingOperations(
                        unbound
                    )
                )
        }

        var cyclic = plan.operations
        cyclic[1] =
            GraphChatComposableReadOperation(
                id: cyclic[1].id,
                input: cyclic.last?.id,
                payload: cyclic[1].payload
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .cyclicStepReference
        ) {
            _ = try GraphChatComposableReadPlanNormalizer
                .normalize(
                    plan.replacingOperations(
                        cyclic
                    )
                )
        }
    }

    @Test
    func validatorAcceptsTextIntegerDoubleDateBoolAndChoiceFilters()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let matrix: [(
            GraphFieldAlias,
            GraphQueryFilterOperator,
            GraphQueryFilterValue
        )] = [
            (
                GraphFieldAlias("F1"),
                .contains,
                .text("Atlas")
            ),
            (
                GraphFieldAlias("F3"),
                .greaterThanOrEqual,
                .integer(8)
            ),
            (
                GraphFieldAlias("F4"),
                .between,
                .decimalRange(
                    GraphQueryDoubleRange(
                        lowerBound: 10.5,
                        upperBound: 99.5
                    )
                )
            ),
            (
                GraphFieldAlias("F5"),
                .before,
                .date(fixture.referenceDate)
            ),
            (
                GraphFieldAlias("F6"),
                .equals,
                .boolean(true)
            ),
            (
                GraphFieldAlias("F7"),
                .oneOf,
                .choices([
                    "Offen",
                    "In Arbeit",
                ])
            ),
        ]

        for (alias, operation, value) in matrix {
            let mapped = try fixture.filtered(
                fieldAlias: alias,
                operation: operation,
                value: value
            )
            let validated =
                try fixture.validator.validate(
                    mapped.adaptation.readPlan,
                    for:
                        mapped.adaptation.intent,
                    schemaContext:
                        fixture.schemaContext,
                    providerPlan:
                        fixture.providerPlan
                )
            #expect(
                validated.action
                    == mapped.action
            )
            #expect(
                validated.validatedQueryPlan?
                    .filters.count == 1
            )
        }
    }

    @Test
    func validatorRejectsTypeScopeLimitOrderAndContractManipulation()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let mapped = try fixture.filtered(
            fieldAlias: GraphFieldAlias("F1"),
            operation: .contains,
            value: .text("Atlas")
        )
        let source = mapped.adaptation.readPlan

        let invalidOperator =
            source.replacingOperations(
                source.operations.map {
                    operation in
                    guard case .filter(let filter) =
                            operation.payload,
                          let predicate =
                            filter.predicates.first
                    else {
                        return operation
                    }
                    return operation.replacingPayload(
                        .filter(
                            GraphChatComposableReadFilter(
                                predicates: [
                                    GraphChatComposableReadPredicate(
                                        field:
                                            predicate.field,
                                        operation:
                                            .greaterThan,
                                        value:
                                            .integer(1)
                                    ),
                                ]
                            )
                        )
                    )
                }
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidQuery
        ) {
            _ = try fixture.validator.validate(
                invalidOperator,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let foreignGraph =
            source.replacingGraphScope(
                GraphScope(
                    graphID:
                        GraphChatTestSupport
                            .otherGraphID
                )
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .scopeMismatch
        ) {
            _ = try fixture.validator.validate(
                foreignGraph,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let excessiveIntermediateLimit =
            source.replacingLimits(
                GraphChatComposableReadLimits(
                    resultLimit:
                        source.limits.resultLimit,
                    maximumResultLimit:
                        source.limits
                            .maximumResultLimit,
                    intermediateResultLimit:
                        GraphChatIntentLimitPolicy
                            .default
                            .maximumComposableReadIntermediateCount
                        + 1,
                    maximumEvidenceCount:
                        source.limits
                            .maximumEvidenceCount,
                    maximumArtifactCount:
                        source.limits
                            .maximumArtifactCount,
                    maximumOperationCount:
                        source.limits
                            .maximumOperationCount,
                    maximumTraversalHopCount:
                        source.limits
                            .maximumTraversalHopCount
                )
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidLimits
        ) {
            _ = try fixture.validator.validate(
                excessiveIntermediateLimit,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let raisedArtifactBudget =
            source.replacingLimits(
                GraphChatComposableReadLimits(
                    resultLimit:
                        source.limits.resultLimit,
                    maximumResultLimit:
                        source.limits.maximumResultLimit,
                    intermediateResultLimit:
                        source.limits.intermediateResultLimit,
                    maximumEvidenceCount:
                        source.limits.maximumEvidenceCount,
                    maximumArtifactCount:
                        source.limits.maximumArtifactCount + 1,
                    maximumOperationCount:
                        source.limits.maximumOperationCount,
                    maximumTraversalHopCount:
                        source.limits.maximumTraversalHopCount,
                    selectedStartNodeLimit:
                        source.limits.selectedStartNodeLimit,
                    visitedNodeLimit:
                        source.limits.visitedNodeLimit,
                    checkedLinkLimit:
                        source.limits.checkedLinkLimit
                )
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidLimits
        ) {
            _ = try fixture.validator.validate(
                raisedArtifactBudget,
                for: mapped.adaptation.intent,
                schemaContext: fixture.schemaContext,
                providerPlan: fixture.providerPlan
            )
        }

        let payloads =
            source.operations.map(\.payload)
        let filterIndex = try #require(
            payloads.firstIndex {
                if case .filter = $0 {
                    return true
                }
                return false
            }
        )
        let projectionIndex = try #require(
            payloads.firstIndex {
                if case .project = $0 {
                    return true
                }
                return false
            }
        )
        var reordered = payloads
        reordered.swapAt(
            filterIndex,
            projectionIndex
        )
        let invalidOrder =
            source.replacingOperations(
                sequentialOperations(
                    reordered
                )
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidOperationOrder
        ) {
            _ = try fixture.validator.validate(
                invalidOrder,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let invalidArtifact =
            source.replacingArtifactContract(
                .comparison
            )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidProjectionAggregation
        ) {
            _ = try fixture.validator.validate(
                invalidArtifact,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let grouped = try fixture.groupCount()
        let invalidGroupProjection =
            grouped.adaptation.readPlan
                .replacingOperations(
                    grouped.adaptation.readPlan
                        .operations.map {
                            operation in
                            guard case .project =
                                    operation.payload
                            else {
                                return operation
                            }
                            return operation.replacingPayload(
                                .project(
                                    GraphChatComposableReadProjection(
                                        includesNodeIdentity:
                                            true,
                                        fields: [
                                            GraphChatComposableReadFieldReference(
                                                alias:
                                                    fixture
                                                        .statusField
                                                        .alias,
                                                identity:
                                                    fixture
                                                        .statusField
                                            ),
                                        ]
                                    )
                                )
                            )
                        }
                )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidProjectionAggregation
        ) {
            _ = try fixture.validator.validate(
                invalidGroupProjection,
                for:
                    grouped.adaptation.intent,
                schemaContext:
                    fixture.schemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }
    }

    @Test
    func directTraversalIsLimitedToOneHop()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let mapped = try fixture.relationships()
        let validated =
            try fixture.validator.validate(
                mapped.adaptation.readPlan,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.nodeSchemaContext,
                providerPlan:
                    fixture.providerPlan
        )
        #expect(validated.action == mapped.action)
        let relationshipSort =
            try #require(
                validated.plan.operations
                    .compactMap {
                        operation
                        -> GraphChatComposableReadSort? in
                        guard case .sort(let value) =
                                operation.payload
                        else {
                            return nil
                        }
                        return value
                    }
                    .first
            )
        #expect(
            relationshipSort.descriptors.last
                == GraphChatComposableReadSortDescriptor(
                    key: .stableLinkID,
                    direction: .ascending
                )
        )

        let twoHop =
            mapped.adaptation.readPlan
                .replacingOperations(
                    mapped.adaptation.readPlan
                        .operations.map {
                            operation in
                            guard case
                                    .traverseDirectRelationships(
                                        let traversal
                                    ) =
                                    operation.payload
                            else {
                                return operation
                            }
                            return operation.replacingPayload(
                                .traverseDirectRelationships(
                                    GraphChatComposableReadTraversal(
                                        request:
                                            traversal.request,
                                        centerEntity:
                                            traversal.centerEntity,
                                        centerNode:
                                            traversal.centerNode,
                                        direction:
                                            traversal.direction,
                                        counterpartEntity:
                                            traversal.counterpartEntity,
                                        counterpartNode:
                                            traversal.counterpartNode,
                                        notePredicate:
                                            traversal.notePredicate,
                                        hopCount: 2,
                                        sourceRelationshipContextID:
                                            traversal
                                                .sourceRelationshipContextID
                                    )
                                )
                            )
                        }
                )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidTraversal
        ) {
            _ = try fixture.validator.validate(
                twoHop,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.nodeSchemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }

        let raisedHopPolicy =
            mapped.adaptation.readPlan
                .replacingLimits(
                    GraphChatComposableReadLimits(
                        resultLimit:
                            mapped.adaptation
                                .readPlan
                                .limits
                                .resultLimit,
                        maximumResultLimit:
                            mapped.adaptation
                                .readPlan
                                .limits
                                .maximumResultLimit,
                        intermediateResultLimit:
                            mapped.adaptation
                                .readPlan
                                .limits
                                .intermediateResultLimit,
                        maximumEvidenceCount:
                            mapped.adaptation
                                .readPlan
                                .limits
                                .maximumEvidenceCount,
                        maximumArtifactCount:
                            mapped.adaptation
                                .readPlan
                                .limits
                                .maximumArtifactCount,
                        maximumOperationCount:
                            mapped.adaptation
                                .readPlan
                                .limits
                                .maximumOperationCount,
                        maximumTraversalHopCount: 3
                    )
                )
        #expect(
            throws:
                GraphChatComposableReadPlanValidationError
                    .invalidLimits
        ) {
            _ = try fixture.validator.validate(
                raisedHopPolicy,
                for: mapped.adaptation.intent,
                schemaContext:
                    fixture.nodeSchemaContext,
                providerPlan:
                    fixture.providerPlan
            )
        }
    }

    @Test
    func everyExistingLocalIntentFamilyMapsLosslessly()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let mappings =
            try fixture.allFamilyMappings()
        let expectedContracts:
            Set<GraphChatComposableReadResultContract> =
            [
                .search,
                .entityCollection,
                .compiledCollection,
                .count,
                .groupCount,
                .refinement,
                .authoritativeSingleField(
                    node: fixture.firstNode,
                    field: fixture.textField
                ),
                .nodeProfile,
                .comparison,
                .graphState,
                .relationships,
            ]

        for mapping in mappings {
            let adaptation = mapping.adaptation
            #expect(
                adaptation.action
                    == mapping.action,
                Comment(
                    rawValue:
                        "Legacy result semantics changed for \(mapping.name)."
                )
            )
            #expect(
                adaptation.readPlan.version
                    == .current
            )
            #expect(
                adaptation.readPlan.binding
                    == adaptation.intent.binding
            )
            #expect(
                adaptation.readPlan.graphScope
                    == adaptation.intent
                        .scope.graphScope
            )
            #expect(
                adaptation.readPlan.operations
                    .first.map {
                        if case .select =
                                $0.payload {
                            return true
                        }
                        return false
                    } == true
            )
            #expect(
                adaptation.readPlan.operations
                    .last.map {
                        if case .limit =
                                $0.payload {
                            return true
                        }
                        return false
                    } == true
            )
        }
        #expect(
            Set(
                mappings.map {
                    $0.adaptation
                        .readPlan
                        .resultContract
                }
            ) == expectedContracts
        )
    }

    @Test
    func compilationIsDomainAgnosticAcrossThreeGraphDomains()
        throws
    {
        let fixture = ComposableReadPlanFixture()
        let mappings = [
            try fixture.domainMapping(
                name: "Klinische Studien",
                suffix: 701,
                shape: .dateFiltered
            ),
            try fixture.domainMapping(
                name: "Museumswerke",
                suffix: 702,
                shape: .collection
            ),
            try fixture.domainMapping(
                name: "IT-Störungen",
                suffix: 703,
                shape: .count
            ),
        ]
        var graphScopes = Set<GraphScope>()
        var entityNames = Set<String>()

        for mapping in mappings {
            graphScopes.insert(
                mapping.adaptation
                    .readPlan.graphScope
            )
            guard case .select(
                .entity(let selected)
            ) = mapping.adaptation
                .readPlan.operations[0]
                .payload
            else {
                Issue.record(
                    "Expected an entity selection for \(mapping.name)."
                )
                continue
            }
            entityNames.insert(
                selected.identity?
                    .displayName ?? ""
            )
            #expect(
                mapping.adaptation.action
                    == mapping.action
            )
        }

        #expect(graphScopes.count == 3)
        #expect(
            entityNames == Set([
                "Klinische Studien",
                "Museumswerke",
                "IT-Störungen",
            ])
        )
        #expect(
            Set(
                mappings.map {
                    $0.adaptation
                        .readPlan
                        .resultContract
                }
            ) == Set([
                .compiledCollection,
                .entityCollection,
                .count,
            ])
        )
    }

    private func requireHashableSendable<
        Value: Hashable & Sendable
    >(
        _ value: Value
    ) {
        _ = value
    }
}

private struct ComposableReadPlanMapping {
    let name: String
    let adaptation: GraphChatTypedIntentAdaptation
    let action: GraphChatLocalIntentAction
}

private enum ComposableReadPlanDomainShape {
    case dateFiltered
    case collection
    case count
}

private struct ComposableReadPlanFixture {
    let graphScope = GraphScope(
        graphID:
            GraphChatTestSupport.graphID
    )
    let requestID = UUID(
        uuidString:
            "51000000-0000-0000-0000-000000000001"
    )!
    let conversationID = UUID(
        uuidString:
            "51000000-0000-0000-0000-000000000002"
    )!
    let referenceDate =
        Date(timeIntervalSince1970: 1_800_000_000)
    let artifactSessionID =
        GraphChatAnswerArtifactSessionID(
            rawValue: UUID(
                uuidString:
                    "51000000-0000-0000-0000-000000000003"
            )!
        )
    let transactionID =
        GraphChatAnswerArtifactTransactionID(
            rawValue: UUID(
                uuidString:
                    "51000000-0000-0000-0000-000000000004"
            )!
        )

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var binding: GraphChatTypedIntentBinding {
        GraphChatTypedIntentBinding(
            requestID: requestID,
            conversationID: conversationID,
            turnID: requestID,
            sourceTurnID: nil,
            clarificationID: nil
        )
    }

    var resolution:
        GraphChatTypedIntentResolution
    {
        GraphChatTypedIntentResolution(
            source: .appSemanticResolution,
            origin: .appRule,
            quality: .exact
        )
    }

    var firstEntity:
        GraphChatTypedEntityIdentity
    {
        typedEntity(
            alias: GraphEntityAlias("E1")
        )
    }

    var secondEntity:
        GraphChatTypedEntityIdentity
    {
        typedEntity(
            alias: GraphEntityAlias("E2")
        )
    }

    var textField:
        GraphChatTypedFieldIdentity
    {
        typedField(
            alias: GraphFieldAlias("F1")
        )
    }

    var statusField:
        GraphChatTypedFieldIdentity
    {
        typedField(
            alias: GraphFieldAlias("F7")
        )
    }

    var firstNode:
        GraphChatTypedNodeIdentity
    {
        GraphChatTypedNodeIdentity(
            node:
                NodeRefKey(
                    kind: .attribute,
                    id:
                        GraphChatTestSupport
                            .projectAttributeID
                ),
            displayName: "Projekt Atlas",
            ownerEntityID:
                GraphChatTestSupport
                    .projectEntityID
        )
    }

    var secondNode:
        GraphChatTypedNodeIdentity
    {
        GraphChatTypedNodeIdentity(
            node:
                NodeRefKey(
                    kind: .attribute,
                    id: UUID(
                        uuidString:
                            "51000000-0000-0000-0000-000000000011"
                    )!
                ),
            displayName: "Projekt Borealis",
            ownerEntityID:
                GraphChatTestSupport
                    .projectEntityID
        )
    }

    var personNode:
        GraphChatTypedNodeIdentity
    {
        GraphChatTypedNodeIdentity(
            node:
                NodeRefKey(
                    kind: .attribute,
                    id:
                        GraphChatTestSupport
                            .personAttributeID
                ),
            displayName: "Ada",
            ownerEntityID:
                GraphChatTestSupport
                    .personEntityID
        )
    }

    var schemaContext: GraphSchemaContext {
        GraphChatTestSupport.makeSchemaContext(
            graphID: graphScope.graphID
        )
    }

    var nodeSchemaContext:
        GraphSchemaContext
    {
        let base = schemaContext
        let aliases =
            GraphSchemaAliasMap(
                graphScope: graphScope,
                entitiesByAlias:
                    base
                        .foundationalAliases
                        .entitiesByAlias,
                fieldsByAlias:
                    base
                        .foundationalAliases
                        .fieldsByAlias,
                nodeEntityIDs:
                    base
                        .foundationalAliases
                        .nodeEntityIDs.merging(
                            [
                                firstNode.node:
                                    firstNode
                                        .ownerEntityID,
                                secondNode.node:
                                    secondNode
                                        .ownerEntityID,
                                personNode.node:
                                    personNode
                                        .ownerEntityID,
                            ],
                            uniquingKeysWith: {
                                _, replacement in
                                replacement
                            }
                        ),
                nodesByKey: [
                    firstNode.node:
                        GraphSchemaNodeResolution(
                            node: firstNode.node,
                            ownerEntityID:
                                firstNode
                                    .ownerEntityID,
                            displayName:
                                firstNode
                                    .displayName
                        ),
                    secondNode.node:
                        GraphSchemaNodeResolution(
                            node: secondNode.node,
                            ownerEntityID:
                                secondNode
                                    .ownerEntityID,
                            displayName:
                                secondNode
                                    .displayName
                        ),
                    personNode.node:
                        GraphSchemaNodeResolution(
                            node: personNode.node,
                            ownerEntityID:
                                personNode
                                    .ownerEntityID,
                            displayName:
                                personNode
                                    .displayName
                        ),
                ]
            )
        return GraphSchemaContext(
            graphScope: graphScope,
            snapshot: base.snapshot,
            aliases: aliases,
            foundationalAliases: aliases
        )
    }

    var providerPlan:
        GraphChatProviderTurnPlan
    {
        let state =
            GraphChatConversationState.initial(
                graphScope: graphScope,
                chatScope: chatScope,
                conversationID:
                    conversationID
            )
        return GraphChatProviderTurnPlan(
            scopeKey:
                GraphChatOrchestrationScopeKey(
                    graphScope: graphScope,
                    chatScope: chatScope
                ),
            normalizedQuestion: "read",
            providerQuestion: "Read.",
            responseLanguage: .german,
            requestBaseState: state,
            expectedCommittedState: state,
            conversationContext:
                GraphChatConversationContextBuilder()
                    .makeSnapshot(
                        from: state.snapshot
                    ),
            currentReference: nil,
            currentResolvedScope: nil,
            continuationOperation: nil,
            foundationalContinuation: nil
        )
    }

    var validator:
        GraphChatComposableReadPlanValidator
    {
        GraphChatComposableReadPlanValidator(
            calendar:
                Calendar(identifier: .gregorian),
            timeZone:
                TimeZone(
                    identifier: "Europe/Berlin"
                )!,
            referenceDate: {
                referenceDate
            }
        )
    }

    func collection()
        throws -> ComposableReadPlanMapping
    {
        let action =
            GraphChatLocalIntentAction
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    firstEntity.alias,
                                scope:
                                    chatScope,
                                sorting: [
                                    GraphQuerySort(
                                        key:
                                            .nodeName,
                                        direction:
                                            .ascending
                                    ),
                                ],
                                projection:
                                    [.nodeIdentity],
                                limit: 20
                            ),
                        resultContract:
                            .entityCollection
                    )
                )
        let intent = try makeIntent(
            payload:
                .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity:
                            firstEntity,
                        projectedFields: []
                    )
                ),
            cardinality: .zeroOrMore,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 20,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 20,
                    maximumArtifactCount: 1
                )
        )
        return mapping(
            "Entity Collection",
            intent: intent,
            action: action
        )
    }

    func filtered(
        fieldAlias: GraphFieldAlias,
        operation: GraphQueryFilterOperator,
        value: GraphQueryFilterValue
    ) throws -> ComposableReadPlanMapping {
        let field = typedField(
            alias: fieldAlias
        )
        let action =
            GraphChatLocalIntentAction
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    firstEntity.alias,
                                scope:
                                    chatScope,
                                filters: [
                                    GraphQueryFilter(
                                        fieldAlias:
                                            field.alias,
                                        operation:
                                            operation,
                                        value: value
                                    ),
                                ],
                                sorting: [
                                    GraphQuerySort(
                                        key:
                                            .nodeName,
                                        direction:
                                            .ascending
                                    ),
                                ],
                                projection: [
                                    .nodeIdentity,
                                    .field(
                                        field.alias
                                    ),
                                ],
                                limit: 20
                            ),
                        resultContract:
                            .compiledCollection,
                        compilationReferenceDate:
                            referenceDate
                    )
                )
        let intent = try makeIntent(
            payload:
                .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity:
                            firstEntity,
                        projectedFields: [field],
                        referencedFields: [field]
                    )
                ),
            cardinality: .zeroOrMore,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 20,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 64,
                    maximumArtifactCount: 1
                )
        )
        return mapping(
            "Filtered List",
            intent: intent,
            action: action
        )
    }

    func relationships()
        throws -> ComposableReadPlanMapping
    {
        let limits =
            GraphChatTypedIntentLimits(
                resultLimit:
                    GraphChatIntentLimitPolicy
                        .default
                        .nodeDetailRelatedItemCount,
                maximumResultLimit:
                    GraphChatIntentLimitPolicy
                        .default
                        .maximumNeighborCount,
                maximumEvidenceCount:
                    GraphChatIntentLimitPolicy
                        .default
                        .maximumNeighborCount
                    + 1,
                maximumArtifactCount: 1
            )
        let plan =
            try GraphChatRelationshipPlan(
                graphScope: graphScope,
                chatScope: chatScope,
                queryScope:
                    .node(
                        firstNode.node,
                        in: graphScope
                    ),
                binding: binding,
                request: .connections,
                centerEntity: firstEntity,
                centerNode: firstNode,
                direction: .both,
                counterpartEntity:
                    secondEntity,
                counterpartNode:
                    personNode,
                limits: limits,
                responseLanguage: .german
            )
        let intent =
            try GraphChatTypedIntent(
                version: .v2,
                scope:
                    GraphChatTypedIntentScope(
                        graphScope: graphScope,
                        chatScope: chatScope,
                        queryScope:
                            plan.queryScope
                    ),
                responseLanguage: .german,
                binding: binding,
                resolution: resolution,
                expectedCardinality:
                    .zeroOrMore,
                factExpectation: .none,
                limits: limits,
                payload: .relationships(plan)
            )
        let action =
            GraphChatLocalIntentAction
                .relationships(plan)
        return mapping(
            "Relationships",
            intent: intent,
            action: action
        )
    }

    func allFamilyMappings()
        throws -> [ComposableReadPlanMapping]
    {
        [
            try findNodes(),
            try collection(),
            try filtered(
                fieldAlias:
                    GraphFieldAlias("F7"),
                operation: .equals,
                value: .choice("Offen")
            ),
            try count(),
            try groupCount(),
            try refinement(),
            try authoritativeNodeField(),
            try nodeProfile(),
            try comparison(),
            try graphState(),
            try relationships(),
        ]
    }

    func domainMapping(
        name: String,
        suffix: Int,
        shape:
            ComposableReadPlanDomainShape
    ) throws -> ComposableReadPlanMapping {
        let graphID = UUID(
            uuidString: String(
                format:
                    "52000000-0000-0000-0000-%012d",
                suffix
            )
        )!
        let entityID = UUID(
            uuidString: String(
                format:
                    "53000000-0000-0000-0000-%012d",
                suffix
            )
        )!
        let fieldID = UUID(
            uuidString: String(
                format:
                    "54000000-0000-0000-0000-%012d",
                suffix
            )
        )!
        let scope =
            GraphScope(graphID: graphID)
        let chat =
            GraphChatScope.entireGraph(scope)
        let entity =
            GraphChatTypedEntityIdentity(
                id: entityID,
                alias: GraphEntityAlias("E1"),
                displayName: name
            )
        let dateField =
            GraphChatTypedFieldIdentity(
                id: fieldID,
                alias:
                    GraphFieldAlias("F1"),
                displayName: "Startdatum",
                ownerEntityID:
                    entityID,
                type: .date,
                unit: nil
            )
        let domainBinding =
            GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID:
                    conversationID,
                turnID: requestID,
                sourceTurnID: nil,
                clarificationID: nil
            )
        let payload:
            GraphChatTypedIntentPayload
        let cardinality:
            GraphChatTypedIntentExpectedCardinality
        let limits:
            GraphChatTypedIntentLimits
        let action:
            GraphChatLocalIntentAction
        switch shape {
        case .dateFiltered:
            payload =
                .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity: entity,
                        projectedFields:
                            [dateField],
                        referencedFields:
                            [dateField]
                    )
                )
            cardinality = .zeroOrMore
            limits =
                GraphChatTypedIntentLimits(
                    resultLimit: 20,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 64,
                    maximumArtifactCount: 1
                )
            action =
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    entity.alias,
                                scope: chat,
                                filters: [
                                    GraphQueryFilter(
                                        fieldAlias:
                                            dateField.alias,
                                        operation:
                                            .after,
                                        value:
                                            .date(
                                                referenceDate
                                            )
                                    ),
                                ],
                                sorting: [
                                    GraphQuerySort(
                                        key:
                                            .nodeName,
                                        direction:
                                            .ascending
                                    ),
                                ],
                                projection: [
                                    .nodeIdentity,
                                    .field(
                                        dateField.alias
                                    ),
                                ],
                                limit: 20
                            ),
                        resultContract:
                            .compiledCollection,
                        compilationReferenceDate:
                            referenceDate
                    )
                )
        case .collection:
            payload =
                .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity: entity,
                        projectedFields: []
                    )
                )
            cardinality = .zeroOrMore
            limits =
                GraphChatTypedIntentLimits(
                    resultLimit: 20,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 20,
                    maximumArtifactCount: 1
                )
            action =
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    entity.alias,
                                scope: chat,
                                sorting: [
                                    GraphQuerySort(
                                        key:
                                            .nodeName,
                                        direction:
                                            .ascending
                                    ),
                                ],
                                projection:
                                    [.nodeIdentity],
                                limit: 20
                            ),
                        resultContract:
                            .entityCollection
                    )
                )
        case .count:
            payload =
                .countOrGroup(
                    GraphChatTypedCountOrGroupIntent(
                        entity: entity,
                        operation: .count
                    )
                )
            cardinality = .exactlyOne
            limits =
                GraphChatTypedIntentLimits(
                    resultLimit: 200,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 512,
                    maximumArtifactCount: 1
                )
            action =
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    entity.alias,
                                scope: chat,
                                sorting: [],
                                projection:
                                    [.nodeIdentity],
                                aggregation:
                                    .count,
                                limit: 200
                            ),
                        resultContract: .count
                    )
                )
        }
        let intent =
            try GraphChatTypedIntent(
                version: .v1,
                scope:
                    GraphChatTypedIntentScope(
                        graphScope: scope,
                        chatScope: chat,
                        queryScope: chat
                    ),
                responseLanguage: .german,
                binding: domainBinding,
                resolution: resolution,
                expectedCardinality:
                    cardinality,
                factExpectation: .none,
                limits: limits,
                payload: payload
            )
        return mapping(
            name,
            intent: intent,
            action: action
        )
    }

    private func findNodes()
        throws -> ComposableReadPlanMapping
    {
        let intent = try makeIntent(
            payload:
                .findNodes(
                    GraphChatTypedFindNodesIntent(
                        entity: firstEntity,
                        fields: [],
                        nodeScope: []
                    )
                ),
            cardinality: .zeroOrMore,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 20,
                    maximumResultLimit: 50,
                    maximumEvidenceCount: 20,
                    maximumArtifactCount: 1
                )
        )
        let action =
            GraphChatLocalIntentAction.searchGraph(
                GraphChatLocalSearchAction(
                    query: "Atlas",
                    limit: 20,
                    scope: chatScope,
                    target: .entityNodes,
                    entityID: firstEntity.id
                )
            )
        return mapping(
            "Find Nodes",
            intent: intent,
            action: action
        )
    }

    private func count()
        throws -> ComposableReadPlanMapping
    {
        let intent = try makeIntent(
            payload:
                .countOrGroup(
                    GraphChatTypedCountOrGroupIntent(
                        entity: firstEntity,
                        operation: .count
                    )
                ),
            cardinality: .exactlyOne,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 200,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 512,
                    maximumArtifactCount: 1
                )
        )
        let action =
            queryAction(
                aggregation: .count,
                contract: .count,
                projection: [.nodeIdentity],
                limit: 200
            )
        return mapping(
            "Count",
            intent: intent,
            action: action
        )
    }

    fileprivate func groupCount()
        throws -> ComposableReadPlanMapping
    {
        let intent = try makeIntent(
            payload:
                .countOrGroup(
                    GraphChatTypedCountOrGroupIntent(
                        entity: firstEntity,
                        operation:
                            .group(
                                field:
                                    statusField
                            )
                    )
                ),
            cardinality: .zeroOrMore,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 200,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 512,
                    maximumArtifactCount: 1
                )
        )
        let action =
            queryAction(
                aggregation:
                    .groupCount(
                        statusField.alias
                    ),
                contract: .groupCount,
                projection: [.nodeIdentity],
                limit: 200
            )
        return mapping(
            "Group Count",
            intent: intent,
            action: action
        )
    }

    private func refinement()
        throws -> ComposableReadPlanMapping
    {
        let resultID = UUID(
            uuidString:
                "51000000-0000-0000-0000-000000000020"
        )!
        let sourceTurnID = UUID(
            uuidString:
                "51000000-0000-0000-0000-000000000021"
        )!
        let nodes = [
            firstNode,
            secondNode,
        ]
        let scope =
            try GraphChatScope.selection(
                nodes.map(\.node),
                in: graphScope
            )
        let reference =
            GraphChatResolvedConversationReference(
                kind: .resultSet,
                alias: "CURRENT",
                nodes: nodes.map(\.node),
                entityID:
                    firstEntity.id,
                fieldID: nil,
                groupID: nil,
                label: "Projekte"
            )
        let resolved =
            GraphChatResolvedConversationScope(
                graphScope: graphScope,
                chatScope: chatScope,
                conversationID:
                    conversationID,
                entityID: firstEntity.id,
                nodes: nodes.map(\.node),
                origin: .latestResults,
                revision:
                    GraphChatResolvedConversationScopeRevision(
                        sourceAlias: "CURRENT",
                        sourceResultID:
                            resultID,
                        sourceTurnID:
                            sourceTurnID,
                        sourceTurnCompletedAt:
                            referenceDate,
                        sourceReferenceCount:
                            nodes.count,
                        validatedQueryPlan: nil
                    ),
                reference: reference
            )
        let refinementBinding =
            GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID:
                    conversationID,
                turnID: requestID,
                sourceTurnID:
                    sourceTurnID,
                clarificationID: nil
            )
        let intent =
            try GraphChatTypedIntent(
                version: .v1,
                scope:
                    GraphChatTypedIntentScope(
                        graphScope: graphScope,
                        chatScope: chatScope,
                        queryScope: scope
                    ),
                responseLanguage: .german,
                binding:
                    refinementBinding,
                resolution: resolution,
                expectedCardinality:
                    .zeroOrMore,
                factExpectation: .none,
                limits:
                    GraphChatTypedIntentLimits(
                        resultLimit: 2,
                        maximumResultLimit: 200,
                        maximumEvidenceCount: 64,
                        maximumArtifactCount: 1
                    ),
                payload:
                    .narrowResultSet(
                        GraphChatTypedNarrowResultSetIntent(
                            sourceResultContextID:
                                resultID,
                            entity: firstEntity,
                            nodes: nodes,
                            fields: [textField],
                            projectedFields:
                                [textField]
                        )
                    )
            )
        let action =
            GraphChatLocalIntentAction
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    firstEntity.alias,
                                scope: scope,
                                filters: [
                                    GraphQueryFilter(
                                        fieldAlias:
                                            textField.alias,
                                        operation:
                                            .contains,
                                        value:
                                            .text(
                                                "Atlas"
                                            )
                                    ),
                                ],
                                sorting: [
                                    GraphQuerySort(
                                        key:
                                            .nodeName,
                                        direction:
                                            .ascending
                                    ),
                                ],
                                projection: [
                                    .nodeIdentity,
                                    .field(
                                        textField.alias
                                    ),
                                ],
                                limit: 2
                            ),
                        resultContract:
                            .refinement,
                        refinementSource:
                            resolved,
                        compilationReferenceDate:
                            referenceDate
                    )
                )
        return mapping(
            "Refinement",
            intent: intent,
            action: action
        )
    }

    private func authoritativeNodeField()
        throws -> ComposableReadPlanMapping
    {
        let scope =
            GraphChatScope.node(
                firstNode.node,
                in: graphScope
            )
        let intent = try makeIntent(
            queryScope: scope,
            payload:
                .nodeDetails(
                    GraphChatTypedNodeDetailsIntent(
                        entity: firstEntity,
                        node: firstNode,
                        fields: [textField]
                    )
                ),
            cardinality: .zeroOrOne,
            factExpectation:
                .authoritativeSingleField,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 1,
                    maximumResultLimit: 200,
                    maximumEvidenceCount: 2,
                    maximumArtifactCount: 1
                )
        )
        let action =
            GraphChatLocalIntentAction
                .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan:
                            GraphQueryPlan(
                                entityAlias:
                                    firstEntity.alias,
                                scope: scope,
                                sorting: [
                                    GraphQuerySort(
                                        key:
                                            .nodeName,
                                        direction:
                                            .ascending
                                    ),
                                ],
                                projection: [
                                    .nodeIdentity,
                                    .field(
                                        textField.alias
                                    ),
                                ],
                                limit: 1
                            ),
                        resultContract:
                            .authoritativeSingleField(
                                node: firstNode,
                                field: textField
                            )
                    )
                )
        return mapping(
            "Node Details Field",
            intent: intent,
            action: action
        )
    }

    private func nodeProfile()
        throws -> ComposableReadPlanMapping
    {
        let scope =
            GraphChatScope.node(
                firstNode.node,
                in: graphScope
            )
        let intent = try makeIntent(
            queryScope: scope,
            payload:
                .nodeDetails(
                    GraphChatTypedNodeDetailsIntent(
                        entity: firstEntity,
                        node: firstNode,
                        fields: []
                    )
                ),
            cardinality: .zeroOrOne,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 1,
                    maximumResultLimit: 8,
                    maximumEvidenceCount: 96,
                    maximumArtifactCount: 4
                )
        )
        let action =
            GraphChatLocalIntentAction
                .nodeDetails(
                    GraphChatLocalNodeDetailsAction(
                        node: firstNode,
                        relatedLimit:
                            GraphChatAdvancedIntentPolicy
                                .default
                                .nodeDetailRelatedLimit
                    )
                )
        return mapping(
            "Node Details Profile",
            intent: intent,
            action: action
        )
    }

    private func comparison()
        throws -> ComposableReadPlanMapping
    {
        let nodes = [
            firstNode,
            personNode,
        ]
        let scope =
            try GraphChatScope.selection(
                nodes.map(\.node),
                in: graphScope
            )
        let plan =
            try GraphChatComparisonPlan(
                graphScope: graphScope,
                chatScope: chatScope,
                binding: binding,
                nodes: nodes,
                kind: .structural,
                features: [
                    .structure(.nodeKind),
                    .structure(
                        .directLinkCount
                    ),
                ],
                selectionQuery: nil,
                relatedLimit:
                    GraphChatAdvancedIntentPolicy
                        .default
                        .structuralRelatedLimit,
                responseLanguage: .german
            )
        let intent = try makeIntent(
            queryScope: scope,
            payload:
                .compareNodes(
                    GraphChatTypedCompareNodesIntent(
                        entities: [
                            firstEntity,
                            secondEntity,
                        ],
                        nodes: nodes,
                        fields: []
                    )
                ),
            cardinality: .twoOrMore,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: 2,
                    maximumResultLimit: 8,
                    maximumEvidenceCount: 96,
                    maximumArtifactCount: 4
                )
        )
        let action =
            GraphChatLocalIntentAction
                .compareNodes(plan)
        return mapping(
            "Compare Nodes",
            intent: intent,
            action: action
        )
    }

    private func graphState()
        throws -> ComposableReadPlanMapping
    {
        let action =
            GraphChatLocalIntentAction
                .inspectGraphState(
                    GraphChatLocalGraphStateAction(
                        aspect: .health,
                        hubLimit:
                            GraphChatIntentLimitPolicy
                                .default
                                .graphHubCount
                    )
                )
        let intent = try makeIntent(
            payload:
                .inspectGraphState(
                    GraphChatTypedInspectGraphStateIntent(
                        aspect: .health
                    )
                ),
            cardinality: .exactlyOne,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit:
                        GraphChatIntentLimitPolicy
                            .default
                            .graphHubCount,
                    maximumResultLimit:
                        GraphChatIntentLimitPolicy
                            .default
                            .graphHubCount,
                    maximumEvidenceCount: 96,
                    maximumArtifactCount: 4
                )
        )
        return mapping(
            "Inspect Graph State",
            intent: intent,
            action: action
        )
    }

    private func queryAction(
        aggregation: GraphQueryAggregation,
        contract:
            GraphChatLocalQueryResultContract,
        projection: [GraphQueryProjection],
        limit: Int
    ) -> GraphChatLocalIntentAction {
        .queryDetailValues(
            GraphChatLocalQueryAction(
                plan:
                    GraphQueryPlan(
                        entityAlias:
                            firstEntity.alias,
                        scope: chatScope,
                        sorting: [],
                        projection:
                            projection,
                        aggregation:
                            aggregation,
                        limit: limit
                    ),
                resultContract: contract
            )
        )
    }

    private func makeIntent(
        queryScope: GraphChatScope? = nil,
        payload: GraphChatTypedIntentPayload,
        cardinality:
            GraphChatTypedIntentExpectedCardinality,
        factExpectation:
            GraphChatTypedIntentFactExpectation = .none,
        limits: GraphChatTypedIntentLimits
    ) throws -> GraphChatTypedIntent {
        try GraphChatTypedIntent(
            version: .v1,
            scope:
                GraphChatTypedIntentScope(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    queryScope:
                        queryScope
                        ?? chatScope
                ),
            responseLanguage: .german,
            binding: binding,
            resolution: resolution,
            expectedCardinality:
                cardinality,
            factExpectation:
                factExpectation,
            limits: limits,
            payload: payload
        )
    }

    private func mapping(
        _ name: String,
        intent: GraphChatTypedIntent,
        action: GraphChatLocalIntentAction
    ) -> ComposableReadPlanMapping {
        ComposableReadPlanMapping(
            name: name,
            adaptation:
                GraphChatTypedIntentAdaptation(
                    intent: intent,
                    action: action
                ),
            action: action
        )
    }

    private func typedEntity(
        alias: GraphEntityAlias
    ) -> GraphChatTypedEntityIdentity {
        let resolution = schemaContext
            .foundationalAliases
            .entity(for: alias)!
        return GraphChatTypedEntityIdentity(
            id: resolution.entityID,
            alias: resolution.alias,
            displayName: resolution.name
        )
    }

    private func typedField(
        alias: GraphFieldAlias
    ) -> GraphChatTypedFieldIdentity {
        let resolution = schemaContext
            .foundationalAliases
            .field(for: alias)!
        return GraphChatTypedFieldIdentity(
            id: resolution.fieldID,
            alias: resolution.alias,
            displayName: resolution.name,
            ownerEntityID:
                resolution.entityID,
            type: resolution.type,
            unit: resolution.unit
        )
    }
}

private func sequentialOperations(
    _ payloads:
        [GraphChatComposableReadOperationPayload]
) -> [GraphChatComposableReadOperation] {
    payloads.enumerated().map {
        index,
        payload in
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
            payload: payload
        )
    }
}

private extension GraphChatComposableReadOperation {
    func replacingPayload(
        _ payload:
            GraphChatComposableReadOperationPayload
    ) -> GraphChatComposableReadOperation {
        GraphChatComposableReadOperation(
            id: id,
            input: input,
            payload: payload
        )
    }
}

private extension GraphChatComposableReadPlan {
    func replacingQueryPlanVersion(
        _ queryPlanVersion: Int
    ) -> GraphChatComposableReadPlan {
        copy(
            graphScope: graphScope,
            operations: operations,
            artifactContract:
                artifactContract,
            limits: limits,
            queryPlanVersion:
                queryPlanVersion
        )
    }

    func replacingOperations(
        _ operations:
            [GraphChatComposableReadOperation]
    ) -> GraphChatComposableReadPlan {
        copy(
            graphScope: graphScope,
            operations: operations,
            artifactContract:
                artifactContract,
            limits: limits,
            queryPlanVersion: nil
        )
    }

    func replacingGraphScope(
        _ graphScope: GraphScope
    ) -> GraphChatComposableReadPlan {
        copy(
            graphScope: graphScope,
            operations: operations,
            artifactContract:
                artifactContract,
            limits: limits,
            queryPlanVersion: nil
        )
    }

    func replacingArtifactContract(
        _ artifactContract:
            GraphChatComposableReadArtifactContract
    ) -> GraphChatComposableReadPlan {
        copy(
            graphScope: graphScope,
            operations: operations,
            artifactContract:
                artifactContract,
            limits: limits,
            queryPlanVersion: nil
        )
    }

    func replacingLimits(
        _ limits:
            GraphChatComposableReadLimits
    ) -> GraphChatComposableReadPlan {
        copy(
            graphScope: graphScope,
            operations: operations.map {
                operation in
                guard case .limit =
                        operation.payload
                else {
                    return operation
                }
                return operation.replacingPayload(
                    .limit(
                        GraphChatComposableReadLimit(
                            resultLimit:
                                limits.resultLimit,
                            intermediateResultLimit:
                                limits
                                    .intermediateResultLimit
                        )
                    )
                )
            },
            artifactContract:
                artifactContract,
            limits: limits,
            queryPlanVersion: nil
        )
    }

    private func copy(
        graphScope: GraphScope,
        operations:
            [GraphChatComposableReadOperation],
        artifactContract:
            GraphChatComposableReadArtifactContract,
        limits: GraphChatComposableReadLimits,
        queryPlanVersion:
            Int?
    ) -> GraphChatComposableReadPlan {
        GraphChatComposableReadPlan(
            version: version,
            queryPlanVersion:
                queryPlanVersion
                ?? self.queryPlanVersion,
            graphScope: graphScope,
            chatScope: chatScope,
            queryScope: queryScope,
            compiledScope: compiledScope,
            binding: binding,
            responseLanguage:
                responseLanguage,
            intentKind: intentKind,
            operations: operations,
            resultContract:
                resultContract,
            evidenceRequirements:
                evidenceRequirements,
            artifactContract:
                artifactContract,
            limits: limits,
            queryReferenceDate:
                queryReferenceDate
        )
    }
}
