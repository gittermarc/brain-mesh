//
//  NodeDetailShared+Connections.Card.swift
//  BrainMesh
//
//  Preview card (detail screen) for connections.
//

import SwiftUI

struct NodeConnectionsCard: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    let outgoing: [LinkRowDTO]
    let incoming: [LinkRowDTO]
    let outgoingCount: Int
    let incomingCount: Int

    @Binding var segment: NodeLinkDirectionSegment
    let previewLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Verbindungen", systemImage: "link")

            Picker("", selection: $segment) {
                ForEach(NodeLinkDirectionSegment.allCases) { seg in
                    Label(seg.title, systemImage: seg.systemImage)
                        .tag(seg)
                }
            }
            .pickerStyle(.segmented)

            let links = segment == .outgoing ? outgoing : incoming
            let count =
                segment == .outgoing ? outgoingCount : incomingCount

            if count == 0 {
                NodeEmptyStateRow(
                    text: segment == .outgoing ? "Keine ausgehenden Links." : "Keine eingehenden Links.",
                    ctaTitle: "Im Toolbelt hinzufügen",
                    ctaSystemImage: "link",
                    ctaAction: {}
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(links.prefix(previewLimit)) { row in
                        if let target = row.navigationTarget {
                            NavigationLink {
                                NodeDestinationView(
                                    kind: target.kind,
                                    id: target.id
                                )
                            } label: {
                                NodeLinkRow(
                                    direction: segment,
                                    title: row.peerLabel,
                                    note: row.note
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            NodeLinkRow(
                                direction: segment,
                                title: row.peerLabel,
                                note: row.note,
                                showsDisclosureIndicator: false
                            )
                        }
                    }
                }

                NavigationLink {
                    NodeConnectionsAllView(
                        ownerKind: ownerKind,
                        ownerID: ownerID,
                        graphID: graphID,
                        initialSegment: segment
                    )
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

private struct NodeLinkRow: View {
    let direction: NodeLinkDirectionSegment
    let title: String
    let note: String?
    var showsDisclosureIndicator: Bool = true

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

            Spacer(minLength: 0)
            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
