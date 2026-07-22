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
