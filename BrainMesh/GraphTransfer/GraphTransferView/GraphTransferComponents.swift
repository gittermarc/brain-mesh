//
//  GraphTransferComponents.swift
//  BrainMesh
//

import Foundation
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
    let kind: GraphTransferExportKind
    let summaryText: String?
    let onShare: () -> Void
    let onSaveToFiles: () -> Void
    let onReset: () -> Void

    var body: some View {
        // Keep this as a plain List row (no card background) to preserve the original UI.
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Export bereit", systemImage: kind.systemImage)
                    .font(.headline)

                Text("\(kind.title) · \(kind.shortTitle)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(fileURL.lastPathComponent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Menu {
                    Button {
                        onShare()
                    } label: {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        onSaveToFiles()
                    } label: {
                        Label("In Dateien speichern", systemImage: "folder")
                    }
                } label: {
                    Label("Teilen / Speichern", systemImage: "square.and.arrow.up")
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


struct GraphTransferExportKindInfoCard: View {
    let kind: GraphTransferExportKind
    let attachmentEstimate: GraphTransferAttachmentEstimate

    var body: some View {
        GraphTransferCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.headline)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if kind == .fullBackup {
                    Text(attachmentEstimate.compactSummary)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if attachmentEstimate.isLargeBackup {
                        Label("Große Backups können länger dauern und viel Speicher benötigen.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var message: String {
        switch kind {
        case .graphStructure:
            return ".bmgraph ist schnell und klein. Es enthält die Graph-Struktur, aber keine separaten Anhänge wie Dateien, Videos oder Galerie-Bilder."
        case .fullBackup:
            return ".bmbackup ist für vollständige Sicherungen gedacht. Es enthält die Graph-Struktur plus separate Anhang-Dateien aus MetaAttachment."
        }
    }
}

struct GraphTransferAttachmentExportOptionView: View {
    @Binding var includeAttachments: Bool
    let estimate: GraphTransferAttachmentEstimate
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Anhänge ins Vollbackup aufnehmen", isOn: $includeAttachments)
                .disabled(isDisabled)

            Text(helpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if includeAttachments, estimate.isLargeBackup {
                Label("Dieses Vollbackup wird voraussichtlich groß. Plane für Export und Import etwas Zeit ein.", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var helpText: String {
        if estimate.hasAttachments == false {
            return "Im aktiven Graph wurden keine Anhänge gefunden. Die Option bleibt verfügbar, falls vor dem Export noch Anhänge hinzukommen."
        }
        return "Geschätzt: \(estimate.compactSummary). Die Schätzung nutzt gespeicherte Metadaten und lädt keine großen Dateien nur für diese Anzeige."
    }
}


struct GraphTransferImportPreviewCard: View {
    let preview: ImportPreview

    var body: some View {
        GraphTransferCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                counts
                if preview.isFullBackup {
                    backupMetrics
                    GraphTransferFullBackupScopeView()
                } else {
                    GraphTransferGraphStructureScopeView()
                }
                GraphTransferPreviewIssuesBlock(title: "Probleme", items: preview.blockingProblems)
                GraphTransferPreviewIssuesBlock(title: "Hinweise", items: preview.warnings)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(preview.kind.title, systemImage: preview.isFullBackup ? "shippingbox" : "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(preview.graphName.isEmpty ? "Graph" : preview.graphName)
                .font(.headline)

            Text("Exportiert am \(preview.exportedAt.formatted(date: .abbreviated, time: .omitted)) · Version \(preview.version)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var counts: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Entitäten", value: "\(preview.counts.entities)")
            LabeledContent("Attribute", value: "\(preview.counts.attributes)")
            LabeledContent("Links", value: "\(preview.counts.links)")
            LabeledContent("Details-Felder", value: "\(preview.counts.detailFieldDefinitions)")
            LabeledContent("Details-Werte", value: "\(preview.counts.detailFieldValues)")
        }
        .font(.footnote)
    }

    private var backupMetrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Anhänge", value: "\(preview.attachmentCount)")
            LabeledContent("Anhang-Größe", value: preview.attachmentBytesText)
        }
        .font(.footnote)
    }
}

struct GraphTransferImportUnavailableCard: View {
    let preview: ImportPreview

    var body: some View {
        GraphTransferCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preview.blockingProblems.isEmpty ? "clock" : "exclamationmark.triangle")
                    .foregroundStyle(preview.blockingProblems.isEmpty ? Color.secondary : Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var title: String {
        "Import aktuell nicht möglich"
    }

    private var message: String {
        if preview.isFullBackup {
            return "Dieses Full Backup enthält blockierende Probleme. Erstelle das Backup erneut oder wähle eine andere Datei."
        }
        return "Die Vorschau enthält blockierende Probleme. Wähle eine andere Datei oder exportiere den Graph erneut."
    }
}

private struct GraphTransferPreviewIssuesBlock: View {
    let title: String
    let items: [GraphBackupPreviewWarning]

    var body: some View {
        if items.isEmpty == false {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                ForEach(items, id: \.stableID) { item in
                    GraphTransferPreviewIssueRow(item: item)
                }
            }
        }
    }
}

private struct GraphTransferPreviewIssueRow: View {
    let item: GraphBackupPreviewWarning

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(item.severity == .blocking ? .red : .orange)
            Text(item.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GraphTransferGraphStructureScopeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
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

private struct GraphTransferFullBackupScopeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            GraphTransferScopeBullet(
                title: "Enthalten",
                detail: "Graph-Struktur plus separate Anhang-Dateien aus dem Backup-Paket."
            )
            GraphTransferScopeBullet(
                title: "Geprüft",
                detail: "Manifest, eingebettete Graph-Datei, Anhang-Pfade, Dateigrößen und vorhandene Prüfsummen."
            )
            GraphTransferScopeBullet(
                title: "Nicht enthalten",
                detail: "Graph-Schutz, Passwörter, Biometrie-Einstellungen und Pro-Status."
            )
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
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
                    if result.importedAttachments > 0 {
                        LabeledContent("Anhänge", value: "\(result.importedAttachments)")
                    }
                    if result.skippedAttachments > 0 {
                        LabeledContent("Übersprungene Anhänge", value: "\(result.skippedAttachments)")
                    }
                    if result.warnings.isEmpty == false {
                        LabeledContent("Hinweise", value: "\(result.warnings.count)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if result.warnings.isEmpty == false {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hinweise")
                            .font(.footnote.weight(.semibold))
                        ForEach(result.warnings, id: \.self) { warning in
                            Text("• \(warning)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
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

                scopeBullets
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
            return "BrainMesh importiert .bmgraph-Struktur-Exporte und .bmbackup-Full-Backups als neuen Graph. Full Backups stellen zusätzlich Anhänge wieder her, soweit die Paketdateien vollständig sind."
        }
    }

    @ViewBuilder
    private var scopeBullets: some View {
        switch mode {
        case .exportScope:
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
        case .importScope:
            VStack(alignment: .leading, spacing: 6) {
                GraphTransferScopeBullet(
                    title: ".bmgraph",
                    detail: "Struktur-Exporte können wie bisher als neuer Graph importiert werden."
                )
                GraphTransferScopeBullet(
                    title: ".bmbackup",
                    detail: "Full Backups werden als neuer Graph importiert und stellen Anhänge inklusive Datei-, Video- und Galerie-Daten wieder her."
                )
                GraphTransferScopeBullet(
                    title: "Nicht enthalten",
                    detail: "Graph-Schutz, Passwörter, Biometrie-Einstellungen und Pro-Status werden nicht aus Transferdateien übernommen."
                )
            }
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
        if fileURL.pathExtension.lowercased() == GraphBackupFormat.filenameExtension {
            return UTType.brainMeshBackup.identifier
        }
        return UTType.brainMeshGraph.identifier
    }
}

// MARK: - File Export Document

struct BMGraphFileDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.brainMeshGraph, .brainMeshBackup] }

    private var wrapper: FileWrapper

    init(data: Data) {
        self.wrapper = FileWrapper(regularFileWithContents: data)
    }

    init(data: Data, contentType: UTType) {
        self.wrapper = FileWrapper(regularFileWithContents: data)
        let fallbackExtension = Self.fallbackFilenameExtension(for: contentType)
        let filenameExtension = contentType.preferredFilenameExtension ?? fallbackExtension
        self.wrapper.preferredFilename = "Export.\(filenameExtension)"
    }

    init(fileURL: URL, contentType: UTType) throws {
        self.wrapper = try FileWrapper(url: fileURL, options: [])
        self.wrapper.preferredFilename = fileURL.lastPathComponent
    }

    init(configuration: ReadConfiguration) throws {
        self.wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }

    private static func fallbackFilenameExtension(for contentType: UTType) -> String {
        if contentType == UTType.brainMeshBackup {
            return UTType.brainMeshBackupFilenameExtension
        }
        return UTType.brainMeshGraphFilenameExtension
    }
}
