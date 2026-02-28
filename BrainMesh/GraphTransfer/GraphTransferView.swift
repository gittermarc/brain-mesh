//
//  GraphTransferView.swift
//  BrainMesh
//
//  UI for exporting and importing graphs as .bmgraph files.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import Combine

struct GraphTransferView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabRouter: RootTabRouter
    @EnvironmentObject private var systemModals: SystemModalCoordinator

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""

    @StateObject private var model = GraphTransferViewModel()

    var body: some View {
        List {
            exportSection
            importSection
        }
        .navigationTitle("Export & Import")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await configureIfNeeded()
            await refreshActiveGraphName()
        }
        .onChange(of: activeGraphIDString) { _, _ in
            Task { await refreshActiveGraphName() }
        }
        .fileImporter(
            isPresented: $model.isShowingFileImporter,
            allowedContentTypes: [.brainMeshGraph],
            allowsMultipleSelection: false
        ) { result in
            // Always end the "system modal" grace window.
            systemModals.endSystemModal()
            model.handlePickedFile(result)
        }
        .sheet(isPresented: $model.isShowingShareSheet, onDismiss: {
            systemModals.endSystemModal()
        }) {
            if let url = model.exportedFileURL {
                ActivityView(itemSource: ExportActivityItemSource(fileURL: url))
            } else {
                ActivityView(itemSource: nil)
            }
        }
        
        .fileExporter(
            isPresented: $model.isShowingFileExporter,
            document: model.exportDocument,
            contentType: .brainMeshGraph,
            defaultFilename: model.exportDefaultFilename
        ) { result in
            systemModals.endSystemModal()
            model.handleFileExportResult(result)
        }
