//
//  EntitiesHomeSearchEmptyState.swift
//  BrainMesh
//
//  Empty-state copy and UI for local Entities Home search.
//

import SwiftUI

struct EntitiesHomeSearchEmptyStateCopy: Equatable, Sendable {
    let title: String
    let message: String
    let actionTitle: String
    let commandCenterQuery: String
}

enum EntitiesHomeSearchEmptyStateBuilder {
    static func copy(for searchText: String) -> EntitiesHomeSearchEmptyStateCopy {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if trimmedQuery.isEmpty {
            message = "Die Entitätenliste findet keine passende Entität oder kein passendes Attribut. Das Command Center durchsucht zusätzlich Details, Links und Anhänge im aktiven Graph."
        } else {
            message = "Für „\(trimmedQuery)“ findet die Entitätenliste keine passende Entität oder kein passendes Attribut. Das Command Center durchsucht zusätzlich Details, Links und Anhänge im aktiven Graph."
        }

        return EntitiesHomeSearchEmptyStateCopy(
            title: "Keine Treffer",
            message: message,
            actionTitle: "Mehr im Command Center suchen",
            commandCenterQuery: trimmedQuery
        )
    }
}

struct EntitiesHomeSearchEmptyStateView: View {
    let searchText: String
    let onOpenCommandCenter: (String) -> Void

    private var copy: EntitiesHomeSearchEmptyStateCopy {
        EntitiesHomeSearchEmptyStateBuilder.copy(for: searchText)
    }

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label(copy.title, systemImage: "magnifyingglass")
            } description: {
                Text(copy.message)
                    .multilineTextAlignment(.center)
            }

            Button {
                onOpenCommandCenter(copy.commandCenterQuery)
            } label: {
                Label(copy.actionTitle, systemImage: "command.circle")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Öffnet das Command Center mit deinem aktuellen Suchbegriff")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
