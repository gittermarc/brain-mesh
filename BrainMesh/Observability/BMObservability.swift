//
//  BMObservability.swift
//  BrainMesh
//
//  Lightweight micro-logging + timing helpers (P0.2)
//

import Foundation
import Dispatch
import os

nonisolated enum BMLog {
    private static let subsystem: String = {
        if let id = Bundle.main.bundleIdentifier, !id.isEmpty { return id }
        return "BrainMesh"
    }()

    static let load = Logger(subsystem: subsystem, category: "load")
    static let expand = Logger(subsystem: subsystem, category: "expand")
    static let physics = Logger(subsystem: subsystem, category: "physics")
    static let canvasDerivedState = Logger(
        subsystem: subsystem,
        category: "canvas-derived-state"
    )
    static let canvasStaticRender = Logger(
        subsystem: subsystem,
        category: "canvas-static-render"
    )
    static let search = Logger(subsystem: subsystem, category: "search")
    static let searchReadiness = Logger(
        subsystem: subsystem,
        category: "search-readiness"
    )
    static let searchReconciliation = Logger(
        subsystem: subsystem,
        category: "search-reconciliation"
    )
    static let searchRebuild = Logger(
        subsystem: subsystem,
        category: "search-rebuild"
    )
    static let searchCutover = Logger(
        subsystem: subsystem,
        category: "search-cutover"
    )
    static let searchCancellation = Logger(
        subsystem: subsystem,
        category: "search-cancellation"
    )
    static let mutationEvents = Logger(
        subsystem: subsystem,
        category: "mutation-events"
    )
    static let detailIntegrity = Logger(
        subsystem: subsystem,
        category: "detail-integrity"
    )
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let chat = Logger(subsystem: subsystem, category: "chat")
}

/// Tiny timer helper (DispatchTime based) for cheap duration measurement.
nonisolated struct BMDuration {
    private let startUptimeNanos: UInt64

    init() {
        startUptimeNanos = DispatchTime.now().uptimeNanoseconds
    }

    var nanosecondsElapsed: UInt64 {
        DispatchTime.now().uptimeNanoseconds &- startUptimeNanos
    }

    var millisecondsElapsed: Double {
        Double(nanosecondsElapsed) / 1_000_000.0
    }
}

/// Content-free signposts for Instruments validation of the canvas runtime.
/// No graph, node, edge, label, note, draft, or identifier is recorded.
nonisolated enum BMGraphPhysicsInstrumentation {
    private static let signposter = OSSignposter(
        logger: BMLog.physics
    )

    @inline(__always)
    static func measureStep<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let state = signposter.beginInterval("PhysicsStep")
        defer {
            signposter.endInterval("PhysicsStep", state)
        }
        return try operation()
    }

    static func snapshotPublished() {
        signposter.emitEvent("SnapshotPublish")
    }

    static func coalescedFrame() {
        signposter.emitEvent("CoalescedFrame")
    }

    static func droppedFrame() {
        signposter.emitEvent("DroppedFrame")
    }

    static func pause() {
        signposter.emitEvent("Pause")
    }

    static func resume() {
        signposter.emitEvent("Resume")
    }

    static func graphChanged() {
        signposter.emitEvent("GraphChange")
    }

    static func memoryPressure() {
        signposter.emitEvent("MemoryPressure")
    }
}

nonisolated enum BMNodeConnectionsPreviewLoadStatus:
    String,
    Equatable,
    Sendable
{
    case success
    case cancelled
    case error
}

/// Technical-only metric payload for detail connection previews.
///
/// It deliberately has no node IDs, graph IDs, names, notes, labels, or link content.
nonisolated struct BMNodeConnectionsPreviewLoadMetric:
    Equatable,
    Sendable
{
    let ownerKindRaw: Int
    let status: BMNodeConnectionsPreviewLoadStatus
    let outgoingCount: Int?
    let incomingCount: Int?
    let durationMilliseconds: Double
}

