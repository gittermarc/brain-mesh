//
//  GraphTransferViewModelLogicTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphTransferViewModelLogicTests {

    @Test
    func canCreateAdditionalGraph_respectsFreeLimitAndProOverride() {
        let model = GraphTransferViewModel()

        #expect(model.canCreateAdditionalGraph(isPro: false, currentGraphCount: 0))
        #expect(model.canCreateAdditionalGraph(isPro: false, currentGraphCount: GraphTransferLimits.freeMaxGraphs - 1))
        #expect(model.canCreateAdditionalGraph(isPro: false, currentGraphCount: GraphTransferLimits.freeMaxGraphs) == false)
        #expect(model.canCreateAdditionalGraph(isPro: true, currentGraphCount: GraphTransferLimits.freeMaxGraphs + 5))
    }

    @Test
    func exportDefaultFilename_usesBaseNameWithoutExtensionAndFallback() {
        let model = GraphTransferViewModel()

        #expect(model.exportDefaultFilename == "BrainMesh-Graph")

        model.exportedFileURL = URL(fileURLWithPath: "/tmp/Meine Exportdatei.bmgraph")
        #expect(model.exportDefaultFilename == "Meine Exportdatei")
    }

    @Test
    func exportConfirmMessage_reflectsSelectedOptionsAndTransferScope() {
        let model = GraphTransferViewModel()
        model.includeNotes = true
        model.includeIcons = false
        model.includeImages = true

        let message = model.exportConfirmMessage(activeGraphName: "Reiseplanung")

        #expect(message.contains("Aktiver Graph: Reiseplanung"))
        #expect(message.contains("Graph-Struktur"))
        #expect(message.contains("Notizen"))
        #expect(message.contains("Headerbilder von Entitäten/Attributen"))
        #expect(message.contains("Icons") == false)
        #expect(message.contains("separate Anhänge"))
        #expect(message.contains("Graph-Schutz"))
        #expect(message.contains("Pro-Status"))
    }

    @Test
    func exportConfirmMessage_describesNoOptionsClearly() {
        let model = GraphTransferViewModel()
        model.includeNotes = false
        model.includeIcons = false
        model.includeImages = false

        let message = model.exportConfirmMessage(activeGraphName: "Minimal")

        #expect(message.contains("Aktiver Graph: Minimal"))
        #expect(message.contains("Keine Zusatzoptionen ausgewählt."))
        #expect(message.contains("Graph-Struktur"))
        #expect(message.contains("separate Anhänge"))
        #expect(message.contains("Headerbilder") == false)
    }

    @Test
    func exportSummaryText_mentionsGraphStructureDetailsAndAttachmentBoundary() {
        let summary = GraphTransferViewModel.ExportSummary(
            counts: CountsDTO(
                graphs: 1,
                entities: 2,
                attributes: 3,
                detailFieldDefinitions: 4,
                detailFieldValues: 5,
                links: 6
            )
        )

        let text = summary.summaryText ?? ""

        #expect(text.contains("Graph-Struktur-Export"))
        #expect(text.contains("2 Entitäten"))
        #expect(text.contains("3 Attribute"))
        #expect(text.contains("6 Links"))
        #expect(text.contains("4 Details-Felder"))
        #expect(text.contains("5 Details-Werte"))
        #expect(text.contains("keine separaten Anhänge"))
    }

    @Test
    func userFacingMessage_mapsTransferErrorsAndCocoaAccessErrors() {
        let model = GraphTransferViewModel()

        #expect(model.userFacingMessage(for: GraphTransferError.invalidFormat) == "Diese Datei ist keine gültige BrainMesh-.bmgraph-Datei. Wähle bitte einen Struktur-Export aus BrainMesh.")
        #expect(model.userFacingMessage(for: GraphTransferError.unsupportedVersion(found: 99)) == "Diese .bmgraph-Datei wurde mit einer neueren BrainMesh-Version erstellt. Aktualisiere BrainMesh und versuche es danach erneut.")
        #expect(model.userFacingMessage(for: GraphTransferError.graphNotFound(graphID: UUID())) == "Der gewählte Graph wurde nicht gefunden. Wähle einen vorhandenen Graph aus und starte den Export erneut.")
        #expect(model.userFacingMessage(for: GraphTransferError.backupManifestReadFailed(underlying: "missing")) == "Das Full-Backup-Manifest konnte nicht gelesen werden. Wähle ein vollständiges .bmbackup-Paket aus BrainMesh.")
        #expect(model.userFacingMessage(for: GraphTransferError.fullBackupImportNotAvailable) == "Full-Backup-Import kommt im nächsten Schritt. Du kannst das Backup hier bereits prüfen, aber noch nicht importieren.")

        let accessError = NSError(domain: NSCocoaErrorDomain, code: 257)
        #expect(model.userFacingMessage(for: accessError) == "BrainMesh hat keinen Zugriff auf die ausgewählte Datei. Wähle sie direkt aus der Dateien-App oder teile sie erneut in BrainMesh.")

        let unknownError = NSError(domain: "Example", code: 1)
        #expect(model.userFacingMessage(for: unknownError) == "Es ist ein unerwarteter Fehler aufgetreten. Bitte versuche es erneut.")
    }
}