.alert(item: $model.alertState) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(
            "Export erstellen?",
            isPresented: $model.isShowingExportConfirm,
            actions: {
                Button("Abbrechen", role: .cancel) { }
                Button("Erstellen") {
                    Task {
                        await model.startExport(activeGraphIDString: activeGraphIDString)
                    }
                }
            },
            message: {
                Text(model.exportConfirmMessage(activeGraphName: model.activeGraphName))
            }
        )
    }

    private var exportSection: some View {
        Section {
            LabeledContent("Aktiver Graph") {
                Text(model.activeGraphName)
                    .foregroundStyle(.secondary)
            }

            Toggle("Notizen exportieren", isOn: $model.includeNotes)
                .disabled(model.isBusy)

            Toggle("Icons exportieren", isOn: $model.includeIcons)
                .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Bilder exportieren", isOn: $model.includeImages)
                    .disabled(model.isBusy)
                Text("Hinweis: Bilder machen die Datei deutlich größer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            exportActionRow
        } header: {
            Text("Export")
        }
    }

    @ViewBuilder
    private var exportActionRow: some View {
        switch model.exportState {
        case .idle:
            Button {
                model.requestExportConfirm()
            } label: {
                Label("Export erstellen", systemImage: "square.and.arrow.up")
            }
            .disabled(model.isBusy || UUID(uuidString: activeGraphIDString) == nil)

        case .exporting(let label):
            HStack(spacing: 10) {
                ProgressView()
                Text(label)
            }

        case .ready(let url, let summary):
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export bereit")
                        .font(.headline)
                    Text(url.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Menu {
                        Button {
                            systemModals.beginSystemModal()
                            model.presentShareSheet()
                        } label: {
                            Label("Teilen…", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            systemModals.beginSystemModal()
                            if model.prepareFileExporter() == false {
                                systemModals.endSystemModal()
                            }
                        } label: {
                            Label("In Dateien speichern…", systemImage: "folder")
                        }
                    } label: {
                        Label("Teilen / Speichern…", systemImage: "square.and.arrow.up")
                    }

                    Spacer()

                    Button("Zurücksetzen") {
                        model.resetExport()
                    }
                    .foregroundStyle(.secondary)
                }

                if let summaryText = summary.summaryText {
                    Text(summaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Erneut versuchen") {
                    model.requestExportConfirm()
                }
                .disabled(model.isBusy || UUID(uuidString: activeGraphIDString) == nil)
            }
        }
    }

    private var importSection: some View {
        Section {
            importActionRows
        } header: {
            Text("Import")
        }
    }

    @ViewBuilder
    private var importActionRows: some View {
        switch model.importState {
        case .idle:
            Button {
                systemModals.beginSystemModal()
                model.isShowingFileImporter = true
            } label: {
                Label("Datei auswählen…", systemImage: "doc")
            }
            .disabled(model.isBusy)

        case .inspecting(let label):
            HStack(spacing: 10) {
                ProgressView()
                Text(label)
            }

        case .ready(let preview):
            VStack(alignment: .leading, spacing: 12) {
                importPreviewCard(preview)

                HStack {
                    Button {
                        Task {
                            await model.startImport()
                        }
                    } label: {
                        Label("Import starten", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(model.isBusy)

                    Spacer()

                    Button("Andere Datei…") {
                        systemModals.beginSystemModal()
                        model.isShowingFileImporter = true
                    }
                    .foregroundStyle(.secondary)
                    .disabled(model.isBusy)
                }
            }

        case .importing(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView(value: progress.fraction)
                    Text(progress.label)
                }
                if let total = progress.total {
                    Text("\(progress.completed)/\(total)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        case .finished(let result):
            VStack(alignment: .leading, spacing: 12) {
                importResultCard(result)

                Button {
                    activeGraphIDString = result.newGraphID.uuidString
                    Task { @MainActor in
                        tabRouter.openGraph()
                    }
                } label: {
                    Label("Zum importierten Graph wechseln", systemImage: "arrow.turn.down.right")
                }

                Button("Fertig") {
                    model.resetImport()
                }
                .foregroundStyle(.secondary)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Andere Datei…") {
                        systemModals.beginSystemModal()
                        model.isShowingFileImporter = true
                    }
                    .disabled(model.isBusy)
                    Spacer()
                    Button("Zurücksetzen") {
                        model.resetImport()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func importPreviewCard(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.graphName.isEmpty ? "Graph" : preview.graphName)
                .font(.headline)

            Text("Exportiert am \(preview.exportedAt.formatted(date: .abbreviated, time: .omitted)) · Version \(preview.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Entitäten", value: "\(preview.counts.entities)")
                LabeledContent("Attribute", value: "\(preview.counts.attributes)")
                LabeledContent("Links", value: "\(preview.counts.links)")
                LabeledContent("Details-Felder", value: "\(preview.counts.detailFieldDefinitions)")
                LabeledContent("Details-Werte", value: "\(preview.counts.detailFieldValues)")
            }
            .font(.footnote)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func importResultCard(_ result: ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import abgeschlossen")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Entitäten", value: "\(result.insertedCounts.entities)")
                LabeledContent("Attribute", value: "\(result.insertedCounts.attributes)")
                LabeledContent("Links", value: "\(result.insertedCounts.links)")
                if result.skippedLinks > 0 {
                    LabeledContent("Übersprungene Links", value: "\(result.skippedLinks)")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func configureIfNeeded() async {
        model.configureIfNeeded(container: AnyModelContainer(modelContext.container))
    }

    @MainActor
    private func refreshActiveGraphName() async {
        model.refreshActiveGraphName(using: modelContext, activeGraphIDString: activeGraphIDString)
    }
}

// MARK: - View Model

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

    @Published var isShowingFileExporter: Bool = false
    @Published var exportDocument: BMGraphFileDocument = BMGraphFileDocument(data: Data())

    @Published var exportedFileURL: URL? = nil
    @Published var selectedImportURL: URL? = nil

    @Published var alertState: AlertState? = nil

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
            alertState = AlertState(title: "Export fehlgeschlagen", message: String(describing: error))
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
            alertState = AlertState(title: "Export", message: "Datei konnte nicht geladen werden: \(error)")
            return false
        }
        return false
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
            alertState = AlertState(title: "Export", message: "Speichern fehlgeschlagen: \(error)")
        }
    }

    func resetExport() {
        exportState = .idle
        exportedFileURL = nil
    }

    func handlePickedFile(_ result: Result<[URL], Error>) {
        guard isBusy == false else { return }

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
            alertState = AlertState(title: "Import", message: String(describing: error))
        }
    }

    private func inspectSelectedFile() async {
        guard let url = selectedImportURL else { return }
        do {
            let preview = try await GraphTransferService.shared.inspectFile(url: url)
            importState = .ready(preview: preview)
        } catch {
            importState = .failed(message: "Datei ist ungültig")
            alertState = AlertState(title: "Import", message: String(describing: error))
        }
    }

    func startImport() async {
        guard isBusy == false else { return }
        guard let url = selectedImportURL else { return }

        importState = .importing(progress: GraphTransferProgress(phase: .inspecting, completed: 0, label: "Import läuft…"))

        let progressHandler: @Sendable (GraphTransferProgress) -> Void = { [weak self] prog in
            Task { @MainActor in
                guard let self else { return }
                self.importState = .importing(progress: prog)
            }
        }

        do {
            let result = try await GraphTransferService.shared.importGraph(from: url, mode: .asNewGraphRemap, progress: progressHandler)
            importState = .finished(result: result)
        } catch {
            importState = .failed(message: "Import fehlgeschlagen")
            alertState = AlertState(title: "Import fehlgeschlagen", message: String(describing: error))
        }
    }

    func resetImport() {
        importState = .idle
        selectedImportURL = nil
    }
}

// MARK: - Share Sheet

private struct ActivityView: UIViewControllerRepresentable {
    let itemSource: ExportActivityItemSource?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = itemSource.map { [$0] } ?? []
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // no-op
    }
}



private final class ExportActivityItemSource: NSObject, UIActivityItemSource {

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.brainMeshGraph.identifier
    }
}

struct BMGraphFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.brainMeshGraph] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#Preview {
    NavigationStack {
        GraphTransferView()
    }
    .environmentObject(RootTabRouter())
    .environmentObject(SystemModalCoordinator())
}
