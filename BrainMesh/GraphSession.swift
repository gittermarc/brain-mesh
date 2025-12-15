//
//  GraphSession.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//


import Foundation
import Combine

@MainActor
final class GraphSession: ObservableObject {
    static let shared = GraphSession()

    /// Aktiver Graph (später per UI umschaltbar)
    @Published var activeGraphID: UUID = GraphBootstrap.defaultGraphID

    private init() {}
}
