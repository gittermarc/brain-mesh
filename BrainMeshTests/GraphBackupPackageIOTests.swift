//
//  GraphBackupPackageIOTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import BrainMesh

struct GraphBackupPackageIOTests {

    @Test
    func temporaryPackageURLUsesBackupExtension() throws {
        let url = try GraphBackupPackageIO.makeTemporaryPackageURL(
            graphName: "Demo/Graph",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(url.pathExtension == UTType.brainMeshBackupFilenameExtension)
        #expect(url.lastPathComponent.contains("BrainMesh-Demo Graph-FullBackup-2023-11-14"))
    }

    @Test
    func writeAndReadManifestRoundtrip() throws {
        let packageURL = try makePackageURL()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let graphID = UUID()
        let manifest = GraphBackupManifestV2(
            exportedAt: Date(timeIntervalSince1970: 100),
            appVersion: "1.0",
            appBuild: "1",
            graphID: graphID,
            graphName: "Roundtrip",
            counts: CountsDTO(graphs: 1, entities: 1),
            attachments: [makeAttachment(byteCount: 5)]
        )

        try GraphBackupPackageIO.writeManifest(manifest, to: packageURL)
        let decoded = try GraphBackupPackageIO.readManifest(from: packageURL)

        #expect(decoded.graphID == graphID)
        #expect(decoded.graphName == "Roundtrip")
        #expect(decoded.attachmentCount == 1)
        #expect(decoded.attachmentBytes == 5)
        #expect(FileManager.default.fileExists(atPath: GraphBackupPackageLayout.attachmentsDirectoryURL(in: packageURL).path))
    }

    @Test
    func sha256HelperIsDeterministic() {
        let data = Data("BrainMesh Backup".utf8)

        let first = GraphBackupPackageIO.sha256Hex(for: data)
        let second = GraphBackupPackageIO.sha256Hex(for: data)

        #expect(first == second)
        #expect(first.count == 64)
        #expect(first == "3fc28c28ea4a89cae18eefe639e21ea2b2b5e0289522902a27e420c08d1e4de4")
    }

    @Test
    func writeCoreGraphDataCreatesGraphJSON() throws {
        let packageURL = try makePackageURL()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let data = Data("{\"format\":\"brainmesh.graph\"}".utf8)

        try GraphBackupPackageIO.writeCoreGraphData(data, to: packageURL)

        let graphURL = GraphBackupPackageLayout.coreGraphURL(in: packageURL)
        #expect(FileManager.default.fileExists(atPath: graphURL.path))
        let writtenData = try Data(contentsOf: graphURL)
        #expect(writtenData == data)
    }

    @Test
    func inspectionReadsSupportedPackage() throws {
        let packageURL = try makePackageURL()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let manifest = GraphBackupManifestV2(
            graphID: UUID(),
            graphName: "Inspection",
            counts: CountsDTO(graphs: 1)
        )

        try GraphBackupPackageIO.writeManifest(manifest, to: packageURL)
        try GraphBackupPackageIO.writeCoreGraphData(Data("{}".utf8), to: packageURL)

        let result = try GraphBackupInspection.inspectPackage(at: packageURL)

        #expect(result.manifest.graphName == "Inspection")
        #expect(result.coreGraphURL.lastPathComponent == GraphBackupPackageLayout.coreGraphFilename)
        #expect(result.attachmentsDirectoryURL.lastPathComponent == GraphBackupPackageLayout.attachmentsDirectoryName)
    }

    @Test
    func backupUTTypeHelperExposesExpectedExtension() {
        #expect(UTType.brainMeshBackupFilenameExtension == "bmbackup")
        #expect(UTType.brainMeshGraphFilenameExtension == "bmgraph")
    }

    private func makePackageURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphBackupPackageIOTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension(GraphBackupFormat.filenameExtension)
        try GraphBackupPackageIO.ensurePackageDirectories(at: url)
        return url
    }

    private func makeAttachment(byteCount: Int64) -> GraphBackupAttachmentManifestEntry {
        GraphBackupAttachmentManifestEntry(
            id: UUID(),
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: UUID(),
            contentKindRaw: AttachmentContentKind.file.rawValue,
            title: "Anhang",
            originalFilename: "anhang.bin",
            contentTypeIdentifier: "public.data",
            fileExtension: "bin",
            byteCount: byteCount
        )
    }
}
