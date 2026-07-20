//
//  AddLinkView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct AddLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let source: NodeRef
    let graphID: UUID?

    @State private var targetKind: NodeKind = .entity
    @State private var selectedTarget: NodeRef?

    @State private var note: String = ""
    @State private var createBidirectional: Bool = false
    @State private var showPicker = false
    @State private var showDuplicateAlert = false
    @State private var duplicateAlertMessage: String = "Diese Verbindung ist schon vorhanden."
    @State private var showSelfLinkAlert = false

    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Quelle") {
                    HStack(spacing: 12) {
                        Image(systemName: source.iconSymbolName ?? (source.kind == .entity ? "cube" : "tag"))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 22)
                            .foregroundStyle(.tint)
                        Text(source.label)
                    }
                }

                Section("Zieltyp") {
                    Picker("Zieltyp", selection: $targetKind) {
                        Text("Entität").tag(NodeKind.entity)
                        Text("Attribut").tag(NodeKind.attribute)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: targetKind) { _, _ in selectedTarget = nil }
                }

                Section("Ziel") {
                    Button { showPicker = true } label: {
                        HStack {
                            if let t = selectedTarget {
                                Image(systemName: t.iconSymbolName ?? (t.kind == .entity ? "cube" : "tag"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 22)
                                    .foregroundStyle(.tint)
                                Text(t.label)
                            } else {
                                Text("Bitte wählen…")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Optionen") {
                    Toggle("Bidirektional", isOn: $createBidirectional)
                }

                Section("Notiz (optional)") {
                    TextField("z.B. Kontext", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Link hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task { await save() }
                    }
                    .disabled(selectedTarget == nil || isSaving)
                }
            }
            .alert("Link existiert bereits", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(duplicateAlertMessage)
            }
            .alert("Nicht möglich", isPresented: $showSelfLinkAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Quelle und Ziel dürfen nicht identisch sein.")
            }
            .alert("Speichern fehlgeschlagen", isPresented: $showSaveErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .sheet(isPresented: $showPicker) {
                NodePickerView(kind: targetKind) { picked in
                    selectedTarget = picked
                    showPicker = false
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func save() async {
        guard let target = selectedTarget, !isSaving else { return }

        if target.kind == source.kind && target.id == source.id {
            showSelfLinkAlert = true
            return
        }

        guard let graphID else {
            saveErrorMessage = "Für diese Verbindung ist kein Graph zugeordnet."
            showSaveErrorAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        let sourceKindRaw = source.kind.rawValue
        let sourceID = source.id
        let targetKindRaw = target.kind.rawValue
        let targetID = target.id
        let graphScopeID = graphID

        let forwardDescriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate { link in
                link.sourceKindRaw == sourceKindRaw &&
                link.sourceID == sourceID &&
                link.targetKindRaw == targetKindRaw &&
                link.targetID == targetID &&
                link.graphID == graphScopeID
            }
        )

        let forwardExists: Bool
        let reverseExists: Bool
        do {
            forwardExists = try modelContext.fetchCount(forwardDescriptor) > 0

            if createBidirectional {
                let reverseDescriptor = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { link in
                        link.sourceKindRaw == targetKindRaw &&
                        link.sourceID == targetID &&
                        link.targetKindRaw == sourceKindRaw &&
                        link.targetID == sourceID &&
                        link.graphID == graphScopeID
                    }
                )
                reverseExists = try modelContext.fetchCount(reverseDescriptor) > 0
            } else {
                reverseExists = false
            }
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
            return
        }

        if !createBidirectional, forwardExists {
            duplicateAlertMessage = "Diese Verbindung ist schon vorhanden."
            showDuplicateAlert = true
            return
        }

        if createBidirectional, forwardExists, reverseExists {
            duplicateAlertMessage = "Beide Richtungen existieren bereits."
            showDuplicateAlert = true
            return
        }

        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = cleaned.isEmpty ? nil : cleaned

        var insertedLinks: [MetaLink] = []

        if !forwardExists {
            let forward = MetaLink(
                sourceKind: source.kind,
                sourceID: source.id,
                sourceLabel: source.label,
                targetKind: target.kind,
                targetID: target.id,
                targetLabel: target.label,
                note: finalNote,
                graphID: graphID
            )
            modelContext.insert(forward)
            insertedLinks.append(forward)
        }

        if createBidirectional, !reverseExists {
            let reverse = MetaLink(
                sourceKind: target.kind,
                sourceID: target.id,
                sourceLabel: target.label,
                targetKind: source.kind,
                targetID: source.id,
                targetLabel: source.label,
                note: finalNote,
                graphID: graphID
            )
            modelContext.insert(reverse)
            insertedLinks.append(reverse)
        }

        guard !insertedLinks.isEmpty else { return }

        do {
            let references = insertedLinks.map { link in
                GraphMutationLinkReference(
                    id: link.id,
                    source: NodeRefKey(kind: link.sourceKind, id: link.sourceID),
                    target: NodeRefKey(kind: link.targetKind, id: link.targetID)
                )
            }
            let batch = try GraphMutationBatchFactory.linksCreated(
                graphID: graphID,
                links: references
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            dismiss()
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}
