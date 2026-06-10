//
//  GraphTransferPreviewTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

struct GraphTransferPreviewTests {

    @Test
    func graphStructurePreviewAllowsImport() {
        let preview = ImportPreview(
            kind: .graphStructure,
            graphName: "Struktur",
            exportedAt: Date(timeIntervalSince1970: 0),
            version: GraphTransferFormat.version,
            counts: CountsDTO(graphs: 1, entities: 1)
        )

        #expect(preview.kind == .graphStructure)
        #expect(preview.canStartImport)
        #expect(preview.isFullBackup == false)
        #expect(preview.attachmentCount == 0)
    }

    @Test
    func fullBackupPreviewAllowsImportWhenNoBlockingProblems() {
        let preview = ImportPreview(
            kind: .fullBackup,
            graphName: "Backup",
            exportedAt: Date(timeIntervalSince1970: 0),
            version: GraphBackupFormat.version,
            counts: CountsDTO(graphs: 1, entities: 1),
            attachmentCount: 2,
            attachmentBytes: 42
        )

        #expect(preview.kind == .fullBackup)
        #expect(preview.canStartImport)
        #expect(preview.isFullBackup)
        #expect(preview.attachmentBytesText.isEmpty == false)
    }

    @Test
    func blockingProblemsKeepPreviewNonImportable() {
        let preview = ImportPreview(
            kind: .graphStructure,
            graphName: "Problem",
            exportedAt: Date(timeIntervalSince1970: 0),
            version: GraphTransferFormat.version,
            counts: CountsDTO(graphs: 1),
            blockingProblems: [
                .blocking(code: "checksum", message: "Prüfsumme stimmt nicht.")
            ]
        )

        #expect(preview.canStartImport == false)
        #expect(preview.blockingProblems.first?.severity == .blocking)
    }
}
