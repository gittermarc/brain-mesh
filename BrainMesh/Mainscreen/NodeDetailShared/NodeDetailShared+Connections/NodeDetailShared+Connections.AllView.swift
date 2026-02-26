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
