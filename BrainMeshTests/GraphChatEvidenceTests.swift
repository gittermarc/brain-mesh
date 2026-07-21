import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEvidenceTests {
    @Test
    func stableEvidenceIdentityUsesSourceFieldAndValue() {
        let graphID = UUID()
        let sourceID = UUID()
        let fieldID = UUID()
        let source = GraphSourceReference(
            graphID: graphID,
            sourceKind: .detailValue,
            sourceID: sourceID,
            node: GraphSourceNodeReference(kind: .attribute, id: UUID()),
            fieldID: fieldID
        )
        let fields = [
            GraphEvidenceFieldValue(
                fieldID: fieldID,
                fieldName: "Status",
                value: .choice("Fertig"),
                unit: nil
            )
        ]
        let first = GraphEvidence(
            sourceReference: source,
            summary: "Erster Text",
            fieldValues: fields,
            navigationTitle: "A",
            identitySuffix: "query"
        )
        let second = GraphEvidence(
            sourceReference: source,
            summary: "Anderer UI-Text",
            fieldValues: fields,
            navigationTitle: "B",
            identitySuffix: "query"
        )
        let changed = GraphEvidence(
            sourceReference: source,
            summary: "Erster Text",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: fieldID,
                    fieldName: "Status",
                    value: .choice("Offen"),
                    unit: nil
                )
            ],
            identitySuffix: "query"
        )

        #expect(first.id == second.id)
        #expect(first.id != changed.id)
        #expect(first.sourceReference.navigationTarget != nil)
    }

    @Test
    func validatorRejectsForeignMissingAndMismatchedFieldSources() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Evidence")
        let otherGraph = fixtures.makeGraph(name: "Other")
        let entity = fixtures.makeEntity(name: "Tasks", in: graph)
        let otherEntity = fixtures.makeEntity(name: "Other Tasks", in: graph)
        let attribute = fixtures.makeAttribute(name: "Task A", owner: entity)
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Offen", "Fertig"]
        )
        let foreignField = fixtures.makeDetailField(
            owner: otherEntity,
            name: "Foreign",
            type: .singleLineText,
            sortIndex: 0
        )
        let value = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Offen"
        )
        let valueWithForeignField = fixtures.makeDetailValue(
            attribute: attribute,
            field: foreignField,
            stringValue: "Invalid"
        )
        try fixtures.save()

        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let validator = GraphEvidenceSourceValidator(repository: repository)
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graph.id))
        let valid = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graph.id,
                sourceKind: .detailValue,
                sourceID: value.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                owner: GraphSourceNodeReference(kind: .entity, id: entity.id),
                fieldID: field.id
            ),
            summary: "Status Offen"
        )
        let foreignGraph = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: otherGraph.id,
                sourceKind: .attribute,
                sourceID: attribute.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id)
            ),
            summary: "Foreign"
        )
        let missing = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graph.id,
                sourceKind: .attribute,
                sourceID: UUID(),
                node: GraphSourceNodeReference(kind: .attribute, id: UUID())
            ),
            summary: "Missing"
        )
        let mismatchedField = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graph.id,
                sourceKind: .attribute,
                sourceID: attribute.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                owner: GraphSourceNodeReference(kind: .entity, id: entity.id),
                fieldID: foreignField.id
            ),
            summary: "Wrong field"
        )
        let detailValueWithForeignField = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graph.id,
                sourceKind: .detailValue,
                sourceID: valueWithForeignField.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                owner: GraphSourceNodeReference(kind: .entity, id: entity.id),
                fieldID: foreignField.id
            ),
            summary: "Wrong value field"
        )

        let result = try await validator.validatedEvidence(
            [valid, foreignGraph, missing, mismatchedField, detailValueWithForeignField],
            in: scope
        )
        #expect(result == [valid])
    }

    @Test
    func linkEvidenceRejectsAReferenceToAnotherLinkSharingTheSameNode() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Links")
        let first = fixtures.makeEntity(name: "First", in: graph)
        let second = fixtures.makeEntity(name: "Second", in: graph)
        let third = fixtures.makeEntity(name: "Third", in: graph)
        let sourceLink = fixtures.makeLink(
            source: .entity(first),
            target: .entity(second)
        )
        let differentLink = fixtures.makeLink(
            source: .entity(first),
            target: .entity(third)
        )
        try fixtures.save()

        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let validator = GraphEvidenceSourceValidator(repository: repository)
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graph.id,
                sourceKind: .link,
                sourceID: sourceLink.id,
                node: GraphSourceNodeReference(kind: .entity, id: first.id),
                linkID: differentLink.id
            ),
            summary: "Mismatched link metadata"
        )

        let result = try await validator.validatedEvidence(
            [evidence],
            in: .entireGraph(GraphScope(graphID: graph.id))
        )
        #expect(result.isEmpty)
    }

    @Test
    func validatorEnforcesEntityNodeAndSelectionScopes() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Scoped")
        let firstEntity = fixtures.makeEntity(name: "First", in: graph)
        let secondEntity = fixtures.makeEntity(name: "Second", in: graph)
        let first = fixtures.makeAttribute(name: "A", owner: firstEntity)
        let second = fixtures.makeAttribute(name: "B", owner: secondEntity)
        try fixtures.save()

        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let validator = GraphEvidenceSourceValidator(repository: repository)
        let evidence = [first, second].map { attribute in
            GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: graph.id,
                    sourceKind: .attribute,
                    sourceID: attribute.id,
                    node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                    owner: GraphSourceNodeReference(kind: .entity, id: attribute.owner!.id)
                ),
                summary: attribute.displayName
            )
        }
        let graphScope = GraphScope(graphID: graph.id)

        let entityResult = try await validator.validatedEvidence(
            evidence,
            in: .entity(firstEntity.id, in: graphScope)
        )
        #expect(entityResult.map(\.sourceReference.sourceID) == [first.id])

        let nodeResult = try await validator.validatedEvidence(
            evidence,
            in: .node(NodeRefKey(kind: .attribute, id: first.id), in: graphScope)
        )
        #expect(nodeResult.map(\.sourceReference.sourceID) == [first.id])

        let selectionResult = try await validator.validatedEvidence(
            evidence,
            in: try .selection([NodeRefKey(kind: .attribute, id: second.id)], in: graphScope)
        )
        #expect(selectionResult.map(\.sourceReference.sourceID) == [second.id])
    }
}
