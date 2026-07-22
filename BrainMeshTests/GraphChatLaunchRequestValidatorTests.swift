import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct GraphChatLaunchRequestValidatorTests {
    @Test
    func selectionKeepsOnlyNodesFromTheActiveGraph() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graph = MetaGraph(name: "Portfolio")
        let entity = MetaEntity(name: "Projekte", graphID: graph.id)
        let attribute = MetaAttribute(name: "Apollo", owner: entity, graphID: graph.id)
        let foreignGraph = MetaGraph(name: "Archiv")
        let foreignEntity = MetaEntity(name: "Archivprojekte", graphID: foreignGraph.id)
        let foreignAttribute = MetaAttribute(
            name: "Altprojekt",
            owner: foreignEntity,
            graphID: foreignGraph.id
        )
        store.context.insert(graph)
        store.context.insert(entity)
        store.context.insert(attribute)
        store.context.insert(foreignGraph)
        store.context.insert(foreignEntity)
        store.context.insert(foreignAttribute)
        try store.context.save()

        let existing = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: attribute.id),
            label: "Stale label"
        )
        let foreign = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: foreignAttribute.id),
            label: "Foreign"
        )
        let launch = try #require(
            GraphChatContextEntryPoint.selection(
                graphID: graph.id,
                nodes: [existing, foreign]
            )
        )
        let request = GraphChatLaunchRequest(
            scope: launch.scope,
            context: launch.context
        )

        let result = GraphChatLaunchRequestValidator(
            modelContext: store.context
        ).validate(request, activeGraphID: graph.id)
        let validated = try #require(result.request)

        #expect(validated.scope.nodeReferences == [existing.node])
        #expect(validated.context.nodeReferences.first?.label == "Apollo")
    }

    @Test
    func emptySelectionAfterDeletedNodesIsRejected() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graph = MetaGraph(name: "Portfolio")
        store.context.insert(graph)
        try store.context.save()
        let deleted = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Deleted"
        )
        let launch = try #require(
            GraphChatContextEntryPoint.selection(graphID: graph.id, nodes: [deleted])
        )
        let result = GraphChatLaunchRequestValidator(
            modelContext: store.context
        ).validate(
            GraphChatLaunchRequest(scope: launch.scope, context: launch.context),
            activeGraphID: graph.id
        )

        #expect(result == .invalid(.emptySelection))
    }

    @Test
    func graphChangeInvalidatesAStaleLaunch() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let oldGraphID = UUID()
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: oldGraphID))
        )

        let result = GraphChatLaunchRequestValidator(
            modelContext: store.context
        ).validate(request, activeGraphID: UUID())

        #expect(result == .invalid(.graphMismatch))
    }

    @Test
    func detailFieldMustStillBelongToItsEntityAndGraph() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graph = MetaGraph(name: "Portfolio")
        let entity = MetaEntity(name: "Projekte", graphID: graph.id)
        let field = MetaDetailFieldDefinition(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0
        )
        store.context.insert(graph)
        store.context.insert(entity)
        store.context.insert(field)
        try store.context.save()
        let launch = GraphChatContextEntryPoint.detailField(
            graphID: graph.id,
            entityID: entity.id,
            entityName: entity.name,
            fieldID: field.id,
            fieldName: field.name,
            fieldType: field.type
        )

        let result = GraphChatLaunchRequestValidator(
            modelContext: store.context
        ).validate(
            GraphChatLaunchRequest(scope: launch.scope, context: launch.context),
            activeGraphID: graph.id
        )

        #expect(result.request?.scope.context == .detailField(entityID: entity.id, fieldID: field.id))
    }

    @Test
    func mismatchedSelectionContextIsRejected() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graph = MetaGraph(name: "Graph")
        let entity = MetaEntity(name: "Projects", graphID: graph.id)
        let first = MetaAttribute(name: "Alpha", owner: entity, graphID: graph.id)
        let second = MetaAttribute(name: "Beta", owner: entity, graphID: graph.id)
        store.context.insert(graph)
        store.context.insert(entity)
        store.context.insert(first)
        store.context.insert(second)
        try store.context.save()

        let firstReference = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: first.id),
            label: first.name,
            entityID: entity.id,
            entityName: entity.name
        )
        let secondReference = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: second.id),
            label: second.name,
            entityID: entity.id,
            entityName: entity.name
        )
        let scope = try GraphChatScope.selection(
            [firstReference.node],
            in: GraphScope(graphID: graph.id)
        )
        let request = GraphChatLaunchRequest(
            scope: scope,
            context: .selection([secondReference])
        )

        let result = GraphChatLaunchRequestValidator(
            modelContext: store.context
        ).validate(request, activeGraphID: graph.id)

        #expect(result == .invalid(.contextUnavailable))
    }

}
