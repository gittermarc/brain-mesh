import CoreGraphics
import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasViewPresetApplyPlanTests {

    @Test
    func applyPlanContainsSavedFocusSelectionLensLimitsAndCamera() throws {
        let graphID = UUID()
        let focusEntityID = UUID()
        let selectedNodeID = UUID()
        let presetID = UUID()
        let preset = GraphCanvasViewPreset(
            id: presetID,
            graphID: graphID,
            name: "Fokus: Atlas",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            focusEntityID: focusEntityID,
            focusLabel: "Atlas",
            selectedNodeKindRaw: NodeKind.attribute.rawValue,
            selectedNodeID: selectedNodeID,
            hops: 3,
            showAttributes: false,
            workModeRaw: "edit",
            lensEnabled: false,
            lensHideNonRelevant: true,
            lensDepth: 1,
            maxNodes: 220,
            maxLinks: 1800,
            collisionStrength: 0.055,
            scale: 1.75,
            panWidth: 120,
            panHeight: -48
        )

        let plan = GraphCanvasViewPresetApplyPlan(preset: preset)

        #expect(plan.presetID == presetID)
        #expect(plan.graphID == graphID)
        #expect(plan.focusEntityID == focusEntityID)
        #expect(plan.selection == NodeKey(kind: .attribute, uuid: selectedNodeID))
        #expect(plan.hops == 3)
        #expect(plan.showAttributes == false)
        #expect(plan.workMode == .organize)
        #expect(plan.lensEnabled == false)
        #expect(plan.lensHideNonRelevant == true)
        #expect(plan.lensDepth == 1)
        #expect(plan.maxNodes == 220)
        #expect(plan.maxLinks == 1800)
        #expect(plan.collisionStrength == 0.055)
        #expect(plan.scale == CGFloat(1.75))
        #expect(plan.pan == CGSize(width: 120, height: -48))
        #expect(plan.shouldResetLayout == true)
    }

    @Test
    func invalidSelectionRawFallsBackToNilSelection() {
        let preset = GraphCanvasViewPreset(
            graphID: UUID(),
            name: "Broken Selection",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            focusEntityID: nil,
            focusLabel: nil,
            selectedNodeKindRaw: 999,
            selectedNodeID: UUID(),
            hops: 1,
            showAttributes: true,
            workModeRaw: WorkMode.present.rawValue,
            lensEnabled: true,
            lensHideNonRelevant: false,
            lensDepth: 2,
            maxNodes: 140,
            maxLinks: 800,
            collisionStrength: 0.030,
            scale: 1.0,
            panWidth: 0,
            panHeight: 0
        )

        let plan = GraphCanvasViewPresetApplyPlan(preset: preset)

        #expect(plan.selection == nil)
        #expect(plan.workMode == .present)
    }
}
