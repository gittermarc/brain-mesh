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
        #expect(result.insertedCounts.detailFieldValues >= 1)

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

    @Test
    func exportImport_doesNotTransferMetaAttachments() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Attachment Boundary")
        let entity = fixtures.makeEntity(name: "Dokumente", in: graph)
        let _ = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "Vertrag",
            originalFilename: "vertrag.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 3,
            fileData: Data([1, 2, 3]),
            localPath: nil
        )

        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let exportURL = try await service.exportGraph(
            graphID: graph.id,
            options: .init(includeNotes: true, includeIcons: true, includeImages: true)
        )
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let result = try await service.importGraph(from: exportURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.newGraphID != graph.id)
        let importedGraphID = result.newGraphID

        let importedAttachments = try context.fetch(FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == importedGraphID
        }))

        #expect(importedAttachments.isEmpty)
    }

    @Test
    func importGraph_skipsLinksWithUnmappedTargets() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context

        let originalGraphID = UUID()
        let entityID = UUID()
        let missingTargetID = UUID()
        let now = Date(timeIntervalSince1970: 0)

        let exportFile = GraphExportFileV1(
            exportedAt: now,
            appVersion: nil,
            appBuild: nil,
            counts: CountsDTO(
                graphs: 1,
                entities: 1,
                attributes: 0,
                detailFieldDefinitions: 0,
                detailFieldValues: 0,
                links: 1
            ),
            graph: GraphDTO(
                id: originalGraphID,
                createdAt: now,
                name: "Graph mit defektem Link"
            ),
            entities: [
                EntityDTO(
                    id: entityID,
                    createdAt: now,
                    graphID: originalGraphID,
                    name: "Quelle",
                    notes: "",
                    iconSymbolName: nil,
                    imageData: nil
                )
            ],
            attributes: [],
            detailFieldDefinitions: [],
            detailFieldValues: [],
            links: [
                LinkDTO(
                    id: UUID(),
                    createdAt: now,
                    graphID: originalGraphID,
                    note: "zeigt auf fehlenden Zielknoten",
                    sourceLabel: "Quelle",
                    targetLabel: "Fehlt",
                    sourceKindRaw: NodeKind.entity.rawValue,
                    sourceID: entityID,
                    targetKindRaw: NodeKind.entity.rawValue,
                    targetID: missingTargetID
                )
            ]
        )

        let importURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainMesh-Invalid-Link-Import-Test-\(UUID().uuidString).bmgraph")
        defer { try? FileManager.default.removeItem(at: importURL) }

        let data = try GraphTransferCodec.encode(exportFile)
        try data.write(to: importURL, options: [.atomic])

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let result = try await service.importGraph(from: importURL, mode: .asNewGraphRemap, progress: nil)

        #expect(result.insertedCounts.graphs == 1)
        #expect(result.insertedCounts.entities == 1)
        #expect(result.insertedCounts.links == 0)
        #expect(result.skippedLinks == 1)

        let newGraphID = result.newGraphID
        let importedEntities = try context.fetch(FetchDescriptor<MetaEntity>(predicate: #Predicate { entity in
            entity.graphID == newGraphID
        }))
        let importedLinks = try context.fetch(FetchDescriptor<MetaLink>(predicate: #Predicate { link in
            link.graphID == newGraphID
        }))

        #expect(importedEntities.count == 1)
        #expect(importedLinks.isEmpty)
    }

}
