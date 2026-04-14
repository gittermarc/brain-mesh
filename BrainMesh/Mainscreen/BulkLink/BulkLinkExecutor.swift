import Foundation

struct BulkLinkExecutor {

    static func execute<Inserted>(
        plan: BulkLinkMutationPlan,
        insert: (BulkLinkDraft) -> Inserted,
        save: () throws -> Void,
        rollback: ([Inserted]) -> Void
    ) throws -> BulkLinkCompletion {
        var inserted: [Inserted] = []

        do {
            for plannedInsert in plan.inserts {
                inserted.append(insert(plannedInsert.draft))
            }
            try save()
            return plan.completion
        } catch {
            rollback(inserted)
            throw error
        }
    }
}
