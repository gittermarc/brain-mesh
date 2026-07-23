import Foundation
import Testing
@testable import BrainMesh

struct GraphChatAnswerArtifactFactoryTests {
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
                evidenceID: GraphEvidenceID(
                    rawValue: UUID(
                        uuidString: String(
                            format: "D0000000-0000-0000-0000-%012d",
                            index + 1
                        )
                    )!
                )
            )
        }
        let node = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let rowEvidenceID = GraphEvidenceID(
            rawValue: UUID(uuidString: "D0000000-0000-0000-0000-000000000100")!
        )
        let result = GraphChatQueryResult(
            state: .success,
            rows: [
                GraphChatQueryResultRow(
                    node: node,
                    label: "Project One",
                    cells: cells,
                    evidenceIDs: [rowEvidenceID]
                )
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: []
        )
        let plan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: context.graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity] + cells.map { .field($0.fieldID) },
            aggregation: nil,
            limit: 10
        )

        let draft = try #require(
            GraphChatAnswerArtifactFactory.queryResult(
                result,
                plan: plan,
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
}
