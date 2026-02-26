//
//  GraphCanvasScreen+DetailsPeek.swift
//  BrainMesh
//
//  Option A (MVP): Details Peek for the Graph selection chip.
//  Read-only in PR A1.
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Model

    private static var entityPinnedSummaryID: UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")! }
    private static var entityTotalSummaryID: UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")! }

    struct GraphDetailsPeekChip: Identifiable, Hashable {
        let fieldID: UUID
        let fieldName: String
        let valueText: String
        let isPlaceholder: Bool

        var id: UUID { fieldID }
    }

    struct GraphEntityFieldPeekItem: Identifiable, Hashable {
        let fieldID: UUID
        let fieldName: String
        let isPinned: Bool

        var id: UUID { fieldID }
    }

    struct GraphDetailsValueEditRequest: Identifiable {
        let attribute: MetaAttribute
        let field: MetaDetailFieldDefinition

        var id: String {
            "\(attribute.id.uuidString)|\(field.id.uuidString)"
        }
    }

    // MARK: - Recompute

    /// Recomputes the Details Peek chips for the current selection.
    ///
    /// Important: This must be called only on selection change (not in `body`) to keep the render path cheap.
    @MainActor
    func recomputeDetailsPeek(for selection: NodeKey?) {
        guard let selection else {
            detailsPeekChips = []
            entityFieldsPeekItems = []
            return
        }

        switch selection.kind {
        case .attribute:
            entityFieldsPeekItems = []

            guard let attr = fetchAttribute(id: selection.uuid) else {
                detailsPeekChips = []
                return
            }
            detailsPeekChips = buildDetailsPeekChips(for: attr, preparedLimit: 5)

        case .entity:
            guard let entity = fetchEntity(id: selection.uuid) else {
                detailsPeekChips = []
                entityFieldsPeekItems = []
                return
            }
            detailsPeekChips = buildEntitySummaryChips(for: entity)
            entityFieldsPeekItems = buildEntityFieldsPeekItems(for: entity)
        }
    }


    // MARK: - Editing

    /// Prepares a sheet request to edit a single field value.
    /// This runs only on user interaction (tap), not during rendering.
    @MainActor
    func openDetailsValueEditor(fieldID: UUID) {
        guard let sel = selection, sel.kind == .attribute else { return }
        guard let attr = fetchAttribute(id: sel.uuid) else { return }
        guard let owner = attr.owner else { return }
        guard let field = owner.detailFieldsList.first(where: { $0.id == fieldID }) else { return }
        detailsValueEditRequest = GraphDetailsValueEditRequest(attribute: attr, field: field)
    }

    // MARK: - Builder

    /// Builds up to `preparedLimit` chips.
    /// UI can decide to display fewer (e.g. 3 on iPhone), while keeping the extra prepared for future iterations.
    func buildDetailsPeekChips(for attribute: MetaAttribute, preparedLimit: Int) -> [GraphDetailsPeekChip] {
        guard preparedLimit > 0 else { return [] }
        guard let owner = attribute.owner else { return [] }

        let pinnedFields = owner.detailFieldsList
            .filter { $0.isPinned }
            .sorted(by: { $0.sortIndex < $1.sortIndex })

        guard !pinnedFields.isEmpty else { return [] }

        // Pre-index values to avoid repeatedly searching `detailValuesList`.
        var valueByFieldID: [UUID: MetaDetailFieldValue] = [:]
        for v in attribute.detailValuesList {
            if valueByFieldID[v.fieldID] == nil {
                valueByFieldID[v.fieldID] = v
            }
        }

        var filled: [GraphDetailsPeekChip] = []
        var empty: [GraphDetailsPeekChip] = []

        for field in pinnedFields {
            let value = valueByFieldID[field.id]
            if let short = DetailsFormatting.shortPillValue(for: field, value: value) {
                filled.append(
                    GraphDetailsPeekChip(
                        fieldID: field.id,
                        fieldName: field.name,
                        valueText: short,
                        isPlaceholder: false
                    )
                )
            } else {
                empty.append(
                    GraphDetailsPeekChip(
                        fieldID: field.id,
                        fieldName: field.name,
                        valueText: "Hinzufügen",
                        isPlaceholder: true
                    )
                )
            }
        }

        var out: [GraphDetailsPeekChip] = []
        out.reserveCapacity(min(preparedLimit, pinnedFields.count))

        out.append(contentsOf: filled.prefix(preparedLimit))

        if out.count < preparedLimit {
            let remaining = preparedLimit - out.count
            out.append(contentsOf: empty.prefix(remaining))
        }

        if out.count > preparedLimit {
            out = Array(out.prefix(preparedLimit))
        }

        return out
    }




    func buildEntityFieldsPeekItems(for entity: MetaEntity) -> [GraphEntityFieldPeekItem] {
        entity.detailFieldsList.map { field in
            GraphEntityFieldPeekItem(
                fieldID: field.id,
                fieldName: field.name,
                isPinned: field.isPinned
            )
        }
    }

    func buildEntitySummaryChips(for entity: MetaEntity) -> [GraphDetailsPeekChip] {
        let total = entity.detailFieldsList.count
        let pinned = entity.detailFieldsList.filter { $0.isPinned }.count

        return [
            GraphDetailsPeekChip(
                fieldID: Self.entityPinnedSummaryID,
                fieldName: "Pinned Felder",
                valueText: String(pinned),
                isPlaceholder: false
            ),
            GraphDetailsPeekChip(
                fieldID: Self.entityTotalSummaryID,
                fieldName: "Felder gesamt",
                valueText: String(total),
                isPlaceholder: false
            )
        ]
    }

}
