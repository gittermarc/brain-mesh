//
//  GraphChatAnswerArtifactPresentationTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph-native answer artifact presentation")
struct GraphChatAnswerArtifactPresentationTests {
    @Test
    func rendererSelectsExactlyOneSpecializedComponentForEveryArtifactType() {
        let fixture = AnswerArtifactPresentationFixture()
        let expectations: [(GraphChatAnswerArtifactPayload, GraphChatAnswerArtifactRenderComponent)] = [
            (
                .nodeProfile(
                    fixture.nodeProfilePayload
                ),
                .nodeProfile
            ),
            (.metric(fixture.metricPayload), .metric),
            (.resultList(fixture.listPayload), .resultList),
            (.table(fixture.tablePayload), .table),
            (.ranking(fixture.rankingPayload), .ranking),
            (.grouping(fixture.groupingPayload), .grouping),
            (.comparison(fixture.comparisonPayload), .comparison),
            (.healthFinding(fixture.healthPayload), .healthFinding),
            (.timeline(fixture.timelinePayload), .timeline)
        ]

        for (index, expectation) in expectations.enumerated() {
            let artifact = fixture.artifact(
                payload: expectation.0,
                index: index
            )
            let descriptor = GraphChatAnswerArtifactRenderDescriptor.make(for: artifact)
            #expect(descriptor.component == expectation.1)
            #expect(descriptor.isEmpty == false)
        }
    }

    @Test
    func emptyArtifactsRemainRenderableAsExplicitEmptyStates() {
        let fixture = AnswerArtifactPresentationFixture()
        let emptyPayloads: [GraphChatAnswerArtifactPayload] = [
            .resultList(
                GraphChatAnswerArtifactResultListPayload(
                    title: "Empty list",
                    rows: [],
                    resultMetadata: fixture.metadata(returnedCount: 0),
                    evidence: fixture.binding
                )
            ),
            .table(
                GraphChatAnswerArtifactTablePayload(
                    title: "Empty table",
                    columns: fixture.tablePayload.columns,
                    rows: [],
                    sorting: [],
                    resultMetadata: fixture.metadata(returnedCount: 0),
                    evidence: fixture.binding
                )
            ),
            .ranking(
                GraphChatAnswerArtifactRankingPayload(
                    title: "Empty ranking",
                    entries: [],
                    resultMetadata: fixture.metadata(returnedCount: 0),
                    evidence: fixture.binding
                )
            ),
            .grouping(
                GraphChatAnswerArtifactGroupingPayload(
                    title: "Empty grouping",
                    groups: [],
                    resultMetadata: fixture.metadata(returnedCount: 0),
                    evidence: fixture.binding
                )
            ),
            .comparison(
                GraphChatAnswerArtifactComparisonPayload(
                    title: "Empty comparison",
                    subjects: [],
                    features: [],
                    values: [],
                    evidence: fixture.binding
                )
            ),
            .healthFinding(
                GraphChatAnswerArtifactHealthFindingPayload(
                    findingType: .other,
                    severity: nil,
                    summary: "",
                    affectedElementCount: 0,
                    affectedNodes: [],
                    evidence: fixture.binding,
                    navigationTargets: []
                )
            ),
            .timeline(
                GraphChatAnswerArtifactTimelinePayload(
                    title: "Empty timeline",
                    entries: [],
                    resultMetadata: fixture.metadata(returnedCount: 0),
                    evidence: fixture.binding
                )
            )
        ]

        for (index, payload) in emptyPayloads.enumerated() {
            let descriptor = GraphChatAnswerArtifactRenderDescriptor.make(
                for: fixture.artifact(payload: payload, index: 100 + index)
            )
            #expect(descriptor.isEmpty)
        }
    }

    @Test
    func renderPlanPreservesRequestedOrderAndFallsBackForUnknownArtifact() {
        let fixture = AnswerArtifactPresentationFixture()
        let first = fixture.artifact(payload: .metric(fixture.metricPayload), index: 1)
        let second = fixture.artifact(payload: .resultList(fixture.listPayload), index: 2)
        let unknownID = GraphChatAnswerArtifactID(rawValue: fixture.uuid(999))
        let resolution = fixture.resolution(
            requestedIDs: [second.id, unknownID, first.id],
            artifacts: [first, second]
        )

        let plan = GraphChatAnswerArtifactRenderPlan(
            artifactIDs: [second.id, unknownID, first.id, second.id],
            resolution: resolution
        )

        #expect(plan.entries.map(\.id) == [second.id, unknownID, first.id])
        #expect(plan.hasFallback)
        guard case .fallback(let id, let reason) = plan.entries[1] else {
            Issue.record("Expected the unknown artifact to use the text fallback")
            return
        }
        #expect(id == unknownID)
        #expect(reason == .notRegisteredOrInvalidated)
    }

