//
//  GraphChatBetaUIContractTests.swift
//  BrainMeshTests
//

import SwiftUI
import Testing
import UIKit

@testable import BrainMesh

@Suite("Graph Chat beta UI contracts")
@MainActor
struct GraphChatBetaUIContractTests {
    @Test
    func navigationNoticeAndSheetRenderAcrossPhonePadAndAccessibilityStyles() throws {
        let configurations: [Configuration] = [
            Configuration(
                width: 390,
                viewportHeight: 844,
                dynamicTypeSize: .accessibility3,
                colorScheme: .light,
                contrast: .standard
            ),
            Configuration(
                width: 390,
                viewportHeight: 844,
                dynamicTypeSize: .accessibility5,
                colorScheme: .dark,
                contrast: .increased
            ),
            Configuration(
                width: 1_024,
                viewportHeight: 1_366,
                dynamicTypeSize: .accessibility3,
                colorScheme: .light,
                contrast: .increased
            ),
        ]
        let copy = GraphChatBetaCopy(language: .german)
        let infoPresentation = GraphChatBetaInfoPresentation(
            copy: copy,
            suggestions: [verifiedSuggestion()]
        )

        for configuration in configurations {
            let title = try #require(
                renderedImage(
                    GraphChatBetaNavigationTitle(copy: copy),
                    configuration: configuration
                )
            )
            let notice = try #require(
                renderedImage(
                    GraphChatBetaCompactNoticeCard(
                        copy: copy,
                        surface: .emptyChat,
                        onOpenInfo: {}
                    ),
                    configuration: configuration
                )
            )
            let previewNotice = try #require(
                renderedImage(
                    GraphChatBetaCompactNoticeCard(
                        copy: copy,
                        surface: .freePreview,
                        onOpenInfo: {}
                    ),
                    configuration: configuration
                )
            )
            let sheet = try #require(
                renderedImage(
                    GraphChatBetaInfoSheet(
                        presentation: infoPresentation,
                        onSelectQuestion: { _ in }
                    ),
                    configuration: configuration,
                    viewportHeight: configuration.viewportHeight
                )
            )

            #expect(title.size.width > 0)
            #expect(title.size.height > 0)
            #expect(notice.size.width > 0)
            #expect(notice.size.height > 0)
            #expect(previewNotice.size.width > 0)
            #expect(previewNotice.size.height > 0)
            #expect(sheet.size.width > 0)
            #expect(sheet.size.height > 0)
        }
    }

    @Test
    func sheetFallbackRendersWithoutPretendingAQuestionIsTappable() throws {
        let copy = GraphChatBetaCopy(language: .english)
        let presentation = GraphChatBetaInfoPresentation(
            copy: copy,
            suggestions: []
        )
        let configuration = Configuration(
            width: 390,
            viewportHeight: 844,
            dynamicTypeSize: .accessibility4,
            colorScheme: .dark,
            contrast: .standard
        )
        let image = try #require(
            renderedImage(
                GraphChatBetaInfoSheet(
                    presentation: presentation,
                    onSelectQuestion: { _ in }
                ),
                configuration: configuration,
                viewportHeight: configuration.viewportHeight
            )
        )

        #expect(presentation.tappableQuestions.isEmpty)
        #expect(presentation.fallbackExamples.isEmpty == false)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    private struct Configuration {
        let width: CGFloat
        let viewportHeight: CGFloat
        let dynamicTypeSize: DynamicTypeSize
        let colorScheme: ColorScheme
        let contrast: ColorSchemeContrast
    }

    private func renderedImage<Content: View>(
        _ content: Content,
        configuration: Configuration,
        viewportHeight: CGFloat? = nil
    ) -> UIImage? {
        let traits = UITraitCollection(
            traitsFrom: [
                UITraitCollection(
                    userInterfaceStyle: configuration.colorScheme == .dark
                        ? .dark
                        : .light
                ),
                UITraitCollection(
                    accessibilityContrast: configuration.contrast == .increased
                        ? .high
                        : .normal
                ),
            ]
        )
        var image: UIImage?

        traits.performAsCurrent {
            let renderedContent = content
                .frame(
                    width: configuration.width,
                    height: viewportHeight,
                    alignment: .topLeading
                )
                .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
                .environment(\.colorScheme, configuration.colorScheme)

            let renderer = ImageRenderer(content: renderedContent)
            renderer.proposedSize = ProposedViewSize(
                width: configuration.width,
                height: viewportHeight
            )
            renderer.scale = 1
            image = renderer.uiImage
        }

        return image
    }

    private func verifiedSuggestion() -> GraphChatEmptyStateSuggestion {
        GraphChatEmptyStateSuggestion(
            id: "verified-beta-question",
            capabilityID: .entityEntries,
            title: "Einträge auflisten",
            prompt: "Zeige mir alle „Einträge“.",
            kind: .list,
            validation: GraphChatCapabilityQuestionValidation(
                capabilityID: .entityEntries,
                compilerFamily: .foundationalEntityCollection,
                typedIntentKind: .entityCollection,
                readPlanFamily: .entityCollection,
                readPlanVersion: .current,
                queryPlanVersion: GraphQueryPlan.currentVersion
            )
        )
    }
}
