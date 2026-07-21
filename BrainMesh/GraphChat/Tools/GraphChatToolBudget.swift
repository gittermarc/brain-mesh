//
//  GraphChatToolBudget.swift
//  BrainMesh
//
//  Central call, result, and evidence budgets for one user request.
//

import Foundation

nonisolated struct GraphChatToolBudgetPolicy: Hashable, Sendable {
    let maximumCalls: Int
    let maximumResultCountPerTool: Int
    let maximumEvidenceCount: Int

    static let `default` = GraphChatToolBudgetPolicy(
        maximumCalls: 8,
        maximumResultCountPerTool: 50,
        maximumEvidenceCount: 200
    )

    init(
        maximumCalls: Int,
        maximumResultCountPerTool: Int,
        maximumEvidenceCount: Int
    ) {
        precondition(maximumCalls > 0)
        precondition(maximumResultCountPerTool > 0)
        precondition(maximumEvidenceCount > 0)
        self.maximumCalls = maximumCalls
        self.maximumResultCountPerTool = maximumResultCountPerTool
        self.maximumEvidenceCount = maximumEvidenceCount
    }
}

actor GraphChatToolBudget {
    private let policy: GraphChatToolBudgetPolicy
    private var usedCalls = 0
    private var usedEvidence = 0

    init(policy: GraphChatToolBudgetPolicy = .default) {
        self.policy = policy
    }

    func beginCall(
        tool: GraphChatToolKind,
        requestedResultCount: Int,
        toolMaximumResultCount: Int
    ) throws -> Int {
        try Task.checkCancellation()
        guard usedCalls < policy.maximumCalls else {
            throw GraphChatToolError(
                code: .budgetExceeded,
                message: "Das maximale Tool-Budget von \(policy.maximumCalls) Aufrufen wurde erreicht."
            )
        }
        let maximum = min(policy.maximumResultCountPerTool, toolMaximumResultCount)
        guard requestedResultCount > 0, requestedResultCount <= maximum else {
            throw GraphChatToolError(
                code: .budgetExceeded,
                message: "\(tool.rawValue) erlaubt höchstens \(maximum) Ergebnisse pro Aufruf."
            )
        }
        usedCalls += 1
        return requestedResultCount
    }

    func consumeEvidence(_ count: Int) throws {
        try Task.checkCancellation()
        guard count >= 0, usedEvidence + count <= policy.maximumEvidenceCount else {
            throw GraphChatToolError(
                code: .budgetExceeded,
                message: "Das maximale Evidence-Budget von \(policy.maximumEvidenceCount) Einträgen wurde erreicht."
            )
        }
        usedEvidence += count
    }

    func snapshotForTesting() -> (calls: Int, evidence: Int) {
        (usedCalls, usedEvidence)
    }
}
