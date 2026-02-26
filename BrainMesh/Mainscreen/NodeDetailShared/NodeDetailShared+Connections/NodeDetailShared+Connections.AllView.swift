//
//  NodeDetailShared+Connections.AllView.swift
//  BrainMesh
//
//  Full connections list (with delete) backed by the snapshot loader.
//

import SwiftUI
import SwiftData

struct NodeConnectionsAllView: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @State private var segment: NodeLinkDirectionSegment

    @State private var snapshot: NodeConnectionsSnapshot = .empty
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String? = nil

    @State private var editNoteRequest: EditLinkNoteRequest? = nil

    init(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?, initialSegment: NodeLinkDirectionSegment = .outgoing) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $segment) {
                    ForEach(NodeLinkDirectionSegment.allCases) { seg in
                        Label(seg.title, systemImage: seg.systemImage)
                            .tag(seg)
                    }
                }
                .pickerStyle(.segmented)
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            if let msg = loadErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)

                        Button(action: { Task { await reload() } }) {
                            Label("Erneut laden", systemImage: "arrow.clockwise")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                if !isLoading && loadErrorMessage == nil && currentRows.isEmpty {
                    Text(segment == .outgoing ? "Keine ausgehenden Links." : "Keine eingehenden Links.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentRows) { row in
                        NavigationLink {
                            NodeDestinationView(kind: peerKind(for: row), id: row.peerID)
                        } label: {
                            NodeLinkListRow(direction: segment, title: row.peerLabel, note: row.note)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editNoteRequest = EditLinkNoteRequest(id: row.id, initialNote: row.note)
                            } label: {
                                Label(rowNoteActionTitle(row.note), systemImage: "square.and.pencil")
                            }
                            .tint(Color.accentColor)
                        }
                    }
                    .onDelete(perform: deleteLinks)
                }
            }
        }
        .navigationTitle("Verbindungen")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .task(id: loadTaskKey) {
            await reload()
        }
        .sheet(item: $editNoteRequest) { req in
            LinkNoteEditorSheet(linkID: req.id, initialNote: req.initialNote) { linkID, newNote in
                applyNoteUpdate(linkID: linkID, note: newNote)
            }
        }
    }

    private var loadTaskKey: String {
        let gid = graphID?.uuidString ?? "nil"
        return "\(ownerKind.rawValue)|\(ownerID.uuidString)|\(gid)"
    }

    private var currentRows: [LinkRowDTO] {
        segment == .outgoing ? snapshot.outgoing : snapshot.incoming
    }

    private func peerKind(for row: LinkRowDTO) -> NodeKind {
        NodeKind(rawValue: row.peerKindRaw) ?? .entity
    }

    private func reload() async {
        await MainActor.run {
            isLoading = true
            loadErrorMessage = nil
        }

        do {
            let snap = try await NodeConnectionsLoader.shared.loadSnapshot(
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID
            )

            await MainActor.run {
                snapshot = snap
                isLoading = false
            }
        } catch is CancellationError {
            await MainActor.run {
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadErrorMessage = (error as NSError).localizedDescription
                isLoading = false
            }
        }
    }

    private func deleteLinks(at offsets: IndexSet) {
        let rows = currentRows

        var idsToDelete: [UUID] = []
        for idx in offsets {
            guard rows.indices.contains(idx) else { continue }
            idsToDelete.append(rows[idx].id)
        }
        guard !idsToDelete.isEmpty else { return }

        for linkID in idsToDelete {
            if let link = fetchLink(id: linkID) {
                modelContext.delete(link)
            }
        }
        try? modelContext.save()

        // Optimistic update (keeps UI snappy).
        let idSet = Set(idsToDelete)
        let newOutgoing = snapshot.outgoing.filter { !idSet.contains($0.id) }
        let newIncoming = snapshot.incoming.filter { !idSet.contains($0.id) }
        snapshot = NodeConnectionsSnapshot(outgoing: newOutgoing, incoming: newIncoming)

        // Ensure list stays consistent (labels, ordering, etc.)
        Task { await reload() }
    }

    private func fetchLink(id: UUID) -> MetaLink? {
        let linkID = id
        let fd = FetchDescriptor<MetaLink>(predicate: #Predicate { l in l.id == linkID })
        return (try? modelContext.fetch(fd).first)
    }

    private func rowNoteActionTitle(_ note: String?) -> String {
        guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Notiz" }
        return "Notiz bearbeiten"
    }

    private func applyNoteUpdate(linkID: UUID, note: String?) {
        let updatedOutgoing = snapshot.outgoing.map { row in
            guard row.id == linkID else { return row }
            return LinkRowDTO(
                id: row.id,
                peerKindRaw: row.peerKindRaw,
                peerID: row.peerID,
                peerLabel: row.peerLabel,
                note: note,
                createdAt: row.createdAt
            )
        }

        let updatedIncoming = snapshot.incoming.map { row in
            guard row.id == linkID else { return row }
            return LinkRowDTO(
                id: row.id,
                peerKindRaw: row.peerKindRaw,
                peerID: row.peerID,
                peerLabel: row.peerLabel,
                note: note,
                createdAt: row.createdAt
            )
        }

        snapshot = NodeConnectionsSnapshot(outgoing: updatedOutgoing, incoming: updatedIncoming)
    }
}

private struct EditLinkNoteRequest: Identifiable, Equatable {
    let id: UUID
    let initialNote: String?
}

private struct LinkNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let linkID: UUID
    let initialNote: String?
    let onSaved: (UUID, String?) -> Void

    @State private var noteDraft: String

    @State private var showSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""

    init(linkID: UUID, initialNote: String?, onSaved: @escaping (UUID, String?) -> Void) {
        self.linkID = linkID
        self.initialNote = initialNote
        self.onSaved = onSaved
        _noteDraft = State(initialValue: initialNote ?? "")
    }

    private var trimmed: String {
        noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNote: Bool {
        !trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notiz") {
                    TextField("z.B. Kontext", text: $noteDraft, axis: .vertical)
                }

                if hasNote {
                    Section {
                        Button(role: .destructive) {
                            save(note: nil)
                        } label: {
                            Label("Notiz entfernen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Link-Notiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let finalNote = trimmed.isEmpty ? nil : trimmed
                        save(note: finalNote)
                    }
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: $showSaveErrorAlert) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save(note: String?) {
        let lid = linkID
        let fd = FetchDescriptor<MetaLink>(predicate: #Predicate { l in l.id == lid })

        guard let link = (try? modelContext.fetch(fd).first) else {
            saveErrorMessage = "Link nicht gefunden."
            showSaveErrorAlert = true
            return
        }

        link.note = note

        do {
            try modelContext.save()
            onSaved(linkID, note)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}

private struct NodeLinkListRow: View {
    let direction: NodeLinkDirectionSegment
    let title: String
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
