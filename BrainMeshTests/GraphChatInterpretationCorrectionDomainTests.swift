//
//  GraphChatInterpretationCorrectionDomainTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat interpretation correction domain")
struct GraphChatInterpretationCorrectionDomainTests {
    @Test
    func legacyInterpretationWithoutTrustedOriginIsNotEditable()
        throws
    {
        let interpretation =
            try GraphChatIntentInterpretationTestFixture()
                .filteredCollection(language: .german)

        #expect(interpretation.correctionOrigin == nil)
        #expect(interpretation.isCorrectionEditable == false)
    }

    @Test
    func capabilitiesAreStrictlyIntentSpecific()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()

        let find = GraphChatInterpretationCorrectionCapabilities
            .derive(
                from:
                    try fixture.findInterpretation(
                        language: .german
                    )
            )
        #expect(
            find.components == [
                .searchTerm,
                .findTarget,
                .entity,
                .resultAmount,
            ]
        )

        let filtered =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.filteredCollection(
                            language: .german
                        )
                )
        #expect(
            filtered.components == [
                .entity,
                .filters,
                .sorting,
                .resultAmount,
            ]
        )

        let count =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.countInterpretation(
                            language: .german
                        )
                )
        #expect(
            count.components == [
                .entity,
                .filters,
            ]
        )

        let group =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.groupInterpretation(
                            language: .german
                        )
                )
        #expect(
            group.components == [
                .entity,
                .filters,
                .groupingField,
            ]
        )

        let details =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.singleFactInterpretation(
                            language: .german
                        )
                )
        #expect(details.components == [.nodes, .fields])
        #expect(
            details.nodeSelectionLimit
                == GraphChatInterpretationCorrectionSelectionLimit(
                    minimum: 1,
                    maximum: 1
                )
        )

        let refinement =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.refinementInterpretation(
                            language: .german
                        )
                )
        #expect(refinement.components == [.filters, .sorting])

        let comparison =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.comparisonInterpretation(
                            language: .german
                        )
                )
        #expect(comparison.components == [.nodes, .fields])
        #expect(
            comparison.nodeSelectionLimit?
                .contains(1) == false
        )
        #expect(
            comparison.nodeSelectionLimit?
                .contains(2) == true
        )

        let graphState =
            GraphChatInterpretationCorrectionCapabilities
                .derive(
                    from:
                        try fixture.graphStateInterpretation(
                            language: .german
                        )
                )
        #expect(
            graphState.components == [.graphStateAspect]
        )
    }

    @Test
    func pureAndFilteredListsExposeOnlyTheirApplicableControls()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let pure = try fixture.entityCollectionTurn(
            includesFilterAndSort: false
        )
        let filtered =
            try fixture.entityCollectionTurn()

        #expect(
            pure.request.capabilities.components
                == [
                    .entity,
                    .resultAmount,
                ]
        )
        #expect(
            filtered.request.capabilities
                .components
                == [
                    .entity,
                    .filters,
                    .sorting,
                    .resultAmount,
                ]
        )
        #expect(
            pure.request.selection.filters
                .isEmpty
        )
        #expect(
            pure.request.selection.sorting
                .isEmpty
        )
        #expect(
            filtered.request.selection.filters
                .isEmpty == false
        )
        #expect(
            filtered.request.selection.sorting
                .isEmpty == false
        )
    }

    @Test
    func foundationalSnapshotUpdatesFieldsAfterEntityChange()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let context = fixture.promptLimitedContext()
        let snapshot =
            GraphChatInterpretationCorrectionSchemaBuilder()
                .makeSnapshot(
                    context: context,
                    chatScope:
                        .entireGraph(context.graphScope),
                    language: .german
                )

        #expect(snapshot.state == .ready)
        #expect(
            Set(snapshot.entities.map(\.id))
                == [
                    GraphChatTestSupport.projectEntityID,
                    GraphChatTestSupport.personEntityID,
                ]
        )

        let projectFields = snapshot.fields(
            for: GraphChatTestSupport.projectEntityID
        )
        let personFields = snapshot.fields(
            for: GraphChatTestSupport.personEntityID
        )

        #expect(projectFields.count == 7)
        #expect(personFields.count == 1)
        #expect(
            Set(projectFields.map(\.id))
                .isDisjoint(
                    with: Set(personFields.map(\.id))
                )
        )
        #expect(
            projectFields
                .first(where: {
                    $0.displayName == "Status"
                })?
                .choiceOptions
                .map(\.displayName)
                == [
                    "Offen",
                    "In Arbeit",
                    "Fertig",
                ]
        )
    }

    @Test
    func snapshotExposesOnlyCompatibleLocalizedFilterEditors()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let snapshot = fixture.graphSnapshot()

        let choice = try #require(
            fixture.field(
                alias: "F7",
                in: snapshot
            )
        )
        #expect(
            choice.operators.first(where: {
                $0.operation == .equals
            })?.valueEditor == .singleChoice
        )
        #expect(
            choice.operators.first(where: {
                $0.operation == .oneOf
            })?.valueEditor == .multipleChoice
        )
        #expect(
            choice.operators.contains {
                $0.operation == .contains
            } == false
        )

        let toggle = try #require(
            fixture.field(
                alias: "F6",
                in: snapshot
            )
        )
        #expect(
            toggle.operators.first(where: {
                $0.operation == .equals
            })?.valueEditor == .toggle
        )

        let number = try #require(
            fixture.field(
                alias: "F4",
                in: snapshot
            )
        )
        #expect(
            number.operators.first(where: {
                $0.operation == .greaterThan
            })?.valueEditor == .decimal
        )
        #expect(
            number.operators.first(where: {
                $0.operation == .between
            })?.valueEditor == .decimalRange
        )

        let date = try #require(
            fixture.field(
                alias: "F5",
                in: snapshot
            )
        )
        #expect(
            date.operators.first(where: {
                $0.operation == .before
            })?.valueEditor == .date
        )
        #expect(
            date.operators.first(where: {
                $0.operation == .between
            })?.valueEditor == .dateRange
        )

        for field in snapshot.entities.flatMap(\.fields) {
            for option in field.operators {
                #expect(
                    option.displayName
                        != option.operation.rawValue
                )
            }
        }
    }

    @Test
    func crossGraphAndUnauthorizedEntitySelectionsAreRejected()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let context = fixture.context
        let foreignScope = GraphScope(
            graphID: GraphChatTestSupport.otherGraphID
        )
        let crossGraph =
            GraphChatInterpretationCorrectionSchemaBuilder()
                .makeSnapshot(
                    context: context,
                    chatScope: .entireGraph(foreignScope),
                    language: .german
                )
        #expect(
            crossGraph.state == .stale(.graphChanged)
        )

        let turn = try fixture.entityCollectionTurn(
            chatScope: .entity(
                GraphChatTestSupport.projectEntityID,
                in: context.graphScope
            )
        )
        var selection = turn.request.selection
        selection.entityID =
            GraphChatTestSupport.personEntityID
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .invalid(.missingEntity)
        )
    }

    @Test
    func entityCanChangeWithinEntireGraphScopeAndIsRecompiled()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.entityCollectionTurn()
        var selection = turn.request.selection
        selection.entityID =
            GraphChatTestSupport.personEntityID
        selection.fields = []
        selection.filters = []
        selection.sorting = []
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: request,
            providerPlan:
                fixture.providerPlan(
                    chatScope:
                        turn.request.binding
                            .chatScope
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .entityCollection(let corrected) =
                compilation.adaptation.intent.payload,
            case .queryDetailValues(let action) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected a locally recompiled entity collection."
            )
            return
        }

        #expect(
            corrected.entity.id
                == GraphChatTestSupport
                    .personEntityID
        )
        #expect(
            action.plan.entityAlias
                == GraphEntityAlias("E2")
        )
        #expect(corrected.projectedFields.isEmpty)
        #expect(action.plan.filters.isEmpty)
        #expect(
            action.plan.sorting == [
                GraphQuerySort(
                    key: .nodeName,
                    direction: .ascending
                ),
            ]
        )
    }

    @Test
    func entityCanChangeWithinAMixedSelectionWithoutExpandingIt()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let projectNode = NodeRefKey(
            kind: .attribute,
            id:
                GraphChatTestSupport
                    .projectAttributeID
        )
        let personNode = NodeRefKey(
            kind: .attribute,
            id:
                GraphChatTestSupport
                    .personAttributeID
        )
        let chatScope =
            try GraphChatScope.selection(
                [
                    projectNode,
                    personNode,
                ],
                in: fixture.context.graphScope
            )
        let turn =
            try fixture.entityCollectionTurn(
                chatScope: chatScope,
                queryScope:
                    .node(
                        projectNode,
                        in:
                            fixture.context
                                .graphScope
                    )
            )
        var selection = turn.request.selection
        selection.entityID =
            GraphChatTestSupport
                .personEntityID
        selection.fields = []
        selection.filters = []
        selection.sorting = []
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: request,
            providerPlan:
                fixture.providerPlan(
                    chatScope: chatScope
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .queryDetailValues(let action) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected a locally recompiled selection-scoped query."
            )
            return
        }
        #expect(
            action.plan.scope
                == .node(
                    personNode,
                    in:
                        fixture.context
                            .graphScope
                )
        )
    }

    @Test
    func staleArtifactSessionCannotAuthorizeCorrection()
        throws
    {
        let turn = try CorrectionDomainFixture()
            .entityCollectionTurn()

        #expect(
            turn.snapshot.validationState(
                for: turn.request,
                currentArtifactSessionID:
                    GraphChatAnswerArtifactSessionID(),
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .stale(.artifactSessionChanged)
        )
    }

    @Test
    func choiceToggleLocalizedNumberAndDateValuesValidate()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.entityCollectionTurn()
        var selection = turn.request.selection
        selection.filters = [
            GraphChatInterpretationCorrectionFilter(
                fieldID:
                    fixture.fieldID(alias: "F7"),
                operation: .equals,
                value: .choice("Offen")
            ),
            GraphChatInterpretationCorrectionFilter(
                fieldID:
                    fixture.fieldID(alias: "F6"),
                operation: .equals,
                value: .toggle(true)
            ),
            GraphChatInterpretationCorrectionFilter(
                fieldID:
                    fixture.fieldID(alias: "F4"),
                operation: .greaterThan,
                value: .decimalInput("1250,5")
            ),
            GraphChatInterpretationCorrectionFilter(
                fieldID:
                    fixture.fieldID(alias: "F5"),
                operation: .before,
                value: .date(
                    Date(
                        timeIntervalSince1970:
                            1_800_000_000
                    )
                )
            ),
        ]
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )
    }

    @Test
    func localizedIntegerEditorRejectsFractionalInput()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.entityCollectionTurn()
        var selection = turn.request.selection
        selection.filters = [
            GraphChatInterpretationCorrectionFilter(
                fieldID:
                    fixture.fieldID(alias: "F3"),
                operation: .equals,
                value:
                    .integerInput("1,5")
            ),
        ]
        let fractional =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: fractional,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .invalid(.invalidFilter)
        )

        selection.filters[0].value =
            .integerInput("1.500")
        let whole =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )
        #expect(
            turn.snapshot.validationState(
                for: whole,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )
    }

    @Test
    func incompatibleOperatorIsRejectedByCorrectionCompiler()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.entityCollectionTurn()
        var selection = turn.request.selection
        selection.filters = [
            GraphChatInterpretationCorrectionFilter(
                fieldID:
                    fixture.fieldID(alias: "F7"),
                operation: .contains,
                value: .text("Offen")
            ),
        ]
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            throws:
                GraphChatInterpretationCorrectionCompilationError
                    .invalid(.invalidFilter)
        ) {
            try fixture.compiler.compile(
                request: request,
                providerPlan:
                    fixture.providerPlan(
                        chatScope:
                            turn.request.binding.chatScope
                    ),
                schemaContext: fixture.context,
                requestID: UUID(),
                requestedAt: fixture.referenceDate
            )
        }
    }

    @Test
    func refinementCannotExpandItsOriginalNodeSet()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.refinementTurn()
        var selection = turn.request.selection
        selection.nodes.append(fixture.thirdProjectNode)
        let craftedRequest =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: craftedRequest,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .invalid(.scopeExpansion)
        )
        #expect(
            throws:
                GraphChatInterpretationCorrectionCompilationError
                    .invalid(.scopeExpansion)
        ) {
            try fixture.compiler.compile(
                request: craftedRequest,
                providerPlan:
                    fixture.providerPlan(
                        chatScope:
                            turn.request.binding.chatScope
                    ),
                schemaContext: fixture.context,
                requestID: UUID(),
                requestedAt: fixture.referenceDate
            )
        }
    }

    @Test
    func groupFieldCorrectionIsRecompiledThroughTheQueryCompiler()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.groupTurn()
        let dueDateID =
            fixture.fieldID(alias: "F5")
        var selection = turn.request.selection
        selection.groupingFieldID =
            dueDateID
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: request,
            providerPlan:
                fixture.providerPlan(
                    chatScope:
                        turn.request.binding
                            .chatScope
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .countOrGroup(let corrected) =
                compilation.adaptation.intent.payload,
            case .group(let field) =
                corrected.operation,
            case .queryDetailValues(let action) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected a locally recompiled grouping."
            )
            return
        }

        #expect(field.id == dueDateID)
        #expect(
            action.plan.aggregation
                == .groupCount(
                    GraphFieldAlias("F5")
                )
        )
    }

    @Test
    func nodeDetailsCanMoveToAnotherAuthorizedNode()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.nodeDetailsTurn()
        var selection = turn.request.selection
        selection.nodes = [
            fixture.personNode,
        ]
        selection.entityID =
            GraphChatTestSupport.personEntityID
        selection.fields = [
            fixture.fieldID(alias: "F8"),
        ]
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.fields(
                for: selection.entityID
            ).map(\.id) == selection.fields
        )
        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: request,
            providerPlan:
                fixture.providerPlan(
                    chatScope:
                        turn.request.binding
                            .chatScope
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .nodeDetails(let corrected) =
                compilation.adaptation.intent.payload,
            case .nodeDetails(let action) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected locally recompiled node details."
            )
            return
        }

        #expect(
            corrected.node.node
                == fixture.personNode
        )
        #expect(
            action.node.node
                == fixture.personNode
        )
        #expect(
            corrected.entity.id
                == GraphChatTestSupport
                    .personEntityID
        )
        #expect(
            corrected.fields.map(\.id)
                == [
                    fixture.fieldID(
                        alias: "F8"
                    ),
                ]
        )
    }

    @Test
    func comparisonSelectionIsRevalidatedAgainstCurrentNodesAndFields()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.comparisonTurn()
        var selection = turn.request.selection
        selection.nodes = [
            fixture.secondProjectNode,
            fixture.thirdProjectNode,
        ]
        selection.fields = [
            fixture.fieldID(alias: "F7"),
            fixture.fieldID(alias: "F5"),
        ]
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            turn.snapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: request,
            providerPlan:
                fixture.providerPlan(
                    chatScope:
                        turn.request.binding
                            .chatScope
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .compareNodes(let corrected) =
                compilation.adaptation.intent.payload,
            case .compareNodes(let plan) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected a locally recompiled comparison."
            )
            return
        }

        #expect(
            corrected.nodes.map(\.node)
                == selection.nodes
        )
        #expect(
            Set(corrected.fields.map(\.id))
                == Set(selection.fields)
        )
        #expect(
            plan.nodes.map(\.node)
                == selection.nodes
        )

        let deletedNode = NodeRefKey(
            kind: .attribute,
            id: UUID(
                uuidString:
                    "CA110000-0000-0000-0000-000000000199"
            )!
        )
        selection.nodes[1] = deletedNode
        let staleRequest =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )
        #expect(
            throws:
                GraphChatInterpretationCorrectionCompilationError
                    .stale(.nodeUnavailable)
        ) {
            try fixture.compiler.compile(
                request: staleRequest,
                providerPlan:
                    fixture.providerPlan(
                        chatScope:
                            turn.request.binding
                                .chatScope
                    ),
                schemaContext: fixture.context,
                requestID: UUID(),
                requestedAt:
                    fixture.referenceDate
            )
        }
    }

    @Test
    func equallyNamedComparisonNodesRemainBoundByTheirSelectedIDs()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.comparisonTurn()
        let duplicateNameContext =
            fixture.contextWithDuplicateProjectNodeNames()
        let freshSnapshot =
            GraphChatInterpretationCorrectionSchemaBuilder()
                .makeSnapshot(
                    context:
                        duplicateNameContext,
                    chatScope:
                        turn.request.binding
                            .chatScope,
                    language: .german
                )
        var selection = turn.request.selection
        selection.nodes = [
            fixture.secondProjectNode,
            fixture.thirdProjectNode,
        ]
        selection.fields = [
            fixture.fieldID(alias: "F7"),
            fixture.fieldID(alias: "F5"),
        ]
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )

        #expect(
            freshSnapshot.validationState(
                for: request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: request,
            providerPlan:
                fixture.providerPlan(
                    chatScope:
                        turn.request.binding
                            .chatScope
                ),
            schemaContext:
                duplicateNameContext,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .compareNodes(let corrected) =
                compilation.adaptation.intent.payload
        else {
            Issue.record(
                "Expected an ID-bound comparison."
            )
            return
        }

        #expect(
            corrected.nodes.map(\.node)
                == selection.nodes
        )
        #expect(
            corrected.nodes.map(\.displayName)
                == [
                    "Gleichnamig",
                    "Gleichnamig",
                ]
        )
    }

    @Test
    func mixedEntityComparisonStartsWithoutAnInapplicableEntityOrFields()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let sameEntity =
            try fixture.comparisonTurn()
        var missingFields =
            sameEntity.request.selection
        missingFields.fields = []
        let invalidSameEntityRequest =
            GraphChatInterpretationCorrectionRequest(
                binding:
                    sameEntity.request.binding,
                selection: missingFields
            )
        #expect(
            sameEntity.snapshot.validationState(
                for: invalidSameEntityRequest,
                currentArtifactSessionID:
                    sameEntity.artifactSessionID,
                currentCheckpoint:
                    sameEntity.expectedCheckpoint,
                graphIsLocked: false
            ) == .invalid(.invalidFieldSelection)
        )

        let turn =
            try fixture
                .mixedEntityComparisonTurn()

        #expect(
            turn.request.selection.entityID
                == nil
        )
        #expect(
            turn.request.selection.fields
                .isEmpty
        )
        #expect(
            turn.snapshot.validationState(
                for: turn.request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: turn.request,
            providerPlan:
                fixture.providerPlan(
                    chatScope:
                        turn.request.binding
                            .chatScope
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .compareNodes(let plan) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected a structural mixed-entity comparison."
            )
            return
        }
        #expect(plan.kind == .structural)
        #expect(
            plan.features == [
                .structure(.nodeKind),
            ]
        )

        var inapplicableField =
            turn.request.selection
        inapplicableField.fields = [
            fixture.fieldID(alias: "F7"),
        ]
        let invalidMixedRequest =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: inapplicableField
            )
        #expect(
            turn.snapshot.validationState(
                for: invalidMixedRequest,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .invalid(.invalidFieldSelection)
        )
    }

    @Test
    func largeRefinementSourceCompilesWithoutNodeTermsOrScopeExpansion()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let sourceNodes =
            fixture.largeProjectNodes(
                count:
                    GraphChatSemanticSafety
                        .maximumNodeTerms
                    + 4
            )
        let context =
            fixture.context(
                includingProjectNodes:
                    sourceNodes
            )
        let turn = try fixture.refinementTurn(
            sourceNodes: sourceNodes,
            schemaContext: context
        )

        #expect(
            sourceNodes.count
                > GraphChatSemanticSafety
                    .maximumNodeTerms
        )
        #expect(
            turn.request.selection.nodes
                == sourceNodes
        )
        #expect(
            turn.snapshot.validationState(
                for: turn.request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let compilation = try fixture.compiler.compile(
            request: turn.request,
            providerPlan:
                fixture.refinementProviderPlan(
                    sourceNodes:
                        sourceNodes,
                    schemaContext: context
                ),
            schemaContext: context,
            requestID: UUID(),
            requestedAt: fixture.referenceDate
        )
        guard
            case .narrowResultSet(let corrected) =
                compilation.adaptation.intent.payload,
            case .queryDetailValues(let action) =
                compilation.adaptation.action
        else {
            Issue.record(
                "Expected a locally recompiled large refinement."
            )
            return
        }
        let exactScope =
            try GraphChatScope.selection(
                sourceNodes,
                in: context.graphScope
            )

        #expect(
            corrected.nodes.map(\.node)
                == sourceNodes
        )
        #expect(
            corrected.sourceResultContextID
                == fixture.sourceResultContextID
        )
        #expect(
            action.plan.scope
                == exactScope
        )
        #expect(
            Set(corrected.nodes.map(\.node))
                == Set(sourceNodes)
        )
    }

    @Test
    func graphStateInterpretationRequiresEntireGraphChat()
        throws
    {
        let fixture = CorrectionDomainFixture()

        #expect(
            try fixture.graphStateInterpretation(
                chatScope:
                    .entireGraph(
                        fixture.context.graphScope
                    )
            ) != nil
        )
        #expect(
            try fixture.graphStateInterpretation(
                chatScope:
                    .entity(
                        GraphChatTestSupport
                            .projectEntityID,
                        in: fixture.context.graphScope
                    )
            ) == nil
        )
    }

    @Test
    func findEntityIsOptionalExceptForEntityNodeSearch()
        throws
    {
        let fixture = CorrectionDomainFixture()
        let turn = try fixture.findTurn()

        #expect(turn.request.selection.entityID == nil)
        #expect(
            turn.snapshot.validationState(
                for: turn.request,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        var selection = turn.request.selection
        selection.search?.target = .entityNodes
        let entityNodeRequest =
            GraphChatInterpretationCorrectionRequest(
                binding: turn.request.binding,
                selection: selection
            )
        #expect(
            turn.snapshot.validationState(
                for: entityNodeRequest,
                currentArtifactSessionID:
                    turn.artifactSessionID,
                currentCheckpoint:
                    turn.expectedCheckpoint,
                graphIsLocked: false
            ) == .invalid(.missingEntity)
        )
    }
}

