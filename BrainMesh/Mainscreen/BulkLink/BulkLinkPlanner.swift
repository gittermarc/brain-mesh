import Foundation

enum BulkLinkPlannerError: Error, Equatable {
    case duplicatesFound(count: Int)

    var message: String {
        switch self {
        case .duplicatesFound(let count):
            return "Es existieren bereits \(count) Verbindungen für deine Auswahl. Entferne diese Ziele oder aktiviere \"Doppelte ignorieren\"."
        }
    }
}

struct BulkLinkPlanner {

    static func makePlan(
        source: NodeRef,
        selectedTargets: Set<NodeRef>,
        note: String,
        createBidirectional: Bool,
        ignoreDuplicates: Bool,
        existingOutgoingTargets: Set<NodeRefKey>,
        existingIncomingSources: Set<NodeRefKey>,
        graphID: UUID?
    ) throws -> BulkLinkMutationPlan {
        try Task.checkCancellation()
        let finalNote = normalizedNote(note)

        if ignoreDuplicates == false {
            let duplicateCount = countDuplicateConflicts(
                source: source,
                selectedTargets: selectedTargets,
                createBidirectional: createBidirectional,
                existingOutgoingTargets: existingOutgoingTargets,
                existingIncomingSources: existingIncomingSources
            )
            if duplicateCount > 0 {
                throw BulkLinkPlannerError.duplicatesFound(count: duplicateCount)
            }
        }

        var inserts: [BulkLinkPlannedInsert] = []
        var createdForward = 0
        var createdReverse = 0
        var skippedDuplicates = 0
        var skippedSelf = 0

        let orderedTargets = selectedTargets.sorted(by: stableTargetOrder)

        for target in orderedTargets {
            try Task.checkCancellation()
            if isSelfLink(source: source, target: target) {
                skippedSelf += 1
                continue
            }

            let targetKey = NodeRefKey(nodeRef: target)
            if existingOutgoingTargets.contains(targetKey) {
                skippedDuplicates += 1
                continue
            }

            let forwardDraft = BulkLinkDraft(
                source: source,
                target: target,
                note: finalNote,
                graphID: graphID
            )
            inserts.append(.forward(forwardDraft))
            createdForward += 1

            if createBidirectional {
                if existingIncomingSources.contains(targetKey) {
                    skippedDuplicates += 1
                } else {
                    let reverseDraft = BulkLinkDraft(
                        source: target,
                        target: source,
                        note: finalNote,
                        graphID: graphID
                    )
                    inserts.append(.reverse(reverseDraft))
                    createdReverse += 1
                }
            }
        }

        return BulkLinkMutationPlan(
            inserts: inserts,
            createdForward: createdForward,
            createdReverse: createdReverse,
            skippedDuplicates: skippedDuplicates,
            skippedSelf: skippedSelf,
            isBidirectional: createBidirectional
        )
    }

    private static func normalizedNote(_ note: String) -> String? {
        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func countDuplicateConflicts(
        source: NodeRef,
        selectedTargets: Set<NodeRef>,
        createBidirectional: Bool,
        existingOutgoingTargets: Set<NodeRefKey>,
        existingIncomingSources: Set<NodeRefKey>
    ) -> Int {
        var duplicates = 0

        for target in selectedTargets {
            if isSelfLink(source: source, target: target) {
                continue
            }

            let targetKey = NodeRefKey(nodeRef: target)
            if existingOutgoingTargets.contains(targetKey) {
                duplicates += 1
            }
            if createBidirectional && existingIncomingSources.contains(targetKey) {
                duplicates += 1
            }
        }

        return duplicates
    }


    private static func stableTargetOrder(_ lhs: NodeRef, _ rhs: NodeRef) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isSelfLink(source: NodeRef, target: NodeRef) -> Bool {
        source.kind == target.kind && source.id == target.id
    }
}
