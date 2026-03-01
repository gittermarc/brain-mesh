//
//  GraphTransferViewModel.swift
//  BrainMesh
//

import Foundation
import Combine
import SwiftData

@MainActor
final class GraphTransferViewModel: ObservableObject, @unchecked Sendable {

    enum ExportState {
        case idle
        case exporting(label: String)
        case ready(url: URL, summary: ExportSummary)
        case failed(message: String)
    }

    enum ImportState {
        case idle
        case inspecting(label: String)
        case ready(preview: ImportPreview)
        case importing(progress: GraphTransferProgress)
        case finished(result: ImportResult)
        case failed(message: String)
    }

    struct ExportSummary {
        var counts: CountsDTO

        var summaryText: String? {
            "\(counts.entities) Entitäten · \(counts.attributes) Attribute · \(counts.links) Links"
        }
    }

    struct AlertState: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    struct ReplaceCandidate: Identifiable, Hashable {
        var id: UUID
        var name: String
        var createdAt: Date
    }

    // UI
    @Published var activeGraphName: String = "—"

    @Published var includeNotes: Bool = true
    @Published var includeIcons: Bool = true
    @Published var includeImages: Bool = false

    @Published var exportState: ExportState = .idle
    @Published var importState: ImportState = .idle

    @Published var isShowingExportConfirm: Bool = false
    @Published var isShowingFileImporter: Bool = false
    @Published var isShowingShareSheet: Bool = false

    @Published var isShowingImportLimitAlert: Bool = false
    @Published var isShowingReplaceSheet: Bool = false
    @Published var isShowingProPaywall: Bool = false

    @Published var isShowingFileExporter: Bool = false
    @Published var exportDocument: BMGraphFileDocument = BMGraphFileDocument(data: Data())

    @Published var exportedFileURL: URL? = nil
    @Published var selectedImportURL: URL? = nil

    @Published var alertState: AlertState? = nil

    @Published var replaceCandidates: [ReplaceCandidate] = []

    private var didConfigure: Bool = false

    var isBusy: Bool {
        if case .exporting = exportState { return true }
        if case .inspecting = importState { return true }
        if case .importing = importState { return true }
        return false
    }

    func configureIfNeeded(container: AnyModelContainer) {
        guard didConfigure == false else { return }
        didConfigure = true
        Task {
            await GraphTransferService.shared.configure(container: container)
        }
    }

    func refreshActiveGraphName(using modelContext: ModelContext, activeGraphIDString: String) {
        guard let id = UUID(uuidString: activeGraphIDString) else {
            activeGraphName = "—"
            return
        }

        let gid = id
        var fd = FetchDescriptor<MetaGraph>(predicate: #Predicate { g in
            g.id == gid
        })
        fd.fetchLimit = 1