private struct CorrectionDomainBoundTurn {
    let request: GraphChatInterpretationCorrectionRequest
    let snapshot:
        GraphChatInterpretationCorrectionSchemaSnapshot
    let artifactSessionID:
        GraphChatAnswerArtifactSessionID
    let expectedCheckpoint:
        GraphChatConversationCheckpoint
}

private struct CorrectionDomainFixture {
    let referenceDate = Date(
        timeIntervalSince1970: 1_735_732_800
    )
    let conversationID = UUID(
        uuidString:
            "CA110000-0000-0000-0000-000000000001"
    )!
    let requestID = UUID(
        uuidString:
            "CA110000-0000-0000-0000-000000000002"
    )!
    let sourceTurnID = UUID(
        uuidString:
            "CA110000-0000-0000-0000-000000000003"
    )!
    let sourceResultContextID = UUID(
        uuidString:
            "CA110000-0000-0000-0000-000000000004"
    )!
    let secondProjectNode = NodeRefKey(
        kind: .attribute,
        id: UUID(
            uuidString:
                "CA110000-0000-0000-0000-000000000101"
        )!
    )
    let thirdProjectNode = NodeRefKey(
        kind: .attribute,
        id: UUID(
            uuidString:
                "CA110000-0000-0000-0000-000000000102"
        )!
    )
    let personNode = NodeRefKey(
        kind: .attribute,
        id:
            GraphChatTestSupport
                .personAttributeID
    )

