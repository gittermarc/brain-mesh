import Foundation
import Testing
@testable import BrainMesh

struct GraphChatAnswerArtifactFactoryTests {
    @Test
    func countMinimumAndMaximumMapToMetrics() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let countDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    aggregation: GraphChatAggregationResult(
                        kind: .count,
                        fieldID: nil,
                        fieldName: nil,
                        count: 7,
                        groups: [],
                        value: nil,
                        evidenceIDs: [evidenceID(1)]
                    )
                ),
                plan: plan(context: context, aggregation: .count),
                schemaContext: context,
                language: .english
            )
        )
        guard case .metric(let count) = countDraft.payload else {
            Issue.record("Expected count metric")
            return
        }
        #expect(count.value == .integer(7))
        #expect(countDraft.querySummary?.entityLabel == "Projekte")

        let budgetFieldID = fieldID("F4", in: context)
        let minimumDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    aggregation: GraphChatAggregationResult(
                        kind: .minimum,
                        fieldID: budgetFieldID,
                        fieldName: "Budget",
                        count: nil,
                        groups: [],
                        value: .decimal(12.5),
                        evidenceIDs: [evidenceID(2)]
                    )
                ),
                plan: plan(context: context, aggregation: .minimum(budgetFieldID)),
                schemaContext: context
            )
        )
        guard case .metric(let minimum) = minimumDraft.payload else {
            Issue.record("Expected minimum metric")
            return
        }
        #expect(minimum.value == .decimal(Decimal(12.5)))
        #expect(minimum.unit == "EUR")

        let maximumDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    aggregation: GraphChatAggregationResult(
                        kind: .maximum,
                        fieldID: budgetFieldID,
                        fieldName: "Budget",
                        count: nil,
                        groups: [],
                        value: .decimal(99.5),
                        evidenceIDs: [evidenceID(3)]
                    )
                ),
                plan: plan(context: context, aggregation: .maximum(budgetFieldID)),
                schemaContext: context
            )
        )
        guard case .metric(let maximum) = maximumDraft.payload else {
            Issue.record("Expected maximum metric")
            return
        }
        #expect(maximum.value == .decimal(Decimal(99.5)))
        #expect(maximum.unit == "EUR")
    }

    @Test
    func multipleProjectedFieldsMapToStableTypedTable() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let titleID = fieldID("F1", in: context)
        let budgetID = fieldID("F4", in: context)
        let dueDateID = fieldID("F5", in: context)
        let statusID = fieldID("F7", in: context)
        let row = GraphChatQueryResultRow(
            node: NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
            label: "Project One",
            cells: [
                cell(fieldID: statusID, name: "Status", value: .choice("Offen"), index: 1),
                cell(fieldID: titleID, name: "Titel", value: .missing, index: 2),
                cell(fieldID: dueDateID, name: "Fällig", value: .date(Date(timeIntervalSince1970: 1_735_732_800)), index: 3),
                cell(fieldID: budgetID, name: "Budget", unit: "EUR", value: .decimal(12.5), index: 4)
            ],
            evidenceIDs: [evidenceID(20)]
        )
        let queryPlan = plan(
            context: context,
            sorting: [GraphValidatedQuerySort(key: .field(dueDateID), direction: .descending)],
            projection: [
                .nodeIdentity,
                .field(titleID),
                .field(budgetID),
                .field(dueDateID),
                .field(statusID)
            ]
        )
        let draft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(rows: [row]),
                plan: queryPlan,
                schemaContext: context,
                language: .german
            )
        )
        guard case .table(let table) = draft.payload else {
            Issue.record("Expected table artifact")
            return
        }

        #expect(table.columns.map(\.title) == ["Name", "Titel", "Budget", "Fällig", "Status"])
        #expect(table.columns.map(\.role) == [.primary, .secondary, .measure, .date, .status])
        #expect(table.columns[3].valuePresentation.dateFormat == .localizedDate)
        #expect(table.columns[4].valuePresentation.choiceLabels.map(\.label) == ["Offen", "In Arbeit", "Fertig"])
        #expect(table.rows.first?.cells.map(\.value) == [
            .text("Project One"),
            .missing,
            .decimal(Decimal(12.5)),
            .date(Date(timeIntervalSince1970: 1_735_732_800)),
            .choice(GraphChatAnswerArtifactChoiceValue(value: "Offen"))
        ])
        #expect(table.sorting == [
            GraphChatAnswerArtifactSortDescriptor(
                columnID: GraphChatAnswerArtifactItemID(rawValue: dueDateID),
                direction: .descending
            )
        ])
        #expect(table.resultMetadata.isComplete)
    }

    @Test
    func simpleHitsMapToResultListAndDatedHitsMapToTimeline() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let titleID = fieldID("F1", in: context)
        let dateID = fieldID("F5", in: context)
        let rows = [
            row(id: uuid(101), label: "Alpha", cells: [cell(fieldID: titleID, name: "Titel", value: .text("A"), index: 101)]),
            row(id: uuid(102), label: "Beta", cells: [cell(fieldID: titleID, name: "Titel", value: .text("B"), index: 102)])
        ]
        let listDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(rows: rows),
                plan: plan(context: context, projection: [.nodeIdentity, .field(titleID)]),
                schemaContext: context
            )
        )
        guard case .resultList(let list) = listDraft.payload else {
            Issue.record("Expected result list")
            return
        }
        #expect(list.rows.map(\.primaryText) == ["Alpha", "Beta"])
        #expect(list.rows.map(\.secondaryText) == ["Titel: A", "Titel: B"])

        let timelineRows = [
            row(id: uuid(103), label: "January", cells: [cell(fieldID: dateID, name: "Fällig", value: .date(Date(timeIntervalSince1970: 1_735_732_800)), index: 103)]),
            row(id: uuid(104), label: "February", cells: [cell(fieldID: dateID, name: "Fällig", value: .date(Date(timeIntervalSince1970: 1_738_411_200)), index: 104)])
        ]
        let timelineDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(rows: timelineRows),
                plan: plan(
                    context: context,
                    sorting: [GraphValidatedQuerySort(key: .field(dateID), direction: .ascending)],
                    projection: [.nodeIdentity, .field(dateID)]
                ),
                schemaContext: context
            )
        )
        guard case .timeline(let timeline) = timelineDraft.payload else {
            Issue.record("Expected timeline")
            return
        }
        #expect(timeline.entries.map(\.title) == ["January", "February"])
        #expect(timeline.entries.map(\.interval.start) == [
            Date(timeIntervalSince1970: 1_735_732_800),
            Date(timeIntervalSince1970: 1_738_411_200)
        ])
    }

    @Test
    func groupCountMapsToGroupingAndStatsHubsMapToRanking() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let statusID = fieldID("F7", in: context)
        let aggregation = GraphChatAggregationResult(
            kind: .groupCount,
            fieldID: statusID,
            fieldName: "Status",
            count: nil,
            groups: [
                GraphChatGroupCount(value: .choice("Offen"), count: 4, evidenceIDs: [evidenceID(201)]),
                GraphChatGroupCount(value: .choice("Fertig"), count: 2, evidenceIDs: [evidenceID(202)])
            ],
            value: nil,
            evidenceIDs: [evidenceID(201), evidenceID(202)]
        )
        let groupingDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    aggregation: aggregation,
                    resultWindow: .complete(totalCount: 2)
                ),
                plan: plan(context: context, aggregation: .groupCount(statusID)),
                schemaContext: context
            )
        )
        guard case .grouping(let grouping) = groupingDraft.payload else {
            Issue.record("Expected grouping")
            return
        }
        #expect(grouping.groups.map(\.count) == [4, 2])
        #expect(grouping.groups.map(\.label) == ["Offen", "Fertig"])

        let graphEvidenceID = evidenceID(203)
        let statsDrafts = GraphChatAnswerArtifactFactory.statistics(
            output: GraphStatsOutput(
                counts: GraphChatStatsCounts(
                    entities: 2,
                    attributes: 4,
                    links: 6,
                    notes: 0,
                    attachments: 0,
                    images: 0,
                    attachmentBytes: 0
                ),
                nodeCount: 6,
                linkCount: 6,
                isolatedNodeCount: 1,
                hubs: [
                    GraphChatStatsHub(
                        node: NodeRefKey(kind: .attribute, id: uuid(205)),
                        label: "Hub A",
                        degree: 5,
                        evidenceID: evidenceID(205)
                    ),
                    GraphChatStatsHub(
                        node: NodeRefKey(kind: .attribute, id: uuid(206)),
                        label: "Hub B",
                        degree: 3,
                        evidenceID: evidenceID(206)
                    )
                ],
                healthScore: 72,
                healthIssueCount: 2,
                evidenceIDs: [graphEvidenceID, evidenceID(205), evidenceID(206)]
            ),
            graphScope: context.graphScope,
            requestedHubLimit: 10
        )
        let rankingDraft = try #require(statsDrafts.first { $0.payload.kind == .ranking })
        guard case .ranking(let ranking) = rankingDraft.payload else {
            Issue.record("Expected ranking")
            return
        }
        #expect(ranking.entries.map(\.rank) == [1, 2])
        #expect(ranking.entries.map(\.value) == [.integer(5), .integer(3)])
        #expect(statsDrafts.map { $0.payload.kind } == [.metric, .ranking, .healthFinding])
    }

    @Test
    func resultMetadataSeparatesTotalsReturnedRowsAndAllLimitSources() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let titleID = fieldID("F1", in: context)
        let rows = (0..<5).map { index in
            row(
                id: uuid(300 + index),
                label: "Row \(index)",
                cells: [cell(fieldID: titleID, name: "Titel", value: .text("Value \(index)"), index: 300 + index)]
            )
        }
        let queryDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    rows: rows,
                    resultWindow: GraphChatResultWindow(
                        totalCount: 10,
                        returnedCount: 5,
                        limit: 5,
                        limitReached: true,
                        limitSources: [.query]
                    )
                ),
                plan: plan(context: context, projection: [.nodeIdentity, .field(titleID)], limit: 5),
                schemaContext: context,
                budget: GraphChatAnswerArtifactFactoryBudget(maximumRows: 3, maximumColumns: 12)
            )
        )
        guard case .resultList(let list) = queryDraft.payload else {
            Issue.record("Expected result list")
            return
        }
        #expect(list.resultMetadata.totalCount == 10)
        #expect(list.resultMetadata.returnedCount == 3)
        #expect(list.resultMetadata.truncation.reasons == [.queryLimit, .uiLimit])
        #expect(list.resultMetadata.truncation.omittedCount == 7)
        #expect(list.resultMetadata.isComplete == false)

        let searchDraft = try #require(
            GraphChatAnswerArtifactFactory.searchResults(
                output: SearchGraphOutput(
                    query: "alpha",
                    hits: (0..<5).map { searchHit(index: 400 + $0, graphID: context.graphScope.graphID) },
                    resultWindow: .unknown(
                        returnedCount: 5,
                        limit: 5,
                        limitReached: true,
                        limitSource: .tool
                    )
                ),
                graphScope: context.graphScope,
                requestedLimit: 5,
                budget: GraphChatAnswerArtifactFactoryBudget(maximumRows: 3, maximumColumns: 12)
            )
        )
        guard case .resultList(let searchList) = searchDraft.payload else {
            Issue.record("Expected search list")
            return
        }
        #expect(searchList.resultMetadata.totalCount == nil)
        #expect(searchList.resultMetadata.returnedCount == 3)
        #expect(searchList.resultMetadata.truncation.reasons == [.toolLimit, .uiLimit])
        #expect(searchList.resultMetadata.truncation.omittedCount == nil)
        #expect(searchList.resultMetadata.totalCountIsKnown == false)
    }

    @Test
    func completeUnknownEmptyAndColumnLimitedResultsRemainDistinct() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let titleID = fieldID("F1", in: context)
        let descriptionID = fieldID("F2", in: context)
        let budgetID = fieldID("F4", in: context)
        let completeDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    rows: [row(id: uuid(501), label: "Only", cells: [])],
                    resultWindow: .complete(totalCount: 1)
                ),
                plan: plan(context: context),
                schemaContext: context
            )
        )
        guard case .resultList(let completeList) = completeDraft.payload else {
            Issue.record("Expected complete result list")
            return
        }
        #expect(completeList.resultMetadata.isComplete)
        #expect(completeList.resultMetadata.truncation == .complete)

        let emptyDraft = GraphChatAnswerArtifactFactory.queryResult(
            queryResult(rows: [], resultWindow: .complete(totalCount: 0)),
            plan: plan(context: context),
            schemaContext: context
        )
        #expect(emptyDraft == nil)

        let tableDraft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                queryResult(
                    rows: [
                        row(
                            id: uuid(502),
                            label: "Limited columns",
                            cells: [
                                cell(fieldID: titleID, name: "Titel", value: .text("A"), index: 502),
                                cell(fieldID: descriptionID, name: "Beschreibung", value: .text("B"), index: 503),
                                cell(fieldID: budgetID, name: "Budget", value: .decimal(1), index: 504)
                            ]
                        )
                    ]
                ),
                plan: plan(
                    context: context,
                    projection: [.nodeIdentity, .field(titleID), .field(descriptionID), .field(budgetID)]
                ),
                schemaContext: context,
                budget: GraphChatAnswerArtifactFactoryBudget(maximumRows: 50, maximumColumns: 3)
            )
        )
        guard case .table(let table) = tableDraft.payload else {
            Issue.record("Expected table")
            return
        }
        #expect(table.columns.count == 3)
        #expect(table.resultMetadata.totalCount == 1)
        #expect(table.resultMetadata.returnedCount == 1)
        #expect(table.resultMetadata.truncation.reasons == [.uiLimit])
        #expect(table.resultMetadata.truncation.omittedCount == 0)
        #expect(table.resultMetadata.truncation.omittedColumnCount == 1)
    }

    @Test
    func querySummaryIsDeterministicAndLocalizedForFiltersSortingProjectionAndGrouping() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let titleID = fieldID("F1", in: context)
        let dueDateID = fieldID("F5", in: context)
        let statusID = fieldID("F7", in: context)
        let queryPlan = plan(
            context: context,
            filters: [
                GraphValidatedQueryFilter(
                    fieldID: titleID,
                    fieldType: .singleLineText,
                    operation: .contains,
                    value: .text("Alpha")
                ),
                GraphValidatedQueryFilter(
                    fieldID: statusID,
                    fieldType: .singleChoice,
                    operation: .oneOf,
                    value: .choices([
                        GraphResolvedChoiceValue(originalValue: "open", canonicalValue: "Offen"),
                        GraphResolvedChoiceValue(originalValue: "done", canonicalValue: "Fertig")
                    ])
                )
            ],
            sorting: [GraphValidatedQuerySort(key: .field(dueDateID), direction: .descending)],
            projection: [.nodeIdentity, .field(titleID), .field(dueDateID)],
            aggregation: .groupCount(statusID),
            limit: 25
        )

        let german = GraphChatAnswerArtifactFactory.querySummary(
            plan: queryPlan,
            schemaContext: context,
            language: .german
        )
        #expect(german.entityLabel == "Projekte")
        #expect(german.filters.map(\.operationLabel) == ["enthält", "ist einer von"])
        #expect(german.filters[1].values == [
            .choice(GraphChatAnswerArtifactChoiceValue(value: "Offen")),
            .choice(GraphChatAnswerArtifactChoiceValue(value: "Fertig"))
        ])
        #expect(german.grouping?.label == "Status")
        #expect(german.sorting.map(\.directionLabel) == ["absteigend"])
        #expect(german.projection.map(\.label) == ["Titel", "Fällig"])
        #expect(german.includesNodeIdentity)
        #expect(german.limit == 25)
        #expect(german.displayText.contains("Entity: Projekte"))
        #expect(german.displayText.contains("Filter: Titel enthält Alpha"))
        #expect(german.displayText.contains("Gruppierung: Status"))
        #expect(german.displayText.contains("Sortierung: Fällig absteigend"))
        #expect(german.displayText.contains("Projektion: Name, Titel, Fällig"))
        #expect(german.displayText.contains("Aggregation: Gruppierte Anzahl: Status"))

        let english = GraphChatAnswerArtifactFactory.querySummary(
            plan: queryPlan,
            schemaContext: context,
            language: .english
        )
        #expect(english.filters.map(\.operationLabel) == ["contains", "is one of"])
        #expect(english.sorting.map(\.directionLabel) == ["descending"])
        #expect(english.displayText.contains("Filters: Title") == false)
        #expect(english.displayText.contains("Filters: Titel contains Alpha"))
        #expect(english.displayText.contains("Grouping: Status"))
        #expect(english.displayText.contains("Aggregation: Grouped count: Status"))
    }

    @Test
    func querySummaryRepresentsEverySupportedAggregation() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let budgetID = fieldID("F4", in: context)
        let statusID = fieldID("F7", in: context)
        let summaries = [
            GraphChatAnswerArtifactFactory.querySummary(
                plan: plan(context: context, aggregation: .count),
                schemaContext: context,
                language: .english
            ),
            GraphChatAnswerArtifactFactory.querySummary(
                plan: plan(context: context, aggregation: .minimum(budgetID)),
                schemaContext: context,
                language: .english
            ),
            GraphChatAnswerArtifactFactory.querySummary(
                plan: plan(context: context, aggregation: .maximum(budgetID)),
                schemaContext: context,
                language: .english
            ),
            GraphChatAnswerArtifactFactory.querySummary(
                plan: plan(context: context, aggregation: .groupCount(statusID)),
                schemaContext: context,
                language: .english
            )
        ]

        guard let countAggregation = summaries[0].aggregation,
              let minimumAggregation = summaries[1].aggregation,
              let maximumAggregation = summaries[2].aggregation,
              let groupAggregation = summaries[3].aggregation,
              case .count = countAggregation,
              case .minimum(let minimumField, _) = minimumAggregation,
              case .maximum(let maximumField, _) = maximumAggregation,
              case .groupCount(let groupField, _) = groupAggregation else {
            Issue.record("Expected all Query Plan v1 aggregations")
            return
        }
        #expect(minimumField.label == "Budget")
        #expect(maximumField.label == "Budget")
        #expect(groupField.label == "Status")
    }

    @Test
    func schemaSearchNodeNeighborStatsAndHealthOutputsMapWithoutSyntheticEmptyCards() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let schemaEvidenceID = evidenceID(601)
        let schemaDraft = try #require(
            GraphChatAnswerArtifactFactory.schemaOverview(
                output: DescribeGraphSchemaOutput(snapshot: context.snapshot),
                schemaContext: context,
                evidenceIDs: [schemaEvidenceID]
            )
        )
        #expect(schemaDraft.payload.kind == .table)

        let searchDraft = try #require(
            GraphChatAnswerArtifactFactory.searchResults(
                output: SearchGraphOutput(
                    query: "alpha",
                    hits: [searchHit(index: 602, graphID: context.graphScope.graphID)]
                ),
                graphScope: context.graphScope,
                requestedLimit: 10
            )
        )
        #expect(searchDraft.payload.kind == .resultList)

        let detailFieldID = fieldID("F4", in: context)
        let nodeEvidenceID = evidenceID(603)
        let nodeDraft = try #require(
            GraphChatAnswerArtifactFactory.nodeDetails(
                output: GetNodeOutput(
                    node: NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
                    label: "Project One",
                    notes: "",
                    owner: GraphChatNodeOwner(entityID: GraphChatTestSupport.projectEntityID, label: "Projekte"),
                    detailValues: [
                        GraphChatNodeDetailValue(
                            valueID: uuid(603),
                            fieldID: detailFieldID,
                            fieldName: "Budget",
                            fieldType: .numberDouble,
                            unit: "EUR",
                            value: .decimal(12.5),
                            evidenceID: evidenceID(604)
                        )
                    ],
                    links: [],
                    attachments: [],
                    evidenceIDs: [nodeEvidenceID, evidenceID(604)]
                ),
                graphScope: context.graphScope
            )
        )
        #expect(nodeDraft.payload.kind == .table)

        let neighborNode = NodeRefKey(kind: .attribute, id: uuid(605))
        let neighborDraft = try #require(
            GraphChatAnswerArtifactFactory.neighbors(
                output: GetNeighborsOutput(
                    center: GraphNodeSummaryDTO(
                        scope: context.graphScope,
                        nodeKey: NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
                        label: "Project One",
                        notes: "",
                        iconSymbolName: nil,
                        ownerEntityID: GraphChatTestSupport.projectEntityID,
                        ownerLabel: "Projekte"
                    ),
                    connections: [
                        GraphChatNeighborConnection(
                            id: uuid(606),
                            direction: .outgoing,
                            neighbor: neighborNode,
                            neighborLabel: "Project Two",
                            note: nil,
                            evidenceID: evidenceID(606)
                        )
                    ],
                    evidenceIDs: [evidenceID(607), evidenceID(606)]
                ),
                graphScope: context.graphScope,
                requestedLimit: 10
            )
        )
        #expect(neighborDraft.payload.kind == .resultList)

        let statsDrafts = GraphChatAnswerArtifactFactory.statistics(
            output: GraphStatsOutput(
                counts: GraphChatStatsCounts(
                    entities: 2,
                    attributes: 4,
                    links: 1,
                    notes: 0,
                    attachments: 0,
                    images: 0,
                    attachmentBytes: 0
                ),
                nodeCount: 6,
                linkCount: 1,
                isolatedNodeCount: 2,
                hubs: [
                    GraphChatStatsHub(
                        node: neighborNode,
                        label: "Project Two",
                        degree: 1,
                        evidenceID: evidenceID(608)
                    )
                ],
                healthScore: 40,
                healthIssueCount: 3,
                evidenceIDs: [evidenceID(609), evidenceID(608)]
            ),
            graphScope: context.graphScope,
            requestedHubLimit: 10
        )
        #expect(statsDrafts.map { $0.payload.kind } == [.metric, .ranking, .healthFinding])

        #expect(GraphChatAnswerArtifactFactory.searchResults(
            output: SearchGraphOutput(query: "none", hits: []),
            graphScope: context.graphScope,
            requestedLimit: 10
        ) == nil)
        #expect(GraphChatAnswerArtifactFactory.nodeDetails(
            output: GetNodeOutput(
                node: NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
                label: "No structured fields",
                notes: "Text remains available",
                owner: nil,
                detailValues: [],
                links: [],
                attachments: [],
                evidenceIDs: [evidenceID(610)]
            ),
            graphScope: context.graphScope
        ) == nil)
    }

    @Test
    func queryTableMapsEveryDetailFieldTypeToTheExpectedColumnRole() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let fieldFixtures: [(GraphFieldAlias, GraphChatQueryCellValue, GraphChatAnswerArtifactColumnRole)] = [
            (GraphFieldAlias("F1"), .text("Single line"), .secondary),
            (GraphFieldAlias("F2"), .text("Multi line"), .secondary),
            (GraphFieldAlias("F3"), .integer(3), .measure),
            (GraphFieldAlias("F4"), .decimal(12.5), .measure),
            (GraphFieldAlias("F5"), .date(Date(timeIntervalSince1970: 1_735_732_800)), .date),
            (GraphFieldAlias("F6"), .boolean(true), .status),
            (GraphFieldAlias("F7"), .choice("Offen"), .status)
        ]
        let cells = try fieldFixtures.enumerated().map { index, fixture in
            let resolution = try #require(context.aliases.field(for: fixture.0))
            return GraphChatQueryCell(
                fieldID: resolution.fieldID,
                fieldName: resolution.name,
                unit: resolution.unit,
                value: fixture.1,
                evidenceID: evidenceID(700 + index)
            )
        }
        let result = queryResult(
            rows: [
                GraphChatQueryResultRow(
                    node: NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
                    label: "Project One",
                    cells: cells,
                    evidenceIDs: [evidenceID(799)]
                )
            ]
        )
        let queryPlan = plan(
            context: context,
            projection: [.nodeIdentity] + cells.map { .field($0.fieldID) }
        )

        let draft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                result,
                plan: queryPlan,
                schemaContext: context
            )
        )
        guard case .table(let table) = draft.payload else {
            Issue.record("Expected table artifact")
            return
        }

        #expect(table.columns.first?.role == .primary)
        #expect(Array(table.columns.dropFirst().map(\.role)) == fieldFixtures.map { $0.2 })
    }

    private func plan(
        context: GraphSchemaContext,
        filters: [GraphValidatedQueryFilter] = [],
        sorting: [GraphValidatedQuerySort] = [],
        projection: [GraphValidatedProjection] = [.nodeIdentity],
        aggregation: GraphValidatedAggregation? = nil,
        limit: Int = 50
    ) -> ValidatedGraphQueryPlan {
        ValidatedGraphQueryPlan(
            version: 1,
            graphScope: context.graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: filters,
            sorting: sorting,
            projection: projection,
            aggregation: aggregation,
            limit: limit
        )
    }

    private func queryResult(
        rows: [GraphChatQueryResultRow] = [],
        aggregation: GraphChatAggregationResult? = nil,
        resultWindow: GraphChatResultWindow? = nil
    ) -> GraphChatQueryResult {
        GraphChatQueryResult(
            state: rows.isEmpty && aggregation == nil ? .noResults : .success,
            rows: rows,
            aggregation: aggregation,
            appliedFilters: [],
            evidence: [],
            resultWindow: resultWindow
        )
    }

    private func row(
        id: UUID,
        label: String,
        cells: [GraphChatQueryCell]
    ) -> GraphChatQueryResultRow {
        GraphChatQueryResultRow(
            node: NodeRefKey(kind: .attribute, id: id),
            label: label,
            cells: cells,
            evidenceIDs: [evidenceID(abs(id.hashValue % 10_000) + 10_000)]
        )
    }

    private func cell(
        fieldID: UUID,
        name: String,
        unit: String? = nil,
        value: GraphChatQueryCellValue,
        index: Int
    ) -> GraphChatQueryCell {
        GraphChatQueryCell(
            fieldID: fieldID,
            fieldName: name,
            unit: unit,
            value: value,
            evidenceID: evidenceID(index)
        )
    }

    private func fieldID(
        _ alias: String,
        in context: GraphSchemaContext
    ) -> UUID {
        context.aliases.field(for: GraphFieldAlias(alias))!.fieldID
    }

    private func searchHit(index: Int, graphID: UUID) -> GraphChatSearchHit {
        let sourceID = uuid(index)
        return GraphChatSearchHit(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: .attribute,
                sourceID: sourceID,
                node: GraphSourceNodeReference(kind: .attribute, id: sourceID)
            ),
            kind: .attribute,
            title: "Result \(index)",
            subtitle: "Projekte",
            matchReason: "Title",
            evidenceID: evidenceID(index)
        )
    }

    private func evidenceID(_ index: Int) -> GraphEvidenceID {
        GraphEvidenceID(rawValue: uuid(index))
    }

    private func uuid(_ index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "D0000000-0000-0000-0000-%012d",
                max(0, index)
            )
        )!
    }
}

private extension GraphChatAnswerArtifactPayload {
    var kind: GraphChatAnswerArtifactKind {
        switch self {
        case .metric:
            return .metric
        case .resultList:
            return .resultList
        case .table:
            return .table
        case .ranking:
            return .ranking
        case .grouping:
            return .grouping
        case .comparison:
            return .comparison
        case .healthFinding:
            return .healthFinding
        case .timeline:
            return .timeline
        }
    }
}
