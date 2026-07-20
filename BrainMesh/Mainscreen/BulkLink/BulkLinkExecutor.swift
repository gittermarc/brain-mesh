import Foundation
import SwiftData

@MainActor
enum BulkLinkExecutor {
    nonisolated enum ExecutionError: LocalizedError, Equatable, Sendable {
        case missingGraphScope
        case mixedGraphScopes

        var errorDescription: String? {
            switch self {
            case .missingGraphScope:
                return "Die Links konnten keinem Graphen eindeutig zugeordnet werden."
            case .mixedGraphScopes:
                return "Eine Bulk-Aktion darf nur Links desselben Graphen enthalten."
            }
        }
    }

    /// Inserts the final mutation plan in its existing order, saves once, and publishes one batch.
    /// A plan without inserts is a true no-op and never reaches the persistence boundary.
    static func execute(
        plan: BulkLinkMutationPlan,
        in modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> BulkLinkCompletion {
        guard plan.inserts.isEmpty == false else {
            return plan.completion
        }

        try Task.checkCancellation()
        let graphID = try commonGraphID(for: plan)
        try Task.checkCancellation()

        var references: [GraphMutationLinkReference] = []
        references.reserveCapacity(plan.inserts.count)

        do {
            for plannedInsert in plan.inserts {
                try Task.checkCancellation()

                let draft = plannedInsert.draft
                let link = MetaLink(
                    sourceKind: draft.source.kind,
                    sourceID: draft.source.id,
                    sourceLabel: draft.source.label,
                    targetKind: draft.target.kind,
                    targetID: draft.target.id,
                    targetLabel: draft.target.label,
                    note: draft.note,
                    graphID: graphID
                )
                modelContext.insert(link)
                references.append(
                    GraphMutationLinkReference(
                        id: link.id,
                        source: NodeRefKey(nodeRef: draft.source),
                        target: NodeRefKey(nodeRef: draft.target)
                    )
                )
            }

            let batch = try GraphMutationBatchFactory.linksCreated(
                graphID: graphID,
                links: references
            )
            try await committer.commit(batch, in: modelContext)
            return plan.completion
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func commonGraphID(
        for plan: BulkLinkMutationPlan
    ) throws -> UUID {
        let graphIDs = plan.inserts.map(\.draft.graphID)
        guard graphIDs.allSatisfy({ $0 != nil }) else {
            throw ExecutionError.missingGraphScope
        }

        let concreteGraphIDs = graphIDs.compactMap { $0 }
        guard let graphID = concreteGraphIDs.first else {
            throw ExecutionError.missingGraphScope
        }
        guard concreteGraphIDs.allSatisfy({ $0 == graphID }) else {
            throw ExecutionError.mixedGraphScopes
        }
        return graphID
    }
}
