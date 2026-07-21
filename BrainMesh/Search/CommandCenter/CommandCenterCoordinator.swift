//
//  CommandCenterCoordinator.swift
//  BrainMesh
//
//  Central presentation coordinator for the global command center.
//

import Combine
import Foundation

enum CommandCenterDestination: Identifiable, Hashable, Sendable {
    case addEntity
    case graphTransfer
    case guide
    case nodeDetail(kind: NodeKind, id: UUID)
    case graphChatSource(GraphChatSourceDestination)

    var id: String {
        switch self {
        case .addEntity:
            return "addEntity"
        case .graphTransfer:
            return "graphTransfer"
        case .guide:
            return "guide"
        case .nodeDetail(let kind, let id):
            return "nodeDetail-\(kind.rawValue)-\(id.uuidString)"
        case .graphChatSource(let destination):
            return "graphChatSource-\(String(describing: destination))"
        }
    }
}

/// Owns global command-center presentation without coupling it to one root tab.
///
/// The type is intentionally not marked `@MainActor` as a whole, matching the existing
/// router/coordinator pattern in the project. Mutating methods are main-actor isolated.
final class CommandCenterCoordinator: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var initialQuery: String = ""
    @Published var destination: CommandCenterDestination? = nil

    @MainActor
    func present(initialQuery: String = "") {
        self.initialQuery = initialQuery
        destination = nil
        isPresented = true
    }

    @MainActor
    func dismiss() {
        isPresented = false
    }

    @MainActor
    func presentDestination(_ destination: CommandCenterDestination) {
        isPresented = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            self.destination = destination
        }
    }

    @MainActor
    func clearDestination() {
        destination = nil
    }
}
