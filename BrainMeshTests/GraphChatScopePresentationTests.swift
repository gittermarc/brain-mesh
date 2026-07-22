import Foundation
import Testing
@testable import BrainMesh

struct GraphChatScopePresentationTests {
    @Test
    func scopeChipUsesTheActualContextAndAccessibleLabel() {
        let entity = GraphChatEntityContextReference(id: UUID(), name: "Eine sehr lange Projekt-Entity")
        let field = GraphChatFieldContextReference(
            id: UUID(),
            name: "Ein sehr langes Statusfeld für Dynamic Type",
            type: .singleChoice,
            entity: entity
        )
        let scope = GraphChatScope.detailField(
            field.id,
            entityID: entity.id,
            in: GraphScope(graphID: UUID())
        )

        let presentation = GraphChatScopePresentation.model(
            for: .detailField(field),
            scope: scope,
            language: .german
        )

        #expect(presentation.title == "Detailfeld")
        #expect(presentation.detail?.contains(entity.name) == true)
        #expect(presentation.detail?.contains(field.name) == true)
        #expect(presentation.accessibilityLabel.contains("Chat-Kontext") == true)
    }

    @Test
    func selectionPresentationUsesActualCountInEnglish() throws {
        let first = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .entity, id: UUID()),
            label: "Projects"
        )
        let second = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Apollo"
        )
        let scope = try GraphChatScope.selection(
            [first.node, second.node],
            in: GraphScope(graphID: UUID())
        )

        let presentation = GraphChatScopePresentation.model(
            for: .selection([first, second]),
            scope: scope,
            language: .english
        )

        #expect(presentation.title == "Selection of 2 nodes")
        #expect(presentation.accessibilityLabel.contains("Chat context") == true)
    }
}
