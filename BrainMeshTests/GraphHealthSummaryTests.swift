import Foundation
import Testing
@testable import BrainMesh

struct GraphHealthSummaryTests {

    @Test
    func summaryComputesActionableEntitySetsAndCounts() throws {
        let entityWithAttribute = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let entityWithDetails = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let isolatedMediaEntity = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let attributeID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

        let summary = GraphHealthSummary.make(
            entities: [
                GraphHealthEntityInput(id: entityWithAttribute, hasHeaderImage: false),
                GraphHealthEntityInput(id: entityWithDetails, hasHeaderImage: false),
                GraphHealthEntityInput(id: isolatedMediaEntity, hasHeaderImage: true)
            ],
            attributes: [
                GraphHealthAttributeInput(id: attributeID, ownerEntityID: entityWithAttribute, hasHeaderImage: false)
            ],
            links: [
                GraphHealthLinkInput(
                    sourceKindRaw: NodeKind.entity.rawValue,
                    sourceID: entityWithAttribute,
                    targetKindRaw: NodeKind.attribute.rawValue,
                    targetID: attributeID
                )
            ],
            detailFields: [
                GraphHealthDetailFieldInput(entityID: entityWithDetails)
            ],
            attachments: [
                GraphHealthAttachmentInput(
                    ownerKindRaw: NodeKind.attribute.rawValue,
                    ownerID: attributeID,
                    byteCount: 512
                ),
                GraphHealthAttachmentInput(
                    ownerKindRaw: NodeKind.entity.rawValue,
                    ownerID: isolatedMediaEntity,
                    byteCount: 256
                )
            ]
        )

        #expect(summary.counts.entities == 3)
        #expect(summary.counts.attributes == 1)
        #expect(summary.counts.links == 1)
        #expect(summary.counts.attachments == 2)
        #expect(summary.counts.attachmentBytes == 768)

        #expect(Set(summary.isolatedEntityIDs) == [entityWithDetails, isolatedMediaEntity])
        #expect(Set(summary.entityIDsWithoutAttributes) == [entityWithDetails, isolatedMediaEntity])
        #expect(Set(summary.entityIDsWithoutDetails) == [entityWithAttribute, isolatedMediaEntity])
        #expect(Set(summary.mediaRichEntityIDs) == [entityWithAttribute, isolatedMediaEntity])
        #expect(summary.hasActionableHints)
    }

    @Test
    func quickFilterSnapshotsExposeExpectedEntityIDs() throws {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!

        let summary = GraphHealthSummary.make(
            entities: [
                GraphHealthEntityInput(id: first, hasHeaderImage: false),
                GraphHealthEntityInput(id: second, hasHeaderImage: true)
            ],
            attributes: [],
            links: [],
            detailFields: [],
            attachments: []
        )

        let snapshots = EntitiesHomeQuickFilterSnapshot.snapshots(from: summary)
        let byFilter = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.filter, $0) })

        #expect(byFilter[.all]?.matchingEntityIDs == [first, second])
        #expect(byFilter[.isolatedEntities]?.matchingEntityIDs == [first, second])
        #expect(byFilter[.entitiesWithoutAttributes]?.matchingEntityIDs == [first, second])
        #expect(byFilter[.entitiesWithoutDetails]?.matchingEntityIDs == [first, second])
        #expect(byFilter[.mediaRich]?.matchingEntityIDs == [second])
    }
}
