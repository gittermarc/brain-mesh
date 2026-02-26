//
//  EntityAttributesAllListModel+PinnedHelpers.swift
//  BrainMesh
//
//  P0.1: Pinned-fields helpers extracted from EntityAttributesAllListModel.swift
//

import Foundation
import SwiftData

extension EntityAttributesAllListModel {
    static func computePinnedFields(for entity: MetaEntity) -> [MetaDetailFieldDefinition] {
        Array(
            entity.detailFieldsList
                .filter { $0.isPinned }
                .sorted(by: { $0.sortIndex < $1.sortIndex })
                .prefix(3)
        )
    }

    static func isSortablePinnedType(_ type: DetailFieldType) -> Bool {
        switch type {
        case .numberInt, .numberDouble, .date, .toggle, .singleChoice:
            return true
        case .singleLineText, .multiLineText:
            return false
        }
    }

    static func compactFieldName(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Feld" }
        if cleaned.count <= 18 { return cleaned }
        return String(cleaned.prefix(18)) + "…"
    }

    static func makePinnedSortMenuOptions(for fields: [MetaDetailFieldDefinition]) -> [PinnedSortMenuOption] {
        guard !fields.isEmpty else { return [] }
        var out: [PinnedSortMenuOption] = []
        out.reserveCapacity(fields.count * 2)

        for field in fields {
            let baseTitle = field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Feld" : field.name
            let sys = DetailsFormatting.systemImage(for: field)

            switch field.type {
            case .toggle:
                out.append(
                    PinnedSortMenuOption(
                        id: "\(field.id.uuidString)|trueFirst",
                        title: "\(baseTitle) (Ja zuerst)",
                        systemImage: sys,
                        selection: .pinned(fieldID: field.id, direction: .descending)
                    )
                )
                out.append(
                    PinnedSortMenuOption(
                        id: "\(field.id.uuidString)|falseFirst",
                        title: "\(baseTitle) (Nein zuerst)",
                        systemImage: sys,
                        selection: .pinned(fieldID: field.id, direction: .ascending)
                    )
                )

            case .singleChoice:
                out.append(
                    PinnedSortMenuOption(
                        id: "\(field.id.uuidString)|asc",
                        title: "\(baseTitle) (Optionen)",
                        systemImage: sys,
                        selection: .pinned(fieldID: field.id, direction: .ascending)
                    )
                )
                out.append(
                    PinnedSortMenuOption(
                        id: "\(field.id.uuidString)|desc",
                        title: "\(baseTitle) (umgekehrt)",
                        systemImage: sys,
                        selection: .pinned(fieldID: field.id, direction: .descending)
                    )
                )

            case .numberInt, .numberDouble, .date:
                out.append(
                    PinnedSortMenuOption(
                        id: "\(field.id.uuidString)|asc",
                        title: "\(baseTitle) (aufsteigend)",
                        systemImage: sys,
                        selection: .pinned(fieldID: field.id, direction: .ascending)
                    )
                )
                out.append(
                    PinnedSortMenuOption(
                        id: "\(field.id.uuidString)|desc",
                        title: "\(baseTitle) (absteigend)",
                        systemImage: sys,
                        selection: .pinned(fieldID: field.id, direction: .descending)
                    )
                )

            case .singleLineText, .multiLineText:
                break
            }
        }

        return out
    }
}
