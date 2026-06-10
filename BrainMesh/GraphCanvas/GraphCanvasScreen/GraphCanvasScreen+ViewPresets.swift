//
//  GraphCanvasScreen+ViewPresets.swift
//  BrainMesh
//
//  Local saved-view integration for GraphCanvasScreen.
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - View preset queries

    func viewPresetsForActiveGraph(limit: Int = 20) -> [GraphCanvasViewPreset] {
        guard let graphID = activeGraphID else { return [] }
        return viewPresetStore.presets(graphID: graphID, limit: limit)
    }

    func viewPresetSubtitle(for preset: GraphCanvasViewPreset) -> String {
        let focusPart: String
        if let focusLabel = preset.focusLabel, !focusLabel.isEmpty {
            focusPart = "Fokus: \(focusLabel)"
        } else {
            focusPart = "Global"
        }

        let hopLabel = preset.hops == 1 ? "1 Hop" : "\(preset.hops) Hops"
        let attributeLabel = preset.showAttributes ? "Attribute an" : "Attribute aus"
        return "\(focusPart) · \(hopLabel) · \(preset.workMode.title) · \(attributeLabel)"
    }

    func viewPresetAccessibilityLabel(for preset: GraphCanvasViewPreset) -> String {
        "Gespeicherte Ansicht anwenden: \(preset.name)"
    }

    // MARK: - View preset mutations

    @MainActor
    func saveCurrentViewPreset() {
        guard let graphID = activeGraphID else { return }

        let now = Date()
        let preset = GraphCanvasViewPreset(
            graphID: graphID,
            name: makeViewPresetName(now: now),
            createdAt: now,
            updatedAt: now,
            focusEntityID: focusEntity?.id,
            focusLabel: focusEntity?.name,
            selectedNodeKindRaw: selection?.kind.rawValue,
            selectedNodeID: selection?.uuid,
            hops: hops,
            showAttributes: showAttributes,
            workModeRaw: workMode.rawValue,
            lensEnabled: lensEnabled,
            lensHideNonRelevant: lensHideNonRelevant,
            lensDepth: lensDepth,
            maxNodes: maxNodes,
            maxLinks: maxLinks,
            collisionStrength: collisionStrength,
            scale: Double(scale),
            panWidth: Double(pan.width),
            panHeight: Double(pan.height)
        )

        viewPresetStore.save(preset)
        viewPresetMessage = "Ansicht lokal gespeichert."
    }

    @MainActor
    func applyViewPreset(_ preset: GraphCanvasViewPreset) {
        let plan = GraphCanvasViewPresetApplyPlan(preset: preset)
        applyViewPresetPlan(plan)
    }

    @MainActor
    func applyViewPresetPlan(_ plan: GraphCanvasViewPresetApplyPlan) {
        guard activeGraphID == plan.graphID else { return }

        viewPresetMessage = nil
        pendingViewPresetSelectionAfterLoad = nil
        pendingViewPresetCenterAfterLoad = nil
        pendingCenterAfterLoad = nil

        let resolvedFocus: MetaEntity?
        if let focusID = plan.focusEntityID {
            guard let entity = fetchEntity(id: focusID) else {
                applyViewPresetPlanValues(plan, focusEntity: nil, restoreSelection: false)
                viewPresetMessage = "Der gespeicherte Fokus existiert nicht mehr. Die globale Ansicht wurde geladen."
                scheduleLoadGraph(resetLayout: plan.shouldResetLayout)
                return
            }
            resolvedFocus = entity
        } else {
            resolvedFocus = nil
        }

        applyViewPresetPlanValues(plan, focusEntity: resolvedFocus, restoreSelection: true)
        scheduleLoadGraph(resetLayout: plan.shouldResetLayout)
    }

    @MainActor
    func deleteViewPreset(_ preset: GraphCanvasViewPreset) {
        viewPresetStore.remove(id: preset.id, graphID: preset.graphID)
        viewPresetMessage = "Ansicht gelöscht."
    }

    @MainActor
    func applyPendingViewPresetAfterLoadIfNeeded(availableKeys: Set<NodeKey>) {
        guard let key = pendingViewPresetSelectionAfterLoad else { return }

        let shouldCenter = pendingViewPresetCenterAfterLoad == key
        pendingViewPresetSelectionAfterLoad = nil
        pendingViewPresetCenterAfterLoad = nil

        guard availableKeys.contains(key) else {
            selection = nil
            viewPresetMessage = "Die gespeicherte Auswahl ist in diesem Ausschnitt nicht sichtbar."
            return
        }

        selection = key
        if shouldCenter {
            centerOnNodeAfterLayout(key)
        }
    }

    // MARK: - Private helpers

    @MainActor
    private func applyViewPresetPlanValues(
        _ plan: GraphCanvasViewPresetApplyPlan,
        focusEntity resolvedFocus: MetaEntity?,
        restoreSelection: Bool
    ) {
        focusEntity = resolvedFocus
        hops = plan.hops
        showAttributes = plan.showAttributes
        workMode = plan.workMode
        lensEnabled = plan.lensEnabled
        lensHideNonRelevant = plan.lensHideNonRelevant
        lensDepth = plan.lensDepth
        maxNodes = plan.maxNodes
        maxLinks = plan.maxLinks
        collisionStrength = plan.collisionStrength
        scale = plan.scale
        pan = plan.pan
        selection = nil
        showAllLinksForSelection = false

        guard restoreSelection, let selectedKey = plan.selection else { return }
        pendingViewPresetSelectionAfterLoad = selectedKey
        pendingViewPresetCenterAfterLoad = selectedKey
    }

    private func makeViewPresetName(now: Date) -> String {
        let baseName: String
        if let focusEntity {
            baseName = "Fokus: \(focusEntity.name)"
        } else if let selection {
            let label = displayLabel(for: selection)
            baseName = label.isEmpty ? "Auswahl" : "Auswahl: \(label)"
        } else {
            baseName = "Global"
        }

        return "\(shortenedViewPresetBaseName(baseName)) · \(GraphCanvasViewPresetDateFormatter.string(from: now))"
    }

    private func shortenedViewPresetBaseName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 52 else { return trimmed }
        let prefix = trimmed.prefix(49)
        return "\(prefix)"
    }
}

enum GraphCanvasViewPresetDateFormatter {
    static func string(from date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}
