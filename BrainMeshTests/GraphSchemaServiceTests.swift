import Foundation
import Testing

@testable import BrainMesh

struct GraphSchemaServiceTests {

    @Test
    func snapshotUsesDeterministicAliasesForAllFieldTypesAndMetadata() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Arbeitsgraph")
        let entity = fixtures.makeEntity(name: "Projekte", in: graph)
        let firstAttribute = fixtures.makeAttribute(name: "Alpha", owner: entity)
        _ = fixtures.makeAttribute(name: "Beta", owner: entity)

        let specifications: [(String, DetailFieldType, String?, [String], Bool)] = [
            ("Titel", .singleLineText, nil, [], true),
            ("Beschreibung", .multiLineText, nil, [], false),
            ("Aufwand", .numberInt, "h", [], true),
            ("Budget", .numberDouble, "EUR", [], false),
            ("Fällig", .date, nil, [], true),
            ("Kritisch", .toggle, nil, [], false),
            ("Status", .singleChoice, nil, ["Offen", "In Arbeit", "Fertig"], false)
        ]
        var fields: [MetaDetailFieldDefinition] = []
        for (index, specification) in specifications.enumerated() {
            fields.append(
                fixtures.makeDetailField(
                    owner: entity,
                    name: specification.0,
                    type: specification.1,
                    sortIndex: index,
                    unit: specification.2,
                    options: specification.3,
                    isPinned: specification.4
                )
            )
        }
        _ = fixtures.makeDetailValue(
            attribute: firstAttribute,
            field: fields[0],
            stringValue: "Interne Roadmap"
        )
        _ = fixtures.makeAttachment(
            owner: .attribute(firstAttribute),
            title: "Secret Attachment",
            fileData: Data("ATTACHMENT-CONTENT-MUST-NOT-LEAK".utf8)
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let service = GraphSchemaService(repository: repository)
        let scope = GraphScope(graphID: graph.id)
        let first = try await service.makeSnapshot(
            in: scope,
            exampleFieldIDs: [fields[0].id]
        )
        let second = try await service.makeSnapshot(
            in: scope,
            exampleFieldIDs: [fields[0].id]
        )

        #expect(first.snapshot == second.snapshot)
        #expect(first.snapshot.graphName == "Arbeitsgraph")
        #expect(first.snapshot.entities.map(\.alias.rawValue) == ["E1"])
        #expect(first.snapshot.entities[0].attributeCount == 2)
        #expect(first.snapshot.entities[0].fields.map(\.alias.rawValue) == [
            "F1", "F2", "F3", "F4", "F5", "F6", "F7"
        ])
        #expect(first.snapshot.entities[0].fields.map(\.type) == DetailFieldType.allCases)
        #expect(first.snapshot.entities[0].fields[2].unit == "h")
        #expect(first.snapshot.entities[0].fields[3].unit == "EUR")
        #expect(first.snapshot.entities[0].fields[6].choiceOptions == [
            "Offen", "In Arbeit", "Fertig"
        ])
        #expect(first.snapshot.entities[0].fields[0].isPinned)
        #expect(first.snapshot.entities[0].fields[0].exampleValues == [
            .text("Interne Roadmap")
        ])
        #expect(first.aliases.entity(for: GraphEntityAlias("E1"))?.entityID == entity.id)
        #expect(first.aliases.field(for: GraphFieldAlias("F7"))?.fieldID == fields[6].id)

        let promptFacingDescription = String(describing: first.snapshot)
        #expect(promptFacingDescription.contains(graph.id.uuidString) == false)
        #expect(promptFacingDescription.contains(entity.id.uuidString) == false)
        #expect(promptFacingDescription.contains(fields[0].id.uuidString) == false)
        #expect(promptFacingDescription.contains("ATTACHMENT-CONTENT-MUST-NOT-LEAK") == false)
    }

    @Test
    func largeSchemasAreDeterministicallyLimited() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: String(repeating: "G", count: 80))

        for entityIndex in 0..<4 {
            let entity = fixtures.makeEntity(
                name: "Entity \(entityIndex)",
                in: graph
            )
            _ = fixtures.makeAttribute(
                name: "Attribute \(entityIndex)",
                owner: entity
            )
            for fieldIndex in 0..<4 {
                _ = fixtures.makeDetailField(
                    owner: entity,
                    name: "Field \(fieldIndex)",
                    type: .singleChoice,
                    sortIndex: fieldIndex,
                    options: ["One", "Two", "Three"]
                )
            }
        }
        try fixtures.save()

        let limits = GraphSchemaLimits(
            maximumEntities: 2,
            maximumFieldsPerEntity: 2,
            maximumFieldsTotal: 3,
            maximumChoiceOptionsPerField: 2,
            maximumExampleValuesPerField: 0,
            maximumStringLength: 12
        )
        let service = GraphSchemaService(
            repository: GraphReadRepository(
                container: AnyModelContainer(store.container)
            ),
            limits: limits
        )
        let scope = GraphScope(graphID: graph.id)
        let first = try await service.makeSnapshot(in: scope)
        let second = try await service.makeSnapshot(in: scope)

        #expect(first.snapshot == second.snapshot)
        #expect(first.snapshot.entities.count == 2)
        #expect(first.snapshot.entities.flatMap(\.fields).count == 3)
        #expect(first.snapshot.entities.flatMap(\.fields).map(\.alias.rawValue) == [
            "F1", "F2", "F3"
        ])
        #expect(first.snapshot.entities.flatMap(\.fields).allSatisfy {
            $0.choiceOptions == ["One", "Two"]
        })
        #expect(first.snapshot.graphName.count == 12)
        #expect(first.snapshot.truncation.isTruncated)
    }

    @Test
    func sameNodeIDsInDifferentGraphsRemainSeparatedByGraphScope() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let firstGraph = fixtures.makeGraph(name: "First")
        let secondGraph = fixtures.makeGraph(name: "Second")
        let sharedEntityID = UUID()
        let sharedAttributeID = UUID()

        let firstEntity = fixtures.makeEntity(
            name: "Shared",
            in: firstGraph,
            id: sharedEntityID
        )
        _ = fixtures.makeAttribute(
            name: "First Attribute",
            owner: firstEntity,
            id: sharedAttributeID
        )
        let secondEntity = fixtures.makeEntity(
            name: "Shared",
            in: secondGraph,
            id: sharedEntityID
        )
        _ = fixtures.makeAttribute(
            name: "Second Attribute",
            owner: secondEntity,
            id: sharedAttributeID
        )
        try fixtures.save()

        let service = GraphSchemaService(
            repository: GraphReadRepository(
                container: AnyModelContainer(store.container)
            )
        )
        let first = try await service.makeSnapshot(
            in: GraphScope(graphID: firstGraph.id)
        )
        let second = try await service.makeSnapshot(
            in: GraphScope(graphID: secondGraph.id)
        )

        #expect(first.graphScope != second.graphScope)
        #expect(first.snapshot.graphName == "First")
        #expect(second.snapshot.graphName == "Second")
        #expect(
            first.aliases.owningEntityID(
                for: NodeRefKey(kind: .attribute, id: sharedAttributeID)
            ) == sharedEntityID
        )
        #expect(
            second.aliases.owningEntityID(
                for: NodeRefKey(kind: .attribute, id: sharedAttributeID)
            ) == sharedEntityID
        )
    }
}
