//
//  GraphTransferView.swift
//  BrainMesh
//
//  UI for exporting and importing graphs as .bmgraph files.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct GraphTransferView: View {

    // NOTE:
    // These properties are intentionally *not* marked `private` because this view is split
    // across multiple extension files (ExportFlow / ImportFlow). Swift `private` is file-scoped,
    // so those extensions would not be able to access the bindings.
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var tabRouter: RootTabRouter
    @EnvironmentObject var systemModals: SystemModalCoordinator
    @EnvironmentObject var graphLock: GraphLockCoordinator
    @EnvironmentObject var proStore: ProEntitlementStore

    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""

    @StateObject var model = GraphTransferViewModel()

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
            Task { @MainActor in
                // Always end the "system modal" grace window.
                systemModals.endSystemModal()
                // Defensive: make sure the file importer can't re-open on state updates.
                model.isShowingFileImporter = false
                model.handlePickedFile(result)
            }
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
        .sheet(isPresented: $model.isShowingReplaceSheet) {
            NavigationStack {
                GraphReplacePickerSheet(
                    candidates: model.replaceCandidates,
                    onCancel: {
                        model.isShowingReplaceSheet = false
                    },
                    onConfirmReplace: { candidate in
                        model.isShowingReplaceSheet = false
                        Task {
                            await model.replaceAndImport(
                                candidate: candidate,
                                modelContext: modelContext,
                                graphLock: graphLock,
                                currentActiveGraphIDString: activeGraphIDString,
                                setActiveGraphIDString: { newValue in
                                    activeGraphIDString = newValue
                                }
                            )
                        }
                    }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $model.isShowingProPaywall) {
            ProPaywallView(feature: .moreGraphs)
        }
        .fileExporter(
            isPresented: $model.isShowingFileExporter,
            document: model.exportDocument,
            contentType: .brainMeshGraph,
            defaultFilename: model.exportDefaultFilename
        ) { result in
            Task { @MainActor in
                systemModals.endSystemModal()
                model.handleFileExportResult(result)
            }
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
        .alert(
            "Mehrere Graphen sind Pro",
            isPresented: $model.isShowingImportLimitAlert,
            actions: {
                Button("Abbrechen", role: .cancel) { }
                Button("Pro aktivieren") {
                    model.presentProPaywall()
                }
                Button("Graph ersetzen") {
                    model.presentReplacePicker(using: modelContext)
                }
            },
            message: {
                Text("In der Gratis-Version kannst du bis zu \(GraphTransferLimits.freeMaxGraphs) Graphen haben. Du kannst einen vorhandenen Graphen ersetzen oder Pro aktivieren.")
            }
        )
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

#Preview {
    NavigationStack {
        GraphTransferView()
    }
    .environmentObject(RootTabRouter())
    .environmentObject(SystemModalCoordinator())
    .environmentObject(GraphLockCoordinator())
    .environmentObject(ProEntitlementStore())
}
