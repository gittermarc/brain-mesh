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
    var exportActionRow: some View {
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
            GraphTransferExportReadyCard(
                fileURL: url,
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
}
