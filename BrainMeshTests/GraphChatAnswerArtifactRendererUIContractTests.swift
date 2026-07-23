//
//  GraphChatAnswerArtifactRendererUIContractTests.swift
//  BrainMeshTests
//

import SwiftUI
import Testing
import UIKit
@testable import BrainMesh

@Suite("Graph-native answer artifact UI contracts")
@MainActor
struct GraphChatAnswerArtifactRendererUIContractTests {
    @Test
    func everyArtifactRendersOnPhoneAndPadWithLargeDynamicType() throws {
        let fixture = AnswerArtifactPresentationFixture()
        let artifacts = [
            fixture.artifact(payload: .metric(fixture.metricPayload), index: 1),
            fixture.artifact(payload: .resultList(fixture.listPayload), index: 2),
            fixture.artifact(payload: .table(fixture.tablePayload), index: 3, querySummary: fixture.querySummary),
            fixture.artifact(payload: .ranking(fixture.rankingPayload), index: 4),
            fixture.artifact(payload: .grouping(fixture.groupingPayload), index: 5),
            fixture.artifact(payload: .comparison(fixture.comparisonPayload), index: 6),
            fixture.artifact(payload: .healthFinding(fixture.healthPayload), index: 7),
            fixture.artifact(payload: .timeline(fixture.timelinePayload), index: 8)
        ]
        let configurations: [RenderConfiguration] = [
            RenderConfiguration(
                width: 390,
                dynamicTypeSize: .accessibility2,
                horizontalSizeClass: .compact,
                reduceMotion: true
            ),
            RenderConfiguration(
                width: 1_024,
                dynamicTypeSize: .xxLarge,
                horizontalSizeClass: .regular,
                reduceMotion: false
            )
        ]

        for artifact in artifacts {
            for configuration in configurations {
                let image = try #require(
                    render(
                        artifact: artifact,
                        fixture: fixture,
                        configuration: configuration
                    )
                )
                #expect(image.size.width > 0)
                #expect(image.size.height > 0)
            }
        }
    }

    @Test
    func fallbackAndEmptyArtifactRenderWithoutCrashing() throws {
        let fixture = AnswerArtifactPresentationFixture()
        let emptyArtifact = fixture.artifact(
            payload: .resultList(
                GraphChatAnswerArtifactResultListPayload(
                    title: "Empty",
                    rows: [],
                    resultMetadata: fixture.metadata(
                        returnedCount: 0,
                        totalCount: 0,
                        truncated: false
                    ),
                    evidence: fixture.binding
                )
            ),
            index: 20
        )

        let fallbackImage = ImageRenderer(
            content: GraphChatAnswerArtifactFallbackView(language: .english)
                .padding()
                .frame(width: 390, alignment: .leading)
        ).uiImage
        let emptyImage = try #require(
            render(
                artifact: emptyArtifact,
                fixture: fixture,
                configuration: RenderConfiguration(
                    width: 390,
                    dynamicTypeSize: .accessibility3,
                    horizontalSizeClass: .compact,
                    reduceMotion: true
                )
            )
        )

        #expect(fallbackImage?.size.width ?? 0 > 0)
        #expect(emptyImage.size.height > 0)
    }

    @Test
    func evidenceDrawerRendersLongGermanAndEnglishTechnicalDetails() throws {
        let fixture = AnswerArtifactPresentationFixture()
        let artifact = fixture.artifact(
            payload: .table(fixture.tablePayload),
            index: 30,
            querySummary: fixture.querySummary
        )
        let resolved = GraphChatResolvedAnswerArtifact(
            artifact: artifact,
            revalidatedAt: fixture.revalidatedAt
        )

        for language in GraphChatResponseLanguage.allCases {
            let presentation = GraphChatEvidenceDrawerPresentation(
                resolved: resolved,
                availableEvidence: fixture.allEvidence,
                language: language
            )
            let content = GraphChatEvidenceDrawerView(
                presentation: presentation,
                onOpenEvidence: { _ in },
                onShowEvidenceInGraph: { _ in }
            )
            .frame(width: 390, height: 760)
            .environment(\.dynamicTypeSize, .accessibility2)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: 390, height: 760)
            renderer.scale = 1
            let image = try #require(renderer.uiImage)

            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    private func render(
        artifact: GraphChatAnswerArtifact,
        fixture: AnswerArtifactPresentationFixture,
        configuration: RenderConfiguration
    ) -> UIImage? {
        let resolved = GraphChatResolvedAnswerArtifact(
            artifact: artifact,
            revalidatedAt: fixture.revalidatedAt
        )
        let evidence = Dictionary(
            uniqueKeysWithValues: fixture.allEvidence.map { ($0.id, $0) }
        )
        let disablesAnimations = configuration.reduceMotion
        let content = GraphChatAnswerArtifactRenderer(
            resolved: resolved,
            availableEvidence: evidence,
            language: artifact.querySummary?.language ?? .english,
            allowsEvidenceActions: true,
            canOpenTarget: { target in
                GraphChatAnswerArtifactNavigationPolicy.route(
                    for: target,
                    activeGraphScope: fixture.graphScope
                ) != nil
            },
            onOpenTarget: { _ in },
            onOpenEvidence: { _ in },
            onShowEvidenceInGraph: { _ in },
            onShowEvidenceDrawer: { _ in }
        )
        .padding()
        .frame(width: configuration.width, alignment: .leading)
        .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
        .environment(\.horizontalSizeClass, configuration.horizontalSizeClass)
        .transaction { transaction in
            transaction.disablesAnimations = disablesAnimations
        }

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(
            width: configuration.width,
            height: nil
        )
        renderer.scale = 1
        return renderer.uiImage
    }
}

private struct RenderConfiguration {
    let width: CGFloat
    let dynamicTypeSize: DynamicTypeSize
    let horizontalSizeClass: UserInterfaceSizeClass
    let reduceMotion: Bool
}
