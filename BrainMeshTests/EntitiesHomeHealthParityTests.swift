import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeHealthParityTests {

    @Test
    func statsAndEntitiesHomeUseTheSameEntityCategoryDefinitions() throws {
        let linked = UUID()
        let withoutAttributes = UUID()
        let mediaOwner = UUID()
        let attributeID = UUID()

        let homeSummary = GraphHealthSummary.make(
            entities: [
                GraphHealthEntityInput(
                    id: linked,
                    hasHeaderImage: false
                ),
                GraphHealthEntityInput(
                    id: withoutAttributes,
                    hasHeaderImage: false
                ),
                GraphHealthEntityInput(
                    id: mediaOwner,
                    hasHeaderImage: false
                )
            ],
            attributes: [
                GraphHealthAttributeInput(
                    id: attributeID,
                    ownerEntityID: mediaOwner,
                    hasHeaderImage: true
                )
            ],
            links: [
                GraphHealthLinkInput(
                    sourceKindRaw: NodeKind.entity.rawValue,
                    sourceID: linked,
                    targetKindRaw: NodeKind.attribute.rawValue,
                    targetID: attributeID
                )
            ],
            detailFields: [
                GraphHealthDetailFieldInput(entityID: linked)
            ],
            attachments: [
                GraphHealthAttachmentInput(
                    ownerKindRaw: NodeKind.attribute.rawValue,
                    ownerID: attributeID,
                    byteCount: 100
                )
            ]
        )

        let statsCategories = GraphHealthIssueEngine.entityCategories(
            entities: [
                GraphHealthEntityNodeInput(
                    id: linked,
                    label: "Linked",
                    hasHeaderImage: false
                ),
                GraphHealthEntityNodeInput(
                    id: withoutAttributes,
                    label: "Without Attributes",
                    hasHeaderImage: false
                ),
                GraphHealthEntityNodeInput(
                    id: mediaOwner,
                    label: "Media",
                    hasHeaderImage: false
                )
            ],
            attributes: [
                GraphHealthAttributeNodeInput(
                    id: attributeID,
                    label: "Media · Photo",
                    ownerEntityID: mediaOwner,
                    hasHeaderImage: true
                )
            ],
            links: [
                GraphHealthLinkEndpointInput(
                    sourceKindRaw: NodeKind.entity.rawValue,
                    sourceID: linked,
                    targetKindRaw: NodeKind.attribute.rawValue,
                    targetID: attributeID
                )
            ],
            detailSchemas: [
                GraphHealthDetailSchemaInput(entityID: linked)
            ],
            attachments: [
                GraphHealthAttachmentMetadataInput(
                    id: UUID(),
                    title: "Photo",
                    originalFilename: "photo.jpg",
                    ownerKindRaw: NodeKind.attribute.rawValue,
                    ownerID: attributeID,
                    ownerLabel: "Media · Photo",
                    byteCount: 100
                )
            ]
        )

        #expect(statsCategories.allEntityIDs == homeSummary.allEntityIDs)
        #expect(
            statsCategories.isolatedEntityIDs
                == homeSummary.isolatedEntityIDs
        )
        #expect(
            statsCategories.entityIDsWithoutAttributes
                == homeSummary.entityIDsWithoutAttributes
        )
        #expect(
            statsCategories.entityIDsWithoutDetails
                == homeSummary.entityIDsWithoutDetails
        )
        #expect(
            statsCategories.entityIDsWithMedia
                == homeSummary.mediaRichEntityIDs
        )
    }

    @Test
    func statsIssueCountsRemainCompleteWhileVisibleItemsStayLimited() {
        let entities = (0..<12).map { index in
            GraphHealthEntityNodeInput(
                id: UUID(),
                label: "Entity \(index)",
                hasHeaderImage: false
            )
        }
        let issues = GraphHealthIssueEngine.makeIssues(
            graphID: UUID(),
            entities: entities,
            attributes: [],
            links: [],
            detailSchemas: [],
            attachments: [],
            structure: GraphStructureSnapshot(
                nodeCount: entities.count,
                linkCount: 0,
                isolatedNodeCount: entities.count,
                topHubs: []
            ),
            media: GraphMediaSnapshot(
                headerImages: 0,
                attachmentsTotal: 0,
                attachmentsFile: 0,
                attachmentsVideo: 0,
                attachmentsGalleryImages: 0,
                topFileExtensions: [],
                largestAttachments: [],
                topMediaNodes: []
            )
        )
        let isolated = issues.first {
            $0.kind == .isolatedEntities
        }

        #expect(isolated?.count == 12)
        #expect(isolated?.affectedItems.count == 8)
    }

    @Test
    func separatedResultsReconstructThePreviousCockpitSnapshot() {
        let graphID = UUID()
        let entityID = UUID()
        let summary = GraphHealthSummary.make(
            entities: [
                GraphHealthEntityInput(
                    id: entityID,
                    hasHeaderImage: false
                )
            ],
            attributes: [],
            links: [],
            detailFields: [],
            attachments: []
        )
        let recent = EntitiesHomeCockpitRecentNode(
            graphID: graphID,
            nodeKindRaw: NodeKind.entity.rawValue,
            nodeID: entityID,
            label: "Entity",
            subtitle: "Entität",
            iconSymbolName: "circle",
            openedAt: Date(timeIntervalSince1970: 100),
            ownerEntityID: entityID
        )
        let revision = parityRevision(entityCount: 1)

        let withRecent = EntitiesHomeCockpitSnapshot
            .empty(graphID: graphID)
            .replacingRecentNodes([recent], for: graphID)
        let reconstructed = withRecent?.replacingHealth(
            EntitiesHomeHealthSummarySnapshot(
                graphID: graphID,
                revision: revision,
                summary: summary
            )
        )

        #expect(reconstructed?.recentNodes == [recent])
        #expect(reconstructed?.healthSummary == summary)
        #expect(
            reconstructed?.quickFilterSnapshot(
                for: .isolatedEntities
            )?.matchingEntityIDs == [entityID]
        )
    }

    @Test
    func graphSwitchRejectsStaleRecentAndHealthResults() {
        let oldGraphID = UUID()
        let currentGraphID = UUID()
        let current = EntitiesHomeCockpitSnapshot.empty(
            graphID: currentGraphID
        )
        let staleRecent = EntitiesHomeCockpitRecentNode(
            graphID: oldGraphID,
            nodeKindRaw: NodeKind.entity.rawValue,
            nodeID: UUID(),
            label: "Old",
            subtitle: "Entität",
            iconSymbolName: "circle",
            openedAt: Date(),
            ownerEntityID: nil
        )
        let staleHealth = EntitiesHomeHealthSummarySnapshot(
            graphID: oldGraphID,
            revision: parityRevision(entityCount: 0),
            summary: .empty
        )

        #expect(
            current.replacingRecentNodes(
                [staleRecent],
                for: oldGraphID
            ) == nil
        )
        #expect(current.replacingHealth(staleHealth) == nil)
    }
}

private func parityRevision(
    entityCount: Int
) -> GraphStatsScopeRevision {
    GraphStatsScopeRevision(
        counts: GraphCounts(
            entities: entityCount,
            attributes: 0,
            links: 0,
            notes: 0,
            images: 0,
            attachments: 0,
            attachmentBytes: 0
        ),
        detailFieldCount: 0,
        newestEntityCreatedAt: nil,
        newestLinkCreatedAt: nil,
        newestAttachmentCreatedAt: nil
    )
}
