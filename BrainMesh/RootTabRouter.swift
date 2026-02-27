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
enum RootTab: Int, Hashable, Sendable {
    case entities = 0
    case graph = 1
    case stats = 2
    case settings = 3
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
    func openStats(animated: Bool = true) { select(.stats, animated: animated) }

    @MainActor
    func openSettings(animated: Bool = true) { select(.settings, animated: animated) }
}
