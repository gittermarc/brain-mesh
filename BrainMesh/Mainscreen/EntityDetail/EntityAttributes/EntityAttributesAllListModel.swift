//
//  EntityAttributesAllListModel.swift
//  BrainMesh
//
//  Snapshot model for Entity → All Attributes list.
//  Builds row models (including pinned detail chips) off the SwiftUI render path.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

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

@MainActor
final class EntityAttributesAllListModel: ObservableObject {
    struct PinnedChip: Identifiable, Hashable {
        let id: String
        let systemImage: String
        let title: String
    }

    struct Row: Identifiable {
        let id: UUID
        let attribute: MetaAttribute
        let iconSymbolName: String
        let isIconSet: Bool
        let title: String
        let notePreview: String?
        let pinnedChips: [PinnedChip]
        let hasDetails: Bool
        let hasMedia: Bool
        let searchIndexFolded: String
    }

    struct PinnedSortMenuOption: Identifiable, Hashable {
        let id: String
        let title: String
        let systemImage: String
        let selection: EntityAttributesAllSortSelection
    }

    @Published private(set) var pinnedFields: [MetaDetailFieldDefinition] = []
    @Published private(set) var pinnedSortableFields: [MetaDetailFieldDefinition] = []
    @Published private(set) var pinnedSortMenuOptions: [PinnedSortMenuOption] = []
    @Published private(set) var visibleRows: [Row] = []

    private var rebuildTask: Task<Void, Never>? = nil

    private struct Cache {
        var entityID: UUID? = nil
        var graphID: UUID? = nil
        var attributeIDs: [UUID] = []

        var pinnedFieldIDs: [UUID] = []
        var pinnedValuesByAttribute: [UUID: [UUID: MetaDetailFieldValue]] = [:]
        var pinnedValueCountsByField: [UUID: Int] = [:]

        var ownersWithMedia: Set<UUID> = []
        var attributeAttachmentsCount: Int? = nil
        var rowsByID: [UUID: Row] = [:]

        var lastShowPinnedDetails: Bool = false
        var lastIncludeNotesPreview: Bool = false
        var lastGrouping: AttributesAllGrouping = .none
    }

    private var cache = Cache()

