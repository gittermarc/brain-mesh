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
    static let search = Logger(subsystem: subsystem, category: "search")
    static let mutationEvents = Logger(
        subsystem: subsystem,
        category: "mutation-events"
    )
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

/// Debug-only signpost wrapper for Attribute Detail link-preview loads.
///
/// The operation always runs synchronously on the caller's actor. Release builds
/// execute the operation directly, without timing, signpost, or result-count work.
@MainActor
enum BMAttributeLinkPreviewLoadInstrumentation {
    #if DEBUG
    private static let signposter = OSSignposter(logger: BMLog.load)
    #endif

    @inline(__always)
    static func measure<Result>(
        counts: (Result) -> (outgoing: Int, incoming: Int),
        operation: () throws -> Result
    ) rethrows -> Result {
        #if DEBUG
        let duration = BMDuration()
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval(
            "AttributeLinkPreviewLoad",
            id: signpostID
        )

        BMLog.load.debug("attribute_link_preview_load status=start")

        do {
            let result = try operation()
            let hitCounts = counts(result)
            let elapsedMilliseconds = duration.millisecondsElapsed

            signposter.endInterval(
                "AttributeLinkPreviewLoad",
                intervalState,
                "status=success outgoing=\(hitCounts.outgoing, privacy: .public) incoming=\(hitCounts.incoming, privacy: .public) duration_ms=\(elapsedMilliseconds, privacy: .public)"
            )
            BMLog.load.debug(
                "attribute_link_preview_load status=success outgoing=\(hitCounts.outgoing, privacy: .public) incoming=\(hitCounts.incoming, privacy: .public) duration_ms=\(elapsedMilliseconds, privacy: .public)"
            )
            return result
        } catch {
            let elapsedMilliseconds = duration.millisecondsElapsed

            signposter.endInterval(
                "AttributeLinkPreviewLoad",
                intervalState,
                "status=error outgoing=unavailable incoming=unavailable duration_ms=\(elapsedMilliseconds, privacy: .public)"
            )
            BMLog.load.error(
                "attribute_link_preview_load status=error outgoing=unavailable incoming=unavailable duration_ms=\(elapsedMilliseconds, privacy: .public)"
            )
            throw error
        }
        #else
        return try operation()
        #endif
    }
}