    var compiler: GraphChatInterpretationCorrectionCompiler {
        GraphChatInterpretationCorrectionCompiler(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(
                identifier: "Europe/Berlin"
            )!
        )
    }

    var context: GraphSchemaContext {
        contextWithNodes()
    }

    func graphSnapshot()
        -> GraphChatInterpretationCorrectionSchemaSnapshot
    {
        GraphChatInterpretationCorrectionSchemaBuilder()
            .makeSnapshot(
                context: context,
                chatScope:
                    .entireGraph(context.graphScope),
                language: .german
            )
    }

    func contextWithDuplicateProjectNodeNames()
        -> GraphSchemaContext
    {
        replacingNodeDisplayNames(
            in: context,
            replacements: [
                secondProjectNode: "Gleichnamig",
                thirdProjectNode: "Gleichnamig",
            ]
        )
    }

    func largeProjectNodes(
        count: Int
    ) -> [NodeRefKey] {
        precondition(count > 0)
        return (0..<count).map { index in
            NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        String(
                            format:
                                "CA110000-0000-0000-0000-%012d",
                            index + 300
                        )
                )!
            )
        }
    }

    func context(
        includingProjectNodes nodes:
            [NodeRefKey]
    ) -> GraphSchemaContext {
        let base = context
        var resolutions =
            base.foundationalAliases
                .nodesByKey
        var owners =
            base.foundationalAliases
                .nodeEntityIDs
        for (index, node) in nodes.enumerated() {
            resolutions[node] =
                GraphSchemaNodeResolution(
                    node: node,
                    ownerEntityID:
                        GraphChatTestSupport
                            .projectEntityID,
                    displayName:
                        "Großes Projekt \(index + 1)"
                )
            owners[node] =
                GraphChatTestSupport
                    .projectEntityID
        }
        let complete = GraphSchemaAliasMap(
            graphScope: base.graphScope,
            entitiesByAlias:
                base.foundationalAliases
                    .entitiesByAlias,
            fieldsByAlias:
                base.foundationalAliases
                    .fieldsByAlias,
            nodeEntityIDs: owners,
            nodesByKey: resolutions
        )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: complete,
            foundationalAliases: complete
        )
    }

    func promptLimitedContext() -> GraphSchemaContext {
        let complete = context
        let projectAlias = GraphEntityAlias("E1")
        let titleAlias = GraphFieldAlias("F1")
        let promptAliases = GraphSchemaAliasMap(
            graphScope: complete.graphScope,
            entitiesByAlias: [
                projectAlias:
                    complete.foundationalAliases
                        .entitiesByAlias[projectAlias]!,
            ],
            fieldsByAlias: [
                titleAlias:
                    complete.foundationalAliases
                        .fieldsByAlias[titleAlias]!,
            ],
            nodeEntityIDs: [:],
            nodesByKey: [:]
        )
        return GraphSchemaContext(
            graphScope: complete.graphScope,
            snapshot: complete.snapshot,
            aliases: promptAliases,
            foundationalAliases:
                complete.foundationalAliases
        )
    }

    func fieldID(alias: String) -> UUID {
        context.foundationalAliases
            .fieldsByAlias[GraphFieldAlias(alias)]!
            .fieldID
    }

    func field(
        alias: String,
        in snapshot:
            GraphChatInterpretationCorrectionSchemaSnapshot
    ) -> GraphChatInterpretationCorrectionFieldOption? {
        snapshot.field(
            id: fieldID(alias: alias),
            entityID:
                GraphChatTestSupport.projectEntityID
        )
    }

    func entityCollectionTurn(
        chatScope: GraphChatScope? = nil,
        queryScope:
            GraphChatScope? = nil,
        includesFilterAndSort:
            Bool = true
    ) throws -> CorrectionDomainBoundTurn {
        let scope =
            chatScope
            ?? .entireGraph(context.graphScope)
        let effectiveQueryScope =
            queryScope ?? scope
        let entity = projectIdentity()
        let status = fieldIdentity(alias: "F7")
        let dueDate = fieldIdentity(alias: "F5")
        let intent = try makeIntent(
            chatScope: scope,
            queryScope:
                effectiveQueryScope,
            expectedCardinality: .zeroOrMore,
            payload: .entityCollection(
                GraphChatTypedEntityCollectionIntent(
                    entity: entity,
                    projectedFields: [status],
                    referencedFields:
                        includesFilterAndSort
                        ? [
                            status,
                            dueDate,
                        ]
                        : [status]
                )
            ),
            resultLimit: 50
        )
        let queryPlan = GraphQueryPlan(
            entityAlias: entity.alias,
            scope: effectiveQueryScope,
            filters:
                includesFilterAndSort
                ? [
                    GraphQueryFilter(
                        fieldAlias:
                            status.alias,
                        operation: .equals,
                        value: .choice("Offen")
                    ),
                ]
                : [],
            sorting:
                includesFilterAndSort
                ? [
                    GraphQuerySort(
                        key:
                            .field(
                                dueDate.alias
                            ),
                        direction: .ascending
                    ),
                ]
                : [],
            projection: [
                .nodeIdentity,
                .field(status.alias),
            ],
            limit: 50
        )
        let action = GraphChatLocalIntentAction
            .queryDetailValues(
                GraphChatLocalQueryAction(
                    plan: queryPlan,
                    resultContract:
                        includesFilterAndSort
                        ? .compiledCollection
                        : .entityCollection
                )
            )
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .queryInterpretation(
                intent: intent,
                plan: ValidatedGraphQueryPlan(
                    version:
                        GraphQueryPlan.currentVersion,
                    graphScope: context.graphScope,
                    entityID: entity.id,
                    scope:
                        resolvedScope(
                            effectiveQueryScope
                        ),
                    filters:
                        includesFilterAndSort
                        ? [
                            GraphValidatedQueryFilter(
                                fieldID:
                                    status.id,
                                fieldType:
                                    status.type,
                                operation:
                                    .equals,
                                value: .choice(
                                    GraphResolvedChoiceValue(
                                        originalValue:
                                            "Offen",
                                        canonicalValue:
                                            "Offen"
                                    )
                                )
                            ),
                        ]
                        : [],
                    sorting:
                        includesFilterAndSort
                        ? [
                            GraphValidatedQuerySort(
                                key:
                                    .field(
                                        dueDate.id
                                    ),
                                direction:
                                    .ascending
                            ),
                        ]
                        : [],
                    projection: [
                        .nodeIdentity,
                        .field(status.id),
                    ],
                    aggregation: nil,
                    limit: 50
                ),
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin
        )
    }

    func groupTurn()
        throws -> CorrectionDomainBoundTurn
    {
        let scope =
            GraphChatScope.entireGraph(
                context.graphScope
            )
        let entity = projectIdentity()
        let status = fieldIdentity(alias: "F7")
        let intent = try makeIntent(
            chatScope: scope,
            queryScope: scope,
            expectedCardinality: .zeroOrMore,
            payload: .countOrGroup(
                GraphChatTypedCountOrGroupIntent(
                    entity: entity,
                    operation: .group(
                        field: status
                    )
                )
            ),
            resultLimit: 50
        )
        let plan = GraphQueryPlan(
            entityAlias: entity.alias,
            scope: scope,
            projection: [.nodeIdentity],
            aggregation:
                .groupCount(status.alias),
            limit: 50
        )
        let action = GraphChatLocalIntentAction
            .queryDetailValues(
                GraphChatLocalQueryAction(
                    plan: plan,
                    resultContract: .groupCount
                )
            )
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .queryInterpretation(
                intent: intent,
                plan: ValidatedGraphQueryPlan(
                    version:
                        GraphQueryPlan.currentVersion,
                    graphScope: context.graphScope,
                    entityID: entity.id,
                    scope: .graph,
                    filters: [],
                    sorting: [],
                    projection: [.nodeIdentity],
                    aggregation:
                        .groupCount(status.id),
                    limit: 50
                ),
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin
        )
    }

    func nodeDetailsTurn()
        throws -> CorrectionDomainBoundTurn
    {
        let chatScope =
            GraphChatScope.entireGraph(
                context.graphScope
            )
        let node = typedNode(
            NodeRefKey(
                kind: .attribute,
                id:
                    GraphChatTestSupport
                        .projectAttributeID
            )
        )
        let dueDate = fieldIdentity(alias: "F5")
        let intent = try makeIntent(
            chatScope: chatScope,
            queryScope:
                .node(
                    node.node,
                    in: context.graphScope
                ),
            expectedCardinality: .zeroOrOne,
            payload: .nodeDetails(
                GraphChatTypedNodeDetailsIntent(
                    entity: projectIdentity(),
                    node: node,
                    fields: [dueDate]
                )
            ),
            resultLimit: 1
        )
        let action =
            GraphChatLocalIntentAction
                .nodeDetails(
                    GraphChatLocalNodeDetailsAction(
                        node: node,
                        relatedLimit:
                            GraphChatAdvancedIntentPolicy
                                .default
                                .nodeDetailRelatedLimit
                    )
                )
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .nodeInterpretation(
                intent: intent,
                action:
                    GraphChatLocalNodeDetailsAction(
                        node: node,
                        relatedLimit:
                            GraphChatAdvancedIntentPolicy
                                .default
                                .nodeDetailRelatedLimit
                    ),
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin
        )
    }

    func comparisonTurn()
        throws -> CorrectionDomainBoundTurn
    {
        let chatScope =
            GraphChatScope.entireGraph(
                context.graphScope
            )
        let sourceNodes = [
            NodeRefKey(
                kind: .attribute,
                id:
                    GraphChatTestSupport
                        .projectAttributeID
            ),
            secondProjectNode,
        ]
        let queryScope =
            try GraphChatScope.selection(
                sourceNodes,
                in: context.graphScope
            )
        let nodes = sourceNodes.map {
            typedNode($0)
        }
        let status = fieldIdentity(alias: "F7")
        let budget = fieldIdentity(alias: "F4")
        let entity = projectIdentity()
        let intent = try makeIntent(
            chatScope: chatScope,
            queryScope: queryScope,
            expectedCardinality: .twoOrMore,
            payload: .compareNodes(
                GraphChatTypedCompareNodesIntent(
                    entities: [entity],
                    nodes: nodes,
                    fields: [
                        status,
                        budget,
                    ]
                )
            ),
            resultLimit: nodes.count
        )
        let plan = try GraphChatComparisonPlan(
            graphScope: context.graphScope,
            chatScope: chatScope,
            binding: intent.binding,
            nodes: nodes,
            kind: .sameEntityAttributes,
            features: [
                .field(status),
                .field(budget),
            ],
            selectionQuery:
                GraphQueryPlan(
                    entityAlias: entity.alias,
                    scope: queryScope,
                    sorting: [
                        GraphQuerySort(
                            key: .nodeName,
                            direction: .ascending
                        ),
                    ],
                    projection: [
                        .nodeIdentity,
                        .field(status.alias),
                        .field(budget.alias),
                    ],
                    limit: nodes.count
                ),
            relatedLimit: 0,
            responseLanguage: .german
        )
        let action =
            GraphChatLocalIntentAction
                .compareNodes(plan)
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .comparisonInterpretation(
                intent: intent,
                plan: plan,
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin
        )
    }

    func mixedEntityComparisonTurn()
        throws -> CorrectionDomainBoundTurn
    {
        let chatScope =
            GraphChatScope.entireGraph(
                context.graphScope
            )
        let sourceNodes = [
            NodeRefKey(
                kind: .attribute,
                id:
                    GraphChatTestSupport
                        .projectAttributeID
            ),
            personNode,
        ]
        let queryScope =
            try GraphChatScope.selection(
                sourceNodes,
                in: context.graphScope
            )
        let nodes = sourceNodes.map {
            typedNode($0)
        }
        let intent = try makeIntent(
            chatScope: chatScope,
            queryScope: queryScope,
            expectedCardinality: .twoOrMore,
            payload: .compareNodes(
                GraphChatTypedCompareNodesIntent(
                    entities: [
                        projectIdentity(),
                        personIdentity(),
                    ],
                    nodes: nodes,
                    fields: []
                )
            ),
            resultLimit: nodes.count
        )
        let plan = try GraphChatComparisonPlan(
            graphScope: context.graphScope,
            chatScope: chatScope,
            binding: intent.binding,
            nodes: nodes,
            kind: .structural,
            features: [
                .structure(.nodeKind),
            ],
            selectionQuery: nil,
            relatedLimit:
                GraphChatAdvancedIntentPolicy
                    .default
                    .structuralRelatedLimit,
            responseLanguage: .german
        )
        let action =
            GraphChatLocalIntentAction
                .compareNodes(plan)
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .comparisonInterpretation(
                intent: intent,
                plan: plan,
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin
        )
    }

    func refinementTurn(
        sourceNodes:
            [NodeRefKey]? = nil,
        schemaContext:
            GraphSchemaContext? = nil
    )
        throws -> CorrectionDomainBoundTurn
    {
        let activeContext =
            schemaContext ?? context
        let chatScope =
            GraphChatScope.entireGraph(
                activeContext.graphScope
            )
        let sourceNodes =
            sourceNodes
            ?? [
                NodeRefKey(
                    kind: .attribute,
                    id:
                        GraphChatTestSupport
                            .projectAttributeID
                ),
                secondProjectNode,
            ]
        let queryScope = try GraphChatScope.selection(
            sourceNodes,
            in: activeContext.graphScope
        )
        let entity = projectIdentity()
        let dueDate = fieldIdentity(alias: "F5")
        let typedNodes = sourceNodes.map {
            typedNode(
                $0,
                in: activeContext
            )
        }
        let intent = try makeIntent(
            chatScope: chatScope,
            queryScope: queryScope,
            expectedCardinality: .zeroOrMore,
            payload: .narrowResultSet(
                GraphChatTypedNarrowResultSetIntent(
                    sourceResultContextID:
                        sourceResultContextID,
                    entity: entity,
                    nodes: typedNodes,
                    fields: [dueDate],
                    projectedFields: []
                )
            ),
            resultLimit:
                sourceNodes.count,
            sourceTurnID: sourceTurnID
        )
        let plan = GraphQueryPlan(
            entityAlias: entity.alias,
            scope: queryScope,
            filters: [
                GraphQueryFilter(
                    fieldAlias: dueDate.alias,
                    operation: .isPresent,
                    value: .none
                ),
            ],
            sorting: [
                GraphQuerySort(
                    key: .nodeName,
                    direction: .ascending
                ),
            ],
            limit: sourceNodes.count
        )
        let action = GraphChatLocalIntentAction
            .queryDetailValues(
                GraphChatLocalQueryAction(
                    plan: plan,
                    resultContract: .refinement
                )
            )
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .queryInterpretation(
                intent: intent,
                plan: ValidatedGraphQueryPlan(
                    version:
                        GraphQueryPlan.currentVersion,
                    graphScope:
                        activeContext.graphScope,
                    entityID: entity.id,
                    scope: .selection(sourceNodes),
                    filters: [
                        GraphValidatedQueryFilter(
                            fieldID: dueDate.id,
                            fieldType: dueDate.type,
                            operation: .isPresent,
                            value: .none
                        ),
                    ],
                    sorting: [
                        GraphValidatedQuerySort(
                            key: .nodeName,
                            direction: .ascending
                        ),
                    ],
                    projection: [.nodeIdentity],
                    aggregation: nil,
                    limit:
                        sourceNodes.count
                ),
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin,
            schemaContext: activeContext
        )
    }

    func findTurn()
        throws -> CorrectionDomainBoundTurn
    {
        let scope =
            GraphChatScope.entireGraph(
                context.graphScope
            )
        let intent = try makeIntent(
            chatScope: scope,
            queryScope: scope,
            expectedCardinality: .zeroOrMore,
            payload: .findNodes(
                GraphChatTypedFindNodesIntent(
                    entity: nil,
                    fields: [],
                    nodeScope: []
                )
            ),
            resultLimit: 20
        )
        let search = GraphChatLocalSearchAction(
            query: "Atlas",
            limit: 20,
            scope: scope,
            target: .anyEntry,
            entityID: nil
        )
        let action =
            GraphChatLocalIntentAction
                .searchGraph(search)
        let sessionID =
            GraphChatAnswerArtifactSessionID()
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: action
                    ),
                artifactSessionID: sessionID,
                requestQuestion: "Offene Projekte"
            )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone: TimeZone(
                    identifier: "Europe/Berlin"
                )!
            )
            .searchInterpretation(
                intent: intent,
                action: search,
                correctionOrigin: origin
            )
        )
        return try boundTurn(
            interpretation: interpretation,
            origin: origin
        )
    }

    func graphStateInterpretation(
        chatScope: GraphChatScope
    ) throws -> GraphChatIntentInterpretation? {
        let action = GraphChatLocalGraphStateAction(
            aspect: .health,
            hubLimit:
                GraphChatAdvancedIntentPolicy
                    .default.graphHubLimit
        )
        let intent = try makeIntent(
            chatScope: chatScope,
            queryScope: chatScope,
            expectedCardinality: .exactlyOne,
            payload: .inspectGraphState(
                GraphChatTypedInspectGraphStateIntent(
                    aspect: .health
                )
            ),
            resultLimit: action.hubLimit
        )
        let origin =
            GraphChatInterpretationCorrectionOrigin(
                adaptation:
                    GraphChatTypedIntentAdaptation(
                        intent: intent,
                        action: .inspectGraphState(
                            action
                        )
                    ),
                artifactSessionID:
                    GraphChatAnswerArtifactSessionID(),
                requestQuestion: "Offene Projekte"
            )
        return GraphChatIntentInterpretationBuilder(
            timeZone: TimeZone(
                identifier: "Europe/Berlin"
            )!
        )
        .graphStateInterpretation(
            intent: intent,
            action: action,
            correctionOrigin: origin
        )
    }

    func providerPlan(
        chatScope: GraphChatScope
    ) -> GraphChatProviderTurnPlan {
        let state =
            GraphChatConversationState.initial(
                graphScope: context.graphScope,
                chatScope: chatScope,
                conversationID: conversationID
            )
        return GraphChatProviderTurnPlan(
            scopeKey:
                GraphChatOrchestrationScopeKey(
                    graphScope: context.graphScope,
                    chatScope: chatScope
                ),
            normalizedQuestion:
                "Offene Projekte",
            providerQuestion:
                "Offene Projekte",
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

    func refinementProviderPlan(
        sourceNodes:
            [NodeRefKey],
        schemaContext:
            GraphSchemaContext
    ) -> GraphChatProviderTurnPlan {
        let chatScope =
            GraphChatScope.entireGraph(
                schemaContext.graphScope
            )
        let completedAt =
            referenceDate.addingTimeInterval(
                -60
            )
        let dueDate =
            schemaContext.foundationalAliases
                .fieldsByAlias[
                    GraphFieldAlias("F5")
                ]!
        let validatedPlan =
            ValidatedGraphQueryPlan(
                version:
                    GraphQueryPlan.currentVersion,
                graphScope:
                    schemaContext.graphScope,
                entityID:
                    GraphChatTestSupport
                        .projectEntityID,
                scope:
                    .selection(sourceNodes),
                filters: [
                    GraphValidatedQueryFilter(
                        fieldID:
                            dueDate.fieldID,
                        fieldType:
                            dueDate.type,
                        operation:
                            .isPresent,
                        value: .none
                    ),
                ],
                sorting: [
                    GraphValidatedQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    ),
                ],
                projection: [.nodeIdentity],
                aggregation: nil,
                limit: sourceNodes.count
            )
        var state =
            GraphChatConversationState.initial(
                graphScope:
                    schemaContext.graphScope,
                chatScope: chatScope,
                conversationID: conversationID
            )
        state.entityReferences = [
            GraphChatConversationEntityReference(
                entityID:
                    GraphChatTestSupport
                        .projectEntityID,
                name: "Projekte",
                alias:
                    GraphEntityAlias("E1")
            ),
        ]
        state.nodeReferences =
            sourceNodes.enumerated().map {
                index, node in
                GraphChatConversationNodeReference(
                    node: node,
                    label:
                        schemaContext
                            .foundationalAliases
                            .nodesByKey[node]?
                            .displayName
                        ?? "Projekt \(index + 1)",
                    ownerEntityID:
                        GraphChatTestSupport
                            .projectEntityID,
                    evidenceIDs: []
                )
            }
        state.resultContexts = [
            GraphChatConversationResultContext(
                id: sourceResultContextID,
                kind: .query,
                state: .success,
                entityID:
                    GraphChatTestSupport
                        .projectEntityID,
                references:
                    sourceNodes.enumerated().map {
                        index, node in
                        GraphChatConversationResultReference(
                            ordinal: index + 1,
                            reference: .node(node),
                            label:
                                state.nodeReferences[
                                    index
                                ].label,
                            evidenceIDs: []
                        )
                    },
                groupReferences: [],
                evidenceIDs: [],
                appliedFilters: [],
                technicalDescription:
                    "Validated large refinement source"
            ),
        ]
        state.turnContexts = [
            GraphChatConversationTurnContext(
                id: sourceTurnID,
                completedAt: completedAt,
                toolKinds: [
                    .queryDetailValues,
                ],
                resultContextIDs: [
                    sourceResultContextID,
                ],
                evidenceIDs: [],
                technicalDescription:
                    "Committed large source turn"
            ),
        ]
        state.lastValidatedQueryPlan =
            validatedPlan
        state.referenceTargets =
            GraphChatConversationReferenceTargets(
                singular: nil,
                plural:
                    sourceNodes.map {
                        .node($0)
                    },
                ordinal:
                    sourceNodes.map {
                        .node($0)
                    },
                group: nil,
                compared: []
            )

        let builder =
            GraphChatConversationContextBuilder()
        let preliminary =
            builder.makeSnapshot(
                from: state.snapshot
            )
        guard
            let sourceAlias =
                preliminary.results.first(
                    where: {
                        $0.id
                            == sourceResultContextID
                    }
                )?.alias
        else {
            preconditionFailure(
                "Expected a bounded source-result alias."
            )
        }
        let reference =
            GraphChatResolvedConversationReference(
                kind: .resultSet,
                alias: sourceAlias,
                nodes: sourceNodes,
                entityID:
                    GraphChatTestSupport
                        .projectEntityID,
                fieldID: nil,
                groupID: nil,
                label: "Große Projektauswahl"
            )
        let resolvedScope =
            GraphChatResolvedConversationScope(
                graphScope:
                    schemaContext.graphScope,
                chatScope: chatScope,
                conversationID: conversationID,
                entityID:
                    GraphChatTestSupport
                        .projectEntityID,
                nodes: sourceNodes,
                origin: .latestResults,
                revision:
                    GraphChatResolvedConversationScopeRevision(
                        sourceAlias:
                            sourceAlias,
                        sourceResultID:
                            sourceResultContextID,
                        sourceTurnID:
                            sourceTurnID,
                        sourceTurnCompletedAt:
                            completedAt,
                        sourceReferenceCount:
                            sourceNodes.count,
                        validatedQueryPlan:
                            validatedPlan
                    ),
                reference: reference
            )
        let conversationContext =
            builder.makeSnapshot(
                from: state.snapshot,
                currentReference: reference,
                currentResolvedScope:
                    resolvedScope
            )
        return GraphChatProviderTurnPlan(
            scopeKey:
                GraphChatOrchestrationScopeKey(
                    graphScope:
                        schemaContext.graphScope,
                    chatScope: chatScope
                ),
            normalizedQuestion:
                "Nur weiterhin offene Projekte",
            providerQuestion:
                "Nur weiterhin offene Projekte",
            responseLanguage: .german,
            requestBaseState: state,
            expectedCommittedState: state,
            conversationContext:
                conversationContext,
            currentReference: reference,
            currentResolvedScope:
                resolvedScope,
            continuationOperation: nil,
            foundationalContinuation: nil
        )
    }

    private func boundTurn(
        interpretation: GraphChatIntentInterpretation,
        origin: GraphChatInterpretationCorrectionOrigin,
        schemaContext:
            GraphSchemaContext? = nil
    ) throws -> CorrectionDomainBoundTurn {
        let activeContext =
            schemaContext ?? context
        let chatScope =
            interpretation.scopeBinding.chatScope
        let user = GraphChatMessage(
            role: .user,
            text: "Offene Projekte"
        )
        let assistant = GraphChatMessage(
            role: .assistant,
            text: "Hier sind die offenen Projekte."
        )
        let request = GraphChatRequest(
            id: requestID,
            scope: chatScope,
            messages: [user]
        )
        let state =
            GraphChatConversationState.initial(
                graphScope: context.graphScope,
                chatScope: chatScope,
                conversationID: conversationID
            )
        let expectedCheckpoint =
            GraphChatConversationCheckpoint.committed(
                state
            )
        let binding =
            try GraphChatInterpretationCorrectionBinding(
                originalUserMessage: user,
                originalAssistantMessage: assistant,
                originalRequest: request,
                originalTurnID: requestID,
                conversationID: conversationID,
                graphScope: context.graphScope,
                chatScope: chatScope,
                intentDomainVersion: .v1,
                originalInterpretation:
                    interpretation,
                artifactSessionID:
                    origin.artifactSessionID,
                checkpointBeforeOriginalTurn:
                    .initial(
                        graphScope:
                            context.graphScope,
                        chatScope: chatScope
                    ),
                expectedCurrentCheckpoint:
                    expectedCheckpoint,
                artifactIDsToReplace: []
            )
        let snapshot =
            GraphChatInterpretationCorrectionSchemaBuilder()
                .makeSnapshot(
                    context: activeContext,
                    chatScope: chatScope,
                    language: .german
                )
        let selection = snapshot.initialSelection(
            interpretation: interpretation,
            origin: origin
        )
        return CorrectionDomainBoundTurn(
            request:
                GraphChatInterpretationCorrectionRequest(
                    binding: binding,
                    selection: selection
                ),
            snapshot: snapshot,
            artifactSessionID:
                origin.artifactSessionID,
            expectedCheckpoint:
                expectedCheckpoint
        )
    }

    private func makeIntent(
        chatScope: GraphChatScope,
        queryScope: GraphChatScope,
        expectedCardinality:
            GraphChatTypedIntentExpectedCardinality,
        payload: GraphChatTypedIntentPayload,
        resultLimit: Int,
        sourceTurnID: UUID? = nil
    ) throws -> GraphChatTypedIntent {
        try GraphChatTypedIntent(
            version: .v1,
            scope: GraphChatTypedIntentScope(
                graphScope: context.graphScope,
                chatScope: chatScope,
                queryScope: queryScope
            ),
            responseLanguage: .german,
            binding: GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID: conversationID,
                turnID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: nil
            ),
            resolution:
                GraphChatTypedIntentResolution(
                    source:
                        sourceTurnID == nil
                        ? .appSemanticResolution
                        : .conversationContinuation,
                    origin:
                        sourceTurnID == nil
                        ? .schemaDisplayName
                        : .conversationReference,
                    quality:
                        sourceTurnID == nil
                        ? .exact
                        : .revalidatedConversationReference
                ),
            expectedCardinality:
                expectedCardinality,
            factExpectation: .none,
            limits: GraphChatTypedIntentLimits(
                resultLimit: resultLimit,
                maximumResultLimit:
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                maximumEvidenceCount:
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                maximumArtifactCount:
                    GraphChatAdvancedIntentPolicy
                        .default.maximumArtifactCount
            ),
            payload: payload
        )
    }

    private func projectIdentity()
        -> GraphChatTypedEntityIdentity
    {
        let entity = context.foundationalAliases
            .entity(
                id:
                    GraphChatTestSupport
                        .projectEntityID
            )!
        return GraphChatTypedEntityIdentity(
            id: entity.entityID,
            alias: entity.alias,
            displayName: entity.name
        )
    }

    private func personIdentity()
        -> GraphChatTypedEntityIdentity
    {
        let entity = context.foundationalAliases
            .entity(
                id:
                    GraphChatTestSupport
                        .personEntityID
            )!
        return GraphChatTypedEntityIdentity(
            id: entity.entityID,
            alias: entity.alias,
            displayName: entity.name
        )
    }

    private func fieldIdentity(
        alias: String
    ) -> GraphChatTypedFieldIdentity {
        let field = context.foundationalAliases
            .fieldsByAlias[GraphFieldAlias(alias)]!
        return GraphChatTypedFieldIdentity(
            id: field.fieldID,
            alias: field.alias,
            displayName: field.name,
            ownerEntityID: field.entityID,
            type: field.type,
            unit: field.unit
        )
    }

    private func typedNode(
        _ node: NodeRefKey,
        in schemaContext:
            GraphSchemaContext? = nil
    ) -> GraphChatTypedNodeIdentity {
        let activeContext =
            schemaContext ?? context
        let resolution =
            activeContext.foundationalAliases
                .nodesByKey[node]!
        return GraphChatTypedNodeIdentity(
            node: node,
            displayName: resolution.displayName,
            ownerEntityID:
                resolution.ownerEntityID
        )
    }

    private func resolvedScope(
        _ scope: GraphChatScope
    ) -> GraphResolvedQueryScope {
        switch scope.target {
        case .graph:
            return .graph
        case .entity(let entityID):
            return .entity(entityID)
        case .node(let node):
            return .node(node)
        case .selection(let nodes):
            return .selection(nodes)
        }
    }

    private func replacingNodeDisplayNames(
        in base: GraphSchemaContext,
        replacements:
            [NodeRefKey: String]
    ) -> GraphSchemaContext {
        var resolutions =
            base.foundationalAliases
                .nodesByKey
        for (node, displayName) in replacements {
            guard
                let existing = resolutions[node]
            else {
                continue
            }
            resolutions[node] =
                GraphSchemaNodeResolution(
                    node: existing.node,
                    ownerEntityID:
                        existing.ownerEntityID,
                    displayName: displayName
                )
        }
        let complete = GraphSchemaAliasMap(
            graphScope: base.graphScope,
            entitiesByAlias:
                base.foundationalAliases
                    .entitiesByAlias,
            fieldsByAlias:
                base.foundationalAliases
                    .fieldsByAlias,
            nodeEntityIDs:
                base.foundationalAliases
                    .nodeEntityIDs,
            nodesByKey: resolutions
        )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: complete,
            foundationalAliases: complete
        )
    }

    private func contextWithNodes()
        -> GraphSchemaContext
    {
        let base = GraphChatTestSupport.makeSchemaContext()
        let projectNode = NodeRefKey(
            kind: .entity,
            id: GraphChatTestSupport.projectEntityID
        )
        let firstProjectNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let nodes: [
            NodeRefKey: GraphSchemaNodeResolution
        ] = [
            projectNode:
                GraphSchemaNodeResolution(
                    node: projectNode,
                    ownerEntityID:
                        GraphChatTestSupport
                            .projectEntityID,
                    displayName: "Projekte"
                ),
            firstProjectNode:
                GraphSchemaNodeResolution(
                    node: firstProjectNode,
                    ownerEntityID:
                        GraphChatTestSupport
                            .projectEntityID,
                    displayName: "Atlas"
                ),
            secondProjectNode:
                GraphSchemaNodeResolution(
                    node: secondProjectNode,
                    ownerEntityID:
                        GraphChatTestSupport
                            .projectEntityID,
                    displayName: "Apollo"
                ),
            thirdProjectNode:
                GraphSchemaNodeResolution(
                    node: thirdProjectNode,
                    ownerEntityID:
                        GraphChatTestSupport
                            .projectEntityID,
                    displayName: "Hermes"
                ),
            personNode:
                GraphSchemaNodeResolution(
                    node: personNode,
                    ownerEntityID:
                        GraphChatTestSupport
                            .personEntityID,
                    displayName: "Ada"
                ),
        ]
        var nodeOwners =
            base.aliases.nodeEntityIDs
        for (node, resolution) in nodes {
            nodeOwners[node] =
                resolution.ownerEntityID
        }
        let complete = GraphSchemaAliasMap(
            graphScope: base.graphScope,
            entitiesByAlias:
                base.aliases.entitiesByAlias,
            fieldsByAlias:
                base.aliases.fieldsByAlias,
            nodeEntityIDs: nodeOwners,
            nodesByKey: nodes
        )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: complete,
            foundationalAliases: complete
        )
    }
}
