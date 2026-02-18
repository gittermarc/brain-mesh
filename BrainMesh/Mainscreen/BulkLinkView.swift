//
//  BulkLinkView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData

struct BulkLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let source: NodeRef
    let graphID: UUID?

    @State private var selectedTargets: Set<NodeRef> = []
    @State private var note: String = ""
    @State private var createBidirectional: Bool = false
    @State private var ignoreDuplicates: Bool = true

    @State private var existingOutgoingTargets: Set<NodeRefKey> = []
    @State private var existingIncomingSources: Set<NodeRefKey> = []

    @State private var showOnlyUnlinked: Bool = false
    @State private var resultAlert: BulkLinkResult?
    @State private var errorAlert: BulkLinkError?

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

                Section("Ziele") {
                    NavigationLink {
                        NodeMultiPickerView(
                            source: source,
                            graphID: graphID,
                            selection: $selectedTargets,
                            alreadyLinkedTargets: existingOutgoingTargets,
                            showOnlyUnlinked: $showOnlyUnlinked
                        )
                    } label: {
                        HStack {
                            Text("Ziele auswählen")
                            Spacer()
                            Text("\(selectedTargets.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !selectedTargets.isEmpty {
                        let preview = selectedPreviewRows
                        ForEach(preview, id: \.self) { r in
                            HStack(spacing: 12) {
                                Image(systemName: r.iconSymbolName ?? (r.kind == .entity ? "cube" : "tag"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 22)
                                    .foregroundStyle(.tint)
                                Text(r.label)
                                Spacer(minLength: 0)
                                Button {
                                    selectedTargets.remove(r)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Entfernen")
                            }
                        }

                        if selectedTargets.count > preview.count {
                            Text("… und \(selectedTargets.count - preview.count) weitere")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Optionen") {
                    Toggle("Bidirektional", isOn: $createBidirectional)
                    Toggle("Doppelte ignorieren", isOn: $ignoreDuplicates)
                }

                Section("Notiz (optional)") {
                    TextField("z.B. Kontext", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Mehrere Links")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        save()
                    } label: {
                        Text(saveButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTargets.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .task {
                loadExistingLinkSets()
            }
            .alert(item: $resultAlert) { result in
                Alert(
                    title: Text("Links erstellt"),
                    message: Text(result.message),
                    dismissButton: .default(Text("OK")) {
                        dismiss()
                    }
                )
            }
            .alert(item: $errorAlert) { err in
                Alert(
                    title: Text("Nicht möglich"),
                    message: Text(err.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var saveButtonTitle: String {
        let c = selectedTargets.count
        if c == 0 { return "Erstelle Links" }
        return "Erstelle \(c) Link\(c == 1 ? "" : "s")"
    }

    private var selectedPreviewRows: [NodeRef] {
        Array(selectedTargets)
            .sorted(by: { BMSearch.fold($0.label) < BMSearch.fold($1.label) })
            .prefix(5)
            .map { $0 }
    }

    private func loadExistingLinkSets() {
        let sKind = source.kind.rawValue
        let sID = source.id

        do {
            let outgoingFD: FetchDescriptor<MetaLink>
            if let gid = graphID {
                outgoingFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { l in
                        l.sourceKindRaw == sKind &&
                        l.sourceID == sID &&
                        l.graphID == gid
                    }
                )
            } else {
                outgoingFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { l in
                        l.sourceKindRaw == sKind &&
                        l.sourceID == sID
                    }
                )
            }

            let outgoing = try modelContext.fetch(outgoingFD)
            existingOutgoingTargets = Set(outgoing.map { NodeRefKey(kind: $0.targetKind, id: $0.targetID) })

            let incomingFD: FetchDescriptor<MetaLink>
            if let gid = graphID {
                incomingFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { l in
                        l.targetKindRaw == sKind &&
                        l.targetID == sID &&
                        l.graphID == gid
                    }
                )
            } else {
                incomingFD = FetchDescriptor<MetaLink>(
                    predicate: #Predicate { l in
                        l.targetKindRaw == sKind &&
                        l.targetID == sID
                    }
                )
            }

            let incoming = try modelContext.fetch(incomingFD)
            existingIncomingSources = Set(incoming.map { NodeRefKey(kind: $0.sourceKind, id: $0.sourceID) })
        } catch {
            existingOutgoingTargets = []
            existingIncomingSources = []
        }
    }

    private func save() {
        // Always work with the latest existing link sets.
        loadExistingLinkSets()

        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = cleanedNote.isEmpty ? nil : cleanedNote

        var createdForward = 0
        var createdReverse = 0
        var skippedDuplicates = 0
        var skippedSelf = 0

        let gid = graphID

        var forwardDuplicates: [NodeRef] = []
        var reverseDuplicates: [NodeRef] = []

        // If the user explicitly disables duplicate ignoring, we abort early (no inserts).
        if !ignoreDuplicates {
            for t in selectedTargets {
                if t.kind == source.kind && t.id == source.id { continue }

                let tKey = NodeRefKey(nodeRef: t)
                if existingOutgoingTargets.contains(tKey) {
                    forwardDuplicates.append(t)
                }
                if createBidirectional && existingIncomingSources.contains(tKey) {
                    reverseDuplicates.append(t)
                }
            }

            let duplicateCount = forwardDuplicates.count + reverseDuplicates.count
            if duplicateCount > 0 {
                errorAlert = BulkLinkError(
                    message: "Es existieren bereits \(duplicateCount) Verbindungen für deine Auswahl. Entferne diese Ziele oder aktiviere \"Doppelte ignorieren\"."
                )
                return
            }
        }

        var inserted: [MetaLink] = []

        for t in selectedTargets {
            if t.kind == source.kind && t.id == source.id {
                skippedSelf += 1
                continue
            }

            let tKey = NodeRefKey(nodeRef: t)
            if existingOutgoingTargets.contains(tKey) {
                forwardDuplicates.append(t)
                continue
            }

            let link = MetaLink(
                sourceKind: source.kind,
                sourceID: source.id,
                sourceLabel: source.label,
                targetKind: t.kind,
                targetID: t.id,
                targetLabel: t.label,
                note: finalNote,
                graphID: gid
            )
            modelContext.insert(link)
            inserted.append(link)
            createdForward += 1
            existingOutgoingTargets.insert(tKey)

            if createBidirectional {
                if existingIncomingSources.contains(tKey) {
                    reverseDuplicates.append(t)
                } else {
                    let reverse = MetaLink(
                        sourceKind: t.kind,
                        sourceID: t.id,
                        sourceLabel: t.label,
                        targetKind: source.kind,
                        targetID: source.id,
                        targetLabel: source.label,
                        note: finalNote,
                        graphID: gid
                    )
                    modelContext.insert(reverse)
                    inserted.append(reverse)
                    createdReverse += 1
                    existingIncomingSources.insert(tKey)
                }
            }
        }

        let duplicateCount = forwardDuplicates.count + reverseDuplicates.count
        skippedDuplicates = duplicateCount

        do {
            try modelContext.save()
        } catch {
            errorAlert = BulkLinkError(message: "Speichern fehlgeschlagen: \(error.localizedDescription)")
            rollback(inserts: inserted)
            loadExistingLinkSets()
            return
        }

        let totalCreated = createdForward + createdReverse
        if totalCreated == 0 {
            resultAlert = BulkLinkResult(
                message: "Keine neuen Links erstellt.\n\nÜbersprungen: \(skippedDuplicates) doppelt, \(skippedSelf) self-link."
            )
        } else {
            var parts: [String] = []
            parts.append("Erstellt: \(createdForward) ausgehend")
            if createBidirectional {
                parts.append("\(createdReverse) rückwärts")
            }
            if skippedDuplicates > 0 {
                parts.append("Übersprungen: \(skippedDuplicates) doppelt")
            }
            if skippedSelf > 0 {
                parts.append("\(skippedSelf) self-link")
            }
            resultAlert = BulkLinkResult(message: parts.joined(separator: "\n"))
        }
    }

    private func rollback(inserts: [MetaLink]) {
        for l in inserts {
            modelContext.delete(l)
        }
    }
}

private struct BulkLinkResult: Identifiable {
    let id: UUID = UUID()
    let message: String
}

private struct BulkLinkError: Identifiable {
    let id: UUID = UUID()
    let message: String
}
