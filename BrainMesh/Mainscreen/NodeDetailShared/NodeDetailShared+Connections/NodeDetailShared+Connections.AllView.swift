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
    @State private var mutationErrorMessage: String? = nil
    @State private var isMutating: Bool = false

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
                    .onDelete { offsets in
                        Task { await deleteLinks(at: offsets) }
                    }
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
        .alert("Änderung fehlgeschlagen", isPresented: Binding(
            get: { mutationErrorMessage != nil },
            set: { if !$0 { mutationErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mutationErrorMessage ?? "")
        }
        .disabled(isMutating)
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

    @MainActor
    private func deleteLinks(at offsets: IndexSet) async {
        guard !isMutating else { return }

        let rows = currentRows
        let selectedIDs = offsets.compactMap { index in
            rows.indices.contains(index) ? rows[index].id : nil
        }
        guard !selectedIDs.isEmpty else { return }

        isMutating = true
        defer { isMutating = false }

        do {
            let links = try selectedIDs.compactMap { linkID in
                try fetchLink(id: linkID)
            }
            guard !links.isEmpty else {
                await reload()
                return
            }

            guard let graphID = links.first?.graphID else {
                throw NodeConnectionMutationError.missingGraphScope
            }
            guard links.allSatisfy({ $0.graphID == graphID }) else {
                throw NodeConnectionMutationError.mixedGraphScopes
            }

            let references = links.map { mutationReference(for: $0) }
            for link in links {
                modelContext.delete(link)
            }

            let batch = try GraphMutationBatchFactory.linksDeleted(
                graphID: graphID,
                links: references
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)

            let deletedIDs = Set(links.map(\.id))
            snapshot = NodeConnectionsSnapshot(
                outgoing: snapshot.outgoing.filter { !deletedIDs.contains($0.id) },
                incoming: snapshot.incoming.filter { !deletedIDs.contains($0.id) }
            )
            await reload()
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            mutationErrorMessage = error.localizedDescription
        }
    }

    private func fetchLink(id: UUID) throws -> MetaLink? {
        let linkID = id
        let descriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate { link in
                link.id == linkID
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func mutationReference(
        for link: MetaLink
    ) -> GraphMutationLinkReference {
        GraphMutationLinkReference(
            id: link.id,
            source: NodeRefKey(kind: link.sourceKind, id: link.sourceID),
            target: NodeRefKey(kind: link.targetKind, id: link.targetID)
        )
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
    @State private var isSaving: Bool = false

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
                            Task { await save(note: nil) }
                        } label: {
                            Label("Notiz entfernen", systemImage: "trash")
                        }
                        .disabled(isSaving)
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
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let finalNote = trimmed.isEmpty ? nil : trimmed
                        Task { await save(note: finalNote) }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: $showSaveErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func save(note: String?) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let linkID = linkID
        let descriptor = FetchDescriptor<MetaLink>(
            predicate: #Predicate { link in
                link.id == linkID
            }
        )

        do {
            guard let link = try modelContext.fetch(descriptor).first else {
                throw NodeConnectionMutationError.linkNotFound
            }
            guard let graphID = link.graphID else {
                throw NodeConnectionMutationError.missingGraphScope
            }

            guard link.note != note else {
                onSaved(linkID, note)
                dismiss()
                return
            }

            let reference = GraphMutationLinkReference(
                id: link.id,
                source: NodeRefKey(kind: link.sourceKind, id: link.sourceID),
                target: NodeRefKey(kind: link.targetKind, id: link.targetID)
            )
            link.note = note

            let batch = try GraphMutationBatchFactory.linkUpdated(
                graphID: graphID,
                link: reference
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            onSaved(linkID, note)
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

private enum NodeConnectionMutationError: LocalizedError {
    case linkNotFound
    case missingGraphScope
    case mixedGraphScopes

    var errorDescription: String? {
        switch self {
        case .linkNotFound:
            return "Der Link wurde nicht gefunden."
        case .missingGraphScope:
            return "Für den Link ist kein Graph zugeordnet."
        case .mixedGraphScopes:
            return "Die ausgewählten Links gehören nicht zum selben Graphen."
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
