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
            let message = userFacingMessage(for: error)
            importState = .failed(message: message)
            alertState = AlertState(title: "Import", message: message)
        }
    }

    func inspectSelectedFile() async {
        guard let url = selectedImportURL else { return }
        do {
            let preview = try await GraphTransferService.shared.inspectFile(url: url)
            importState = .ready(preview: preview)
        } catch {
            let message = userFacingMessage(for: error)
            importState = .failed(message: message)
            alertState = AlertState(title: "Import", message: message)
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
            let message = userFacingMessage(for: error)
            importState = .failed(message: message)
            alertState = AlertState(title: "Import fehlgeschlagen", message: message)
        }
    }
}
