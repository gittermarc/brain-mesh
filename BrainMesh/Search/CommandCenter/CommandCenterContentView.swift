//
//  CommandCenterContentView.swift
//  BrainMesh
//
//  Sectioned command center content.
//

import SwiftUI

struct CommandCenterContentView: View {
    let state: CommandCenterContentState
    let onQuickAction: (CommandCenterQuickAction) -> Void
    let onOpenRecent: (RecentNodeItem) -> Void
    let onJumpRecent: (RecentNodeItem) -> Void
    let onOpenResult: (BrainMeshSearchResult) -> Void
    let onJumpResult: (BrainMeshSearchResult) -> Void

    var body: some View {
        switch state {
        case .overview(let recents, let quickActions):
            LazyVStack(alignment: .leading, spacing: 16) {
                CommandCenterQuickActionsSection(actions: quickActions, onSelect: onQuickAction)
                CommandCenterRecentSection(
                    items: recents,
                    onOpen: onOpenRecent,
                    onJumpToGraph: onJumpRecent
                )
            }

        case .searching:
            CommandCenterLoadingView()

        case .results(_, let sections):
            CommandCenterSearchResultsView(
                sections: sections,
                onOpen: onOpenResult,
                onJumpToGraph: onJumpResult
            )

        case .noResults(let query):
            CommandCenterNoResultsView(query: query)

        case .error(let message):
            CommandCenterErrorView(message: message)
        }
    }
}

struct CommandCenterQuickActionsSection: View {
    let actions: [CommandCenterQuickAction]
    let onSelect: (CommandCenterQuickAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommandCenterSectionHeader(title: "Schnellaktionen", systemImage: "bolt")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(actions) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: action.systemImage)
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)

                            Text(action.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.secondary.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.subtitle)
                }
            }
        }
    }
}

struct CommandCenterRecentSection: View {
    let items: [RecentNodeItem]
    let onOpen: (RecentNodeItem) -> Void
    let onJumpToGraph: (RecentNodeItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommandCenterSectionHeader(title: "Zuletzt geöffnet", systemImage: "clock.arrow.circlepath")

            if items.isEmpty {
                CommandCenterEmptyCard(
                    systemImage: "clock",
                    title: "Noch keine zuletzt geöffneten Nodes",
                    message: "Öffne eine Entität oder ein Attribut. Danach findest du sie hier direkt wieder."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        CommandCenterRecentRow(
                            item: item,
                            onOpen: { onOpen(item) },
                            onJumpToGraph: { onJumpToGraph(item) }
                        )
                    }
                }
            }
        }
    }
}

struct CommandCenterSearchResultsView: View {
    let sections: [CommandCenterResultSection]
    let onOpen: (BrainMeshSearchResult) -> Void
    let onJumpToGraph: (BrainMeshSearchResult) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    CommandCenterSectionHeader(
                        title: section.title,
                        systemImage: section.kind.defaultIconSymbolName
                    )

                    LazyVStack(spacing: 8) {
                        ForEach(section.results) { result in
                            CommandCenterResultRow(
                                result: result,
                                onOpen: { onOpen(result) },
                                onJumpToGraph: { onJumpToGraph(result) }
                            )
                        }
                    }
                }
            }
        }
    }
}
