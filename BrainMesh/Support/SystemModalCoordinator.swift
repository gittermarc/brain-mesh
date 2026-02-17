//
//  SystemModalCoordinator.swift
//  BrainMesh
//
//  Created by Marc Fechner on 17.02.26.
//

import SwiftUI
import Combine

/// Tracks whether a system modal (Photos picker, video picker, etc.) is currently presented.
///
/// Motivation:
/// Some iOS versions/devices can briefly report `.background` during Face ID prompts
/// shown from inside pickers (notably Photos' "Hidden" album). If we auto-lock the app
/// during that transient phase, SwiftUI tends to dismiss/reset the picker UI.
///
/// We keep this intentionally lightweight: a simple reference count.
@MainActor
final class SystemModalCoordinator: ObservableObject {

    @Published private(set) var activeSystemModalCount: Int = 0

    var isSystemModalPresented: Bool {
        activeSystemModalCount > 0
    }

    func beginSystemModal() {
        activeSystemModalCount += 1
    }

    func endSystemModal() {
        if activeSystemModalCount > 0 {
            activeSystemModalCount -= 1
        } else {
            activeSystemModalCount = 0
        }
    }
}
