//
//  GraphChatTabUIContractTests.swift
//  BrainMeshTests
//

import SwiftUI
import Testing
import UIKit
@testable import BrainMesh

@Suite("Graph Chat tab UI contracts")
@MainActor
struct GraphChatTabUIContractTests {
    @Test
    func statusPreviewAndLockedContentRenderAtAccessibilitySizesOnPhoneAndPad() throws {
        let configurations: [(width: CGFloat, dynamicTypeSize: DynamicTypeSize)] = [
            (390, .accessibility3),
            (1_024, .accessibility5)
        ]
        let suggestion = GraphChatEmptyStateSuggestion(
            id: "preview:open-projects",
            title: "Offene Projekte",
            prompt: "Welche Projekte sind noch offen?",
            kind: .list
        )

        for configuration in configurations {
            let statusImage = try #require(
                renderedImage(
                    GraphChatTabStatusView(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Lokaler Index wird vorbereitet",
                        message: "BrainMesh bereitet die dokumentierten Graphdaten für eine begrenzte, quellenbasierte Suche vor.",
                        showsProgress: true
                    ),
                    width: configuration.width,
                    dynamicTypeSize: configuration.dynamicTypeSize
                )
            )
            let previewImage = try #require(
                renderedImage(
                    GraphChatTabFreePreviewView(
                        draft: .constant("Welche Projekte sind offen?"),
                        presentation: GraphChatTabFreePreviewPresentation(
                            showsDraft: true,
                            suggestions: [suggestion],
                            errorMessage: nil
                        ),
                        onSelectSuggestion: { _ in },
                        onOpenPaywall: {}
                    ),
                    width: configuration.width,
                    dynamicTypeSize: configuration.dynamicTypeSize
                )
            )
            let lockedImage = try #require(
                renderedImage(
                    GraphChatTabLockedGraphView(onUnlock: {}),
                    width: configuration.width,
                    dynamicTypeSize: configuration.dynamicTypeSize
                )
            )

            #expect(statusImage.size.width > 0)
            #expect(statusImage.size.height > 0)
            #expect(previewImage.size.width > 0)
            #expect(previewImage.size.height > 0)
            #expect(lockedImage.size.width > 0)
            #expect(lockedImage.size.height > 0)
        }
    }

    private func renderedImage<Content: View>(
        _ content: Content,
        width: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> UIImage? {
        let renderedContent = content
            .frame(width: width, alignment: .topLeading)
            .environment(\.dynamicTypeSize, dynamicTypeSize)

        let renderer = ImageRenderer(content: renderedContent)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        return renderer.uiImage
    }
}
