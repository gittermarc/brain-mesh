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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(selectedTarget == nil)
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
    }

    private func save() {
        guard let target = selectedTarget else { return }

        if target.kind == source.kind && target.id == source.id {
            showSelfLinkAlert = true
            return
        }

        let sKind = source.kind.rawValue
        let sID = source.id
        let tKind = target.kind.rawValue
        let tID = target.id
        let gid = graphID

        let forwardFD: FetchDescriptor<MetaLink>
        if let gid {
            forwardFD = FetchDescriptor<MetaLink>(
                predicate: #Predicate { l in
                    l.sourceKindRaw == sKind &&
                    l.sourceID == sID &&
                    l.targetKindRaw == tKind &&
                    l.targetID == tID &&
                    l.graphID == gid
                }
            )
        } else {
            forwardFD = FetchDescriptor<MetaLink>(
                predicate: #Predicate { l in
                    l.sourceKindRaw == sKind &&
                    l.sourceID == sID &&
                    l.targetKindRaw == tKind &&
                    l.targetID == tID
                }
            )
        }

        let forwardExists = ((try? modelContext.fetchCount(forwardFD)) ?? 0) > 0

        var reverseExists = false
        if createBidirectional {
            let reverseFD: FetchDescriptor<MetaLink>
            if let gid {
                reverseFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { l in
                        l.sourceKindRaw == tKind &&
                        l.sourceID == tID &&
                        l.targetKindRaw == sKind &&
                        l.targetID == sID &&
                        l.graphID == gid
                    }
                )
            } else {
                reverseFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { l in
                        l.sourceKindRaw == tKind &&
                        l.sourceID == tID &&
                        l.targetKindRaw == sKind &&
                        l.targetID == sID
                    }
                )
            }
            reverseExists = ((try? modelContext.fetchCount(reverseFD)) ?? 0) > 0
        }

        if !createBidirectional {
            if forwardExists {
                duplicateAlertMessage = "Diese Verbindung ist schon vorhanden."
                showDuplicateAlert = true
                return
            }
        } else {
            if forwardExists && reverseExists {
                duplicateAlertMessage = "Beide Richtungen existieren bereits."
                showDuplicateAlert = true
                return
            }
        }

        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = cleaned.isEmpty ? nil : cleaned

        var inserted: [MetaLink] = []

        if !forwardExists {
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
            inserted.append(link)
        }

        if createBidirectional && !reverseExists {
            let reverse = MetaLink(
                sourceKind: target.kind,
                sourceID: target.id,
                sourceLabel: target.label,
                targetKind: source.kind,
                targetID: source.id,
                targetLabel: source.label,
                note: finalNote,
                graphID: gid
            )
            modelContext.insert(reverse)
            inserted.append(reverse)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
            for l in inserted {
                modelContext.delete(l)
            }
        }
    }
}
