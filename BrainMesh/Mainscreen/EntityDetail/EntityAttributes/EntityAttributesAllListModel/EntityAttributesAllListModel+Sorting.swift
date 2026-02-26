//
//  EntityAttributesAllListModel+Sorting.swift
//  BrainMesh
//
//  P0.1: Sorting extracted from EntityAttributesAllListModel.swift
//

import Foundation
import SwiftData

enum EntityAttributesAllSortDirection: String, Codable, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    mutating func toggle() {
        self = (self == .ascending) ? .descending : .ascending
    }
}

enum EntityAttributesAllSortSelection: Hashable {
    case base(EntityAttributeSortMode)
    case pinned(fieldID: UUID, direction: EntityAttributesAllSortDirection)

    static let `default`: EntityAttributesAllSortSelection = .base(.nameAZ)

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("pinned:") {
            // pinned:<uuid>:asc|desc
            let parts = trimmed.split(separator: ":")
            if parts.count >= 3,
               let fid = UUID(uuidString: String(parts[1])) {
                let dirToken = String(parts[2])
                let dir: EntityAttributesAllSortDirection = (dirToken == "desc" || dirToken == "descending") ? .descending : .ascending
                self = .pinned(fieldID: fid, direction: dir)
                return
            }
        }

        if trimmed.hasPrefix("base:") {
            let modeToken = trimmed.replacingOccurrences(of: "base:", with: "")
            if let mode = EntityAttributeSortMode(rawValue: modeToken) {
                self = .base(mode)
                return
            }
        }

        // Backward compatibility: allow plain base raw values.
        if let mode = EntityAttributeSortMode(rawValue: trimmed) {
            self = .base(mode)
            return
        }

        self = .default
    }

    var rawValue: String {
        switch self {
        case .base(let mode):
            return "base:\(mode.rawValue)"
        case .pinned(let fieldID, let direction):
            let token = (direction == .descending) ? "desc" : "asc"
            return "pinned:\(fieldID.uuidString):\(token)"
        }
    }

    var isDefault: Bool {
        if case .base(let mode) = self {
            return mode == .nameAZ
        }
        return false
    }

    var baseModeOrDefault: EntityAttributeSortMode {
        if case .base(let mode) = self { return mode }
        return .nameAZ
    }
}

extension EntityAttributesAllListModel {
    static func sortAttributes(
        _ attrs: [MetaAttribute],
        sortSelection: EntityAttributesAllSortSelection,
        pinnedFields: [MetaDetailFieldDefinition],
        pinnedValuesByAttribute: [UUID: [UUID: MetaDetailFieldValue]]
    ) -> [MetaAttribute] {
        switch sortSelection {
        case .base(let mode):
            return mode.sort(attrs)

        case .pinned(let fieldID, let direction):
            guard let field = pinnedFields.first(where: { $0.id == fieldID }) else {
                return EntityAttributeSortMode.nameAZ.sort(attrs)
            }

            return attrs.sorted { lhs, rhs in
                comparePinned(
                    field: field,
                    lhs: lhs,
                    rhs: rhs,
                    direction: direction,
                    pinnedValuesByAttribute: pinnedValuesByAttribute
                )
            }
        }
    }

    private static func comparePinned(
        field: MetaDetailFieldDefinition,
        lhs: MetaAttribute,
        rhs: MetaAttribute,
        direction: EntityAttributesAllSortDirection,
        pinnedValuesByAttribute: [UUID: [UUID: MetaDetailFieldValue]]
    ) -> Bool {
        let l = pinnedValuesByAttribute[lhs.id]?[field.id]
        let r = pinnedValuesByAttribute[rhs.id]?[field.id]

        let leftMissing = isMissingValue(field: field, value: l)
        let rightMissing = isMissingValue(field: field, value: r)

        // Missing always last (independent of direction).
        if leftMissing != rightMissing {
            return rightMissing
        }

        // Both missing → stable tie-breaker.
        if leftMissing && rightMissing {
            return lhs.nameFolded < rhs.nameFolded
        }

        // Both present.
        let isAscending = (direction == .ascending)
        switch field.type {
        case .numberInt:
            let lv = l?.intValue ?? 0
            let rv = r?.intValue ?? 0
            if lv != rv { return isAscending ? (lv < rv) : (lv > rv) }

        case .numberDouble:
            let lv = l?.doubleValue ?? 0
            let rv = r?.doubleValue ?? 0
            if lv != rv { return isAscending ? (lv < rv) : (lv > rv) }

        case .date:
            let lv = l?.dateValue ?? .distantPast
            let rv = r?.dateValue ?? .distantPast
            if lv != rv { return isAscending ? (lv < rv) : (lv > rv) }

        case .toggle:
            let lv = (l?.boolValue ?? false) ? 1 : 0
            let rv = (r?.boolValue ?? false) ? 1 : 0
            if lv != rv { return isAscending ? (lv < rv) : (lv > rv) }

        case .singleChoice:
            let lv = choiceIndex(field: field, value: l)
            let rv = choiceIndex(field: field, value: r)
            if lv != rv { return isAscending ? (lv < rv) : (lv > rv) }

        case .singleLineText, .multiLineText:
            // Not supposed to happen (we don't offer these as sort options).
            // Still keep a deterministic order.
            break
        }

        // Tie-breaker.
        return lhs.nameFolded < rhs.nameFolded
    }

    private static func choiceIndex(field: MetaDetailFieldDefinition, value: MetaDetailFieldValue?) -> Int {
        let raw = (value?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return Int.max }

        if let idx = field.options.firstIndex(of: raw) {
            return idx
        }

        // Option was changed; keep value grouped towards the end.
        return 10_000
    }

    private static func isMissingValue(field: MetaDetailFieldDefinition, value: MetaDetailFieldValue?) -> Bool {
        guard let value else { return true }
        switch field.type {
        case .singleLineText, .multiLineText, .singleChoice:
            let s = (value.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty
        case .numberInt:
            return value.intValue == nil
        case .numberDouble:
            return value.doubleValue == nil
        case .date:
            return value.dateValue == nil
        case .toggle:
            return value.boolValue == nil
        }
    }
}
