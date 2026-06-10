//
//  GraphFullBackupExportTests.swift
//  BrainMeshTests
//

import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct GraphFullBackupExportTests {

    @Test
    func exportFullBackupCreatesPackageManifestCoreGraphAndAttachments() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graph = fixtures.makeGraph(name: "Backup Graph")
        let entity = fixtures.makeEntity(
            name: "Dokumente",
            in: graph,
            notes: "Notiz",
            iconSymbolName: "doc",
            imageData: Data([9, 9, 9])
        )
        let attribute = fixtures.makeAttribute(
            name: "Vertrag",
            owner: entity,
            notes: "Attributnotiz",
            iconSymbolName: "paperclip",
            imageData: Data([8, 8])
        )
        let _ = fixtures.makeLink(source: .entity(entity), target: .attribute(attribute), note: "hat")

        let fileData = Data([1, 2, 3, 4])
        let videoData = Data([5, 6, 7])
        let galleryData = Data([8, 9])
        let fileAttachment = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "PDF",
            originalFilename: "vertrag.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: fileData,
            localPath: "cache-should-not-be-used.pdf"
        )
        let videoAttachment = fixtures.makeAttachment(
            owner: .attribute(attribute),
            contentKind: .video,
            title: "Video",
            originalFilename: "clip.mov",
            contentTypeIdentifier: "com.apple.quicktime-movie",
            fileExtension: "mov",
            fileData: videoData,
            localPath: nil
        )
        let galleryAttachment = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .galleryImage,
            title: "Galerie",
            originalFilename: "bild.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: galleryData,
            localPath: nil
        )
        let missingDataAttachment = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "Fehlende Daten",
            originalFilename: "missing.bin",
            contentTypeIdentifier: "public.data",
            fileExtension: "bin",
            byteCount: 10,
            fileData: nil,
            localPath: nil
        )

        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(
            graphID: graph.id,
            options: .init(
                includeNotes: true,
                includeIcons: true,
                includeHeaderImages: true,
                includeAttachments: true
            )
        )
        defer { try? FileManager.default.removeItem(at: backupURL) }

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: backupURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(backupURL.pathExtension == GraphBackupFormat.filenameExtension)

        let manifest = try GraphBackupPackageIO.readManifest(from: backupURL)
        #expect(manifest.isSupportedFormat)
        #expect(manifest.graphID == graph.id)
        #expect(manifest.graphName == "Backup Graph")
        #expect(manifest.coreGraphFilename == GraphBackupPackageLayout.coreGraphFilename)
        #expect(manifest.attachmentCount == 3)
        #expect(manifest.attachmentBytes == Int64(fileData.count + videoData.count + galleryData.count))
        #expect(manifest.attachments.contains { $0.id == missingDataAttachment.id } == false)
        #expect(manifest.warnings.contains { $0.code == GraphBackupAttachmentExportWarningCode.missingFileData })

        let coreGraphURL = GraphBackupPackageLayout.coreGraphURL(in: backupURL)
        #expect(FileManager.default.fileExists(atPath: coreGraphURL.path))
        let coreGraphData = try Data(contentsOf: coreGraphURL)
        let coreGraph = try GraphTransferCodec.decode(coreGraphData)
        #expect(coreGraph.format == GraphTransferFormat.formatID)
        #expect(coreGraph.version == GraphTransferFormat.version)
        #expect(coreGraph.graph.id == graph.id)
        #expect(coreGraph.entities.count == 1)
        #expect(coreGraph.attributes.count == 1)
        #expect(coreGraph.links.count == 1)
        #expect(coreGraph.entities.first?.notes == "Notiz")
        #expect(coreGraph.entities.first?.imageData == Data([9, 9, 9]))

        try expectExportedAttachment(
            id: fileAttachment.id,
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: entity.id,
            contentKindRaw: AttachmentContentKind.file.rawValue,
            data: fileData,
            manifest: manifest,
            packageURL: backupURL
        )
        try expectExportedAttachment(
            id: videoAttachment.id,
            ownerKindRaw: NodeKind.attribute.rawValue,
            ownerID: attribute.id,
            contentKindRaw: AttachmentContentKind.video.rawValue,
            data: videoData,
            manifest: manifest,
            packageURL: backupURL
        )
        try expectExportedAttachment(
            id: galleryAttachment.id,
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: entity.id,
            contentKindRaw: AttachmentContentKind.galleryImage.rawValue,
            data: galleryData,
            manifest: manifest,
            packageURL: backupURL
        )
    }

    @Test
    func exportFullBackupIsGraphScoped() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let firstGraph = fixtures.makeGraph(name: "First")
        let secondGraph = fixtures.makeGraph(name: "Second")
        let firstEntity = fixtures.makeEntity(name: "First Entity", in: firstGraph)
        let secondEntity = fixtures.makeEntity(name: "Second Entity", in: secondGraph)
        let firstAttachment = fixtures.makeAttachment(
            owner: .entity(firstEntity),
            title: "First Asset",
            fileData: Data([1])
        )
        let secondAttachment = fixtures.makeAttachment(
            owner: .entity(secondEntity),
            title: "Second Asset",
            fileData: Data([2])
        )

        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(graphID: firstGraph.id, options: .init())
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let manifest = try GraphBackupPackageIO.readManifest(from: backupURL)
        #expect(manifest.attachments.map(\.id) == [firstAttachment.id])
        #expect(manifest.attachments.contains { $0.id == secondAttachment.id } == false)
    }

    @Test
    func exportFullBackupCanSkipAttachmentsByOption() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graph = fixtures.makeGraph(name: "No Attachments")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let _ = fixtures.makeAttachment(owner: .entity(entity), title: "Asset", fileData: Data([1, 2, 3]))

        try fixtures.save()

        let service = GraphTransferService()
        await service.configure(container: AnyModelContainer(testStore.container))

        let backupURL = try await service.exportFullBackup(
            graphID: graph.id,
            options: .init(includeAttachments: false)
        )
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let manifest = try GraphBackupPackageIO.readManifest(from: backupURL)
        #expect(manifest.attachmentCount == 0)
        #expect(manifest.attachmentBytes == 0)
        #expect(manifest.attachments.isEmpty)
        #expect(manifest.warnings.isEmpty)
    }

    private func expectExportedAttachment(
        id: UUID,
        ownerKindRaw: Int,
        ownerID: UUID,
        contentKindRaw: Int,
        data: Data,
        manifest: GraphBackupManifestV2,
        packageURL: URL
    ) throws {
        let entry = try #require(manifest.attachments.first { $0.id == id })
        #expect(entry.ownerKindRaw == ownerKindRaw)
        #expect(entry.ownerID == ownerID)
        #expect(entry.contentKindRaw == contentKindRaw)
        #expect(entry.byteCount == Int64(data.count))
        #expect(entry.sha256Hex == GraphBackupPackageIO.sha256Hex(for: data))
        #expect(entry.assetRelativePath.hasPrefix("attachments/"))

        let assetURL = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: entry.assetRelativePath)
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
        let writtenData = try Data(contentsOf: assetURL)
        #expect(writtenData == data)
    }
}