    func scheduleRebuild(
        context: ModelContext,
        entity: MetaEntity,
        searchText: String,
        showPinnedDetails: Bool,
        includeNotesPreview: Bool,
        sortSelection: EntityAttributesAllSortSelection,
        grouping: AttributesAllGrouping,
        debounce: Bool
    ) {
        rebuildTask?.cancel()

        rebuildTask = Task { @MainActor in
            if debounce {
                // 150ms feels responsive but keeps typing smooth.
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            rebuildInternal(
                context: context,
                entity: entity,
                searchText: searchText,
                showPinnedDetails: showPinnedDetails,
                includeNotesPreview: includeNotesPreview,
                sortSelection: sortSelection,
                grouping: grouping,
                allowCachedRows: debounce
            )
        }
    }

    func rebuild(
        context: ModelContext,
        entity: MetaEntity,
        searchText: String,
        showPinnedDetails: Bool,
        includeNotesPreview: Bool,
        sortSelection: EntityAttributesAllSortSelection,
        grouping: AttributesAllGrouping
    ) {
        rebuildInternal(
            context: context,
            entity: entity,
            searchText: searchText,
            showPinnedDetails: showPinnedDetails,
            includeNotesPreview: includeNotesPreview,
            sortSelection: sortSelection,
            grouping: grouping,
            allowCachedRows: true
        )
    }

    private func rebuildInternal(
        context: ModelContext,
        entity: MetaEntity,
        searchText: String,
        showPinnedDetails: Bool,
        includeNotesPreview: Bool,
        sortSelection: EntityAttributesAllSortSelection,
        grouping: AttributesAllGrouping,
        allowCachedRows: Bool
    ) {
        let attrs = entity.attributesList

        // Always keep these published properties fresh (cheap).
        let pinned = EntityAttributesAllListModel.computePinnedFields(for: entity)
        pinnedFields = pinned
        pinnedSortableFields = pinned.filter { EntityAttributesAllListModel.isSortablePinnedType($0.type) }
        pinnedSortMenuOptions = EntityAttributesAllListModel.makePinnedSortMenuOptions(for: pinnedSortableFields)

        let currentPinnedIDs = pinned.map { $0.id }
        let currentAttributeIDs = attrs.map { $0.id }

        let entityChanged = (cache.entityID != entity.id) || (cache.graphID != entity.graphID)
        let pinnedChanged = (cache.pinnedFieldIDs != currentPinnedIDs)
        let attributesChanged = (cache.attributeIDs != currentAttributeIDs)
        let groupingChanged = (cache.lastGrouping != grouping)
        let showPinnedChanged = (cache.lastShowPinnedDetails != showPinnedDetails)
        let notesPreviewChanged = (cache.lastIncludeNotesPreview != includeNotesPreview)

        var pinnedCountsChanged = false
        var currentPinnedCountsByField: [UUID: Int] = [:]
        currentPinnedCountsByField.reserveCapacity(pinned.count)

        if !pinned.isEmpty {
            for field in pinned {
                let fieldID: UUID = field.id
                let fd = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate<MetaDetailFieldValue> { v in
                    v.fieldID == fieldID
                })
                let count = (try? context.fetchCount(fd)) ?? 0
                currentPinnedCountsByField[fieldID] = count
                if cache.pinnedValueCountsByField[fieldID] != count {
                    pinnedCountsChanged = true
                }
            }
        }

        let needsPinnedValuesRefetch = entityChanged || pinnedChanged || attributesChanged || pinnedCountsChanged
        if needsPinnedValuesRefetch {
            cache.pinnedValuesByAttribute = fetchPinnedValuesLookup(context: context, pinnedFields: pinned)
            cache.pinnedValueCountsByField = currentPinnedCountsByField
        }

        let needsMediaFlags: Bool = (grouping == .hasMedia)
        if needsMediaFlags {
            let ownerKindRaw = NodeKind.attribute.rawValue
            let attachmentCount: Int
            if let graphID = entity.graphID {
                let gid: UUID? = graphID
                let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { a in
                    a.ownerKindRaw == ownerKindRaw && a.graphID == gid
                })
                attachmentCount = (try? context.fetchCount(fd)) ?? 0
            } else {
                let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { a in
                    a.ownerKindRaw == ownerKindRaw
                })
                attachmentCount = (try? context.fetchCount(fd)) ?? 0
            }

