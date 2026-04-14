import Foundation

struct BulkLinkDraft: Sendable, Equatable {
    let source: NodeRef
    let target: NodeRef
    let note: String?
    let graphID: UUID?
}

enum BulkLinkPlannedDirection: Sendable, Equatable {
    case forward
    case reverse
}

struct BulkLinkPlannedInsert: Sendable, Equatable {
    let direction: BulkLinkPlannedDirection
    let draft: BulkLinkDraft

    static func forward(_ draft: BulkLinkDraft) -> BulkLinkPlannedInsert {
        BulkLinkPlannedInsert(direction: .forward, draft: draft)
    }

    static func reverse(_ draft: BulkLinkDraft) -> BulkLinkPlannedInsert {
        BulkLinkPlannedInsert(direction: .reverse, draft: draft)
    }
}

struct BulkLinkMutationPlan: Sendable, Equatable {
    let inserts: [BulkLinkPlannedInsert]
    let createdForward: Int
    let createdReverse: Int
    let skippedDuplicates: Int
    let skippedSelf: Int
    let isBidirectional: Bool

    var completion: BulkLinkCompletion {
        BulkLinkCompletion(
            createdForward: createdForward,
            createdReverse: createdReverse,
            skippedDuplicates: skippedDuplicates,
            skippedSelf: skippedSelf,
            isBidirectional: isBidirectional
        )
    }
}

struct BulkLinkCompletion: Sendable, Equatable {
    let createdForward: Int
    let createdReverse: Int
    let skippedDuplicates: Int
    let skippedSelf: Int
    let isBidirectional: Bool

    var totalCreated: Int { createdForward + createdReverse }
}