        do {
            if let graph = try modelContext.fetch(fd).first {
                let name = graph.name.trimmingCharacters(in: .whitespacesAndNewlines)
                activeGraphName = name.isEmpty ? "Graph" : name
            } else {
                activeGraphName = "—"
            }
        } catch {
            activeGraphName = "—"
        }
    }

    func requestExportConfirm() {
        guard isBusy == false else { return }
        isShowingExportConfirm = true
    }

    func exportConfirmMessage(activeGraphName: String) -> String {
        var parts: [String] = []
        parts.append("Aktiver Graph: \(activeGraphName)")

        var options: [String] = []
        if includeNotes { options.append("Notizen") }
        if includeIcons { options.append("Icons") }
        if includeImages { options.append("Bilder") }

        if options.isEmpty {
            parts.append("Export ohne Zusatzdaten.")
        } else {
            parts.append("Enthält: \(options.joined(separator: ", ")).")
        }

        return parts.joined(separator: "\n")
    }

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
            exportState = .failed(message: "Export fehlgeschlagen")
            alertState = AlertState(title: "Export fehlgeschlagen", message: userFacingMessage(for: error))
        }
    }

    func presentShareSheet() {
        guard exportedFileURL != nil else { return }
        isShowingShareSheet = true
    }

    var exportDefaultFilename: String {
        guard let url = exportedFileURL else { return "BrainMesh-Graph" }
        // fileExporter expects a filename without path.
        // We keep the base (without extension) as default.
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
            alertState = AlertState(title: "Export", message: "Datei konnte nicht geladen werden.")
            return false
        }
    }

    func handleFileExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            // optional success toast/alert is overkill; keep silent.
            break
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == 3072 {
                // userCancelled
                return
            }
            alertState = AlertState(title: "Export", message: "Speichern fehlgeschlagen.")
        }
    }

    func resetExport() {
        exportState = .idle
        exportedFileURL = nil
    }

    func handlePickedFile(_ result: Result<[URL], Error>) {
        guard isBusy == false else { return }

        // Defensive: fileImporter should be dismissed after a result.
        // If the binding remains true, SwiftUI may re-present the picker on the next render pass.
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
                // userCancelled
                return
            }
            importState = .failed(message: "Datei konnte nicht geöffnet werden")
            alertState = AlertState(title: "Import", message: userFacingMessage(for: error))
        }
    }

    private func inspectSelectedFile() async {
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

        // Defensive: ensure we never re-present the picker while starting import.
        isShowingFileImporter = false

        let uniqueGraphs = fetchUniqueGraphs(using: modelContext)
        let currentCount = uniqueGraphs.count

        if canCreateAdditionalGraph(isPro: isProActive, currentGraphCount: currentCount) {
            await performImport()
        } else {
            isShowingImportLimitAlert = true
        }
    }

    func presentReplacePicker(using modelContext: ModelContext) {
        isShowingImportLimitAlert = false
        isShowingProPaywall = false

        let uniqueGraphs = fetchUniqueGraphs(using: modelContext)
        replaceCandidates = uniqueGraphs
            .sorted { $0.createdAt < $1.createdAt }
            .map { g in
                let n = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return ReplaceCandidate(id: g.id, name: n.isEmpty ? "Graph" : n, createdAt: g.createdAt)
            }

        isShowingReplaceSheet = true
    }

    func presentProPaywall() {
        isShowingImportLimitAlert = false
        isShowingReplaceSheet = false
        isShowingProPaywall = true
    }

    func replaceAndImport(
        candidate: ReplaceCandidate,
        modelContext: ModelContext,
        graphLock: GraphLockCoordinator,
        currentActiveGraphIDString: String,
        setActiveGraphIDString: @MainActor @escaping (String) -> Void
    ) async {
        guard isBusy == false else { return }
        guard selectedImportURL != nil else { return }

        do {
            let activeID = UUID(uuidString: currentActiveGraphIDString)

            let uniqueGraphs = fetchUniqueGraphs(using: modelContext)
            let graphRecord = try fetchGraphRecord(for: candidate.id, using: modelContext)

            let deleteResult = try await GraphDeletionService.deleteGraphCompletely(
                graphToDelete: graphRecord,
                currentActiveGraphID: activeID,
                graphs: uniqueGraphs,
                uniqueGraphs: uniqueGraphs,
                modelContext: modelContext,
                graphLock: graphLock
            )

            if let newActive = deleteResult.newActiveGraphID {
                await MainActor.run {
                    setActiveGraphIDString(newActive.uuidString)
                }
            }

            await performImport()
        } catch {
            alertState = AlertState(title: "Graph ersetzen", message: "Löschen fehlgeschlagen.")
        }
    }

    func resetImport() {
        importState = .idle
        selectedImportURL = nil
    }

    private func fetchUniqueGraphs(using modelContext: ModelContext) -> [MetaGraph] {
        var fd = FetchDescriptor<MetaGraph>()
        fd.sortBy = [SortDescriptor(\MetaGraph.createdAt, order: .forward)]
        do {
            let graphs = try modelContext.fetch(fd)
            var seen = Set<UUID>()
            return graphs.filter { seen.insert($0.id).inserted }
        } catch {
            return []
        }
    }

    private func fetchGraphRecord(for id: UUID, using modelContext: ModelContext) throws -> MetaGraph {
        let gid = id
        var fd = FetchDescriptor<MetaGraph>(predicate: #Predicate { g in
            g.id == gid
        })
        fd.fetchLimit = 1
        if let g = try modelContext.fetch(fd).first {
            return g
        }
        throw GraphTransferError.graphNotFound(graphID: id)
    }

    private func performImport() async {
        guard isBusy == false else { return }
        guard let url = selectedImportURL else { return }

        // Defensive: ensure the picker is not shown while importing.
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

    private func userFacingMessage(for error: Error) -> String {
        #if DEBUG
        print("⚠️ GraphTransfer error: \(error)")
        #endif

        if let e = error as? GraphTransferError {
            switch e {
            case .fileAccessDenied:
                return "Kein Zugriff auf die ausgewählte Datei. Bitte wähle eine Datei aus der Dateien-App oder teile sie erneut in BrainMesh."
            case .invalidFormat:
                return "Diese Datei ist keine BrainMesh-Exportdatei."
            case .unsupportedVersion:
                return "Diese Exportdatei wurde mit einer neueren Version erstellt und kann aktuell nicht importiert werden."
            case .decodeFailed:
                return "Die Exportdatei ist beschädigt oder kann nicht gelesen werden."
            case .readFailed:
                return "Die Datei konnte nicht gelesen werden."
            case .saveFailed:
                return "Beim Speichern der importierten Daten ist ein Fehler aufgetreten."
            case .writeFailed:
                return "Die Exportdatei konnte nicht geschrieben werden."
            case .graphNotFound:
                return "Der gewählte Graph wurde nicht gefunden."
            case .notConfigured:
                return "Export/Import ist noch nicht bereit. Bitte starte die App neu und versuche es erneut."
            case .notImplemented:
                return "Diese Funktion ist noch nicht verfügbar."
            }
        }

        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, (ns.code == 257 || ns.code == 513) {
            return "Kein Zugriff auf die ausgewählte Datei."
        }

        return "Es ist ein unerwarteter Fehler aufgetreten."
    }
}
