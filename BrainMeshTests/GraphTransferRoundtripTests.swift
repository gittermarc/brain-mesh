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
        // In-memory SwiftData container (no CloudKit).
        let schema = Schema([
            MetaGraph.self,
            MetaEntity.self,
            MetaAttribute.self,
            MetaLink.self,
            MetaAttachment.self,
            MetaDetailFieldDefinition.self,
            MetaDetailFieldValue.self,
            MetaDetailsTemplate.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Seed a small test graph.
        let graph = MetaGraph(name: "TestGraph")
        context.insert(graph)

        let e1 = MetaEntity(name: "Person", graphID: graph.id, iconSymbolName: "person")
        let e2 = MetaEntity(name: "Ort", graphID: graph.id, iconSymbolName: "mappin")
        context.insert(e1)
        context.insert(e2)

        let a1 = MetaAttribute(name: "Marc", owner: e1, graphID: graph.id)
        let a2 = MetaAttribute(name: "Lisa", owner: e1, graphID: graph.id)
        let a3 = MetaAttribute(name: "München", owner: e2, graphID: graph.id)
        e1.addAttribute(a1)
        e1.addAttribute(a2)
        e2.addAttribute(a3)
        context.insert(a1)
        context.insert(a2)
        context.insert(a3)

        let field = MetaDetailFieldDefinition(owner: e1, name: "Geburtstag", type: .date, sortIndex: 0)
        e1.addDetailField(field)
        context.insert(field)

        let v1 = MetaDetailFieldValue(attribute: a1, fieldID: field.id)
        v1.dateValue = Date(timeIntervalSince1970: 0)
        if a1.detailValues == nil { a1.detailValues = [] }
        a1.detailValues?.append(v1)
        context.insert(v1)

        let link = MetaLink(
            sourceKind: .entity,
            sourceID: e1.id,
            sourceLabel: e1.name,
            targetKind: .entity,
            targetID: e2.id,
            targetLabel: e2.name,
            note: "kennt",
            graphID: graph.id
        )
        context.insert(link)

        try context.save()

        // Configure a fresh service instance (avoid cross-test interference via the shared singleton).
        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(container))

        // Export
        let exportURL = try await service.exportGraph(graphID: graph.id, options: .init(includeImages: false))
        defer { try? FileManager.default.removeItem(at: exportURL) }

        // Inspect
        let preview = try await service.inspectFile(url: exportURL)
        #expect(preview.version == GraphTransferFormat.version)
        #expect(preview.counts.entities >= 2)
        #expect(preview.counts.attributes >= 2)
        #expect(preview.counts.links >= 1)

        // Import
        let result = try await service.importGraph(from: exportURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.newGraphID != graph.id)
        #expect(result.skippedLinks == 0)
        #expect(result.insertedCounts.entities >= 2)
        #expect(result.insertedCounts.attributes >= 2)

        // Validate: imported graph exists.
        let newGID = result.newGraphID
        var gfd = FetchDescriptor<MetaGraph>(predicate: #Predicate { g in
            g.id == newGID
        })
        gfd.fetchLimit = 1
        let importedGraph = try context.fetch(gfd).first
        #expect(importedGraph != nil)

        // Validate: no dangling endpoints.
        let entities = try context.fetch(FetchDescriptor<MetaEntity>(predicate: #Predicate { e in
            e.graphID == newGID
        }))
        let attributes = try context.fetch(FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in
            a.graphID == newGID
        }))
        let links = try context.fetch(FetchDescriptor<MetaLink>(predicate: #Predicate { l in
            l.graphID == newGID
        }))

        let entityIDs = Set(entities.map { $0.id })
        let attributeIDs = Set(attributes.map { $0.id })

        for l in links {
            switch l.sourceKind {
            case .entity:
                #expect(entityIDs.contains(l.sourceID))
            case .attribute:
                #expect(attributeIDs.contains(l.sourceID))
            }
            switch l.targetKind {
            case .entity:
                #expect(entityIDs.contains(l.targetID))
            case .attribute:
                #expect(attributeIDs.contains(l.targetID))
            }
        }
    }
}
