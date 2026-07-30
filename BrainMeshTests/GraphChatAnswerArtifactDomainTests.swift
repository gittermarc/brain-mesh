import Foundation
import Testing

@testable import BrainMesh

struct GraphChatAnswerArtifactDomainTests {
    @Test
    func allSupportedPayloadKindsRemainValueOnlyAndSendable() {
        let fixture = ArtifactDomainFixture()
        let payloads: [GraphChatAnswerArtifactPayload] = [
            .nodeProfile(
                fixture.nodeProfilePayload
            ),
            .metric(fixture.metricPayload),
            .resultList(fixture.listPayload),
            .table(fixture.tablePayload),
            .ranking(fixture.rankingPayload),
            .grouping(fixture.groupingPayload),
            .comparison(fixture.comparisonPayload),
            .healthFinding(fixture.healthPayload),
            .timeline(fixture.timelinePayload),
        ]
        let artifacts = payloads.enumerated().map { index, payload in
            GraphChatAnswerArtifact(
                id: GraphChatAnswerArtifactID(
                    rawValue: fixture.uuid(index + 100)
                ),
                sessionID: fixture.sessionID,
                graphScope: fixture.graphScope,
                title: "Artifact \(index)",
                payload: payload,
                evidence: fixture.evidence,
                navigationTargets: [fixture.openTarget]
            )
        }

        requireSendable(payloads)
        requireSendable(artifacts)
        #expect(Set(artifacts.map(\.kind)) == Set(GraphChatAnswerArtifactKind.allCases))
    }

