import Foundation
import Testing
@testable import BrainMesh

struct GraphChatReadOnlyContractTests {
    @Test
    func graphChatToolSurfaceContainsOnlyReadOnlyOperations() {
        let toolTypes: [Any.Type] = [
            graphChatToolType(DescribeGraphSchemaTool.self),
            graphChatToolType(SearchGraphTool.self),
            graphChatToolType(QueryDetailValuesTool.self),
            graphChatToolType(GetNodeTool.self),
            graphChatToolType(GetNeighborsTool.self),
            graphChatToolType(GraphStatsTool.self)
        ]

        #expect(toolTypes.count == 6)
        #expect(Set(toolTypes.map { String(reflecting: $0) }).count == 6)
        #expect(GraphChatToolKind.allCases == [
            .describeGraphSchema,
            .searchGraph,
            .queryDetailValues,
            .getNode,
            .getNeighbors,
            .graphStats
        ])
        let writeVerbs = ["insert", "delete", "save", "update", "mutate", "write"]
        #expect(GraphChatToolKind.allCases.allSatisfy { kind in
            writeVerbs.allSatisfy { verb in
                kind.rawValue.localizedCaseInsensitiveContains(verb) == false
            }
        })
    }

    private func graphChatToolType<T: GraphChatTool>(
        _ type: T.Type
    ) -> Any.Type {
        type
    }
}