/// Debug-only signpost wrapper for Entity and Attribute detail connection previews.
///
/// Release builds execute the async operation directly, without timing, signposts,
/// result-count extraction, or metric construction.
@MainActor
enum BMNodeConnectionsPreviewLoadInstrumentation {
    #if DEBUG
    private static let signposter = OSSignposter(logger: BMLog.load)
    #endif

    @inline(__always)
    static func measure<Result>(
        ownerKind: NodeKind,
        counts: (Result) -> (outgoing: Int, incoming: Int),
        operation: () async throws -> Result
    ) async rethrows -> Result {
        #if DEBUG
        let duration = BMDuration()
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval(
            "NodeConnectionsPreviewLoad",
            id: signpostID
        )
        let ownerKindRaw = ownerKind.rawValue

        BMLog.load.debug(
            "node_connections_preview_load status=start owner_kind=\(ownerKindRaw, privacy: .public)"
        )

        do {
            let result = try await operation()
            let hitCounts = counts(result)
            let metric = makeMetric(
                ownerKind: ownerKind,
                status: .success,
                outgoingCount: hitCounts.outgoing,
                incomingCount: hitCounts.incoming,
                durationMilliseconds: duration.millisecondsElapsed
            )

            signposter.endInterval(
                "NodeConnectionsPreviewLoad",
                intervalState,
                "status=success owner_kind=\(metric.ownerKindRaw, privacy: .public) outgoing=\(hitCounts.outgoing, privacy: .public) incoming=\(hitCounts.incoming, privacy: .public) duration_ms=\(metric.durationMilliseconds, privacy: .public)"
            )
            BMLog.load.debug(
                "node_connections_preview_load status=success owner_kind=\(metric.ownerKindRaw, privacy: .public) outgoing=\(hitCounts.outgoing, privacy: .public) incoming=\(hitCounts.incoming, privacy: .public) duration_ms=\(metric.durationMilliseconds, privacy: .public)"
            )
            return result
        } catch {
            let status: BMNodeConnectionsPreviewLoadStatus =
                error is CancellationError ? .cancelled : .error
            let metric = makeMetric(
                ownerKind: ownerKind,
                status: status,
                outgoingCount: nil,
                incomingCount: nil,
                durationMilliseconds: duration.millisecondsElapsed
            )

            signposter.endInterval(
                "NodeConnectionsPreviewLoad",
                intervalState,
                "status=\(metric.status.rawValue, privacy: .public) owner_kind=\(metric.ownerKindRaw, privacy: .public) outgoing=unavailable incoming=unavailable duration_ms=\(metric.durationMilliseconds, privacy: .public)"
            )
            if status == .cancelled {
                BMLog.load.debug(
                    "node_connections_preview_load status=cancelled owner_kind=\(metric.ownerKindRaw, privacy: .public) outgoing=unavailable incoming=unavailable duration_ms=\(metric.durationMilliseconds, privacy: .public)"
                )
            } else {
                BMLog.load.error(
                    "node_connections_preview_load status=error owner_kind=\(metric.ownerKindRaw, privacy: .public) outgoing=unavailable incoming=unavailable duration_ms=\(metric.durationMilliseconds, privacy: .public)"
                )
            }
            throw error
        }
        #else
        return try await operation()
        #endif
    }

    static func makeMetric(
        ownerKind: NodeKind,
        status: BMNodeConnectionsPreviewLoadStatus,
        outgoingCount: Int?,
        incomingCount: Int?,
        durationMilliseconds: Double
    ) -> BMNodeConnectionsPreviewLoadMetric {
        BMNodeConnectionsPreviewLoadMetric(
            ownerKindRaw: ownerKind.rawValue,
            status: status,
            outgoingCount: outgoingCount,
            incomingCount: incomingCount,
            durationMilliseconds: durationMilliseconds
        )
    }
}
