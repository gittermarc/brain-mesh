import Foundation
import Testing
@testable import BrainMesh

private actor GraphChatQueryEngineRepositoryStub: GraphChatQueryReading {
    enum Mode: Sendable {
        case snapshot(GraphChatQuerySourceSnapshot)
        case delayed(GraphChatQuerySourceSnapshot)
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func graphChatQuerySource(
        entityID: UUID,
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) async throws -> GraphChatQuerySourceSnapshot? {
        switch mode {
        case .snapshot(let snapshot):
            return snapshot
        case .delayed(let snapshot):
            try await Task.sleep(for: .seconds(30))
            return snapshot
        }
    }
}

struct GraphChatQueryEngineTests {
    private struct Fixture {
        let graphScope: GraphScope
        let entity: GraphEntityDTO
        let attributes: [GraphAttributeDTO]
        let fields: [GraphDetailFieldDefinitionDTO]
        let values: [GraphDetailValueDTO]

        var snapshot: GraphChatQuerySourceSnapshot {
            GraphChatQuerySourceSnapshot(
                graphScope: graphScope,
                entity: entity,
                attributes: attributes,
                fields: fields,
                values: values
            )
        }
    }

    @Test
    func executesTypedFiltersAndPresenceOperators() async throws {
        let fixture = makeFixture()
        let cases: [(GraphValidatedQueryFilter, [UUID])] = [
            (
                filter(fixture, field: 0, type: .singleLineText, operation: .contains, value: .text("alpha")),
                [fixture.attributes[0].id]
            ),
            (
                filter(fixture, field: 2, type: .numberInt, operation: .greaterThan, value: .integer(7)),
                [fixture.attributes[1].id]
            ),
            (
                filter(fixture, field: 3, type: .numberDouble, operation: .lessThanOrEqual, value: .decimal(4.2)),
                [fixture.attributes[1].id]
            ),
            (
                filter(
                    fixture,
                    field: 4,
                    type: .date,
                    operation: .equals,
                    value: .dateInterval(
                        GraphQueryDateInterval(
                            lowerBound: date(2024, 1, 10),
                            upperBoundExclusive: date(2024, 1, 11)
                        )
                    )
                ),
                [fixture.attributes[0].id]
            ),
            (
                filter(
                    fixture,
                    field: 4,
                    type: .date,
                    operation: .inYear,
                    value: .dateInterval(
                        GraphQueryDateInterval(
                            lowerBound: date(2024, 1, 1),
                            upperBoundExclusive: date(2025, 1, 1)
                        )
                    )
                ),
                [fixture.attributes[0].id]
            ),
            (
                filter(fixture, field: 5, type: .toggle, operation: .equals, value: .boolean(false)),
                [fixture.attributes[1].id]
            ),
            (
                filter(
                    fixture,
                    field: 6,
                    type: .singleChoice,
                    operation: .equals,
                    value: .choice(
                        GraphResolvedChoiceValue(
                            originalValue: "hoch",
                            canonicalValue: "Hoch"
                        )
                    )
                ),
                [fixture.attributes[0].id]
            ),
            (
                filter(fixture, field: 1, type: .multiLineText, operation: .isPresent, value: .none),
                [fixture.attributes[0].id, fixture.attributes[1].id]
            ),
            (
                filter(fixture, field: 1, type: .multiLineText, operation: .isMissing, value: .none),
                [fixture.attributes[2].id]
            )
        ]

        for (queryFilter, expectedIDs) in cases {
            let result = try await makeEngine(fixture).execute(
                plan(
                    fixture,
                    filters: [queryFilter],
                    projection: [.nodeIdentity, .field(queryFilter.fieldID)]
                )
            )
            #expect(result.state == .success)
            #expect(result.rows.map(\.node.id) == expectedIDs)
            #expect(result.rows.allSatisfy { $0.evidenceIDs.isEmpty == false })
        }
    }

    @Test
    func executesAllAggregationsWithExplicitEvidence() async throws {
        let fixture = makeFixture()
        let engine = makeEngine(fixture)

        let count = try await engine.execute(
            plan(fixture, aggregation: .count)
        )
        #expect(count.aggregation?.kind == .count)
        #expect(count.aggregation?.count == 3)
        #expect(count.evidence.isEmpty == false)

        let grouped = try await engine.execute(
            plan(fixture, aggregation: .groupCount(fixture.fields[6].id))
        )
        #expect(grouped.aggregation?.groups.map(\.count).reduce(0, +) == 3)
        #expect(grouped.aggregation?.groups.contains { $0.value == .missing } == true)
        #expect(
            grouped.aggregation?.groups.allSatisfy {
                $0.memberNodes.count == $0.count
            } == true
        )
        #expect(grouped.evidence.isEmpty == false)

        let minimum = try await engine.execute(
            plan(fixture, aggregation: .minimum(fixture.fields[2].id))
        )
        #expect(minimum.aggregation?.value == .integer(5))
        #expect(minimum.aggregation?.evidenceIDs.isEmpty == false)

        let maximum = try await engine.execute(
            plan(fixture, aggregation: .maximum(fixture.fields[3].id))
        )
        #expect(maximum.aggregation?.value == .decimal(9.5))
        #expect(maximum.aggregation?.evidenceIDs.isEmpty == false)
    }

    @Test
    func aggregationLimitDoesNotChangeTheFilteredDataBasis() async throws {
        let fixture = makeFixture()
        let engine = makeEngine(fixture)

        let count = try await engine.execute(
            plan(fixture, aggregation: .count, limit: 1)
        )
        #expect(count.aggregation?.count == 3)
        #expect(count.evidence.count == 2)

        let grouped = try await engine.execute(
            plan(
                fixture,
                aggregation: .groupCount(fixture.fields[6].id),
                limit: 1
            )
        )
        #expect(grouped.aggregation?.count == 3)
        #expect(grouped.aggregation?.groups.count == 1)
        #expect(grouped.aggregation?.groups[0].evidenceIDs.isEmpty == false)
    }

    @Test
    func entityNodeAndSelectionScopesRemainDeterministic() async throws {
        let fixture = makeFixture()
        let engine = makeEngine(fixture)

        let entityResult = try await engine.execute(
            plan(fixture, scope: .entity(fixture.entity.id))
        )
        #expect(entityResult.rows.count == 3)

        let nodeResult = try await engine.execute(
            plan(
                fixture,
                scope: .node(fixture.attributes[1].nodeKey)
            )
        )
        #expect(nodeResult.rows.map(\.node) == [fixture.attributes[1].nodeKey])

        let selectionResult = try await engine.execute(
            plan(
                fixture,
                scope: .selection([
                    fixture.attributes[2].nodeKey,
                    fixture.attributes[0].nodeKey
                ])
            )
        )
        #expect(selectionResult.rows.map(\.node) == [
            fixture.attributes[0].nodeKey,
            fixture.attributes[2].nodeKey
        ])
    }

    @Test
    func descendingSortKeepsMissingValuesLastAndUsesIDTiebreaker() async throws {
        let fixture = makeFixture()
        let result = try await makeEngine(fixture).execute(
            plan(
                fixture,
                sorting: [
                    GraphValidatedQuerySort(
                        key: .field(fixture.fields[2].id),
                        direction: .descending
                    )
                ],
                projection: [.nodeIdentity, .field(fixture.fields[2].id)]
            )
        )

        #expect(result.rows.map(\.node.id) == [
            fixture.attributes[1].id,
            fixture.attributes[0].id,
            fixture.attributes[2].id
        ])
    }

    @Test
    func rejectsAValidatedPlanWhenItsFieldDefinitionBecameStale() async throws {
        let fixture = makeFixture()
        let staleSnapshot = GraphChatQuerySourceSnapshot(
            graphScope: fixture.graphScope,
            entity: fixture.entity,
            attributes: fixture.attributes,
            fields: Array(fixture.fields.dropFirst()),
            values: fixture.values.filter { $0.fieldID != fixture.fields[0].id }
        )
        let engine = GraphChatQueryEngine(
            repository: GraphChatQueryEngineRepositoryStub(mode: .snapshot(staleSnapshot)),
            evidenceValidator: PassthroughGraphEvidenceValidator()
        )
        let query = plan(
            fixture,
            filters: [
                filter(
                    fixture,
                    field: 0,
                    type: .singleLineText,
                    operation: .equals,
                    value: .text("Alpha Project")
                )
            ]
        )

        do {
            _ = try await engine.execute(query)
            Issue.record("Expected stale validated field rejection")
        } catch let error as GraphChatQueryEngineError {
            #expect(error == .sourceUnavailable)
        }
    }

    @Test
    func rejectsAValidatedChoiceFilterWhenTheOptionBecameStale() async throws {
        let fixture = makeFixture()
        let choiceField = fixture.fields[6]
        let staleChoiceField = GraphDetailFieldDefinitionDTO(
            id: choiceField.id,
            scope: choiceField.scope,
            entityID: choiceField.entityID,
            entityLabel: choiceField.entityLabel,
            name: choiceField.name,
            typeRaw: choiceField.typeRaw,
            sortIndex: choiceField.sortIndex,
            isPinned: choiceField.isPinned,
            unit: choiceField.unit,
            options: ["Niedrig"]
        )
        var fields = fixture.fields
        fields[6] = staleChoiceField
        let staleSnapshot = GraphChatQuerySourceSnapshot(
            graphScope: fixture.graphScope,
            entity: fixture.entity,
            attributes: fixture.attributes,
            fields: fields,
            values: fixture.values
        )
        let engine = GraphChatQueryEngine(
            repository: GraphChatQueryEngineRepositoryStub(mode: .snapshot(staleSnapshot)),
            evidenceValidator: PassthroughGraphEvidenceValidator()
        )
        let query = plan(
            fixture,
            filters: [
                filter(
                    fixture,
                    field: 6,
                    type: .singleChoice,
                    operation: .equals,
                    value: .choice(
                        GraphResolvedChoiceValue(
                            originalValue: "hoch",
                            canonicalValue: "Hoch"
                        )
                    )
                )
            ]
        )

        do {
            _ = try await engine.execute(query)
            Issue.record("Expected stale validated choice rejection")
        } catch let error as GraphChatQueryEngineError {
            #expect(error == .sourceUnavailable)
        }
    }

    @Test
    func rejectsForeignGraphSource() async throws {
        let fixture = makeFixture()
        let foreignSnapshot = GraphChatQuerySourceSnapshot(
            graphScope: GraphScope(graphID: UUID()),
            entity: fixture.entity,
            attributes: fixture.attributes,
            fields: fixture.fields,
            values: fixture.values
        )
        let engine = GraphChatQueryEngine(
            repository: GraphChatQueryEngineRepositoryStub(mode: .snapshot(foreignSnapshot)),
            evidenceValidator: PassthroughGraphEvidenceValidator()
        )

        do {
            _ = try await engine.execute(plan(fixture))
            Issue.record("Expected a graph-scope mismatch")
        } catch let error as GraphChatQueryEngineError {
            #expect(error == .graphScopeMismatch)
        }
    }

    @Test
    func cancellationStopsBetweenReadBatches() async throws {
        let fixture = makeFixture()
        let engine = GraphChatQueryEngine(
            repository: GraphChatQueryEngineRepositoryStub(mode: .delayed(fixture.snapshot)),
            evidenceValidator: PassthroughGraphEvidenceValidator()
        )
        let task = Task {
            try await engine.execute(plan(fixture))
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(Bool(true))
        }
    }

    @Test
    func emptyTypedMatchReturnsStructuredNoResults() async throws {
        let fixture = makeFixture()
        let result = try await makeEngine(fixture).execute(
            plan(
                fixture,
                filters: [
                    filter(
                        fixture,
                        field: 0,
                        type: .singleLineText,
                        operation: .equals,
                        value: .text("Does not exist")
                    )
                ]
            )
        )

        #expect(result.state == .noResults)
        #expect(result.rows.isEmpty)
        #expect(result.evidence.isEmpty)
    }

    @Test
    func queryPlanCannotBroadenActiveChatScope() throws {
        let fixture = makeFixture()
        let graphScope = fixture.graphScope
        let first = fixture.attributes[0].nodeKey
        let second = fixture.attributes[1].nodeKey
        let entityNode = fixture.entity.nodeKey

        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .graph),
                within: .entireGraph(graphScope)
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .graph),
                within: .entity(fixture.entity.id, in: graphScope)
            ) == false
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .node(first)),
                within: .entity(fixture.entity.id, in: graphScope)
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .entity(fixture.entity.id)),
                within: .node(first, in: graphScope)
            ) == false
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .node(first)),
                within: .node(first, in: graphScope)
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .node(second)),
                within: .node(first, in: graphScope)
            ) == false
        )

        let selectionScope = try GraphChatScope.selection([first, second], in: graphScope)
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .node(first)),
                within: selectionScope
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .selection([first, second])),
                within: selectionScope
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .entity(fixture.entity.id)),
                within: selectionScope
            ) == false
        )

        let entitySelection = try GraphChatScope.selection([entityNode], in: graphScope)
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture, scope: .entity(fixture.entity.id)),
                within: entitySelection
            )
        )

        let foreignScope = GraphChatScope.entireGraph(GraphScope(graphID: UUID()))
        #expect(
            GraphChatScopeAuthorization.allows(
                plan: plan(fixture),
                within: foreignScope
            ) == false
        )
    }

    private func makeEngine(_ fixture: Fixture) -> GraphChatQueryEngine {
        GraphChatQueryEngine(
            repository: GraphChatQueryEngineRepositoryStub(mode: .snapshot(fixture.snapshot)),
            evidenceValidator: PassthroughGraphEvidenceValidator()
        )
    }

    private func plan(
        _ fixture: Fixture,
        scope: GraphResolvedQueryScope = .graph,
        filters: [GraphValidatedQueryFilter] = [],
        sorting: [GraphValidatedQuerySort] = [
            GraphValidatedQuerySort(key: .nodeName, direction: .ascending)
        ],
        projection: [GraphValidatedProjection] = [.nodeIdentity],
        aggregation: GraphValidatedAggregation? = nil,
        limit: Int = 50
    ) -> ValidatedGraphQueryPlan {
        ValidatedGraphQueryPlan(
            version: GraphQueryPlan.currentVersion,
            graphScope: fixture.graphScope,
            entityID: fixture.entity.id,
            scope: scope,
            filters: filters,
            sorting: sorting,
            projection: projection,
            aggregation: aggregation,
            limit: limit
        )
    }

    private func filter(
        _ fixture: Fixture,
        field index: Int,
        type: DetailFieldType,
        operation: GraphQueryFilterOperator,
        value: GraphValidatedFilterValue
    ) -> GraphValidatedQueryFilter {
        GraphValidatedQueryFilter(
            fieldID: fixture.fields[index].id,
            fieldType: type,
            operation: operation,
            value: value
        )
    }

    private func makeFixture() -> Fixture {
        let graphScope = GraphScope(
            graphID: UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
        )
        let entity = GraphEntityDTO(
            id: UUID(uuidString: "72000000-0000-0000-0000-000000000001")!,
            scope: graphScope,
            name: "Projekte",
            notes: "",
            iconSymbolName: nil,
            createdAt: .distantPast
        )
        let attributes = [
            attribute("73000000-0000-0000-0000-000000000001", "Alpha", entity: entity),
            attribute("73000000-0000-0000-0000-000000000002", "Beta", entity: entity),
            attribute("73000000-0000-0000-0000-000000000003", "Gamma", entity: entity)
        ]
        let fieldTypes = DetailFieldType.allCases
        let fieldNames = ["Titel", "Notizen", "Punkte", "Budget", "Datum", "Aktiv", "Priorität"]
        let fields = fieldTypes.enumerated().map { index, type in
            GraphDetailFieldDefinitionDTO(
                id: UUID(uuidString: String(format: "74000000-0000-0000-0000-%012d", index + 1))!,
                scope: graphScope,
                entityID: entity.id,
                entityLabel: entity.name,
                name: fieldNames[index],
                typeRaw: type.rawValue,
                sortIndex: index,
                isPinned: index < 2,
                unit: type == .numberDouble ? "EUR" : nil,
                options: type == .singleChoice ? ["Niedrig", "Hoch"] : []
            )
        }
        let firstValues: [GraphDetailValuePayload] = [
            .text("Alpha Project"),
            .text("Critical notes"),
            .integer(5),
            .decimal(9.5),
            .date(date(2024, 1, 10)),
            .boolean(true),
            .choice("Hoch")
        ]
        let secondValues: [GraphDetailValuePayload] = [
            .text("Beta Project"),
            .text("Routine"),
            .integer(10),
            .decimal(4.2),
            .date(date(2025, 1, 1)),
            .boolean(false),
            .choice("Niedrig")
        ]
        var values: [GraphDetailValueDTO] = []
        for (attributeIndex, payloads) in [firstValues, secondValues].enumerated() {
            for (fieldIndex, payload) in payloads.enumerated() {
                values.append(
                    GraphDetailValueDTO(
                        id: UUID(
                            uuidString: String(
                                format: "75000000-0000-0000-%04d-%012d",
                                attributeIndex + 1,
                                fieldIndex + 1
                            )
                        )!,
                        scope: graphScope,
                        attributeID: attributes[attributeIndex].id,
                        attributeLabel: attributes[attributeIndex].displayLabel,
                        fieldID: fields[fieldIndex].id,
                        fieldName: fields[fieldIndex].name,
                        fieldTypeRaw: fields[fieldIndex].typeRaw,
                        value: payload
                    )
                )
            }
        }
        return Fixture(
            graphScope: graphScope,
            entity: entity,
            attributes: attributes,
            fields: fields,
            values: values
        )
    }

    private func attribute(
        _ id: String,
        _ name: String,
        entity: GraphEntityDTO
    ) -> GraphAttributeDTO {
        GraphAttributeDTO(
            id: UUID(uuidString: id)!,
            scope: entity.scope,
            ownerEntityID: entity.id,
            ownerLabel: entity.name,
            name: name,
            displayLabel: "\(entity.name) · \(name)",
            notes: "",
            iconSymbolName: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
    }
}
