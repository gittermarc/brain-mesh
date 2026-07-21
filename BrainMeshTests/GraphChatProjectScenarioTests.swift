import Foundation
import Testing
@testable import BrainMesh

struct GraphChatProjectScenarioTests {
    @Test
    func highOpenOverdueTasksAreFilteredAndSortedDeterministically() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let calendar = Calendar(identifier: .gregorian)
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        let referenceDate = try #require(
            configuredCalendar.date(
                from: DateComponents(
                    calendar: configuredCalendar,
                    timeZone: timeZone,
                    year: 2026,
                    month: 7,
                    day: 21,
                    hour: 14
                )
            )
        )
        let fixture = fixtures.makeGraphChatProjectFixture(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        try fixtures.save()

        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let schema = try await GraphSchemaService(repository: repository).makeSnapshot(
            in: GraphScope(graphID: fixture.graph.id)
        )
        let entityAlias = try #require(schema.entityAlias(named: "Aufgaben"))
        let statusAlias = try #require(schema.fieldAlias(named: "Status", in: entityAlias))
        let priorityAlias = try #require(schema.fieldAlias(named: "Priorität", in: entityAlias))
        let deadlineAlias = try #require(schema.fieldAlias(named: "Deadline", in: entityAlias))
        let plan = try GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate
        ).validate(
            GraphQueryPlan(
                entityAlias: entityAlias,
                filters: [
                    GraphQueryFilter(
                        fieldAlias: priorityAlias,
                        operation: .equals,
                        value: .choice("Hoch")
                    ),
                    GraphQueryFilter(
                        fieldAlias: statusAlias,
                        operation: .oneOf,
                        value: .choices(["Offen", "In Arbeit"])
                    ),
                    GraphQueryFilter(
                        fieldAlias: deadlineAlias,
                        operation: .isOverdue,
                        value: .none
                    )
                ],
                sorting: [
                    GraphQuerySort(key: .field(deadlineAlias), direction: .ascending),
                    GraphQuerySort(key: .nodeName, direction: .ascending)
                ],
                projection: [
                    .nodeIdentity,
                    .field(statusAlias),
                    .field(priorityAlias),
                    .field(deadlineAlias)
                ],
                limit: 20
            ),
            against: schema
        )
        let result = try await GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: GraphEvidenceSourceValidator(repository: repository)
        ).execute(plan)

        #expect(result.state == .success)
        #expect(result.rows.map(\.label) == [
            "Aufgaben · Security Review",
            "Aufgaben · API Migration"
        ])
        #expect(result.appliedFilters.map(\.fieldName) == [
            "Priorität", "Status", "Deadline"
        ])
        #expect(result.appliedFilters.map(\.operationDescription) == [
            "ist gleich", "ist einer von", "ist überfällig"
        ])
        #expect(result.rows.contains { $0.label.contains("Release Notes") } == false)
        #expect(result.rows.contains { $0.label.contains("Backlog Pflege") } == false)
        #expect(result.rows.contains { $0.label.contains("Roadmap Workshop") } == false)
        #expect(result.rows.allSatisfy { $0.evidenceIDs.isEmpty == false })
    }
}
