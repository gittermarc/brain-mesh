//
//  GraphFullBackupRoundtripTests.swift
//  BrainMeshTests
//

import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct GraphFullBackupRoundtripTests {

    @Test
    func fullBackupRoundtripImportsGraphAsNewGraphWithAttachments() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Roundtrip Backup")
        let entity = fixtures.makeEntity(name: "System", in: graph, notes: "Quelle", iconSymbolName: "server.rack")
        let attribute = fixtures.makeAttribute(name: "Datenprodukt", owner: entity, notes: "Attribut")
        let field = fixtures.makeDetailField(owner: entity, name: "Status", type: .singleLineText, sortIndex: 0)
        let _ = fixtures.makeDetailValue(attribute: attribute, field: field, stringValue: "Aktiv")
        let _ = fixtures.makeLink(source: .entity(entity), target: .attribute(attribute), note: "besitzt")
        let _ = fixtures.makeAttachment(owner: .entity(entity), contentKind: .file, title: "Spec", fileData: Data([1, 1, 1]))
        let _ = fixtures.makeAttachment(owner: .attribute(attribute), contentKind: .galleryImage, title: "Bild", fileData: Data([2, 2]))
        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: graph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let result = try await service.importGraph(from: backupURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.newGraphID != graph.id)
        #expect(result.insertedCounts.entities == 1)
        #expect(result.insertedCounts.attributes == 1)
        #expect(result.insertedCounts.detailFieldValues == 1)
        #expect(result.insertedCounts.links == 1)
        #expect(result.importedAttachments == 2)
        #expect(result.skippedAttachments == 0)

        let importedGraphID = result.newGraphID
        let importedGraph = try #require(try context.fetch(FetchDescriptor<MetaGraph>(predicate: #Predicate { graph in
            graph.id == importedGraphID
        })).first)
        #expect(importedGraph.name == "Roundtrip Backup")

        let importedAttachments = try context.fetch(FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == importedGraphID
        }))
        #expect(importedAttachments.count == 2)
        #expect(importedAttachments.allSatisfy { $0.fileData != nil })
    }
}
