//
//  MetaGraph.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation
import SwiftData

// MARK: - Graph (Workspace)

@Model
final class MetaGraph {
    var id: UUID = UUID()
    // When this field was introduced, we intentionally defaulted to `.distantPast`
    // so existing records don't suddenly look "new" after automatic migration.
    var createdAt: Date = Date.distantPast

    var name: String = "" {
        didSet { nameFolded = BMSearch.fold(name) }
    }
    var nameFolded: String = ""

    // MARK: - Graph Security (optional)
    // Pro Graph kann der User Zugriffsschutz aktivieren (Biometrie und/oder Passwort).

    /// Entsperren via Face ID / Touch ID (LocalAuthentication)
    var lockBiometricsEnabled: Bool = false

    /// Eigenes Passwort (Hash + Salt) pro Graph
    var lockPasswordEnabled: Bool = false
    var passwordSaltB64: String? = nil
    var passwordHashB64: String? = nil
    var passwordIterations: Int = GraphLockCrypto.defaultIterations

    var isPasswordConfigured: Bool {
        lockPasswordEnabled && passwordSaltB64 != nil && passwordHashB64 != nil && passwordIterations > 0
    }

    var isProtected: Bool {
        lockBiometricsEnabled || isPasswordConfigured
    }

    init(name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleaned.isEmpty ? "Neuer Graph" : cleaned
        self.nameFolded = BMSearch.fold(self.name)
        self.createdAt = Date()
    }
}
