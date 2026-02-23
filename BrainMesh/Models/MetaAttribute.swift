//
//  MetaAttribute.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation
import SwiftData

@Model
final class MetaAttribute {

    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    var name: String = "" {
        didSet {
            nameFolded = BMSearch.fold(name)
            recomputeSearchLabelFolded()
        }
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
    var notes: String = ""

    /// Optional SF Symbol name (e.g. "tag", "calendar.badge.clock").
    /// Stored as a simple String for performance and easy rendering via `Image(systemName:)`.
    var iconSymbolName: String? = nil

    // ✅ CloudKit-sync: Bilddaten (JPEG, klein gehalten)
    var imageData: Data? = nil

    // ✅ Lokaler Cache (Dateiname in AppSupport/BrainMeshImages). Kann leer sein.
    var imagePath: String? = nil

    // ✅ NICHT "entity" nennen (Konflikt mit Core Data)
    // ❗️KEIN inverse hier, sonst Macro-Zirkularität
    var owner: MetaEntity? = nil {
        didSet {
            // ✅ wenn owner gesetzt ist, Graph scope angleichen
            if let o = owner, graphID == nil { graphID = o.graphID }
            recomputeSearchLabelFolded()
        }
    }

    // MARK: - Details (Werte pro Attribut)

    /// Werte der frei konfigurierbaren Felder (Schema) der zugehörigen Entität.
    @Relationship(deleteRule: .cascade, inverse: \MetaDetailFieldValue.attribute)
    var detailValues: [MetaDetailFieldValue]? = nil

    var searchLabelFolded: String = ""

    init(name: String, owner: MetaEntity? = nil, graphID: UUID? = nil, iconSymbolName: String? = nil) {
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.owner = owner
        self.graphID = graphID ?? owner?.graphID
        self.iconSymbolName = iconSymbolName
        self.searchLabelFolded = BMSearch.fold(self.displayName)
        self.detailValues = []
    }

    func recomputeSearchLabelFolded() {
        searchLabelFolded = BMSearch.fold(displayName)
    }

    var displayName: String {
        if let e = owner { return "\(e.name) · \(name)" }
        return name
    }

    var detailValuesList: [MetaDetailFieldValue] {
        guard let detailValues else { return [] }
        var seen = Set<UUID>()
        return detailValues.filter { seen.insert($0.id).inserted }
    }
}
