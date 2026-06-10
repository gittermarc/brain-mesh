//
//  GraphTransferView+ExportFlow.swift
//  BrainMesh
//

import SwiftUI

extension GraphTransferView {

    var exportSection: some View {
        Section {
            LabeledContent("Aktiver Graph") {
                Text(model.activeGraphName)
                    .foregroundStyle(.secondary)
            }

            Picker("Exporttyp", selection: $model.exportKind) {
                ForEach(GraphTransferExportKind.allCases) { kind in
                    Text(kind.shortTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isBusy)

            GraphTransferExportKindInfoCard(
                kind: model.exportKind,
                attachmentEstimate: model.activeGraphAttachmentEstimate
            )

            Toggle("Notizen exportieren", isOn: $model.includeNotes)
                .disabled(model.isBusy)

            Toggle("Icons exportieren", isOn: $model.includeIcons)
                .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Headerbilder exportieren", isOn: $model.includeImages)
                    .disabled(model.isBusy)
                Text(headerImagesHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.exportKind == .fullBackup {
                GraphTransferAttachmentExportOptionView(
                    includeAttachments: $model.includeAttachments,
                    estimate: model.activeGraphAttachmentEstimate,
                    isDisabled: model.isBusy
                )
            }

            exportActionRow
        } header: {
            Text("Export")
        }
    }

    @ViewBuilder
    var exportActionRow: some View {
        switch model.exportState {
        case .idle:
            Button {
                model.requestExportConfirm()
            } label: {
                Label(exportButtonTitle, systemImage: model.exportKind.systemImage)
            }
            .disabled(model.isBusy || UUID(uuidString: activeGraphIDString) == nil)

        case .exporting(let label):
            HStack(spacing: 10) {
                ProgressView()
                Text(label)
            }

        case .ready(let url, let summary):
            GraphTransferExportReadyCard(
                fileURL: url,
                kind: summary.kind,
                summaryText: summary.summaryText,
                onShare: {
                    systemModals.beginSystemModal()
                    model.presentShareSheet()
                },
                onSaveToFiles: {
                    systemModals.beginSystemModal()
                    if model.prepareFileExporter() == false {
                        systemModals.endSystemModal()
                    }
                },
                onReset: {
                    model.resetExport()
                }
            )

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

    private var headerImagesHelpText: String {
        switch model.exportKind {
        case .graphStructure:
            return "Exportiert nur Titelbilder von Entitäten und Attributen. Separate Anhänge, Dateien, Videos und Galerie-Bilder bleiben außerhalb der .bmgraph-Datei."
        case .fullBackup:
            return "Nimmt Titelbilder von Entitäten und Attributen in die eingebettete Graph-Struktur auf. Separate Anhänge steuerst du unten."
        }
    }

    private var exportButtonTitle: String {
        switch model.exportKind {
        case .graphStructure:
            return "Struktur-Export erstellen"
        case .fullBackup:
            return "Vollbackup erstellen"
        }
    }
}
