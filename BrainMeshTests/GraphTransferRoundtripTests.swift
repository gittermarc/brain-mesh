//
//  GraphTransferRoundtripTests.swift
//  BrainMeshTests
//

import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct GraphTransferRoundtripTests {

    @Test
    func exportInspectImport_roundtrip_createsNewGraphWithValidLinks() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "TestGraph")

        let e1 = fixtures.makeEntity(name: "Person", in: graph, iconSymbolName: "person")
        let e2 = fixtures.makeEntity(name: "Ort", in: graph, iconSymbolName: "mappin")

        let a1 = fixtures.makeAttribute(name: "Marc", owner: e1)
        let _ = fixtures.makeAttribute(name: "Lisa", owner: e1)
        let _ = fixtures.makeAttribute(name: "München", owner: e2)

        let field = fixtures.makeDetailField(owner: e1, name: "Geburtstag", type: .date, sortIndex: 0)
        let _ = fixtures.makeDetailValue(
            attribute: a1,
            field: field,
            dateValue: Date(timeIntervalSince1970: 0)
        )

        let _ = fixtures.makeLink(
            source: .entity(e1),
            target: .entity(e2),
            note: "kennt"
        )

        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let exportURL = try await service.exportGraph(graphID: graph.id, options: .init(includeImages: false))
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let preview = try await service.inspectFile(url: exportURL)
        #expect(preview.version == GraphTransferFormat.version)
        #expect(preview.counts.entities >= 2)
        #expect(preview.counts.attributes >= 2)
        #expect(preview.counts.links >= 1)

        let result = try await service.importGraph(from: exportURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.newGraphID != graph.id)
        #expect(result.skippedLinks == 0)
        #expect(result.insertedCounts.entities >= 2)
        #expect(result.insertedCounts.attributes >= 2)

        let newGraphID = result.newGraphID
        var graphDescriptor = FetchDescriptor<MetaGraph>(predicate: #Predicate { graph in
            graph.id == newGraphID
        })
        graphDescriptor.fetchLimit = 1
        let importedGraph = try context.fetch(graphDescriptor).first
        #expect(importedGraph != nil)

        let entities = try context.fetch(FetchDescriptor<MetaEntity>(predicate: #Predicate { entity in
            entity.graphID == newGraphID
        }))
        let attributes = try context.fetch(FetchDescriptor<MetaAttribute>(predicate: #Predicate { attribute in
            attribute.graphID == newGraphID
        }))
        let links = try context.fetch(FetchDescriptor<MetaLink>(predicate: #Predicate { link in
            link.graphID == newGraphID
        }))

        let entityIDs = Set(entities.map(\.id))
        let attributeIDs = Set(attributes.map(\.id))

        for link in links {
            switch link.sourceKind {
            case .entity:
                #expect(entityIDs.contains(link.sourceID))
            case .attribute:
                #expect(attributeIDs.contains(link.sourceID))
            }

            switch link.targetKind {
            case .entity:
                #expect(entityIDs.contains(link.targetID))
            case .attribute:
                #expect(attributeIDs.contains(link.targetID))
            }
        }
    }
}
