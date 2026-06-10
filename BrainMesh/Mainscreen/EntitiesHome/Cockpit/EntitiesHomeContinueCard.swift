//
//  EntitiesHomeContinueCard.swift
//  BrainMesh
//
//  Continue-working cards for the Entities Home Cockpit.
//

import SwiftUI

struct EntitiesHomeContinueCard: View {
    let item: EntitiesHomeCockpitRecentNode
    let onOpen: () -> Void
    let onJumpToGraph: () -> Void

    private var canJumpToGraph: Bool {
        item.graphID != nil && item.nodeKey != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.iconSymbolName)
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label("Öffnen", systemImage: "arrow.forward.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Öffnet den Detailbereich")

                if canJumpToGraph {
                    Button(action: onJumpToGraph) {
                        Label("Graph", systemImage: "scope")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Im Graph anzeigen")
                }
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

struct EntitiesHomeContinueEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Noch nichts zuletzt geöffnet")
                .font(.headline)

            Text("Öffne eine Entität oder ein Attribut. Danach kannst du hier direkt weitermachen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}
