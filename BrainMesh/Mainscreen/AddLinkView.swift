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
    @State private var showPicker = false
    @State private var showDuplicateAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Quelle") { Text(source.label) }

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
                            Text(selectedTarget?.label ?? "Bitte wählen…")
                                .foregroundStyle(selectedTarget == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notiz (optional)") {
                    TextField("z.B. Kontext", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Link hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(selectedTarget == nil)
                }
            }
            .alert("Link existiert bereits", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Diese Verbindung ist schon vorhanden.")
            }
            .sheet(isPresented: $showPicker) {
                NodePickerView(kind: targetKind) { picked in
                    selectedTarget = picked
                    showPicker = false
                }
            }
        }
    }

    private func save() {
        guard let target = selectedTarget else { return }

        let sKind = source.kind.rawValue
        let sID = source.id
        let tKind = target.kind.rawValue
        let tID = target.id
        let gid = graphID

        let fd = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == sKind &&
                l.sourceID == sID &&
                l.targetKindRaw == tKind &&
                l.targetID == tID &&
                (gid == nil || l.graphID == gid)
            }
        )

        if let existing = try? modelContext.fetch(fd), !existing.isEmpty {
            showDuplicateAlert = true
            return
        }

        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = cleaned.isEmpty ? nil : cleaned

        let link = MetaLink(
            sourceKind: source.kind,
            sourceID: source.id,
            sourceLabel: source.label,
            targetKind: target.kind,
            targetID: target.id,
            targetLabel: target.label,
            note: finalNote,
            graphID: gid
        )

        modelContext.insert(link)
        try? modelContext.save()
        dismiss()
    }
}
