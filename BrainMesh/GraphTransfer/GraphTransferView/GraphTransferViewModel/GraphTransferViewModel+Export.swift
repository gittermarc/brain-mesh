//
//  GraphTransferViewModel+Export.swift
//  BrainMesh
//

import Foundation

extension GraphTransferViewModel {

    func startExport(activeGraphIDString: String) async {
        guard isBusy == false else { return }
        guard let gid = UUID(uuidString: activeGraphIDString) else {
            alertState = AlertState(title: "Kein aktiver Graph", message: "Bitte wähle zuerst einen Graphen aus.")
            return
        }

        exportState = .exporting(label: "Export wird erstellt…")

        do {
            let options = GraphTransferService.ExportOptions(
                includeNotes: includeNotes,
                includeIcons: includeIcons,
                includeImages: includeImages
            )
            let url = try await GraphTransferService.shared.exportGraph(graphID: gid, options: options)
            exportedFileURL = url
            let preview = try await GraphTransferService.shared.inspectFile(url: url)
            let summary = ExportSummary(counts: preview.counts)
            exportState = .ready(url: url, summary: summary)
        } catch {
            let message = userFacingMessage(for: error)
            exportState = .failed(message: message)
            alertState = AlertState(title: "Export fehlgeschlagen", message: message)
        }
    }

    func presentShareSheet() {
        guard exportedFileURL != nil else { return }
        isShowingShareSheet = true
    }

    var exportDefaultFilename: String {
        guard let url = exportedFileURL else { return "BrainMesh-Graph" }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "BrainMesh-Graph" : name
    }

    @discardableResult
    func prepareFileExporter() -> Bool {
        guard let url = exportedFileURL else { return false }
        do {
            let data = try Data(contentsOf: url)
            exportDocument = BMGraphFileDocument(data: data)
            isShowingFileExporter = true
            return true
        } catch {
            alertState = AlertState(title: "Export", message: "Die Exportdatei konnte nicht geladen werden. Erstelle den Export bitte erneut.")
            return false
        }
    }

    func handleFileExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            break
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == 3072 {
                return
            }
            alertState = AlertState(title: "Export", message: "Die Datei konnte nicht gespeichert werden. Prüfe den Speicherort und versuche es erneut.")
        }
    }
}
