//
//  RootTabRouter.swift
//  BrainMesh
//
//  Lightweight tab routing for programmatic jumps (PR 1).
//

import Combine
import SwiftUI

/// Root tabs shown in `ContentView`.
///
/// Using an `Int` raw value keeps tab selection stable and works nicely with
/// `TabView(selection:)`.
nonisolated enum RootTab: Int, Hashable, Sendable {
    case entities = 0
    case graph = 1
    case stats = 2
    case settings = 3
    case chat = 4

    static let visibleOrder: [RootTab] = [
        .entities,
        .graph,
        .chat,
        .stats,
        .settings
    ]

    var title: String {
        switch self {
        case .entities: return "Entitäten"
        case .graph: return "Graph"
        case .chat: return "Chat"
        case .stats: return "Stats"
        case .settings: return "Einstellungen"
        }
    }

    var systemImage: String {
        switch self {
        case .entities: return "list.bullet"
        case .graph: return "circle.grid.cross"
        case .chat: return "bubble.left.and.bubble.right"
        case .stats: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

/// Small router that owns the currently selected root tab.
///
/// Note: We intentionally do **not** mark the whole type `@MainActor`.
/// In strict concurrency builds this can break `ObservableObject` conformance
/// (nonisolated protocol requirement vs actor-isolated synthesis).
/// Instead, we keep mutations on the main actor via `@MainActor` methods.
final class RootTabRouter: ObservableObject {
    @Published var selection: RootTab = .entities

    @MainActor
    func select(_ tab: RootTab, animated: Bool = true) {
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                selection = tab
            }
        } else {
            selection = tab
        }
    }

    @MainActor
    func openEntities(animated: Bool = true) { select(.entities, animated: animated) }

    @MainActor
    func openGraph(animated: Bool = true) { select(.graph, animated: animated) }

    @MainActor
    func openChat(animated: Bool = true) { select(.chat, animated: animated) }

    @MainActor
    func openStats(animated: Bool = true) { select(.stats, animated: animated) }

    @MainActor
    func openSettings(animated: Bool = true) { select(.settings, animated: animated) }
}
