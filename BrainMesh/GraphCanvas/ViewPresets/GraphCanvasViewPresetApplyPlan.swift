//
//  GraphCanvasViewPresetApplyPlan.swift
//  BrainMesh
//
//  Pure apply model for restoring saved GraphCanvas views.
//

import CoreGraphics
import Foundation

nonisolated struct GraphCanvasViewPresetApplyPlan: Equatable, Sendable {
    let presetID: UUID
    let graphID: UUID
    let focusEntityID: UUID?
    let selection: NodeKey?
    let hops: Int
    let showAttributes: Bool
    let workMode: WorkMode
    let lensEnabled: Bool
    let lensHideNonRelevant: Bool
    let lensDepth: Int
    let maxNodes: Int
    let maxLinks: Int
    let collisionStrength: Double
    let scale: CGFloat
    let pan: CGSize
    let shouldResetLayout: Bool

    init(preset: GraphCanvasViewPreset) {
        self.presetID = preset.id
        self.graphID = preset.graphID
        self.focusEntityID = preset.focusEntityID
        self.selection = preset.selectedNodeKey
        self.hops = GraphCanvasViewPresetApplyPlan.clamped(preset.hops, lower: 1, upper: 3)
        self.showAttributes = preset.showAttributes
        self.workMode = WorkMode.canonical(rawValue: preset.workModeRaw)
        self.lensEnabled = preset.lensEnabled
        self.lensHideNonRelevant = preset.lensHideNonRelevant
        self.lensDepth = GraphCanvasViewPresetApplyPlan.clamped(preset.lensDepth, lower: 1, upper: 2)
        self.maxNodes = max(1, preset.maxNodes)
        self.maxLinks = max(1, preset.maxLinks)
        self.collisionStrength = max(0, preset.collisionStrength)
        self.scale = CGFloat(max(0.1, preset.scale))
        self.pan = CGSize(width: CGFloat(preset.panWidth), height: CGFloat(preset.panHeight))
        self.shouldResetLayout = true
    }

    private static func clamped(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
