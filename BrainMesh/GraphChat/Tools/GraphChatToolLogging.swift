//
//  GraphChatToolLogging.swift
//  BrainMesh
//
//  Technical tool metrics without questions or graph content.
//

import Foundation
import os

nonisolated struct GraphChatToolExecutionMetric: Hashable, Sendable {
    let tool: GraphChatToolKind
    let durationMilliseconds: Double
    let resultCount: Int
    let wasCancelled: Bool
    let usedIndexFallback: Bool
}

nonisolated protocol GraphChatToolLogging: Sendable {
    func record(_ metric: GraphChatToolExecutionMetric)
}

nonisolated struct GraphChatTechnicalLogger: GraphChatToolLogging {
    func record(_ metric: GraphChatToolExecutionMetric) {
        BMLog.chat.info(
            "Tool completed type=\(metric.tool.rawValue, privacy: .public) results=\(metric.resultCount) cancelled=\(metric.wasCancelled) indexFallback=\(metric.usedIndexFallback) durationMS=\(metric.durationMilliseconds, format: .fixed(precision: 2))"
        )
    }
}

nonisolated struct GraphChatToolTimer: Sendable {
    private let startedAt: ContinuousClock.Instant

    init(clock: ContinuousClock = ContinuousClock()) {
        startedAt = clock.now
    }

    func metric(
        tool: GraphChatToolKind,
        resultCount: Int,
        wasCancelled: Bool,
        usedIndexFallback: Bool = false
    ) -> GraphChatToolExecutionMetric {
        let duration = startedAt.duration(to: ContinuousClock().now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return GraphChatToolExecutionMetric(
            tool: tool,
            durationMilliseconds: max(0, milliseconds),
            resultCount: resultCount,
            wasCancelled: wasCancelled,
            usedIndexFallback: usedIndexFallback
        )
    }
}

nonisolated struct NoOpGraphChatToolLogger: GraphChatToolLogging {
    func record(_ metric: GraphChatToolExecutionMetric) {}
}
