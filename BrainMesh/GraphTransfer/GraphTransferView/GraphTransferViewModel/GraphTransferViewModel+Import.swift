//
//  GraphTransferViewModel+Import.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphTransferViewModel {

    func handlePickedFile(_ result: Result<[URL], Error>) {
        guard isBusy == false else { return }

        isShowingFileImporter = false

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedImportURL = url
            importState = .inspecting(label: "Datei wird geprüft…")
            Task {
                await inspectSelectedFile()
            }

        case .failure(let error):
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == 3072 {
                return
            }
            importState = .failed(message: "Datei konnte nicht geöffnet werden")
            alertState = AlertState(title: "Import", message: userFacingMessage(for: error))
        }
    }

    func inspectSelectedFile() async {
        guard let url = selectedImportURL else { return }
        do {
            let preview = try await GraphTransferService.shared.inspectFile(url: url)
            importState = .ready(preview: preview)
        } catch {
            importState = .failed(message: "Datei ist ungültig")
            alertState = AlertState(title: "Import", message: userFacingMessage(for: error))
        }
    }

    func startImport() async {
        await performImport()
    }

    func canCreateAdditionalGraph(isPro: Bool, currentGraphCount: Int) -> Bool {
        if isPro { return true }
        return currentGraphCount < GraphTransferLimits.freeMaxGraphs
    }

    func attemptStartImport(using modelContext: ModelContext, isProActive: Bool) async {
        guard isBusy == false else { return }
        guard selectedImportURL != nil else { return }

        isShowingFileImporter = false

        let uniqueGraphs = fetchUniqueGraphs(using: modelContext)
        let currentCount = uniqueGraphs.count

        if canCreateAdditionalGraph(isPro: isProActive, currentGraphCount: currentCount) {
            await performImport()
        } else {
            isShowingImportLimitAlert = true
        }
    }

    func performImport() async {
        guard isBusy == false else { return }
        guard let url = selectedImportURL else { return }

        isShowingFileImporter = false

        importState = .importing(progress: GraphTransferProgress(phase: .inspecting, completed: 0, label: "Datei wird geprüft…"))

        let progressHandler: @Sendable (GraphTransferProgress) -> Void = { prog in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.importState = .importing(progress: prog)
            }
        }

        do {
            let result = try await GraphTransferService.shared.importGraph(from: url, mode: .asNewGraphRemap, progress: progressHandler)
            importState = .finished(result: result)
        } catch {
            importState = .failed(message: "Import fehlgeschlagen")
            alertState = AlertState(title: "Import fehlgeschlagen", message: userFacingMessage(for: error))
        }
    }
}
