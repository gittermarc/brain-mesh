//
//  GraphTransferView+ImportFlow.swift
//  BrainMesh
//

import SwiftUI

extension GraphTransferView {

    var importSection: some View {
        Section {
            importActionRows
        } header: {
            Text("Import")
        }
    }

    @ViewBuilder
    var importActionRows: some View {
        switch model.importState {
        case .idle:
            Button {
                presentFileImporter()
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
            // NOTE: In a List row, nested buttons inside a single VStack can sometimes become unreliable
            // (the row highlights but the inner buttons don't fire). By returning multiple top-level rows
            // here, each button becomes its own List row and remains consistently tappable.
            GraphTransferImportPreviewCard(preview: preview)

            Button {
                Task {
                    await model.attemptStartImport(using: modelContext, isProActive: proStore.isProActive)
                }
            } label: {
                Label("Import starten", systemImage: "tray.and.arrow.down")
            }
            .disabled(model.isBusy)
            .buttonStyle(.borderless)

            Button {
                presentFileImporter()
            } label: {
                Text("Andere Datei…")
            }
            .foregroundStyle(.secondary)
            .disabled(model.isBusy)
            .buttonStyle(.borderless)

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
            GraphTransferImportResultCard(result: result)

            Button {
                activeGraphIDString = result.newGraphID.uuidString
                Task { @MainActor in
                    tabRouter.openGraph()
                }
            } label: {
                Label("Zum importierten Graph wechseln", systemImage: "arrow.turn.down.right")
            }
            .buttonStyle(.borderless)

            Button {
                model.resetImport()
            } label: {
                Text("Fertig")
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)

        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)

            Button {
                presentFileImporter()
            } label: {
                Text("Andere Datei…")
            }
            .disabled(model.isBusy)
            .buttonStyle(.borderless)

            Button {
                model.resetImport()
            } label: {
                Text("Zurücksetzen")
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
        }
    }

    @MainActor
    private func presentFileImporter() {
        // Always close any stale presentation state first.
        model.isShowingFileImporter = false
        systemModals.beginSystemModal()
        // Present on the next runloop tick so SwiftUI sees a state change.
        Task { @MainActor in
            await Task.yield()
            model.isShowingFileImporter = true
        }
    }
}
