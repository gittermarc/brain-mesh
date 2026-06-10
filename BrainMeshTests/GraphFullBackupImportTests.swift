//
//  GraphFullBackupImportTests.swift
//  BrainMeshTests
//

import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct GraphFullBackupImportTests {

    @Test
    func fullBackupImportRestoresEntityAttachmentFileDataAndCache() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Attachment Import")
        let entity = fixtures.makeEntity(name: "Dokumente", in: graph)
        let data = Data([1, 2, 3, 4, 5])
        let originalAttachment = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "PDF",
            originalFilename: "vertrag.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: data
        )
        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: graph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let result = try await service.importGraph(from: backupURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.newGraphID != graph.id)
        #expect(result.importedAttachments == 1)
        #expect(result.skippedAttachments == 0)

        let importedGraphID = result.newGraphID
        let importedEntities = try context.fetch(FetchDescriptor<MetaEntity>(predicate: #Predicate { entity in
            entity.graphID == importedGraphID
        }))
        let importedEntity = try #require(importedEntities.first { $0.name == "Dokumente" })

        let importedAttachments = try context.fetch(FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == importedGraphID
        }))
        let importedAttachment = try #require(importedAttachments.first)

        #expect(importedAttachment.id != originalAttachment.id)
        #expect(importedAttachment.ownerKindRaw == NodeKind.entity.rawValue)
        #expect(importedAttachment.ownerID == importedEntity.id)
        #expect(importedAttachment.fileData == data)
        #expect(importedAttachment.byteCount == data.count)
        #expect(importedAttachment.localPath != nil)
        #expect(AttachmentStore.fileExists(localPath: importedAttachment.localPath))
    }

    @Test
    func fullBackupImportRemapsAttributeAttachmentOwner() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Attribute Attachment")
        let entity = fixtures.makeEntity(name: "Person", in: graph)
        let attribute = fixtures.makeAttribute(name: "Marc", owner: entity)
        let data = Data([9, 8, 7])
        let _ = fixtures.makeAttachment(
            owner: .attribute(attribute),
            contentKind: .video,
            title: "Clip",
            originalFilename: "clip.mov",
            contentTypeIdentifier: "com.apple.quicktime-movie",
            fileExtension: "mov",
            fileData: data
        )
        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: graph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let result = try await service.importGraph(from: backupURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.importedAttachments == 1)
        #expect(result.skippedAttachments == 0)

        let importedGraphID = result.newGraphID
        let importedAttributes = try context.fetch(FetchDescriptor<MetaAttribute>(predicate: #Predicate { attribute in
            attribute.graphID == importedGraphID
        }))
        let importedAttribute = try #require(importedAttributes.first { $0.name == "Marc" })

        let importedAttachments = try context.fetch(FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == importedGraphID
        }))
        let importedAttachment = try #require(importedAttachments.first)

        #expect(importedAttachment.ownerKindRaw == NodeKind.attribute.rawValue)
        #expect(importedAttachment.ownerID == importedAttribute.id)
        #expect(importedAttachment.fileData == data)
    }

    @Test
    func fullBackupImportPreservesAttachmentContentKinds() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Content Kinds")
        let entity = fixtures.makeEntity(name: "Medien", in: graph)
        let _ = fixtures.makeAttachment(owner: .entity(entity), contentKind: .file, title: "File", fileData: Data([1]))
        let _ = fixtures.makeAttachment(owner: .entity(entity), contentKind: .video, title: "Video", fileData: Data([2]))
        let _ = fixtures.makeAttachment(owner: .entity(entity), contentKind: .galleryImage, title: "Gallery", fileData: Data([3]))
        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: graph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let result = try await service.importGraph(from: backupURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.importedAttachments == 3)

        let importedGraphID = result.newGraphID
        let importedAttachments = try context.fetch(FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == importedGraphID
        }))
        let kinds = Set(importedAttachments.map(\.contentKindRaw))

        #expect(kinds.contains(AttachmentContentKind.file.rawValue))
        #expect(kinds.contains(AttachmentContentKind.video.rawValue))
        #expect(kinds.contains(AttachmentContentKind.galleryImage.rawValue))
    }

    @Test
    func fullBackupImportSkipsMissingAttachmentAsset() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Missing Asset")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let _ = fixtures.makeAttachment(owner: .entity(entity), title: "Missing", fileData: Data([1, 2, 3]))
        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: graph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }
        let manifest = try GraphBackupPackageIO.readManifest(from: backupURL)
        let entry = try #require(manifest.attachments.first)
        let assetURL = try GraphBackupPackageLayout.safeURL(in: backupURL, relativePath: entry.assetRelativePath)
        try FileManager.default.removeItem(at: assetURL)

        let result = try await service.importGraph(from: backupURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.importedAttachments == 0)
        #expect(result.skippedAttachments == 1)
        #expect(result.warnings.contains { $0.contains("fehlt") })

        let importedGraphID = result.newGraphID
        let importedAttachments = try context.fetch(FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == importedGraphID
        }))
        #expect(importedAttachments.isEmpty)
    }

    @Test
    func fullBackupImportSkipsChecksumMismatchAttachment() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let context = testStore.context
        let fixtures = BrainMeshFixtureBuilder(context: context)

        let graph = fixtures.makeGraph(name: "Checksum")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let _ = fixtures.makeAttachment(owner: .entity(entity), title: "Broken", fileData: Data([4, 5, 6]))
        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: graph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }
        try rewriteFirstAttachmentChecksum(in: backupURL, checksum: String(repeating: "0", count: 64))

        let result = try await service.importGraph(from: backupURL, mode: .asNewGraphRemap, progress: nil)
        #expect(result.importedAttachments == 0)
        #expect(result.skippedAttachments == 1)
        #expect(result.warnings.contains { $0.contains("Prüfsumme") })
    }

    private func rewriteFirstAttachmentChecksum(in packageURL: URL, checksum: String) throws {
        let manifestURL = GraphBackupPackageLayout.manifestURL(in: packageURL)
        let data = try Data(contentsOf: manifestURL)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var attachments = try #require(object["attachments"] as? [[String: Any]])
        var first = try #require(attachments.first)
        first["sha256Hex"] = checksum
        attachments[0] = first
        object["attachments"] = attachments
        let rewritten = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try rewritten.write(to: manifestURL, options: [.atomic])
    }
}