    @Test
    func wrongSessionAndWrongGraphArtifactsAreNeverRendered() {
        let fixture = AnswerArtifactPresentationFixture()
        let wrongSession = GraphChatAnswerArtifact(
            id: GraphChatAnswerArtifactID(rawValue: fixture.uuid(110)),
            sessionID: GraphChatAnswerArtifactSessionID(rawValue: fixture.uuid(111)),
            graphScope: fixture.graphScope,
            title: "Wrong session",
            payload: .metric(fixture.metricPayload),
            evidence: fixture.binding,
            navigationTargets: []
        )
        let wrongGraph = GraphChatAnswerArtifact(
            id: GraphChatAnswerArtifactID(rawValue: fixture.uuid(112)),
            sessionID: fixture.sessionID,
            graphScope: GraphScope(graphID: fixture.uuid(113)),
            title: "Wrong graph",
            payload: .metric(fixture.metricPayload),
            evidence: fixture.binding,
            navigationTargets: []
        )
        let resolution = GraphChatAnswerPresentationResolution(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            artifactSessionID: fixture.sessionID,
            requestedArtifactIDs: [wrongSession.id, wrongGraph.id],
            artifacts: [
                GraphChatResolvedAnswerArtifact(
                    artifact: wrongSession,
                    revalidatedAt: fixture.revalidatedAt
                ),
                GraphChatResolvedAnswerArtifact(
                    artifact: wrongGraph,
                    revalidatedAt: fixture.revalidatedAt
                )
            ],
            evidence: [fixture.nodeEvidence]
        )

        #expect(resolution.artifacts.isEmpty)
        #expect(resolution.unavailableArtifactReasons[wrongSession.id] == .sessionMismatch)
        #expect(resolution.unavailableArtifactReasons[wrongGraph.id] == .graphScopeMismatch)
    }

    @Test
    func unavailableResolutionRetainsTheSpecificFallbackReason() {
        let fixture = AnswerArtifactPresentationFixture()
        let artifactID = GraphChatAnswerArtifactID(rawValue: fixture.uuid(120))
        let resolution = GraphChatAnswerPresentationResolution.unavailable(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            requestedArtifactIDs: [artifactID],
            reason: .scopeMismatch
        )

        #expect(resolution.unavailableArtifactReasons[artifactID] == .scopeMismatch)
    }

