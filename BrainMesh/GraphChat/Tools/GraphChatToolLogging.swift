//
//  GraphChatToolLogging.swift
//  BrainMesh
//
//  Technical tool metrics without questions or graph content.
//

import Foundation
#if canImport(os)
import os
#endif

nonisolated struct GraphChatToolExecutionMetric: Hashable, Sendable {
    let tool: GraphChatToolKind
    let durationMilliseconds: Double
    let resultCount: Int
    let wasCancelled: Bool
}

nonisolated protocol GraphChatToolLogging: Sendable {
    func record(_ metric: GraphChatToolExecutionMetric)
}

nonisolated struct GraphChatTechnicalLogger: GraphChatToolLogging {
    func record(_ metric: GraphChatToolExecutionMetric) {
        #if canImport(os)
        let logger = Logger(subsystem: "BrainMesh", category: "GraphChatTools")
        logger.info(
            "Tool completed type=\(metric.tool.rawValue, privacy: .public) results=\(metric.resultCount) cancelled=\(metric.wasCancelled) durationMS=\(metric.durationMilliseconds, format: .fixed(precision: 2))"
        )
        #endif
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
        wasCancelled: Bool
    ) -> GraphChatToolExecutionMetric {
        let duration = startedAt.duration(to: ContinuousClock().now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return GraphChatToolExecutionMetric(
            tool: tool,
            durationMilliseconds: max(0, milliseconds),
            resultCount: resultCount,
            wasCancelled: wasCancelled
        )
    }
}

nonisolated struct NoOpGraphChatToolLogger: GraphChatToolLogging {
    func record(_ metric: GraphChatToolExecutionMetric) {}
}
