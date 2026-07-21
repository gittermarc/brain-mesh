import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphChatEvidencePresentationTests {
    @Test
    func sourceKindsReceiveDistinctPresentationTitles() {
        let graphID = GraphChatTestSupport.graphID
        let owner = GraphSourceNodeReference(
            kind: .entity,
            id: GraphChatTestSupport.projectEntityID
        )
        let node = GraphSourceNodeReference(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let evidence: [GraphEvidence] = [
            makeEvidence(graphID: graphID, kind: .entity),
            makeEvidence(graphID: graphID, kind: .attribute),
            makeEvidence(graphID: graphID, kind: .detailField, owner: owner),
            makeEvidence(graphID: graphID, kind: .detailValue, node: node),
            makeEvidence(graphID: graphID, kind: .link, owner: owner),
            makeEvidence(graphID: graphID, kind: .attachment, owner: owner),
            GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: graphID,
                    sourceKind: .graph,
                    sourceID: graphID
                ),
                summary: "Graph-Statistik",
                fieldValues: [
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Entities",
                        value: .integer(12),
                        unit: nil
                    ),
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Links",
                        value: .integer(24),
                        unit: nil
                    )
                ],
                navigationTitle: "Graph",
                identitySuffix: "stats"
            )
        ]

        let titles = evidence.map {
            GraphChatEvidencePresentation(evidence: $0).sourceKindTitle
        }

        #expect(titles == [
            "Entity",
            "Attribut",
            "Detailfeld",
            "Detailwert",
            "Verbindung",
            "Attachment-Metadaten",
            "Statistik"
        ])
    }

    @Test
    func relevantFieldValuesAreFormattedAndLimited() {
        let fieldValues = (0..<10).map { index in
            GraphEvidenceFieldValue(
                fieldID: UUID(),
                fieldName: "Feld \(index)",
                value: index == 0 ? .boolean(true) : .integer(index),
                unit: index == 1 ? "kg" : nil
            )
        }
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: GraphChatTestSupport.graphID,
                sourceKind: .entity,
                sourceID: GraphChatTestSupport.projectEntityID
            ),
            summary: "Projekt",
            fieldValues: fieldValues,
            navigationTitle: "Projekt"
        )

        let presentation = GraphChatEvidencePresentation(evidence: evidence)

        #expect(presentation.fieldValues.count == GraphChatEvidencePresentation.maximumFieldValues)
        #expect(presentation.fieldValues.first?.valueText == "Ja")
        #expect(presentation.fieldValues.dropFirst().first?.valueText == "1 kg")
    }

    @Test
    func injectedNavigationActionsReceiveValidatedTarget() throws {
        let recorder = GraphChatUINavigationRecorder()
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            navigationActions: recorder.actions()
        )
        let evidence = makeEvidence(
            graphID: GraphChatTestSupport.graphID,
            kind: .entity
        )
        let presentation = GraphChatEvidencePresentation(evidence: evidence)
        let target = try #require(presentation.navigationTarget)

        setup.viewModel.openEntry(presentation)
        setup.viewModel.showInGraph(presentation)

        #expect(recorder.openedTargets == [target])
        #expect(recorder.shownTargets == [target])
    }

    private func makeEvidence(
        graphID: UUID,
        kind: GraphSourceKind,
        node: GraphSourceNodeReference? = nil,
        owner: GraphSourceNodeReference? = nil
    ) -> GraphEvidence {
        let sourceID = UUID()
        return GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: kind,
                sourceID: sourceID,
                node: node,
                owner: owner,
                fieldID: kind == .detailField || kind == .detailValue ? sourceID : nil,
                linkID: kind == .link ? sourceID : nil,
                attachmentID: kind == .attachment ? sourceID : nil
            ),
            summary: "Quelle",
            navigationTitle: "Quelle",
            identitySuffix: kind.rawValue
        )
    }
}