    @Test
    func formatterHandlesNumberPercentageDateDurationAndMissingContext() {
        let german = GraphChatAnswerArtifactValueFormatter(language: .german)
        let english = GraphChatAnswerArtifactValueFormatter(language: .english)
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let fixture = AnswerArtifactPresentationFixture()

        #expect(german.string(for: .integer(12_500)).isEmpty == false)
        #expect(german.string(for: .decimal(Decimal(string: "12.375")!)).contains("12"))
        #expect(german.string(for: .percentage(Decimal(string: "0.625")!)).contains("%"))
        #expect(english.string(for: .percentage(Decimal(string: "0.625")!)).contains("%"))
        let localizedDateTime = GraphChatAnswerArtifactValuePresentation(
            dateFormat: .localizedDateTime
        )
        let localizedDate = GraphChatAnswerArtifactValuePresentation(
            dateFormat: .localizedDate
        )
        #expect(german.string(for: .date(date)).isEmpty == false)
        #expect(
            german.string(for: .date(date), presentation: localizedDateTime)
                != german.string(for: .date(date), presentation: localizedDate)
        )
        #expect(german.string(for: .duration(5_400)) == "1 Std. 30 Min.")
        #expect(english.string(for: .duration(5_400)) == "1 hr 30 min")
        #expect(german.string(for: .missing) == "Nicht vorhanden")
        #expect(english.string(for: .missing) == "Missing")
        #expect(german.string(for: .integer(42), unit: "Tage").hasSuffix(" Tage"))
        #expect(fixture.metricPayload.contextDescription == nil)
    }

    @Test
    func tableLayoutAdaptsForPhonePadAndAccessibilityDynamicType() {
        #expect(
            GraphChatAnswerArtifactLayoutPolicy.tableLayoutMode(
                hasRegularHorizontalSizeClass: false,
                isAccessibilityDynamicType: false,
                columnCount: 4
            ) == .rowCards
        )
        #expect(
            GraphChatAnswerArtifactLayoutPolicy.tableLayoutMode(
                hasRegularHorizontalSizeClass: true,
                isAccessibilityDynamicType: false,
                columnCount: 4
            ) == .columns
        )
        #expect(
            GraphChatAnswerArtifactLayoutPolicy.tableLayoutMode(
                hasRegularHorizontalSizeClass: true,
                isAccessibilityDynamicType: true,
                columnCount: 4
            ) == .rowCards
        )
    }

    @Test
    func listTableRankingGroupingComparisonAndTimelineKeepArtifactOrder() {
        let fixture = AnswerArtifactPresentationFixture()

        #expect(fixture.listPayload.rows.map(\.primaryText) == fixture.expectedListOrder)
        #expect(fixture.tablePayload.rows.map(\.id) == fixture.expectedTableRowOrder)
        #expect(fixture.rankingPayload.entries.map(\.rank) == [2, 1, 3])
        #expect(fixture.groupingPayload.groups.map(\.label) == ["Open", "Blocked", "Done"])
        #expect(fixture.comparisonPayload.subjects.map(\.label) == ["Alpha", "Beta"])
        #expect(fixture.comparisonPayload.features.map(\.label) == ["Budget", "Due date", "Owner"])
        #expect(fixture.timelinePayload.entries.map(\.title) == ["Kickoff", "Review", "Launch"])
        #expect(fixture.timelinePayload.entries.map(\.interval.start) == fixture.timelineDates)
    }

    @Test
    func rowAndCellMissingValuesRemainExplicitAndLongValuesRemainIntact() {
        let fixture = AnswerArtifactPresentationFixture()
        let formatter = GraphChatAnswerArtifactValueFormatter(language: .english)
        let longValue = fixture.longValue
        let missingCell = fixture.tablePayload.rows[1].cells.first {
            $0.columnID == fixture.ownerColumnID
        }

        #expect(missingCell?.value == .missing)
        #expect(formatter.string(for: missingCell?.value ?? .missing) == "Missing")
        #expect(fixture.listPayload.rows[0].secondaryText == longValue)
        #expect(formatter.string(for: .text(longValue)) == longValue)
    }

    @Test
    func rankingShareAndEmptyGroupNavigationStayOptional() {
        let fixture = AnswerArtifactPresentationFixture()
        let formatter = GraphChatAnswerArtifactValueFormatter(language: .english)
        let strings = GraphChatAnswerArtifactStrings(language: .english)

        #expect(
            formatter.string(for: fixture.rankingPayload.entries[0].share ?? .missing)
                .contains("%")
        )
        #expect(fixture.groupingPayload.groups[1].includedResultReferences.isEmpty)
        #expect(fixture.groupingPayload.groups[1].navigationTarget == nil)
        #expect(
            strings.resultCountText(fixture.groupingPayload.resultMetadata)
                == "3 results, total unknown"
        )
    }

    @Test
    func evidenceChipUsesSectionAndRowEvidenceKindsWithoutInventingSources() {
        let fixture = AnswerArtifactPresentationFixture()
        let queryArtifact = fixture.artifact(
            payload: .table(fixture.tablePayload),
            index: 130,
            querySummary: fixture.querySummary
        )
        let healthArtifact = fixture.artifact(
            payload: .healthFinding(fixture.healthPayload),
            index: 131
        )

        let queryChip = GraphChatEvidenceChipPresentation(
            evidence: fixture.graphEvidence,
            artifact: queryArtifact,
            language: .english
        )
        let nodeChip = GraphChatEvidenceChipPresentation(
            evidence: fixture.nodeEvidence,
            artifact: nil,
            language: .english
        )
        let entityChip = GraphChatEvidenceChipPresentation(
            evidence: fixture.entityEvidence,
            artifact: nil,
            language: .english
        )
        let fieldChip = GraphChatEvidenceChipPresentation(
            evidence: fixture.fieldEvidence,
            artifact: nil,
            language: .english
        )
        let linkChip = GraphChatEvidenceChipPresentation(
            evidence: fixture.linkEvidence,
            artifact: nil,
            language: .english
        )
        let healthChip = GraphChatEvidenceChipPresentation(
            evidence: fixture.nodeEvidence,
            artifact: healthArtifact,
            language: .english
        )

        #expect(queryChip.kind == .queryResult)
        #expect(nodeChip.kind == .node)
        #expect(entityChip.kind == .entity)
        #expect(fieldChip.kind == .field)
        #expect(linkChip.kind == .link)
        #expect(healthChip.kind == .healthFinding)
        #expect(nodeChip.accessibilityLabel.contains(nodeChip.title))
    }

    @Test
    func sectionAndRowEvidenceBindingsResolveOnlyTheirOwnSources() {
        let fixture = AnswerArtifactPresentationFixture()
        let artifact = fixture.artifact(
            payload: .resultList(fixture.listPayload),
            index: 132
        )
        let resolution = fixture.resolution(
            requestedIDs: [artifact.id],
            artifacts: [artifact]
        )
        let firstRow = fixture.listPayload.rows[0]
        let secondRow = fixture.listPayload.rows[1]

        #expect(
            resolution.evidence(for: fixture.binding.evidenceIDs).map(\.id)
                == fixture.binding.evidenceIDs
        )
        #expect(
            resolution.evidence(for: firstRow.evidence.evidenceIDs).map(\.id)
                == [fixture.nodeEvidence.id]
        )
        #expect(
            resolution.evidence(for: secondRow.evidence.evidenceIDs).map(\.id)
                == [fixture.fieldEvidence.id]
        )
    }

    @Test
    func deletedOrForeignEvidenceDisappearsFromSectionAndRowLookups() {
        let fixture = AnswerArtifactPresentationFixture()
        let foreignEvidence = fixture.evidence(
            sourceKind: .attribute,
            sourceID: fixture.uuid(140),
            graphID: fixture.uuid(141),
            title: "Foreign"
        )
        let resolution = GraphChatAnswerPresentationResolution(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            artifactSessionID: fixture.sessionID,
            requestedArtifactIDs: [],
            artifacts: [],
            evidence: [fixture.nodeEvidence, foreignEvidence]
        )

        #expect(resolution.evidence.map(\.id) == [fixture.nodeEvidence.id])
        #expect(resolution.evidence(for: [fixture.nodeEvidence.id]).count == 1)
        #expect(resolution.evidence(for: [fixture.fieldEvidence.id]).isEmpty)
    }

    @Test
    func evidenceDrawerShowsOnlyVerifiableQueryResultFilterSortAndRevalidationData() {
        let fixture = AnswerArtifactPresentationFixture()
        let artifact = fixture.artifact(
            payload: .table(fixture.tablePayload),
            index: 150,
            querySummary: fixture.querySummary
        )
        let drawer = GraphChatEvidenceDrawerPresentation(
            resolved: GraphChatResolvedAnswerArtifact(
                artifact: artifact,
                revalidatedAt: fixture.revalidatedAt
            ),
            availableEvidence: fixture.allEvidence,
            language: .english
        )

        #expect(drawer.querySummary == fixture.querySummary.displayText)
        #expect(drawer.resultCount == "3 of 8 results")
        #expect(drawer.truncation?.contains("5 additional items") == true)
        #expect(drawer.filters.map(\.fieldName) == ["Status"])
        #expect(drawer.sorting.map(\.fieldName) == ["Due date"])
        #expect(drawer.revalidatedAt == fixture.revalidatedAt)
        #expect(drawer.sources.isEmpty == false)
        #expect(drawer.visibleTextForTesting.contains("Entity: Projects"))
        #expect(drawer.visibleTextForTesting.localizedCaseInsensitiveContains("system prompt") == false)
        #expect(drawer.visibleTextForTesting.localizedCaseInsensitiveContains("chain of thought") == false)
    }

    @Test
    func navigationPolicyAllowsOnlyExistingReliableRoutes() {
        let fixture = AnswerArtifactPresentationFixture()
        let node = NodeRefKey(kind: .attribute, id: fixture.uuid(160))
        let filteredEntity = GraphChatAnswerArtifactFilterValue(
            fieldName: "Status",
            operationDescription: "equals",
            values: [.choice(GraphChatAnswerArtifactChoiceValue(value: "open"))]
        )

        #expect(
            GraphChatAnswerArtifactNavigationPolicy.route(
                for: .openNode(graphScope: fixture.graphScope, node: node),
                activeGraphScope: fixture.graphScope
            ) == .openNode(graphScope: fixture.graphScope, node: node)
        )
        #expect(
            GraphChatAnswerArtifactNavigationPolicy.route(
                for: .focusNodeInGraph(graphScope: fixture.graphScope, node: node),
                activeGraphScope: fixture.graphScope
            ) == .focusNodeInGraph(graphScope: fixture.graphScope, node: node)
        )
        #expect(
            GraphChatAnswerArtifactNavigationPolicy.route(
                for: .openEntityList(
                    graphScope: fixture.graphScope,
                    entityID: fixture.entityID,
                    filters: []
                ),
                activeGraphScope: fixture.graphScope
            ) == .openEntityList(
                graphScope: fixture.graphScope,
                entityID: fixture.entityID
            )
        )
        #expect(
            GraphChatAnswerArtifactNavigationPolicy.route(
                for: .openEntityList(
                    graphScope: fixture.graphScope,
                    entityID: fixture.entityID,
                    filters: [filteredEntity]
                ),
                activeGraphScope: fixture.graphScope
            ) == nil
        )
        #expect(
            GraphChatAnswerArtifactNavigationPolicy.route(
                for: .openResultFilter(
                    graphScope: fixture.graphScope,
                    entityID: fixture.entityID,
                    filters: [],
                    resultNodes: [node]
                ),
                activeGraphScope: fixture.graphScope
            ) == nil
        )
        let workspaceOnlyTargets: [GraphChatAnswerArtifactNavigationTarget] = [
            .showResultNodes(
                graphScope: fixture.graphScope,
                title: "Results",
                nodes: [node]
            ),
            .highlightNodesInCanvas(
                graphScope: fixture.graphScope,
                nodes: [node]
            ),
            .clearCanvasHighlight(graphScope: fixture.graphScope),
            .addNodesToCanvasSelection(
                graphScope: fixture.graphScope,
                nodes: [node]
            ),
            .replaceCanvasSelection(
                graphScope: fixture.graphScope,
                nodes: [node]
            ),
            .compareNodes(
                graphScope: fixture.graphScope,
                nodes: [node, NodeRefKey(kind: .attribute, id: fixture.uuid(162))]
            ),
        ]
        for target in workspaceOnlyTargets {
            #expect(
                GraphChatAnswerArtifactNavigationPolicy.route(
                    for: target,
                    activeGraphScope: fixture.graphScope
                ) == nil
            )
        }
        #expect(
            GraphChatAnswerArtifactNavigationPolicy.route(
                for: .openNode(
                    graphScope: GraphScope(graphID: fixture.uuid(161)),
                    node: node
                ),
                activeGraphScope: fixture.graphScope
            ) == nil
        )
    }

    @Test
    func germanAndEnglishAccessibilityStringsRemainNonemptyForLongContent() {
        let german = GraphChatAnswerArtifactStrings(language: .german)
        let english = GraphChatAnswerArtifactStrings(language: .english)

        #expect(german.structuredUnavailable.isEmpty == false)
        #expect(english.structuredUnavailable.isEmpty == false)
        #expect(german.visibleRowsText(visible: 5, available: 125).contains("125"))
        #expect(english.visibleRowsText(visible: 5, available: 125).contains("125"))
        #expect(german.healthType(.missingRequiredValues).isEmpty == false)
        #expect(english.healthType(.missingRequiredValues).isEmpty == false)
        #expect(german.showAllResults.isEmpty == false)
        #expect(english.showAllResults.isEmpty == false)
        #expect(german.openAsFilter.isEmpty == false)
        #expect(english.openAsFilter.isEmpty == false)
        #expect(german.highlightInGraph.isEmpty == false)
        #expect(english.highlightInGraph.isEmpty == false)
        #expect(german.clearHighlight.isEmpty == false)
        #expect(english.clearHighlight.isEmpty == false)
        #expect(german.addToSelection.isEmpty == false)
        #expect(english.addToSelection.isEmpty == false)
        #expect(german.replaceSelection.isEmpty == false)
        #expect(english.replaceSelection.isEmpty == false)
        #expect(german.compareNodes.isEmpty == false)
        #expect(english.compareNodes.isEmpty == false)
    }
}

