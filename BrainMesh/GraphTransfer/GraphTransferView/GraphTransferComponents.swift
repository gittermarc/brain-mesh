//
//  GraphTransferComponents.swift
//  BrainMesh
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Shared Cards

struct GraphTransferCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GraphTransferExportReadyCard: View {
    let fileURL: URL
    let summaryText: String?
    let onShare: () -> Void
    let onSaveToFiles: () -> Void
    let onReset: () -> Void

    var body: some View {
        // Keep this as a plain List row (no card background) to preserve the original UI.
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export bereit")
                    .font(.headline)
                Text(fileURL.lastPathComponent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Menu {
                    Button {
                        onShare()
                    } label: {
                        Label("Teilen…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        onSaveToFiles()
                    } label: {
                        Label("In Dateien speichern…", systemImage: "folder")
                    }
                } label: {
                    Label("Teilen / Speichern…", systemImage: "square.and.arrow.up")
                }

                Spacer()

                Button("Zurücksetzen") {
                    onReset()
                }
                .foregroundStyle(.secondary)
            }

            if let summaryText {
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GraphTransferImportPreviewCard: View {
    let preview: ImportPreview

    var body: some View {
        GraphTransferCard {
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

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    GraphTransferScopeBullet(
                        title: "Importiert",
                        detail: "Graph-Struktur, Entitäten, Attribute, Links, Details-Felder und Details-Werte aus dieser Datei."
                    )
                    GraphTransferScopeBullet(
                        title: "Möglich",
                        detail: "Notizen, Icons und Headerbilder, wenn sie in diesem Export enthalten sind."
                    )
                    GraphTransferScopeBullet(
                        title: "Nicht dabei",
                        detail: "Separate Anhänge, Dateien, Videos, Galerie-Bilder, Graph-Schutz und Pro-Status."
                    )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct GraphTransferImportResultCard: View {
    let result: ImportResult

    var body: some View {
        GraphTransferCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import abgeschlossen")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Entitäten", value: "\(result.insertedCounts.entities)")
                    LabeledContent("Attribute", value: "\(result.insertedCounts.attributes)")
                    LabeledContent("Links", value: "\(result.insertedCounts.links)")
                    LabeledContent("Details-Felder", value: "\(result.insertedCounts.detailFieldDefinitions)")
                    LabeledContent("Details-Werte", value: "\(result.insertedCounts.detailFieldValues)")
                    if result.skippedLinks > 0 {
                        LabeledContent("Übersprungene Links", value: "\(result.skippedLinks)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}


struct GraphTransferScopeInfoCard: View {
    enum Mode {
        case exportScope
        case importScope
    }

    let mode: Mode

    var body: some View {
        GraphTransferCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Text(intro)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    GraphTransferScopeBullet(
                        title: "Enthalten",
                        detail: "Graph-Struktur, Entitäten, Attribute, Links, Details-Felder und Details-Werte."
                    )
                    GraphTransferScopeBullet(
                        title: "Optional",
                        detail: "Notizen, Icons und Headerbilder von Entitäten oder Attributen, wenn sie beim Export ausgewählt wurden."
                    )
                    GraphTransferScopeBullet(
                        title: "Nicht enthalten",
                        detail: "Separate Anhänge, Dateien, Videos, Galerie-Bilder, Graph-Schutz, Passwörter, Biometrie-Einstellungen und Pro-Status."
                    )
                }
                .font(.footnote)
            }
        }
    }

    private var title: String {
        switch mode {
        case .exportScope:
            return "Was wird exportiert?"
        case .importScope:
            return "Was wird importiert?"
        }
    }

    private var systemImage: String {
        switch mode {
        case .exportScope:
            return "square.and.arrow.up"
        case .importScope:
            return "tray.and.arrow.down"
        }
    }

    private var intro: String {
        switch mode {
        case .exportScope:
            return ".bmgraph ist ein Graph-Struktur-Export. Er ist ideal zum Umziehen, Teilen oder Wiederherstellen der Graph-Struktur, aber kein vollständiges Medien-Backup."
        case .importScope:
            return "BrainMesh prüft die .bmgraph-Datei vor dem Import und legt daraus einen neuen Graph an. Bestehende Graphen bleiben unverändert, solange du keinen Graph ersetzt."
        }
    }
}

private struct GraphTransferScopeBullet: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Share Sheet

struct ActivityView: UIViewControllerRepresentable {
    let itemSource: ExportActivityItemSource?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = itemSource.map { [$0] } ?? []
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // no-op
    }
}

final class ExportActivityItemSource: NSObject, UIActivityItemSource {

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.brainMeshGraph.identifier
    }
}

// MARK: - File Export Document

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
