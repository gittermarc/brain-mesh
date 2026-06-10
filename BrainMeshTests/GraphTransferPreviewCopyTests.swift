//
//  GraphTransferPreviewCopyTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

struct GraphTransferPreviewCopyTests {

    @Test
    func previewCopyDistinguishesGraphStructureAndFullBackup() {
        let counts = CountsDTO(graphs: 1, entities: 1)
        let graphPreview = ImportPreview(
            kind: .graphStructure,
            graphName: "Struktur",
            exportedAt: Date(timeIntervalSince1970: 0),
            version: GraphTransferFormat.version,
            counts: counts
        )
        let backupPreview = ImportPreview(
            kind: .fullBackup,
            graphName: "Backup",
            exportedAt: Date(timeIntervalSince1970: 0),
            version: GraphBackupFormat.version,
            counts: counts,
            attachmentCount: 2,
            attachmentBytes: 2048
        )

        #expect(GraphTransferPreviewCopy.headline(for: graphPreview) == "Struktur-Export importieren")
        #expect(GraphTransferPreviewCopy.headline(for: backupPreview) == "Vollbackup importieren")
        #expect(GraphTransferPreviewCopy.scopeSummary(for: graphPreview).contains(".bmgraph"))
        #expect(GraphTransferPreviewCopy.scopeSummary(for: backupPreview).contains(".bmbackup"))
        #expect(GraphTransferPreviewCopy.scopeSummary(for: backupPreview).contains("Anhänge"))
    }

    @Test
    func previewIssueSummaryPrioritizesBlockingProblems() throws {
        let preview = ImportPreview(
            kind: .fullBackup,
            graphName: "Problem",
            exportedAt: Date(timeIntervalSince1970: 0),
            version: GraphBackupFormat.version,
            counts: CountsDTO(graphs: 1),
            warnings: [.warning(code: "missing", message: "Anhang fehlt")],
            blockingProblems: [.blocking(code: "checksum", message: "Prüfsumme falsch")]
        )

        let summary = try #require(GraphTransferPreviewCopy.issueSummary(for: preview))
        #expect(summary.contains("blockierende"))
        #expect(summary.contains("Import ist nicht möglich"))
    }

    @Test
    func partialBackupImportResultSummaryIsUnderstandable() {
        let result = ImportResult(
            newGraphID: UUID(),
            insertedCounts: CountsDTO(graphs: 1, entities: 2, attributes: 3, links: 4),
            skippedLinks: 0,
            importedAttachments: 5,
            skippedAttachments: 1,
            warnings: ["Ein Anhang fehlt."]
        )

        #expect(GraphTransferPreviewCopy.resultTitle(for: result) == "Import teilweise abgeschlossen")
        let summary = GraphTransferPreviewCopy.resultSummary(for: result)
        #expect(summary.contains("2 Entitäten"))
        #expect(summary.contains("5 importierte Anhänge"))
        #expect(summary.contains("1 übersprungen"))
    }
}
