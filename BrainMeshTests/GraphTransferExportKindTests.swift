//
//  GraphTransferExportKindTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import BrainMesh

struct GraphTransferExportKindTests {

    @Test
    func exportKindsExposeExpectedExtensionsAndContentTypes() {
        #expect(GraphTransferExportKind.graphStructure.fileExtension == "bmgraph")
        #expect(GraphTransferExportKind.fullBackup.fileExtension == "bmbackup")
        #expect(GraphTransferExportKind.graphStructure.contentType == .brainMeshGraph)
        #expect(GraphTransferExportKind.fullBackup.contentType == .brainMeshBackup)
    }

    @Test
    func attachmentEstimateFormatsEmptySmallAndLargeStates() {
        let empty = GraphTransferAttachmentEstimate.empty
        #expect(empty.compactSummary == "Keine Anhänge im aktiven Graph gefunden.")
        #expect(empty.isLargeBackup == false)

        let small = GraphTransferAttachmentEstimate(count: 2, byteCount: 4096)
        #expect(small.hasAttachments)
        #expect(small.compactSummary.contains("2 Anhang-Dateien"))

        let large = GraphTransferAttachmentEstimate(
            count: 1,
            byteCount: GraphTransferAttachmentEstimate.largeBackupThresholdBytes
        )
        #expect(large.isLargeBackup)
    }

    @Test
    func exportReadySummaryDistinguishesGraphStructureAndFullBackup() {
        let counts = CountsDTO(graphs: 1, entities: 1, attributes: 2, detailFieldDefinitions: 3, detailFieldValues: 4, links: 5)

        let graphSummary = GraphTransferExportCopy.readySummary(
            kind: .graphStructure,
            counts: counts,
            attachmentCount: 0,
            attachmentBytes: 0,
            warningCount: 0
        )
        let backupSummary = GraphTransferExportCopy.readySummary(
            kind: .fullBackup,
            counts: counts,
            attachmentCount: 6,
            attachmentBytes: 8192,
            warningCount: 1
        )

        #expect(graphSummary.contains("Struktur-Export"))
        #expect(graphSummary.contains("keine separaten Anhänge"))
        #expect(backupSummary.contains("Vollbackup"))
        #expect(backupSummary.contains("6 Anhänge"))
        #expect(backupSummary.contains("1 Hinweis"))
    }
}
