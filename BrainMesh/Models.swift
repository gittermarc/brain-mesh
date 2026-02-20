//
//  Models.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import Foundation
import SwiftData

nonisolated enum NodeKind: Int, Codable, CaseIterable, Sendable {
    case entity = 0
    case attribute = 1
}

// Helper für case-/diacritic-insensitive Suche
nonisolated enum BMSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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

@Model
final class MetaLink {

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var note: String? = nil

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    var sourceLabel: String = ""
    var targetLabel: String = ""

    var sourceKindRaw: Int = NodeKind.entity.rawValue
    var sourceID: UUID = UUID()

    var targetKindRaw: Int = NodeKind.entity.rawValue
    var targetID: UUID = UUID()

    init(
        sourceKind: NodeKind,
        sourceID: UUID,
        sourceLabel: String,
        targetKind: NodeKind,
        targetID: UUID,
        targetLabel: String,
        note: String? = nil,
        graphID: UUID? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.note = note

        self.graphID = graphID

        self.sourceKindRaw = sourceKind.rawValue
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel

        self.targetKindRaw = targetKind.rawValue
        self.targetID = targetID
        self.targetLabel = targetLabel
    }

    var sourceKind: NodeKind { NodeKind(rawValue: sourceKindRaw) ?? .entity }
    var targetKind: NodeKind { NodeKind(rawValue: targetKindRaw) ?? .entity }
}

// MARK: - Details (Schema + Werte)

enum DetailFieldType: Int, Codable, CaseIterable, Identifiable {
    case singleLineText = 0
    case multiLineText = 1
    case numberInt = 2
    case numberDouble = 3
    case date = 4
    case toggle = 5
    case singleChoice = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .singleLineText: return "Text"
        case .multiLineText: return "Mehrzeilig"
        case .numberInt: return "Zahl (Int)"
        case .numberDouble: return "Zahl (Double)"
        case .date: return "Datum"
        case .toggle: return "Ja/Nein"
        case .singleChoice: return "Auswahl"
        }
    }

    var systemImage: String {
        switch self {
        case .singleLineText: return "textformat"
        case .multiLineText: return "text.justify"
        case .numberInt: return "number"
        case .numberDouble: return "number"
        case .date: return "calendar"
        case .toggle: return "checkmark.circle"
        case .singleChoice: return "list.bullet"
        }
    }

    var supportsUnit: Bool {
        switch self {
        case .numberInt, .numberDouble: return true
        default: return false
        }
    }

    var supportsOptions: Bool {
        self == .singleChoice
    }
}

@Model
final class MetaDetailFieldDefinition {
    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    // Scalars für Stabilität/Queries
    var entityID: UUID = UUID()

    var name: String = "" {
        didSet { nameFolded = BMSearch.fold(name) }
    }

    var nameFolded: String = ""

    /// Stored as Int to keep SwiftData/CloudKit schema simple.
    var typeRaw: Int = 0

    /// Display order.
    var sortIndex: Int = 0

    /// Up to 3 fields can be pinned (enforced in UI).
    var isPinned: Bool = false

    /// For number fields.
    var unit: String? = nil

    /// For choice fields (JSON encoded array of strings).
    var optionsJSON: String? = nil

    // ❗️Inverse comes from MetaEntity.detailFields
    // ⚠️ NICHT "entity" nennen (Konflikt mit Core Data / CloudKit)
    @Relationship(deleteRule: .nullify, originalName: "entity")
    var owner: MetaEntity? = nil {
        didSet {
            if let e = owner {
                entityID = e.id
                if graphID == nil { graphID = e.graphID }
            }
        }
    }

    init(
        owner: MetaEntity,
        name: String,
        type: DetailFieldType,
        sortIndex: Int,
        unit: String? = nil,
        options: [String] = [],
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.owner = owner
        self.entityID = owner.id
        self.graphID = owner.graphID

        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleaned
        self.nameFolded = BMSearch.fold(cleaned)

        self.typeRaw = type.rawValue
        self.sortIndex = sortIndex
        self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPinned = isPinned
        self.setOptions(options)
    }

    var type: DetailFieldType {
        get { DetailFieldType(rawValue: typeRaw) ?? .singleLineText }
        set { typeRaw = newValue.rawValue }
    }

    var options: [String] {
        guard let optionsJSON, let data = optionsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setOptions(_ options: [String]) {
        let cleaned = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.isEmpty {
            optionsJSON = nil
            return
        }

        if let data = try? JSONEncoder().encode(cleaned), let str = String(data: data, encoding: .utf8) {
            optionsJSON = str
        } else {
            optionsJSON = nil
        }
    }
}

@Model
final class MetaDetailFieldValue {
    var id: UUID = UUID()

    // ✅ Graph scope (Multi-DB). Optional für Migration.
    var graphID: UUID? = nil

    // Scalars für Stabilität/Queries
    var attributeID: UUID = UUID()
    var fieldID: UUID = UUID()

    // Typed storage (so Sort/Filter später sauber möglich ist)
    var stringValue: String? = nil
    var intValue: Int? = nil
    var doubleValue: Double? = nil
    var dateValue: Date? = nil
    var boolValue: Bool? = nil

    // ❗️Inverse comes from MetaAttribute.detailValues
    var attribute: MetaAttribute? = nil {
        didSet {
            if let a = attribute {
                attributeID = a.id
                if graphID == nil { graphID = a.graphID }
            }
        }
    }

    init(attribute: MetaAttribute, fieldID: UUID) {
        self.id = UUID()
        self.attribute = attribute
        self.attributeID = attribute.id
        self.graphID = attribute.graphID
        self.fieldID = fieldID
    }

    func clearTypedValues() {
        stringValue = nil
        intValue = nil
        doubleValue = nil
        dateValue = nil
        boolValue = nil
    }
}