    @Test
    func typedValuesPreserveTheirSemanticTypesWithoutStringReduction() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 123_456.75)
        let values: [GraphChatAnswerArtifactValue] = [
            .text("42"),
            .integer(42),
            .decimal(Decimal(string: "42.125")!),
            .boolean(true),
            .date(timestamp),
            .dateTime(timestamp),
            .duration(3_600.5),
            .percentage(Decimal(string: "0.875")!),
            .choice(GraphChatAnswerArtifactChoiceValue(value: "open", label: "Open")),
            .missing,
        ]

        #expect(values[0] == .text("42"))
        #expect(values[1] == .integer(42))
        #expect(values[2] == .decimal(Decimal(string: "42.125")!))
        #expect(values[4] == .date(timestamp))
        #expect(values[5] == .dateTime(timestamp))
        #expect(values[6] == .duration(3_600.5))
        #expect(values[7] == .percentage(Decimal(string: "0.875")!))
        #expect(values[9] == .missing)
        #expect(GraphChatAnswerArtifactValue.missing != .text(""))
    }

    @Test
    func queryCellConversionKeepsMissingAndTypedNumbersDistinct() {
        let decimal = GraphChatAnswerArtifactValue(
            queryValue: .decimal(12.75)
        )
        let missing = GraphChatAnswerArtifactValue(queryValue: .missing)
        let emptyText = GraphChatAnswerArtifactValue(queryValue: .text(""))

        #expect(decimal == .decimal(Decimal(12.75)))
        #expect(missing == .missing)
        #expect(missing != emptyText)
    }

    @Test
    func resultCountAndTruncationAreModeledIndependently() {
        let metadata = GraphChatAnswerArtifactResultMetadata(
            resultCount: 125,
            returnedCount: 50,
            truncation: GraphChatAnswerArtifactTruncation(
                isTruncated: true,
                omittedCount: 75,
                reason: .queryLimit
            )
        )

        #expect(metadata.resultCount == 125)
        #expect(metadata.returnedCount == 50)
        #expect(metadata.truncation.isTruncated)
        #expect(metadata.truncation.omittedCount == 75)
        #expect(metadata.truncation.reason == .queryLimit)
    }

    @Test
    func resultMetadataNormalizesImpossibleCountsAndCompleteTruncationDetails() {
        let metadata = GraphChatAnswerArtifactResultMetadata(
            resultCount: 1,
            returnedCount: 3,
            truncation: GraphChatAnswerArtifactTruncation(
                isTruncated: false,
                omittedCount: 9,
                reason: .sourceLimited
            )
        )

        #expect(metadata.resultCount == 3)
        #expect(metadata.returnedCount == 3)
        #expect(metadata.truncation.isTruncated == false)
        #expect(metadata.truncation.omittedCount == nil)
        #expect(metadata.truncation.reason == nil)
    }

    @Test
    func evidenceCanBeBoundAtArtifactRowAndCellLevel() {
        let fixture = ArtifactDomainFixture()
        let artifact = GraphChatAnswerArtifact(
            id: GraphChatAnswerArtifactID(rawValue: fixture.uuid(400)),
            sessionID: fixture.sessionID,
            graphScope: fixture.graphScope,
            title: "Evidence levels",
            payload: .table(fixture.tablePayload),
            evidence: fixture.evidence,
            navigationTargets: [fixture.openTarget]
        )

        guard case .table(let table) = artifact.payload else {
            Issue.record("Expected table payload")
            return
        }
        #expect(artifact.evidence.evidenceIDs == [fixture.evidenceID])
        #expect(table.rows[0].evidence.evidenceIDs == [fixture.evidenceID])
        #expect(table.rows[0].cells[0].evidence?.evidenceIDs == [fixture.evidenceID])
        #expect(artifact.allEvidenceIDs == [fixture.evidenceID])
    }

    @Test
    func everyNavigationTargetCarriesItsGraphScope() {
        let fixture = ArtifactDomainFixture()
        let node = fixture.node
        let targets: [GraphChatAnswerArtifactNavigationTarget] = [
            .openNode(graphScope: fixture.graphScope, node: node),
            .focusNodeInGraph(graphScope: fixture.graphScope, node: node),
            .openEntityList(
                graphScope: fixture.graphScope,
                entityID: fixture.uuid(2),
                filters: []
            ),
            .showResultNodes(
                graphScope: fixture.graphScope,
                title: "Results",
                nodes: [node]
            ),
            .openResultFilter(
                graphScope: fixture.graphScope,
                entityID: fixture.uuid(2),
                filters: [],
                resultNodes: [node]
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
            .compareNodes(graphScope: fixture.graphScope, nodes: [node]),
        ]

        #expect(targets.allSatisfy { $0.graphScope == fixture.graphScope })
    }

    @Test
    func workspaceActionsUseOnlyTheBoundedLoadedNodeSet() throws {
        let fixture = ArtifactDomainFixture()
        let nodes = (0..<170).map { index in
            NodeRefKey(kind: .attribute, id: fixture.uuid(index + 1_000))
        }
        let navigationTargets = (nodes + [nodes[0]]).map { node in
            GraphChatAnswerArtifactNavigationTarget.openNode(
                graphScope: fixture.graphScope,
                node: node
            )
        }
        let querySummary = GraphChatAnswerArtifactQuerySummary(
            language: .english,
            entityID: fixture.uuid(900),
            entityLabel: "Projects",
            filters: [],
            grouping: nil,
            sorting: [],
            projection: [],
            includesNodeIdentity: true,
            limit: 200,
            aggregation: nil,
            displayText: "Projects"
        )
        let artifact = GraphChatAnswerArtifact(
            id: GraphChatAnswerArtifactID(rawValue: fixture.uuid(901)),
            sessionID: fixture.sessionID,
            graphScope: fixture.graphScope,
            title: "Results",
            payload: .metric(fixture.metricPayload),
            evidence: fixture.evidence,
            navigationTargets: navigationTargets,
            querySummary: querySummary
        )

        let targets = artifact.workspaceNavigationTargets
        #expect(targets.count == 7)
        #expect(targets.allSatisfy { $0.graphScope == fixture.graphScope })

        let showTarget = try #require(
            targets.first { target in
                if case .showResultNodes = target { return true }
                return false
            })
        #expect(
            showTarget.nodeReferences == Array(nodes.prefix(GraphChatWorkspaceBudget.maximumActionNodes)))

        #expect(
            targets.contains { target in
                if case .openResultFilter(_, let entityID, _, let resultNodes) = target {
                    return entityID == querySummary.entityID
                        && resultNodes.count == GraphChatWorkspaceBudget.maximumActionNodes
                }
                return false
            })
        #expect(
            targets.contains { target in
                if case .highlightNodesInCanvas(_, let resultNodes) = target {
                    return resultNodes.count == GraphChatWorkspaceBudget.maximumActionNodes
                }
                return false
            })
        #expect(
            targets.contains { target in
                if case .clearCanvasHighlight = target { return true }
                return false
            })
        #expect(
            targets.contains { target in
                if case .addNodesToCanvasSelection(_, let resultNodes) = target {
                    return resultNodes.count == GraphChatWorkspaceBudget.maximumActionNodes
                }
                return false
            })
        #expect(
            targets.contains { target in
                if case .replaceCanvasSelection(_, let resultNodes) = target {
                    return resultNodes.count == GraphChatWorkspaceBudget.maximumActionNodes
                }
                return false
            })
        #expect(
            targets.contains { target in
                if case .compareNodes(_, let resultNodes) = target {
                    return resultNodes.count == GraphChatWorkspaceBudget.maximumActionNodes
                }
                return false
            })
    }

    @Test
    func artifactsWithoutNodeTargetsDoNotInventWorkspaceActions() {
        let fixture = ArtifactDomainFixture()
        let artifact = GraphChatAnswerArtifact(
            id: GraphChatAnswerArtifactID(rawValue: fixture.uuid(950)),
            sessionID: fixture.sessionID,
            graphScope: fixture.graphScope,
            title: "Count",
            payload: .metric(fixture.metricPayload),
            evidence: fixture.evidence,
            navigationTargets: []
        )

        #expect(artifact.workspaceNavigationTargets.isEmpty)
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

private struct ArtifactDomainFixture {
    let graphScope = GraphScope(
        graphID: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    )
    let sessionID = GraphChatAnswerArtifactSessionID(
        rawValue: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    )
    let evidenceID = GraphEvidenceID(
        rawValue: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
    )

    var node: NodeRefKey {
        NodeRefKey(kind: .attribute, id: uuid(4))
    }

    var evidence: GraphChatAnswerArtifactEvidenceBinding {
        GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [evidenceID])
    }

    var openTarget: GraphChatAnswerArtifactNavigationTarget {
        .openNode(graphScope: graphScope, node: node)
    }

    var metricPayload: GraphChatAnswerArtifactMetricPayload {
        GraphChatAnswerArtifactMetricPayload(
            title: "Count",
            value: .integer(4),
            unit: nil,
            contextDescription: "Validated scope",
            evidence: evidence
        )
    }

    var nodeProfilePayload:
        GraphChatAnswerArtifactNodeProfilePayload
    {
        let complete =
            GraphChatAnswerArtifactResultMetadata(
                resultCount: 1,
                returnedCount: 1
            )
        return GraphChatAnswerArtifactNodeProfilePayload(
            node: node,
            visibleName: "Gateway",
            displayName:
                "Services • Gateway",
            owner:
                GraphChatAnswerArtifactNodeProfileOwner(
                    label: "Services",
                    navigationTarget:
                        .openNode(
                            graphScope:
                                graphScope,
                            node:
                                NodeRefKey(
                                    kind:
                                        .entity,
                                    id:
                                        uuid(5)
                                )
                        )
                ),
            notes:
                GraphChatAnswerArtifactNodeProfileNotes(
                    text: "Public edge",
                    evidence: evidence
                ),
            detailValues: [
                GraphChatAnswerArtifactNodeProfileDetailValue(
                    id:
                        GraphChatAnswerArtifactItemID(
                            rawValue:
                                uuid(6)
                        ),
                    fieldID: uuid(7),
                    fieldName: "Port",
                    fieldType:
                        .numberInt,
                    value: .integer(443),
                    unit: nil,
                    evidence: evidence
                ),
            ],
            incomingConnections: [],
            outgoingConnections: [
                GraphChatAnswerArtifactNodeProfileConnection(
                    id:
                        GraphChatAnswerArtifactItemID(
                            rawValue:
                                uuid(8)
                        ),
                    direction: .outgoing,
                    sourceLabel:
                        "Services • Gateway",
                    targetLabel:
                        "Services • Backend",
                    counterpartLabel:
                        "Services • Backend",
                    counterpartNavigationTarget:
                        openTarget,
                    note: "TLS",
                    evidence: evidence
                ),
            ],
            attachments: [
                GraphChatAnswerArtifactNodeProfileAttachment(
                    id:
                        GraphChatAnswerArtifactItemID(
                            rawValue:
                                uuid(9)
                        ),
                    contentKind: .file,
                    title: "Runbook",
                    originalFilename:
                        "runbook.pdf",
                    contentTypeIdentifier:
                        "com.adobe.pdf",
                    fileExtension: "pdf",
                    byteCount: 1_024,
                    evidence: evidence
                ),
            ],
            detailValueMetadata: complete,
            incomingConnectionMetadata:
                GraphChatAnswerArtifactResultMetadata(
                    resultCount: 0,
                    returnedCount: 0
                ),
            outgoingConnectionMetadata:
                complete,
            attachmentMetadata:
                complete,
            nodeNavigationTarget:
                openTarget,
            identityEvidence: evidence,
            evidence: evidence
        )
    }

    var listPayload: GraphChatAnswerArtifactResultListPayload {
        GraphChatAnswerArtifactResultListPayload(
            title: "Results",
            rows: [
                GraphChatAnswerArtifactListRow(
                    id: GraphChatAnswerArtifactItemID(rawValue: uuid(10)),
                    primaryText: "Primary",
                    secondaryText: "Secondary",
                    navigationTargets: [openTarget],
                    evidence: evidence
                )
            ],
            resultMetadata: GraphChatAnswerArtifactResultMetadata(
                resultCount: 1,
                returnedCount: 1
            ),
            evidence: evidence
        )
    }

    var tablePayload: GraphChatAnswerArtifactTablePayload {
        let columnID = GraphChatAnswerArtifactItemID(rawValue: uuid(20))
        return GraphChatAnswerArtifactTablePayload(
            title: "Table",
            columns: [
                GraphChatAnswerArtifactTableColumn(
                    id: columnID,
                    key: "value",
                    title: "Value",
                    role: .measure,
                    unit: nil
                )
            ],
            rows: [
                GraphChatAnswerArtifactTableRow(
                    id: GraphChatAnswerArtifactItemID(rawValue: uuid(21)),
                    cells: [
                        GraphChatAnswerArtifactTableCell(
                            columnID: columnID,
                            value: .decimal(Decimal(string: "12.5")!),
                            evidence: evidence
                        )
                    ],
                    navigationTarget: openTarget,
                    evidence: evidence
                )
            ],
            sorting: [
                GraphChatAnswerArtifactSortDescriptor(
                    columnID: columnID,
                    direction: .descending
                )
            ],
            resultMetadata: GraphChatAnswerArtifactResultMetadata(
                resultCount: 1,
                returnedCount: 1
            ),
            evidence: evidence
        )
    }

    var rankingPayload: GraphChatAnswerArtifactRankingPayload {
        GraphChatAnswerArtifactRankingPayload(
            title: "Ranking",
            entries: [
                GraphChatAnswerArtifactRankingEntry(
                    id: GraphChatAnswerArtifactItemID(rawValue: uuid(30)),
                    rank: 1,
                    label: "First",
                    value: .integer(10),
                    share: .percentage(Decimal(string: "0.5")!),
                    navigationTarget: openTarget,
                    evidence: evidence
                )
            ],
            resultMetadata: GraphChatAnswerArtifactResultMetadata(
                resultCount: 1,
                returnedCount: 1
            ),
            evidence: evidence
        )
    }

    var groupingPayload: GraphChatAnswerArtifactGroupingPayload {
        GraphChatAnswerArtifactGroupingPayload(
            title: "Grouping",
            groups: [
                GraphChatAnswerArtifactGroupingEntry(
                    id: GraphChatAnswerArtifactItemID(rawValue: uuid(40)),
                    groupKey: .choice(
                        GraphChatAnswerArtifactChoiceValue(value: "open")
                    ),
                    label: "Open",
                    count: 3,
                    share: .percentage(Decimal(string: "0.75")!),
                    includedResultReferences: [
                        GraphChatAnswerArtifactItemID(rawValue: uuid(41))
                    ],
                    navigationTarget: openTarget,
                    evidence: evidence
                )
            ],
            resultMetadata: GraphChatAnswerArtifactResultMetadata(
                resultCount: 1,
                returnedCount: 1
            ),
            evidence: evidence
        )
    }

    var comparisonPayload: GraphChatAnswerArtifactComparisonPayload {
        let subjectID = GraphChatAnswerArtifactItemID(rawValue: uuid(50))
        let featureID = GraphChatAnswerArtifactItemID(rawValue: uuid(51))
        return GraphChatAnswerArtifactComparisonPayload(
            title: "Comparison",
            subjects: [
                GraphChatAnswerArtifactComparisonSubject(
                    id: subjectID,
                    label: "Subject",
                    navigationTarget: openTarget,
                    evidence: evidence
                )
            ],
            features: [
                GraphChatAnswerArtifactComparisonFeature(
                    id: featureID,
                    key: "deadline",
                    label: "Deadline",
                    unit: nil,
                    evidence: evidence
                )
            ],
            values: [
                GraphChatAnswerArtifactComparisonValue(
                    subjectID: subjectID,
                    featureID: featureID,
                    value: .missing,
                    evidence: evidence
                )
            ],
            evidence: evidence
        )
    }

    var healthPayload: GraphChatAnswerArtifactHealthFindingPayload {
        GraphChatAnswerArtifactHealthFindingPayload(
            findingType: .missingRequiredValues,
            severity: .warning,
            summary: "Missing values",
            affectedElementCount: 1,
            affectedNodes: [node],
            evidence: evidence,
            navigationTargets: [openTarget]
        )
    }

    var timelinePayload: GraphChatAnswerArtifactTimelinePayload {
        GraphChatAnswerArtifactTimelinePayload(
            title: "Timeline",
            entries: [
                GraphChatAnswerArtifactTimelineEntry(
                    id: GraphChatAnswerArtifactItemID(rawValue: uuid(60)),
                    interval: GraphChatAnswerArtifactTimeInterval(
                        start: Date(timeIntervalSinceReferenceDate: 10),
                        end: Date(timeIntervalSinceReferenceDate: 20)
                    ),
                    title: "Period",
                    value: .duration(10),
                    resultReferences: [
                        GraphChatAnswerArtifactItemID(rawValue: uuid(61))
                    ],
                    navigationTarget: openTarget,
                    evidence: evidence
                )
            ],
            resultMetadata: GraphChatAnswerArtifactResultMetadata(
                resultCount: 1,
                returnedCount: 1
            ),
            evidence: evidence
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "A0000000-0000-0000-0000-%012d", suffix))!
    }
}
