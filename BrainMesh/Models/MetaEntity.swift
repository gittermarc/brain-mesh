//
//  MetaEntity.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation
import SwiftData

@Model
final class MetaEntity {

    var id: UUID = UUID()

    var createdAt: Date = Date.distantPast

    // ✅ Graph scope (Multi-DB). Optional für sanfte Migration alter Daten.
    var graphID: UUID? = nil

    var name: String = "" {
        didSet {
            nameFolded = BMSearch.fold(name)
            for a in attributesList { a.recomputeSearchLabelFolded() }
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

    /// Optional SF Symbol name (e.g. "cube", "tag.fill").
    /// Stored as a simple String for performance and easy rendering via `Image(systemName:)`.
    var iconSymbolName: String? = nil

    // ✅ CloudKit-sync: Bilddaten (JPEG, klein gehalten)
    var imageData: Data? = nil

    // ✅ Lokaler Cache (Dateiname in AppSupport/BrainMeshImages). Kann leer sein.
    var imagePath: String? = nil

    // ✅ Relationship optional + Cascade ok
    // ✅ Inverse NUR HIER definieren (eine Seite!)
    @Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner)
    var attributes: [MetaAttribute]? = nil

    // MARK: - Details (Felder pro Entität)

    /// Frei konfigurierbare Felder (Schema) für Attribute dieser Entität.
    @Relationship(deleteRule: .cascade, inverse: \MetaDetailFieldDefinition.owner)
    var detailFields: [MetaDetailFieldDefinition]? = nil

    init(name: String, graphID: UUID? = nil, iconSymbolName: String? = nil) {
        self.name = name
        self.nameFolded = BMSearch.fold(name)
        self.createdAt = Date()
        self.graphID = graphID
        self.iconSymbolName = iconSymbolName
        self.attributes = []
        self.detailFields = []
    }

    // MARK: - Convenience

    /// De-dupe by id (falls aus der Vergangenheit schon Dopplungen entstanden sind)
    var attributesList: [MetaAttribute] {
        guard let attributes else { return [] }
        var seen = Set<UUID>()
        return attributes.filter { seen.insert($0.id).inserted }
    }

    var detailFieldsList: [MetaDetailFieldDefinition] {
        guard let detailFields else { return [] }
        var seen = Set<UUID>()
        return detailFields
            .filter { seen.insert($0.id).inserted }
            .sorted(by: { $0.sortIndex < $1.sortIndex })
    }

    func addDetailField(_ field: MetaDetailFieldDefinition) {
        if detailFields == nil { detailFields = [] }
        if detailFields?.contains(where: { $0.id == field.id }) == true { return }
        detailFields?.append(field)

        if field.graphID == nil { field.graphID = self.graphID }
        field.owner = self
        field.entityID = self.id
    }

    func removeDetailField(_ field: MetaDetailFieldDefinition) {
        detailFields?.removeAll { $0.id == field.id }
        if field.owner?.id == self.id { field.owner = nil }
    }

    /// Eine Quelle der Wahrheit: wir setzen owner hier explizit.
    func addAttribute(_ attr: MetaAttribute) {
        if attributes == nil { attributes = [] }
        if attributes?.contains(where: { $0.id == attr.id }) == true { return }
        attributes?.append(attr)

        // ✅ Scope Attribute in denselben Graph wie die Entität
        if attr.graphID == nil { attr.graphID = self.graphID }
        attr.owner = self
    }

    func removeAttribute(_ attr: MetaAttribute) {
        attributes?.removeAll { $0.id == attr.id }
        if attr.owner?.id == self.id { attr.owner = nil }
    }
}