            let attachmentCountChanged = (cache.attributeAttachmentsCount != attachmentCount)
            let needsOwnersRefetch = entityChanged || groupingChanged || attributesChanged || attachmentCountChanged
            if needsOwnersRefetch {
                let attributeIDs = Set(currentAttributeIDs)
                cache.ownersWithMedia = fetchAttributeOwnersWithMedia(
                    context: context,
                    attributeIDs: attributeIDs,
                    graphID: entity.graphID
                )
                cache.attributeAttachmentsCount = attachmentCount
            }
        }

        // Rebuild row models only when a structural input changed.
        let needsRowRebuild = !allowCachedRows || entityChanged || pinnedChanged || attributesChanged || groupingChanged || showPinnedChanged || notesPreviewChanged
        if needsRowRebuild {
            let ownersWithMedia: Set<UUID> = needsMediaFlags ? cache.ownersWithMedia : []

            var rowsByID: [UUID: Row] = [:]
            rowsByID.reserveCapacity(min(attrs.count, 512))

            for a in attrs {
                let row = makeRow(
                    attribute: a,
                    pinnedFields: pinned,
                    pinnedValuesByAttribute: cache.pinnedValuesByAttribute,
                    showPinnedDetails: showPinnedDetails,
                    includeNotesPreview: includeNotesPreview,
                    ownersWithMedia: ownersWithMedia
                )
                rowsByID[a.id] = row
            }

            cache.rowsByID = rowsByID
            cache.entityID = entity.id
            cache.graphID = entity.graphID
            cache.attributeIDs = currentAttributeIDs
            cache.pinnedFieldIDs = currentPinnedIDs
            cache.lastShowPinnedDetails = showPinnedDetails
            cache.lastIncludeNotesPreview = includeNotesPreview
            cache.lastGrouping = grouping
        }

        // Fast path for typing/search and sort changes: filter + sort based on cached rows.
        let needle = BMSearch.fold(searchText)
        let filteredAttrs: [MetaAttribute]
        if needle.isEmpty {
            filteredAttrs = attrs
        } else {
            let rowsByID = cache.rowsByID
            filteredAttrs = attrs.filter { a in
                guard let row = rowsByID[a.id] else { return false }
                return row.searchIndexFolded.contains(needle)
            }
        }

        let sortedAttrs = EntityAttributesAllListModel.sortAttributes(
            filteredAttrs,
            sortSelection: sortSelection,
            pinnedFields: pinned,
            pinnedValuesByAttribute: cache.pinnedValuesByAttribute
        )

        let rowsByID = cache.rowsByID
        visibleRows = sortedAttrs.compactMap { rowsByID[$0.id] }
    }

    // MARK: - Row building

    private func makeRow(
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

    private static func attributeHasAnyDetails(_ attribute: MetaAttribute) -> Bool {
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

    private func fetchAttributeOwnersWithMedia(
        context: ModelContext,
        attributeIDs: Set<UUID>,
        graphID: UUID?
    ) -> Set<UUID> {
        guard !attributeIDs.isEmpty else { return [] }

        let ownerKindRaw = NodeKind.attribute.rawValue

        let attachments: [MetaAttachment]
        if let graphID {
            let gid: UUID? = graphID
            let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == ownerKindRaw && a.graphID == gid
            })
            attachments = (try? context.fetch(fd)) ?? []
        } else {
            let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == ownerKindRaw
            })
            attachments = (try? context.fetch(fd)) ?? []
        }

        var owners = Set<UUID>()
        owners.reserveCapacity(min(attachments.count, 256))
        for a in attachments {
            if attributeIDs.contains(a.ownerID) {
                owners.insert(a.ownerID)
            }
        }
        return owners
    }

    // MARK: - Pinned values lookup

    private func fetchPinnedValuesLookup(
        context: ModelContext,
        pinnedFields: [MetaDetailFieldDefinition]
    ) -> [UUID: [UUID: MetaDetailFieldValue]] {
        guard !pinnedFields.isEmpty else { return [:] }

        var result: [UUID: [UUID: MetaDetailFieldValue]] = [:]
        result.reserveCapacity(256)

        for field in pinnedFields {
            // SwiftData #Predicate can't reliably compare against a captured model object's property
            // (e.g. `field.id`). Capture the UUID as a constant instead.
            let fieldID: UUID = field.id
            let fd = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate<MetaDetailFieldValue> { v in
                v.fieldID == fieldID
            })
            let values = (try? context.fetch(fd)) ?? []

            for v in values {
                result[v.attributeID, default: [:]][field.id] = v
            }
        }

        return result
    }

    // MARK: - Sort

    private static func sortAttributes(
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

    // MARK: - Helpers

    private static func computePinnedFields(for entity: MetaEntity) -> [MetaDetailFieldDefinition] {
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

    private static func compactFieldName(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Feld" }
        if cleaned.count <= 18 { return cleaned }
        return String(cleaned.prefix(18)) + "…"
    }

    private static func makePinnedSortMenuOptions(for fields: [MetaDetailFieldDefinition]) -> [PinnedSortMenuOption] {
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
