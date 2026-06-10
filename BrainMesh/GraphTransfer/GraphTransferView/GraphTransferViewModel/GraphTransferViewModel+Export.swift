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

        switch exportKind {
        case .graphStructure:
            await startGraphStructureExport(graphID: gid)
        case .fullBackup:
            await startFullBackupExport(graphID: gid)
        }
    }

    func presentShareSheet() {
        guard exportedFileURL != nil else { return }
        isShowingShareSheet = true
    }

    var exportDefaultFilename: String {
        guard let url = exportedFileURL else { return exportKind.defaultFilename }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? exportKind.defaultFilename : name
    }

    @discardableResult
    func prepareFileExporter() -> Bool {
        guard let url = exportedFileURL else { return false }
        do {
            exportDocument = try BMGraphFileDocument(fileURL: url, contentType: exportContentType)
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

private extension GraphTransferViewModel {

    func startGraphStructureExport(graphID: UUID) async {
        exportState = .exporting(label: "Struktur-Export wird erstellt")

        do {
            let options = GraphTransferService.ExportOptions(
                includeNotes: includeNotes,
                includeIcons: includeIcons,
                includeImages: includeImages
            )
            let url = try await GraphTransferService.shared.exportGraph(graphID: graphID, options: options)
            exportedFileURL = url
            let preview = try await GraphTransferService.shared.inspectFile(url: url)
            let summary = ExportSummary(kind: .graphStructure, counts: preview.counts)
            exportState = .ready(url: url, summary: summary)
        } catch {
            let message = userFacingMessage(for: error)
            exportState = .failed(message: message)
            alertState = AlertState(title: "Export fehlgeschlagen", message: message)
        }
    }

    func startFullBackupExport(graphID: UUID) async {
        exportState = .exporting(label: "Vollbackup wird erstellt")

        let progressHandler: @Sendable (GraphTransferProgress) -> Void = { progress in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .exporting = self.exportState {
                    self.exportState = .exporting(label: progress.label)
                }
            }
        }

        do {
            let options = GraphTransferService.FullBackupOptions(
                includeNotes: includeNotes,
                includeIcons: includeIcons,
                includeHeaderImages: includeImages,
                includeAttachments: includeAttachments
            )
            let url = try await GraphTransferService.shared.exportFullBackup(
                graphID: graphID,
                options: options,
                progress: progressHandler
            )
            exportedFileURL = url
            let preview = try await GraphTransferService.shared.inspectFile(url: url)
            let summary = ExportSummary(
                kind: .fullBackup,
                counts: preview.counts,
                attachmentCount: preview.attachmentCount,
                attachmentBytes: preview.attachmentBytes,
                warningCount: preview.warnings.count
            )
            exportState = .ready(url: url, summary: summary)
        } catch {
            let message = userFacingMessage(for: error)
            exportState = .failed(message: message)
            alertState = AlertState(title: "Export fehlgeschlagen", message: message)
        }
    }
}
