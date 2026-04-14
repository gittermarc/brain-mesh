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
    func exportConfirmMessage_reflectsSelectedOptions() {
        let model = GraphTransferViewModel()
        model.includeNotes = true
        model.includeIcons = false
        model.includeImages = true

        let message = model.exportConfirmMessage(activeGraphName: "Reiseplanung")

        #expect(message.contains("Aktiver Graph: Reiseplanung"))
        #expect(message.contains("Notizen"))
        #expect(message.contains("Bilder"))
        #expect(message.contains("Icons") == false)
    }

    @Test
    func userFacingMessage_mapsTransferErrorsAndCocoaAccessErrors() {
        let model = GraphTransferViewModel()

        #expect(model.userFacingMessage(for: GraphTransferError.invalidFormat) == "Diese Datei ist keine BrainMesh-Exportdatei.")
        #expect(model.userFacingMessage(for: GraphTransferError.unsupportedVersion(found: 99)) == "Diese Exportdatei wurde mit einer neueren Version erstellt und kann aktuell nicht importiert werden.")
        #expect(model.userFacingMessage(for: GraphTransferError.graphNotFound(graphID: UUID())) == "Der gewählte Graph wurde nicht gefunden.")

        let accessError = NSError(domain: NSCocoaErrorDomain, code: 257)
        #expect(model.userFacingMessage(for: accessError) == "Kein Zugriff auf die ausgewählte Datei.")

        let unknownError = NSError(domain: "Example", code: 1)
        #expect(model.userFacingMessage(for: unknownError) == "Es ist ein unerwarteter Fehler aufgetreten.")
    }
}
