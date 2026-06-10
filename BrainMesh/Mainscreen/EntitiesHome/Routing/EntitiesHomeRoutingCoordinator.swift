//
//  EntitiesHomeRoutingCoordinator.swift
//  BrainMesh
//
//  Lightweight routing bridge for opening Entities Home with a prepared quick filter.
//

import Combine
import Foundation

nonisolated struct EntitiesHomeQuickFilterRoute: Identifiable, Equatable, Sendable {
    let id: UUID
    let requestedAt: Date
    let graphID: UUID?
    let filter: EntitiesHomeQuickFilter

    init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        graphID: UUID?,
        filter: EntitiesHomeQuickFilter
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.graphID = graphID
        self.filter = filter
    }
}

/// Stores one pending request for Entities Home.
///
/// The type intentionally stays non-MainActor as a class, matching the root router and graph-jump
/// coordinator. Mutating methods are individually main-actor isolated.
final class EntitiesHomeRoutingCoordinator: ObservableObject {
    @Published private(set) var pendingQuickFilterRoute: EntitiesHomeQuickFilterRoute? = nil

    @MainActor
    func requestQuickFilter(_ filter: EntitiesHomeQuickFilter, graphID: UUID?) {
        pendingQuickFilterRoute = EntitiesHomeQuickFilterRoute(
            graphID: graphID,
            filter: filter
        )
    }

    @MainActor
    func consumeQuickFilterRoute(id: UUID) -> EntitiesHomeQuickFilterRoute? {
        guard pendingQuickFilterRoute?.id == id else { return nil }
        let route = pendingQuickFilterRoute
        pendingQuickFilterRoute = nil
        return route
    }

    @MainActor
    func clear() {
        pendingQuickFilterRoute = nil
    }
}
