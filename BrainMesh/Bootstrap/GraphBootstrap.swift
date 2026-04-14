//
//  GraphBootstrap.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import Foundation
import SwiftData

@MainActor
enum GraphBootstrap {
    static func saveIfChanged(_ changed: Bool, using modelContext: ModelContext) {
        guard changed else { return }
        try? modelContext.save()
    }
}
