//
//  CommandCenterRows.swift
//  BrainMesh
//
//  Reusable rows and status cards for the command center.
//

import SwiftUI

struct CommandCenterSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .labelStyle(.titleAndIcon)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CommandCenterRecentRow: View {
    let item: RecentNodeItem
    let onOpen: () -> Void
    let onJumpToGraph: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CommandCenterIcon(symbolName: item.iconSymbolName)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(item.nodeKind?.commandCenterTitle ?? "Node")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet den Detailbereich")

            if CommandCenterActionResolver.graphActionPlan(for: item) != nil {
                Button(action: onJumpToGraph) {
                    Image(systemName: "scope")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Im Graph anzeigen")
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CommandCenterResultRow: View {
    let result: BrainMeshSearchResult
    let onOpen: () -> Void
    let onJumpToGraph: () -> Void

    private var canJumpToGraph: Bool {
        CommandCenterActionResolver.graphActionPlan(for: result) != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            CommandCenterIcon(symbolName: result.iconSymbolName)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if result.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(result.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Label(result.matchReason, systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(result.ownerNodeKey == nil && result.nodeKey == nil ? "Öffnet den passenden Graph-Bereich" : "Öffnet den passenden Detailbereich")

            if canJumpToGraph {
                Button(action: onJumpToGraph) {
                    Image(systemName: "scope")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Im Graph anzeigen")
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CommandCenterIcon: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .frame(width: 38, height: 38)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct CommandCenterLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Suche läuft")
                .font(.headline)
            Text("BrainMesh durchsucht Entitäten, Attribute, Details, Links und Anhänge im aktuellen Graph.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

struct CommandCenterNoResultsView: View {
    let query: String

    var body: some View {
        CommandCenterEmptyCard(
            systemImage: "magnifyingglass",
            title: "Keine Treffer",
            message: query.isEmpty ? "BrainMesh konnte nichts Passendes finden." : "Für „\(query)” wurden keine Entitäten, Attribute, Details, Links oder Anhänge gefunden."
        )
    }
}

struct CommandCenterErrorView: View {
    let message: CommandCenterUserFacingErrorMessage

    var body: some View {
        CommandCenterEmptyCard(
            systemImage: "exclamationmark.triangle",
            title: message.title,
            message: message.message
        )
    }
}

struct CommandCenterEmptyCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

private extension NodeKind {
    var commandCenterTitle: String {
        switch self {
        case .entity:
            return "Entität"
        case .attribute:
            return "Attribut"
        }
    }
}
