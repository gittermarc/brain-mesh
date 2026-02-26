//
//  EntityAttributesAllListModel+RowBuilder.swift
//  BrainMesh
//
//  P0.1: Row building extracted from EntityAttributesAllListModel.swift
//

import Foundation
import SwiftData

extension EntityAttributesAllListModel {
    func makeRow(
        attribute: MetaAttribute,
        pinnedFields: [MetaDetailFieldDefinition],
        pinnedValuesByAttribute: [UUID: [UUID: MetaDetailFieldValue]],
        showPinnedDetails: Bool,
        includeNotesPreview: Bool,
        ownersWithMedia: Set<UUID>
    ) -> Row {
        let title = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Attribut" : attribute.name

        let notePreview: String?
        if includeNotesPreview {
            let note = attribute.notes
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            notePreview = note.isEmpty ? nil : note
        } else {
            notePreview = nil
        }

        let iconRaw = (attribute.iconSymbolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isIconSet = !iconRaw.isEmpty

        let hasDetails = EntityAttributesAllListModel.attributeHasAnyDetails(attribute)
        let hasMedia = ownersWithMedia.contains(attribute.id)

        let pinnedChips: [PinnedChip]
        if showPinnedDetails {
            let valuesByField = pinnedValuesByAttribute[attribute.id] ?? [:]
            pinnedChips = pinnedFields.compactMap { field in
                let value = valuesByField[field.id]
                guard let short = DetailsFormatting.shortPillValue(for: field, value: value) else { return nil }

                let key = EntityAttributesAllListModel.compactFieldName(field.name)
                let title = "\(key): \(short)"

                return PinnedChip(
                    id: "\(field.id.uuidString)|\(title)",
                    systemImage: DetailsFormatting.systemImage(for: field),
                    title: title
                )
            }
        } else {
            pinnedChips = []
        }

        var searchParts: [String] = [
            attribute.nameFolded,
            attribute.searchLabelFolded
        ]

        if !attribute.notes.isEmpty {
            searchParts.append(BMSearch.fold(attribute.notes))
        }

        let valuesByField = pinnedValuesByAttribute[attribute.id] ?? [:]
        for field in pinnedFields {
            guard let value = DetailsFormatting.displayValue(for: field, value: valuesByField[field.id]) else { continue }
            let combined = "\(field.name) \(value)"
            searchParts.append(BMSearch.fold(combined))
        }

        let searchIndexFolded = searchParts.joined(separator: "\n")

        return Row(
            id: attribute.id,
            attribute: attribute,
            iconSymbolName: isIconSet ? iconRaw : "tag",
            isIconSet: isIconSet,
            title: title,
            notePreview: notePreview,
            pinnedChips: pinnedChips,
            hasDetails: hasDetails,
            hasMedia: hasMedia,
            searchIndexFolded: searchIndexFolded
        )
    }

    static func attributeHasAnyDetails(_ attribute: MetaAttribute) -> Bool {
        for v in attribute.detailValuesList {
            if let s = v.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return true
            }
            if v.intValue != nil { return true }
            if v.doubleValue != nil { return true }
            if v.dateValue != nil { return true }
            if v.boolValue != nil { return true }
        }
        return false
    }
}
