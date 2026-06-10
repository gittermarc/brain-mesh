//
//  GraphBackupManifestTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

struct GraphBackupManifestTests {

    @Test
    func manifestRoundtripCodablePreservesFields() throws {
        let graphID = UUID()
        let attachmentID = UUID()
        let ownerID = UUID()
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = GraphBackupAttachmentManifestEntry(
            id: attachmentID,
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: ownerID,
            contentKindRaw: AttachmentContentKind.file.rawValue,
            title: "Vertrag",
            originalFilename: "vertrag.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 12_345,
            sha256Hex: "abcd"
        )
        let manifest = GraphBackupManifestV2(
            exportedAt: exportedAt,
            appVersion: "1.2.3",
            appBuild: "456",
            graphID: graphID,
            graphName: "Wissensgraph",
            counts: CountsDTO(
                graphs: 1,
                entities: 2,
                attributes: 3,
                detailFieldDefinitions: 4,
                detailFieldValues: 5,
                links: 6
            ),
            attachments: [entry],
            warnings: [GraphBackupManifestWarning(code: "missing-cache", message: "Ein Anhang hat keine lokale Cache-Datei.")]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GraphBackupManifestV2.self, from: data)

        #expect(decoded.format == GraphBackupFormat.formatID)
        #expect(decoded.version == GraphBackupFormat.version)
        #expect(decoded.exportedAt == exportedAt)
        #expect(decoded.appVersion == "1.2.3")
        #expect(decoded.appBuild == "456")
        #expect(decoded.graphID == graphID)
        #expect(decoded.graphName == "Wissensgraph")
        #expect(decoded.coreGraphFilename == GraphBackupPackageLayout.coreGraphFilename)
        #expect(decoded.counts.entities == 2)
        #expect(decoded.attachmentCount == 1)
        #expect(decoded.attachmentBytes == 12_345)
        #expect(decoded.attachments.first?.assetRelativePath == "attachments/\(attachmentID.uuidString.lowercased()).pdf")
        #expect(decoded.attachments.first?.sha256Hex == "abcd")
        #expect(decoded.warnings.first?.code == "missing-cache")
    }

    @Test
    func manifestDerivesAttachmentCountAndBytes() {
        let graphID = UUID()
        let first = makeAttachment(byteCount: 10)
        let second = makeAttachment(byteCount: 25)

        let manifest = GraphBackupManifestV2(
            graphID: graphID,
            graphName: "Backup",
            counts: CountsDTO(graphs: 1),
            attachments: [second, first]
        )

        #expect(manifest.attachmentCount == 2)
        #expect(manifest.attachmentBytes == 35)
        #expect(manifest.attachments.map(\.id).sorted { $0.uuidString < $1.uuidString }.count == 2)
        #expect(manifest.isSupportedFormat)
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
