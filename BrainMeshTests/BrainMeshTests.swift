//
//  BrainMeshTests.swift
//  BrainMeshTests
//
//  Created by Marc Fechner on 13.12.25.
//

import Foundation
import Testing
@testable import BrainMesh

struct BrainMeshTests {

    @Test
    func fixtureBuilder_createsGraphScopedRelatedModels() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Knowledge")
        let entity = fixtures.makeEntity(name: "Person", in: graph, notes: "Entity note")
        let attribute = fixtures.makeAttribute(name: "Marc", owner: entity, notes: "Attribute note")
        let field = fixtures.makeDetailField(owner: entity, name: "Geburtstag", type: .date, sortIndex: 0)
        let value = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            dateValue: Date(timeIntervalSince1970: 0)
        )
        let attachment = fixtures.makeAttachment(
            owner: .attribute(attribute),
            title: "Profil",
            originalFilename: "profil.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x01, 0x02, 0x03])
        )
        let link = fixtures.makeLink(
            source: .entity(entity),
            target: .attribute(attribute),
            note: "hat"
        )

        try fixtures.save()

        #expect(entity.graphID == graph.id)
        #expect(attribute.graphID == graph.id)
        #expect(field.graphID == graph.id)
        #expect(value.graphID == graph.id)
        #expect(attachment.graphID == graph.id)
        #expect(link.graphID == graph.id)
        #expect(entity.attributesList.map(\.id) == [attribute.id])
        #expect(attribute.detailValuesList.map(\.id) == [value.id])
        #expect(link.noteFolded == BMSearch.fold("hat"))
        #expect(attachment.byteCount == 3)
        #expect(attachment.ownerKind == .attribute)
    }
}
