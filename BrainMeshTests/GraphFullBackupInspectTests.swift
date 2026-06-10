//
//  GraphFullBackupInspectTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

struct GraphFullBackupInspectTests {

    @Test
    func fullBackupPreviewReadsManifestAndCoreGraph() throws {
        let fixture = try BackupFixture.make(
            attachmentData: Data([1, 2, 3]),
            checksum: nil
        )
        defer { fixture.cleanup() }

        let preview = try GraphTransferFileInspection.inspect(url: fixture.packageURL)

        #expect(preview.kind == .fullBackup)
        #expect(preview.graphName == "Preview Backup")
        #expect(preview.version == GraphBackupFormat.version)
        #expect(preview.counts.entities == 1)
        #expect(preview.attachmentCount == 1)
        #expect(preview.attachmentBytes == 3)
        #expect(preview.warnings.isEmpty)
        #expect(preview.blockingProblems.isEmpty)
        #expect(preview.canStartImport == false)
    }

    @Test
    func graphStructurePreviewStillWorks() throws {
        let graphURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphTransferPreview-\(UUID().uuidString)")
            .appendingPathExtension("bmgraph")
        defer { try? FileManager.default.removeItem(at: graphURL) }

        let coreGraph = BackupFixture.makeCoreGraph()
        let data = try GraphTransferCodec.encode(coreGraph)
        try data.write(to: graphURL, options: [.atomic])

        let preview = try GraphTransferFileInspection.inspect(url: graphURL)

        #expect(preview.kind == .graphStructure)
        #expect(preview.graphName == "Preview Backup")
        #expect(preview.version == GraphTransferFormat.version)
        #expect(preview.counts.entities == 1)
        #expect(preview.canStartImport)
    }

    @Test
    func missingAttachmentCreatesWarning() throws {
        let fixture = try BackupFixture.make(
            attachmentData: Data([1, 2, 3]),
            checksum: nil
        )
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.attachmentURL)

        let preview = try GraphTransferFileInspection.inspect(url: fixture.packageURL)

        #expect(preview.warnings.contains { $0.code == GraphBackupPreviewInspectionWarningCode.missingAttachmentAsset })
        #expect(preview.blockingProblems.isEmpty)
    }

    @Test
    func checksumMismatchCreatesBlockingProblem() throws {
        let fixture = try BackupFixture.make(
            attachmentData: Data([1, 2, 3]),
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
        defer { fixture.cleanup() }

        let preview = try GraphTransferFileInspection.inspect(url: fixture.packageURL)

        #expect(preview.blockingProblems.contains { $0.code == GraphBackupPreviewInspectionWarningCode.checksumMismatch })
    }

    @Test
    func missingManifestIsFatal() throws {
        let fixture = try BackupFixture.make(
            attachmentData: Data([1]),
            checksum: nil
        )
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: GraphBackupPackageLayout.manifestURL(in: fixture.packageURL))

        do {
            _ = try GraphTransferFileInspection.inspect(url: fixture.packageURL)
            Issue.record("Missing manifest should throw")
        } catch let error as GraphTransferError {
            if case .backupManifestReadFailed = error {
                #expect(true)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func unsupportedBackupVersionIsFatal() throws {
        let fixture = try BackupFixture.make(
            attachmentData: Data([1]),
            checksum: nil
        )
        defer { fixture.cleanup() }
        try fixture.rewriteManifestVersion(99)

        do {
            _ = try GraphTransferFileInspection.inspect(url: fixture.packageURL)
            Issue.record("Unsupported version should throw")
        } catch let error as GraphTransferError {
            if case .unsupportedBackupVersion(let version) = error {
                #expect(version == 99)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}

private struct BackupFixture {
    let packageURL: URL
    let attachmentURL: URL

    static func make(attachmentData: Data, checksum: String?) throws -> BackupFixture {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphFullBackupInspectTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension(GraphBackupFormat.filenameExtension)
        try GraphBackupPackageIO.ensurePackageDirectories(at: packageURL)

        let coreGraph = makeCoreGraph()
        let graphData = try GraphTransferCodec.encode(coreGraph)
        try GraphBackupPackageIO.writeCoreGraphData(graphData, to: packageURL)

        let attachmentID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let attachmentURL = try GraphBackupPackageLayout.attachmentURL(
            in: packageURL,
            attachmentID: attachmentID,
            fileExtension: "bin"
        )
        try attachmentData.write(to: attachmentURL, options: [.atomic])

        let entry = GraphBackupAttachmentManifestEntry(
            id: attachmentID,
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: coreGraph.entities[0].id,
            contentKindRaw: AttachmentContentKind.file.rawValue,
            title: "Asset",
            originalFilename: "asset.bin",
            contentTypeIdentifier: "public.data",
            fileExtension: "bin",
            byteCount: Int64(attachmentData.count),
            sha256Hex: checksum ?? GraphBackupPackageIO.sha256Hex(for: attachmentData)
        )
        let manifest = GraphBackupManifestV2(
            exportedAt: coreGraph.exportedAt,
            graphID: coreGraph.graph.id,
            graphName: coreGraph.graph.name,
            counts: coreGraph.counts,
            attachments: [entry]
        )
        try GraphBackupPackageIO.writeManifest(manifest, to: packageURL)

        return BackupFixture(packageURL: packageURL, attachmentURL: attachmentURL)
    }

    static func makeCoreGraph() -> GraphExportFileV1 {
        let graphID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let entityID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return GraphExportFileV1(
            exportedAt: exportedAt,
            counts: CountsDTO(graphs: 1, entities: 1),
            graph: GraphDTO(id: graphID, createdAt: exportedAt, name: "Preview Backup"),
            entities: [
                EntityDTO(
                    id: entityID,
                    createdAt: exportedAt,
                    graphID: graphID,
                    name: "Entity",
                    notes: "",
                    iconSymbolName: nil,
                    imageData: nil
                )
            ],
            attributes: [],
            detailFieldDefinitions: [],
            detailFieldValues: [],
            links: []
        )
    }

    func rewriteManifestVersion(_ version: Int) throws {
        let manifestURL = GraphBackupPackageLayout.manifestURL(in: packageURL)
        let data = try Data(contentsOf: manifestURL)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = version
        let rewritten = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try rewritten.write(to: manifestURL, options: [.atomic])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: packageURL)
    }
}