struct AnswerArtifactPresentationFixture {
    let graphScope = GraphScope(
        graphID: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!
    )
    let sessionID = GraphChatAnswerArtifactSessionID(
        rawValue: UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!
    )
    let entityID = UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!
    let revalidatedAt = Date(timeIntervalSince1970: 1_735_689_600)
    let timelineDates = [
        Date(timeIntervalSince1970: 1_700_000_000),
        Date(timeIntervalSince1970: 1_710_000_000),
        Date(timeIntervalSince1970: 1_720_000_000)
    ]
    let longValue = "A deliberately long English and German-compatible value that must wrap without being shortened or replaced."

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var nodeEvidence: GraphEvidence {
        evidence(
            sourceKind: .attribute,
            sourceID: uuid(10),
            graphID: graphScope.graphID,
            title: "Project Alpha"
        )
    }

    var entityEvidence: GraphEvidence {
        evidence(
            sourceKind: .entity,
            sourceID: entityID,
            graphID: graphScope.graphID,
            title: "Projects"
        )
    }

    var fieldEvidence: GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .detailField,
                sourceID: uuid(11),
                owner: GraphSourceNodeReference(kind: .attribute, id: uuid(10)),
                fieldID: uuid(12)
            ),
            summary: "Validated status field",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: uuid(12),
                    fieldName: "Status",
                    value: .choice("open"),
                    unit: nil
                )
            ],
            navigationTitle: "Status"
        )
    }

    var linkEvidence: GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .link,
                sourceID: uuid(13),
                node: GraphSourceNodeReference(kind: .attribute, id: uuid(10)),
                linkID: uuid(13)
            ),
            summary: "Validated dependency link",
            navigationTitle: "Depends on"
        )
    }

    var graphEvidence: GraphEvidence {
        evidence(
            sourceKind: .graph,
            sourceID: graphScope.graphID,
            graphID: graphScope.graphID,
            title: "Query result"
        )
    }

    var allEvidence: [GraphEvidence] {
        [nodeEvidence, entityEvidence, fieldEvidence, linkEvidence, graphEvidence]
    }

    var binding: GraphChatAnswerArtifactEvidenceBinding {
        GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: allEvidence.map(\.id)
        )
    }

    var nodeTarget: GraphChatAnswerArtifactNavigationTarget {
        .openNode(
            graphScope: graphScope,
            node: NodeRefKey(kind: .attribute, id: uuid(10))
        )
    }

    var querySummary: GraphChatAnswerArtifactQuerySummary {
        GraphChatAnswerArtifactQuerySummary(
            language: .english,
            entityID: entityID,
            entityLabel: "Projects",
            filters: [
                GraphChatAnswerArtifactQueryFilterSummary(
                    field: GraphChatAnswerArtifactQueryFieldSummary(
                        fieldID: uuid(20),
                        label: "Status"
                    ),
                    operation: .equals,
                    operationLabel: "equals",
                    values: [
                        .choice(GraphChatAnswerArtifactChoiceValue(value: "open", label: "Open"))
                    ],
                    valueDescription: "Open"
                )
            ],
            grouping: nil,
            sorting: [
                GraphChatAnswerArtifactQuerySortSummary(
                    key: "dueDate",
                    label: "Due date",
                    direction: .ascending,
                    directionLabel: "ascending"
                )
            ],
            projection: [
                GraphChatAnswerArtifactQueryFieldSummary(
                    fieldID: uuid(21),
                    label: "Due date"
                )
            ],
            includesNodeIdentity: true,
            limit: 3,
            aggregation: nil,
            displayText: "Entity: Projects; Status equals Open; sorted by Due date ascending; limit 3"
        )
    }

    var metricPayload: GraphChatAnswerArtifactMetricPayload {
        GraphChatAnswerArtifactMetricPayload(
            title: "Completion",
            value: .percentage(Decimal(string: "0.625")!),
            unit: nil,
            contextDescription: nil,
            evidence: binding
        )
    }

    var nodeProfilePayload:
        GraphChatAnswerArtifactNodeProfilePayload
    {
        let empty =
            GraphChatAnswerArtifactResultMetadata(
                resultCount: 0,
                returnedCount: 0
            )
        return GraphChatAnswerArtifactNodeProfilePayload(
            node:
                NodeRefKey(
                    kind: .attribute,
                    id: uuid(10)
                ),
            visibleName: "Alpha",
            displayName:
                "Projects • Alpha",
            owner:
                GraphChatAnswerArtifactNodeProfileOwner(
                    label: "Projects",
                    navigationTarget:
                        nodeTarget
                ),
            notes:
                GraphChatAnswerArtifactNodeProfileNotes(
                    text: "Validated notes",
                    evidence:
                        GraphChatAnswerArtifactEvidenceBinding(
                            evidenceIDs: [
                                nodeEvidence.id,
                            ]
                        )
                ),
            detailValues: [],
            incomingConnections: [],
            outgoingConnections: [],
            attachments: [],
            detailValueMetadata: empty,
            incomingConnectionMetadata:
                empty,
            outgoingConnectionMetadata:
                empty,
            attachmentMetadata: empty,
            nodeNavigationTarget:
                nodeTarget,
            identityEvidence:
                GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [
                        nodeEvidence.id,
                    ]
                ),
            evidence:
                GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [
                        nodeEvidence.id,
                    ]
                )
        )
    }

    var expectedListOrder: [String] {
        ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta"]
    }

    var listPayload: GraphChatAnswerArtifactResultListPayload {
        GraphChatAnswerArtifactResultListPayload(
            title: "Projects",
            rows: expectedListOrder.enumerated().map { index, label in
                GraphChatAnswerArtifactListRow(
                    id: GraphChatAnswerArtifactItemID(rawValue: uuid(100 + index)),
                    primaryText: label,
                    secondaryText: index == 0 ? longValue : "Secondary \(index)",
                    navigationTargets: index == 1 ? [] : [nodeTarget],
                    evidence: GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: index == 0 ? [nodeEvidence.id] : [fieldEvidence.id]
                    )
                )
            },
            resultMetadata: metadata(returnedCount: 7, totalCount: 12),
            evidence: binding
        )
    }

    let nameColumnID = GraphChatAnswerArtifactItemID(
        rawValue: UUID(uuidString: "B1000000-0000-0000-0000-000000000201")!
    )
    let budgetColumnID = GraphChatAnswerArtifactItemID(
        rawValue: UUID(uuidString: "B1000000-0000-0000-0000-000000000202")!
    )
    let dueDateColumnID = GraphChatAnswerArtifactItemID(
        rawValue: UUID(uuidString: "B1000000-0000-0000-0000-000000000203")!
    )
    let ownerColumnID = GraphChatAnswerArtifactItemID(
        rawValue: UUID(uuidString: "B1000000-0000-0000-0000-000000000204")!
    )

    var expectedTableRowOrder: [GraphChatAnswerArtifactItemID] {
        [
            GraphChatAnswerArtifactItemID(rawValue: uuid(220)),
            GraphChatAnswerArtifactItemID(rawValue: uuid(221)),
            GraphChatAnswerArtifactItemID(rawValue: uuid(222))
        ]
    }

    var tablePayload: GraphChatAnswerArtifactTablePayload {
        let columns = [
            GraphChatAnswerArtifactTableColumn(
                id: nameColumnID,
                key: "name",
                title: "Name",
                role: .primary,
                unit: nil
            ),
            GraphChatAnswerArtifactTableColumn(
                id: budgetColumnID,
                key: "budget",
                title: "Budget",
                role: .measure,
                unit: "EUR"
            ),
            GraphChatAnswerArtifactTableColumn(
                id: dueDateColumnID,
                key: "dueDate",
                title: "Due date",
                role: .date,
                unit: nil
            ),
            GraphChatAnswerArtifactTableColumn(
                id: ownerColumnID,
                key: "owner",
                title: "Owner",
                role: .secondary,
                unit: nil,
                valuePresentation: GraphChatAnswerArtifactValuePresentation(
                    missingLabel: "Not assigned"
                )
            )
        ]
        let rows = expectedTableRowOrder.enumerated().map { index, rowID in
            GraphChatAnswerArtifactTableRow(
                id: rowID,
                cells: [
                    GraphChatAnswerArtifactTableCell(
                        columnID: nameColumnID,
                        value: .text(expectedListOrder[index]),
                        evidence: GraphChatAnswerArtifactEvidenceBinding(
                            evidenceIDs: [nodeEvidence.id]
                        )
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: budgetColumnID,
                        value: .decimal(Decimal(10_000 + index * 2_500)),
                        evidence: nil
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: dueDateColumnID,
                        value: .date(timelineDates[index]),
                        evidence: GraphChatAnswerArtifactEvidenceBinding(
                            evidenceIDs: [fieldEvidence.id]
                        )
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: ownerColumnID,
                        value: index == 1 ? .missing : .text("Owner \(index + 1)"),
                        evidence: nil
                    )
                ],
                navigationTarget: index == 2 ? nil : nodeTarget,
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [nodeEvidence.id]
                )
            )
        }
        return GraphChatAnswerArtifactTablePayload(
            title: "Project table",
            columns: columns,
            rows: rows,
            sorting: [
                GraphChatAnswerArtifactSortDescriptor(
                    columnID: dueDateColumnID,
                    direction: .ascending
                )
            ],
            resultMetadata: metadata(returnedCount: 3, totalCount: 8),
            evidence: binding
        )
    }

    var rankingPayload: GraphChatAnswerArtifactRankingPayload {
        GraphChatAnswerArtifactRankingPayload(
            title: "Priority ranking",
            entries: [
                rankingEntry(id: 300, rank: 2, label: "Beta", value: 80, share: "0.40"),
                rankingEntry(id: 301, rank: 1, label: "Alpha", value: 100, share: "0.50"),
                rankingEntry(id: 302, rank: 3, label: "Gamma", value: 20, share: "0.10")
            ],
            resultMetadata: metadata(returnedCount: 3, totalCount: 3, truncated: false),
            evidence: binding
        )
    }

    var groupingPayload: GraphChatAnswerArtifactGroupingPayload {
        GraphChatAnswerArtifactGroupingPayload(
            title: "Status groups",
            groups: [
                groupingEntry(id: 320, label: "Open", count: 4, share: "0.50", hasNavigation: true),
                groupingEntry(id: 321, label: "Blocked", count: 0, share: "0.00", hasNavigation: false),
                groupingEntry(id: 322, label: "Done", count: 4, share: "0.50", hasNavigation: true)
            ],
            resultMetadata: metadata(returnedCount: 3, totalCount: nil, truncated: false),
            evidence: binding
        )
    }

    var comparisonPayload: GraphChatAnswerArtifactComparisonPayload {
        let alpha = GraphChatAnswerArtifactItemID(rawValue: uuid(340))
        let beta = GraphChatAnswerArtifactItemID(rawValue: uuid(341))
        let budget = GraphChatAnswerArtifactItemID(rawValue: uuid(342))
        let dueDate = GraphChatAnswerArtifactItemID(rawValue: uuid(343))
        let owner = GraphChatAnswerArtifactItemID(rawValue: uuid(344))
        return GraphChatAnswerArtifactComparisonPayload(
            title: "Project comparison",
            subjects: [
                GraphChatAnswerArtifactComparisonSubject(
                    id: alpha,
                    label: "Alpha",
                    navigationTarget: nodeTarget,
                    evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [nodeEvidence.id])
                ),
                GraphChatAnswerArtifactComparisonSubject(
                    id: beta,
                    label: "Beta",
                    navigationTarget: nil,
                    evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [entityEvidence.id])
                )
            ],
            features: [
                comparisonFeature(id: budget, key: "budget", label: "Budget", unit: "EUR"),
                comparisonFeature(id: dueDate, key: "dueDate", label: "Due date", unit: nil),
                comparisonFeature(id: owner, key: "owner", label: "Owner", unit: nil)
            ],
            values: [
                comparisonValue(subject: alpha, feature: budget, value: .decimal(10_000)),
                comparisonValue(subject: beta, feature: budget, value: .decimal(12_500)),
                comparisonValue(subject: alpha, feature: dueDate, value: .date(timelineDates[0])),
                comparisonValue(subject: beta, feature: dueDate, value: .missing),
                comparisonValue(subject: alpha, feature: owner, value: .text("Marc")),
                comparisonValue(subject: beta, feature: owner, value: .text("Claudia"))
            ],
            evidence: binding
        )
    }

    var healthPayload: GraphChatAnswerArtifactHealthFindingPayload {
        GraphChatAnswerArtifactHealthFindingPayload(
            findingType: .missingRequiredValues,
            severity: .warning,
            summary: "Three projects have no required owner value.",
            affectedElementCount: 3,
            affectedNodes: [
                NodeRefKey(kind: .attribute, id: uuid(360)),
                NodeRefKey(kind: .attribute, id: uuid(361)),
                NodeRefKey(kind: .attribute, id: uuid(362))
            ],
            evidence: binding,
            navigationTargets: [nodeTarget]
        )
    }

    var timelinePayload: GraphChatAnswerArtifactTimelinePayload {
        GraphChatAnswerArtifactTimelinePayload(
            title: "Project timeline",
            entries: [
                timelineEntry(id: 380, date: timelineDates[0], title: "Kickoff", value: .text("Started")),
                timelineEntry(id: 381, date: timelineDates[1], title: "Review", value: .percentage(Decimal(string: "0.50")!)),
                timelineEntry(id: 382, date: timelineDates[2], title: "Launch", value: .date(timelineDates[2]))
            ],
            resultMetadata: metadata(returnedCount: 3, totalCount: 3, truncated: false),
            evidence: binding
        )
    }

    func artifact(
        payload: GraphChatAnswerArtifactPayload,
        index: Int,
        querySummary: GraphChatAnswerArtifactQuerySummary? = nil
    ) -> GraphChatAnswerArtifact {
        GraphChatAnswerArtifact(
            id: GraphChatAnswerArtifactID(rawValue: uuid(500 + index)),
            sessionID: sessionID,
            graphScope: graphScope,
            title: "Artifact \(index)",
            payload: payload,
            evidence: binding,
            navigationTargets: [nodeTarget],
            querySummary: querySummary
        )
    }

    func resolution(
        requestedIDs: [GraphChatAnswerArtifactID],
        artifacts: [GraphChatAnswerArtifact]
    ) -> GraphChatAnswerPresentationResolution {
        GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: sessionID,
            requestedArtifactIDs: requestedIDs,
            artifacts: artifacts.map {
                GraphChatResolvedAnswerArtifact(
                    artifact: $0,
                    revalidatedAt: revalidatedAt
                )
            },
            evidence: allEvidence
        )
    }

    func metadata(
        returnedCount: Int,
        totalCount: Int? = nil,
        truncated: Bool = true
    ) -> GraphChatAnswerArtifactResultMetadata {
        GraphChatAnswerArtifactResultMetadata(
            resultCount: totalCount,
            returnedCount: returnedCount,
            truncation: truncated
                ? GraphChatAnswerArtifactTruncation(
                    isTruncated: true,
                    omittedCount: totalCount.map { max(0, $0 - returnedCount) },
                    reason: .queryLimit
                )
                : .complete
        )
    }

    func evidence(
        sourceKind: GraphSourceKind,
        sourceID: UUID,
        graphID: UUID,
        title: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: sourceKind,
                sourceID: sourceID,
                node: sourceKind == .attribute
                    ? GraphSourceNodeReference(kind: .attribute, id: sourceID)
                    : nil
            ),
            summary: "Validated source: \(title)",
            fieldValues: [],
            navigationTitle: title
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "B1000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    }

    private func rankingEntry(
        id: Int,
        rank: Int,
        label: String,
        value: Int,
        share: String
    ) -> GraphChatAnswerArtifactRankingEntry {
        GraphChatAnswerArtifactRankingEntry(
            id: GraphChatAnswerArtifactItemID(rawValue: uuid(id)),
            rank: rank,
            label: label,
            value: .integer(value),
            share: .percentage(Decimal(string: share)!),
            navigationTarget: rank == 3 ? nil : nodeTarget,
            evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [nodeEvidence.id])
        )
    }

    private func groupingEntry(
        id: Int,
        label: String,
        count: Int,
        share: String,
        hasNavigation: Bool
    ) -> GraphChatAnswerArtifactGroupingEntry {
        GraphChatAnswerArtifactGroupingEntry(
            id: GraphChatAnswerArtifactItemID(rawValue: uuid(id)),
            groupKey: .choice(GraphChatAnswerArtifactChoiceValue(value: label.lowercased(), label: label)),
            label: label,
            count: count,
            share: .percentage(Decimal(string: share)!),
            includedResultReferences: count == 0
                ? []
                : [GraphChatAnswerArtifactItemID(rawValue: uuid(id + 1000))],
            navigationTarget: hasNavigation ? nodeTarget : nil,
            evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [fieldEvidence.id])
        )
    }

    private func comparisonFeature(
        id: GraphChatAnswerArtifactItemID,
        key: String,
        label: String,
        unit: String?
    ) -> GraphChatAnswerArtifactComparisonFeature {
        GraphChatAnswerArtifactComparisonFeature(
            id: id,
            key: key,
            label: label,
            unit: unit,
            evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [fieldEvidence.id])
        )
    }

    private func comparisonValue(
        subject: GraphChatAnswerArtifactItemID,
        feature: GraphChatAnswerArtifactItemID,
        value: GraphChatAnswerArtifactValue
    ) -> GraphChatAnswerArtifactComparisonValue {
        GraphChatAnswerArtifactComparisonValue(
            subjectID: subject,
            featureID: feature,
            value: value,
            evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [fieldEvidence.id])
        )
    }

    private func timelineEntry(
        id: Int,
        date: Date,
        title: String,
        value: GraphChatAnswerArtifactValue
    ) -> GraphChatAnswerArtifactTimelineEntry {
        GraphChatAnswerArtifactTimelineEntry(
            id: GraphChatAnswerArtifactItemID(rawValue: uuid(id)),
            interval: GraphChatAnswerArtifactTimeInterval(start: date),
            title: title,
            value: value,
            resultReferences: [],
            navigationTarget: id == 381 ? nil : nodeTarget,
            evidence: GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [nodeEvidence.id])
        )
    }
}
