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

    // Muss identisch sein mit @AppStorage("BMActiveGraphID")
    private let storageKey = "BMActiveGraphID"

    /// Aktiver Graph (später per UI umschaltbar)
    @Published var activeGraphID: UUID

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Default: "unset" UUID (stabil, kein random UUID-Schrott)
        let unset = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        if let s = UserDefaults.standard.string(forKey: storageKey),
           let id = UUID(uuidString: s) {
            self.activeGraphID = id
        } else {
            self.activeGraphID = unset
        }

        // Bleibt automatisch synchron, wenn AppStorage/UserDefaults sich ändern
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if let s = UserDefaults.standard.string(forKey: self.storageKey),
                   let id = UUID(uuidString: s),
                   id != self.activeGraphID {
                    self.activeGraphID = id
                }
            }
            .store(in: &cancellables)
    }
}
