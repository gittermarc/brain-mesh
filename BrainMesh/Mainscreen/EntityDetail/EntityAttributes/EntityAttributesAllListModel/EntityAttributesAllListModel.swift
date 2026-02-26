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
        let currentAttributeIDSet = Set(currentAttributeIDs)

        let entityChanged = (cache.entityID != entity.id) || (cache.graphID != entity.graphID)
        let pinnedChanged = (cache.pinnedFieldIDs != currentPinnedIDs)
        let attributesChanged = (cache.attributeIDs != currentAttributeIDs)
        let groupingChanged = (cache.lastGrouping != grouping)
        let showPinnedChanged = (cache.lastShowPinnedDetails != showPinnedDetails)
        let notesPreviewChanged = (cache.lastIncludeNotesPreview != includeNotesPreview)

        let needsMediaFlags: Bool = (grouping == .hasMedia)

        // Fast path: When only searchText/sort changes while typing, we only filter + sort on cached rows.
        let structuralChanged = entityChanged || pinnedChanged || attributesChanged || groupingChanged || showPinnedChanged || notesPreviewChanged
        if allowCachedRows && !structuralChanged && !cache.rowsByID.isEmpty {
            applyFilterSortAndPublish(
                attrs: attrs,
                searchText: searchText,
                sortSelection: sortSelection,
                pinnedFields: pinned
            )
            return
        }

        // Pinned values: Only refetch when a structural input changed, or when we do a non-cached rebuild.
        if pinned.isEmpty {
            cache.pinnedValuesByAttribute = [:]
        } else {
            let needsPinnedValuesRefetch = !allowCachedRows
                || entityChanged
                || pinnedChanged
                || attributesChanged
                || showPinnedChanged
                || cache.pinnedValuesByAttribute.isEmpty

            if needsPinnedValuesRefetch {
                cache.pinnedValuesByAttribute = fetchPinnedValuesLookup(
                    context: context,
                    pinnedFields: pinned,
                    graphID: entity.graphID,
                    attributeIDs: currentAttributeIDSet
                )
            }
        }

        if needsMediaFlags {
            let needsOwnersRefetch = !allowCachedRows
                || entityChanged
                || groupingChanged
                || attributesChanged

            if needsOwnersRefetch {
                cache.ownersWithMedia = fetchAttributeOwnersWithMedia(
                    context: context,
                    attributeIDs: currentAttributeIDSet,
                    graphID: entity.graphID
                )
            }
        } else {
            cache.ownersWithMedia = []
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

        applyFilterSortAndPublish(
            attrs: attrs,
            searchText: searchText,
            sortSelection: sortSelection,
            pinnedFields: pinned
        )
    }

    private func applyFilterSortAndPublish(
        attrs: [MetaAttribute],
        searchText: String,
        sortSelection: EntityAttributesAllSortSelection,
        pinnedFields: [MetaDetailFieldDefinition]
    ) {
        let needle = BMSearch.fold(searchText)

        let rowsByID = cache.rowsByID
        let filteredAttrs: [MetaAttribute]
        if needle.isEmpty {
            filteredAttrs = attrs
        } else {
            filteredAttrs = attrs.filter { a in
                guard let row = rowsByID[a.id] else { return false }
                return row.searchIndexFolded.contains(needle)
            }
        }

        let sortedAttrs = EntityAttributesAllListModel.sortAttributes(
            filteredAttrs,
            sortSelection: sortSelection,
            pinnedFields: pinnedFields,
            pinnedValuesByAttribute: cache.pinnedValuesByAttribute
        )

        let updatedRowsByID = cache.rowsByID
        visibleRows = sortedAttrs.compactMap { updatedRowsByID[$0.id] }
    }
}
