import Foundation
import Testing
@testable import BrainMesh

struct GraphChatTravelScenarioTests {
    @Test
    func year2024ReturnsOnlyTypedTravelDatesWithFieldEvidence() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let calendar = Calendar(identifier: .gregorian)
        let fixture = fixtures.makeGraphChatTravelFixture(
            calendar: calendar,
            timeZone: timeZone
        )
        try fixtures.save()

        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let schema = try await GraphSchemaService(repository: repository).makeSnapshot(
            in: GraphScope(graphID: fixture.graph.id)
        )
        let entityAlias = try #require(schema.entityAlias(named: "Reisen"))
        let startAlias = try #require(schema.fieldAlias(named: "Startdatum", in: entityAlias))
        let endAlias = try #require(schema.fieldAlias(named: "Enddatum", in: entityAlias))
        let countryAlias = try #require(schema.fieldAlias(named: "Land", in: entityAlias))
        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: Date(timeIntervalSince1970: 1_768_413_600)
        )
        let plan = try validator.validate(
            GraphQueryPlan(
                entityAlias: entityAlias,
                filters: [
                    GraphQueryFilter(
                        fieldAlias: startAlias,
                        operation: .inYear,
                        value: .year(2024)
                    )
                ],
                sorting: [
                    GraphQuerySort(key: .field(startAlias), direction: .ascending)
                ],
                projection: [
                    .nodeIdentity,
                    .field(startAlias),
                    .field(endAlias),
                    .field(countryAlias)
                ],
                limit: 20
            ),
            against: schema
        )
        let engine = GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: GraphEvidenceSourceValidator(repository: repository)
        )

        let result = try await engine.execute(plan)

        #expect(result.state == .success)
        #expect(result.rows.map(\.label) == [
            "Reisen · Paris Neujahr",
            "Reisen · New York Sommer"
        ])
        #expect(result.appliedFilters.count == 1)
        #expect(result.appliedFilters[0].fieldName == "Startdatum")
        #expect(result.appliedFilters[0].valueDescription?.contains("2024-01-01") == true)
        #expect(result.appliedFilters[0].valueDescription?.contains("2025-01-01") == true)
        #expect(result.rows.allSatisfy { row in
            row.evidenceIDs.isEmpty == false
                && row.cells.contains(where: { $0.fieldName == "Startdatum" })
        })
        #expect(result.evidence.contains { evidence in
            evidence.sourceReference.sourceKind == .detailValue
                && evidence.sourceReference.fieldID == fixture.startDateField.id
        })
        #expect(result.rows.contains { $0.label.contains("Berlin 2023") } == false)
        #expect(result.rows.contains { $0.label.contains("Tokio 2025") } == false)
    }
}
