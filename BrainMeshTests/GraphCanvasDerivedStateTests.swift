import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasDerivedStateTests {

    @Test
    func displayEdges_limitsLinkEdgesForSelectionWhileKeepingContainment() {
        let selection = makeKey("00000000-0000-0000-0000-000000000001")
        let alpha = makeKey("00000000-0000-0000-0000-000000000002")
        let beta = makeKey("00000000-0000-0000-0000-000000000003")
        let zulu = makeKey("00000000-0000-0000-0000-000000000004")
        let child = makeKey("00000000-0000-0000-0000-000000000005")

        let containment = GraphEdge(a: selection, b: child, type: .containment)
        let linkZulu = GraphEdge(a: selection, b: zulu, type: .link)
        let linkAlpha = GraphEdge(a: selection, b: alpha, type: .link)
        let linkBeta = GraphEdge(a: selection, b: beta, type: .link)
        let unrelated = GraphEdge(a: beta, b: zulu, type: .link)

        let labels: [NodeKey: String] = [
            alpha: "Alpha",
            beta: "Beta",
            child: "Child",
            selection: "Selected",
            zulu: "Zulu"
        ]

        let drawEdges = GraphCanvasDisplayEdgesPlanner.displayEdges(
            selection: selection,
            allEdges: [containment, linkZulu, linkAlpha, linkBeta, unrelated],
            showAllLinksForSelection: false,
            degreeCap: 2,
            labelForKey: { key in
                labels[key, default: ""]
            }
        )

        #expect(drawEdges.count == 3)
        #expect(Set(drawEdges) == Set([containment, linkAlpha, linkBeta]))
    }

    @Test
    func displayEdges_showAllLinksReturnsAllIncidentEdges() {
        let selection = makeKey("00000000-0000-0000-0000-000000000011")
        let alpha = makeKey("00000000-0000-0000-0000-000000000012")
        let beta = makeKey("00000000-0000-0000-0000-000000000013")
        let gamma = makeKey("00000000-0000-0000-0000-000000000014")

        let linkAlpha = GraphEdge(a: selection, b: alpha, type: .link)
        let linkBeta = GraphEdge(a: selection, b: beta, type: .link)
        let linkGamma = GraphEdge(a: selection, b: gamma, type: .link)

        let drawEdges = GraphCanvasDisplayEdgesPlanner.displayEdges(
            selection: selection,
            allEdges: [linkAlpha, linkBeta, linkGamma],
            showAllLinksForSelection: true,
            degreeCap: 1,
            labelForKey: { _ in "" }
        )

        #expect(Set(drawEdges) == Set([linkAlpha, linkBeta, linkGamma]))
        #expect(GraphCanvasDisplayEdgesPlanner.hiddenLinkCount(
            selection: selection,
            allEdges: [linkAlpha, linkBeta, linkGamma],
            showAllLinksForSelection: true,
            degreeCap: 1
        ) == 0)
    }

    @Test
    func derivedStateBuilder_autoSpotlightForcesLensAndPhysicsRelevantNeighbors() {
        let selection = makeKey("00000000-0000-0000-0000-000000000021")
        let alpha = makeKey("00000000-0000-0000-0000-000000000022")
        let beta = makeKey("00000000-0000-0000-0000-000000000023")

        let linkAlpha = GraphEdge(a: selection, b: alpha, type: .link)
        let linkBeta = GraphEdge(a: selection, b: beta, type: .link)

        let derived = GraphCanvasDerivedStateBuilder.build(
            selection: selection,
            edges: [linkAlpha, linkBeta],
            showAllLinksForSelection: false,
            degreeCap: 12,
            lensEnabled: false,
            lensHideNonRelevant: false,
            lensDepth: 5,
            labelForKey: { _ in "" }
        )

        #expect(derived.lens.enabled == true)
        #expect(derived.lens.hideNonRelevant == true)
        #expect(derived.lens.depth == 1)
        #expect(derived.physicsRelevant == Set([selection, alpha, beta]))
    }

    @Test
    func derivedStateBuilder_withoutSelectionKeepsPhysicsRelevantNil() {
        let alpha = makeKey("00000000-0000-0000-0000-000000000032")
        let beta = makeKey("00000000-0000-0000-0000-000000000033")
        let link = GraphEdge(a: alpha, b: beta, type: .link)

        let derived = GraphCanvasDerivedStateBuilder.build(
            selection: nil,
            edges: [link],
            showAllLinksForSelection: false,
            degreeCap: 12,
            lensEnabled: true,
            lensHideNonRelevant: true,
            lensDepth: 3,
            labelForKey: { _ in "" }
        )

        #expect(derived.drawEdges.isEmpty)
        #expect(derived.lens.enabled == false)
        #expect(derived.physicsRelevant == nil)
    }

    @Test
    func cacheMutation_reportsOnlyRealChanges() {
        let selection = makeKey("00000000-0000-0000-0000-000000000041")
        let alpha = makeKey("00000000-0000-0000-0000-000000000042")
        let beta = makeKey("00000000-0000-0000-0000-000000000043")

        let linkAlpha = GraphEdge(a: selection, b: alpha, type: .link)
        let linkBeta = GraphEdge(a: selection, b: beta, type: .link)

        let base = GraphCanvasDerivedStateBuilder.build(
            selection: selection,
            edges: [linkAlpha, linkBeta],
            showAllLinksForSelection: false,
            degreeCap: 1,
            lensEnabled: false,
            lensHideNonRelevant: false,
            lensDepth: 4,
            labelForKey: { key in
                key == alpha ? "Alpha" : "Beta"
            }
        )

        let unchanged = GraphCanvasDerivedStateCacheMutation.diff(
            cachedDrawEdges: base.drawEdges,
            cachedLens: base.lens,
            cachedPhysicsRelevant: base.physicsRelevant,
            cachedDetailsFocusSummary: base.detailsFocusSummary,
            derived: base
        )

        let expanded = GraphCanvasDerivedStateBuilder.build(
            selection: selection,
            edges: [linkAlpha, linkBeta],
            showAllLinksForSelection: true,
            degreeCap: 1,
            lensEnabled: false,
            lensHideNonRelevant: false,
            lensDepth: 4,
            labelForKey: { key in
                key == alpha ? "Alpha" : "Beta"
            }
        )

        let changed = GraphCanvasDerivedStateCacheMutation.diff(
            cachedDrawEdges: base.drawEdges,
            cachedLens: base.lens,
            cachedPhysicsRelevant: base.physicsRelevant,
            cachedDetailsFocusSummary: base.detailsFocusSummary,
            derived: expanded
        )

        #expect(unchanged.hasChanges == false)
        #expect(unchanged.drawEdgesChanged == false)
        #expect(unchanged.lensChanged == false)
        #expect(unchanged.physicsRelevantChanged == false)
        #expect(unchanged.detailsFocusSummaryChanged == false)

        #expect(changed.hasChanges == true)
        #expect(changed.drawEdgesChanged == true)
        #expect(changed.detailsFocusSummaryChanged == false)
    }

    @Test
    func derivedStateBuilder_includesDetailsFocusSummaryForVisibleAttributes() {
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let fieldID = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let matchingKey = NodeKey(kind: .attribute, uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000053")!)
        let nonMatchingKey = NodeKey(kind: .attribute, uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000054")!)

        let preparedState = GraphDetailsPreparedState(
            attributes: [
                GraphDetailsPreparedAttribute(
                    nodeKey: matchingKey,
                    attributeID: matchingKey.uuid,
                    entityID: entityID,
                    valuesByFieldID: [
                        fieldID: GraphDetailsPreparedValue(
                            stringValue: "In Arbeit",
                            intValue: nil,
                            doubleValue: nil,
                            dateValue: nil,
                            boolValue: nil
                        )
                    ]
                ),
                GraphDetailsPreparedAttribute(
                    nodeKey: nonMatchingKey,
                    attributeID: nonMatchingKey.uuid,
                    entityID: entityID,
                    valuesByFieldID: [
                        fieldID: GraphDetailsPreparedValue(
                            stringValue: "Geplant",
                            intValue: nil,
                            doubleValue: nil,
                            dateValue: nil,
                            boolValue: nil
                        )
                    ]
                )
            ],
            fieldsByEntityID: [
                entityID: [
                    GraphDetailsPreparedField(
                        id: fieldID,
                        entityID: entityID,
                        name: "Status",
                        type: .singleChoice,
                        sortIndex: 0,
                        isPinned: true,
                        unit: nil,
                        options: ["Geplant", "In Arbeit"]
                    )
                ]
            ]
        )

        let focusState = GraphDetailsFocusState(
            entityID: entityID,
            entityName: "Projekt",
            rule: GraphDetailsMatchRule(
                fieldID: fieldID,
                fieldName: "Status",
                fieldType: .singleChoice,
                comparison: .equals(.choice("In Arbeit"))
            ),
            mode: .highlight
        )

        let derived = GraphCanvasDerivedStateBuilder.build(
            selection: nil,
            edges: [],
            showAllLinksForSelection: false,
            degreeCap: 12,
            lensEnabled: false,
            lensHideNonRelevant: false,
            lensDepth: 2,
            detailsFocusState: focusState,
            detailsFocusPreparedState: preparedState,
            labelForKey: { _ in "" }
        )

        #expect(derived.detailsFocusSummary.hasActiveFocus == true)
        #expect(derived.detailsFocusSummary.inspectedAttributeCount == 2)
        #expect(derived.detailsFocusSummary.matchCount == 1)
        #expect(derived.detailsFocusSummary.matchedAttributeNodeKeys == Set([matchingKey]))
    }

    private func makeKey(_ uuidString: String) -> NodeKey {
        NodeKey(kind: .entity, uuid: UUID(uuidString: uuidString)!)
    }
}
