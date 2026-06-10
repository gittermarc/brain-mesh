//
//  CommandCenterState.swift
//  BrainMesh
//
//  Pure state helpers for the command center UI.
//

import Foundation

struct CommandCenterResultSection: Identifiable, Hashable, Sendable {
    let kind: BrainMeshSearchResultKind
    let results: [BrainMeshSearchResult]

    var id: BrainMeshSearchResultKind { kind }
    var title: String { kind.title }
}

enum CommandCenterContentState: Equatable, Sendable {
    case overview(recents: [RecentNodeItem], quickActions: [CommandCenterQuickAction])
    case searching
    case results(query: String, sections: [CommandCenterResultSection])
    case noResults(query: String)
    case error(CommandCenterUserFacingErrorMessage)
}

struct CommandCenterUserFacingErrorMessage: Equatable, Sendable {
    let title: String
    let message: String

    static func message(for error: Error) -> CommandCenterUserFacingErrorMessage? {
        if error is CancellationError {
            return nil
        }

        let nsError = error as NSError
        if nsError.domain.contains("BrainMeshSearchService") {
            return CommandCenterUserFacingErrorMessage(
                title: "Suche ist gerade nicht bereit",
                message: "BrainMesh konnte den Suchdienst noch nicht vorbereiten. Schließe das Command Center kurz und versuche es erneut."
            )
        }

        return CommandCenterUserFacingErrorMessage(
            title: "Suche fehlgeschlagen",
            message: "BrainMesh konnte die Suche nicht vollständig ausführen. Prüfe kurz, ob der aktuelle Graph noch verfügbar ist, und versuche es erneut."
        )
    }
}

enum CommandCenterStateBuilder {
    static let defaultQuickActions: [CommandCenterQuickAction] = CommandCenterQuickAction.allCases

    static func state(
        query: String,
        snapshot: BrainMeshSearchSnapshot,
        recents: [RecentNodeItem],
        isSearching: Bool,
        error: CommandCenterUserFacingErrorMessage?
    ) -> CommandCenterContentState {
        let foldedQuery = BMSearch.fold(query)

        if let error {
            return .error(error)
        }

        if foldedQuery.isEmpty {
            return .overview(recents: recents, quickActions: defaultQuickActions)
        }

        if isSearching && snapshot.results.isEmpty {
            return .searching
        }

        let sections = groupedSections(for: snapshot.results)
        if sections.isEmpty {
            return .noResults(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return .results(query: query.trimmingCharacters(in: .whitespacesAndNewlines), sections: sections)
    }

    static func groupedSections(for results: [BrainMeshSearchResult]) -> [CommandCenterResultSection] {
        BrainMeshSearchResultKind.allCases.compactMap { kind in
            let matches = results.filter { $0.kind == kind }
            guard matches.isEmpty == false else { return nil }
            return CommandCenterResultSection(kind: kind, results: matches)
        }
    }
}
