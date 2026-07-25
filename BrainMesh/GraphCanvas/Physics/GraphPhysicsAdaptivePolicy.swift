//
//  GraphPhysicsAdaptivePolicy.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

nonisolated enum GraphPhysicsCadencePhase:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case active
    case settling
    case quiet

    var framesPerSecond: Double {
        switch self {
        case .active:
            return 30
        case .settling:
            return 20
        case .quiet:
            return 12
        }
    }

    var interval: TimeInterval {
        1.0 / framesPerSecond
    }
}

/// Named adaptive-runtime values derived from the former `0.03` idle speed.
///
/// Quiet uses the original idle boundary. Settling entry is four times that
/// value. The higher exit values form explicit hysteresis bands so small speed
/// changes cannot repeatedly switch cadence.
nonisolated struct GraphPhysicsAdaptiveConfiguration:
    Equatable,
    Sendable
{
    static let production = GraphPhysicsAdaptiveConfiguration(
        quietEntryMaximumSpeed: 0.03,
        quietExitSpeed: 0.045,
        settlingEntryMaximumSpeed: 0.12,
        activeReentrySpeed: 0.15,
        settlingSamplesRequired: 6,
        quietSamplesRequired: 8,
        stableQuietSamplesRequired: 24,
        visualCommitEpsilon: 0.20,
        maximumTicksWithoutCommit: 3
    )

    let quietEntryMaximumSpeed: CGFloat
    let quietExitSpeed: CGFloat
    let settlingEntryMaximumSpeed: CGFloat
    let activeReentrySpeed: CGFloat
    let settlingSamplesRequired: Int
    let quietSamplesRequired: Int
    let stableQuietSamplesRequired: Int
    let visualCommitEpsilon: CGFloat
    let maximumTicksWithoutCommit: Int

    init(
        quietEntryMaximumSpeed: CGFloat,
        quietExitSpeed: CGFloat,
        settlingEntryMaximumSpeed: CGFloat,
        activeReentrySpeed: CGFloat,
        settlingSamplesRequired: Int,
        quietSamplesRequired: Int,
        stableQuietSamplesRequired: Int,
        visualCommitEpsilon: CGFloat,
        maximumTicksWithoutCommit: Int
    ) {
        self.quietEntryMaximumSpeed = max(
            0,
            quietEntryMaximumSpeed
        )
        self.quietExitSpeed = max(
            self.quietEntryMaximumSpeed,
            quietExitSpeed
        )
        self.settlingEntryMaximumSpeed = max(
            self.quietExitSpeed,
            settlingEntryMaximumSpeed
        )
        self.activeReentrySpeed = max(
            self.settlingEntryMaximumSpeed,
            activeReentrySpeed
        )
        self.settlingSamplesRequired = max(
            1,
            settlingSamplesRequired
        )
        self.quietSamplesRequired = max(1, quietSamplesRequired)
        self.stableQuietSamplesRequired = max(
            2,
            stableQuietSamplesRequired
        )
        self.visualCommitEpsilon = max(0, visualCommitEpsilon)
        self.maximumTicksWithoutCommit = max(
            1,
            maximumTicksWithoutCommit
        )
    }
}

nonisolated struct GraphPhysicsCadencePolicy:
    Equatable,
    Sendable
{
    private(set) var phase: GraphPhysicsCadencePhase = .active
    private(set) var settlingCandidateSamples = 0
    private(set) var quietCandidateSamples = 0

    mutating func resetToActive() {
        phase = .active
        settlingCandidateSamples = 0
        quietCandidateSamples = 0
    }

    @discardableResult
    mutating func observe(
        maxSimSpeed: CGFloat,
        isDragging: Bool,
        configuration: GraphPhysicsAdaptiveConfiguration
    ) -> GraphPhysicsCadencePhase {
        guard !isDragging else {
            resetToActive()
            return phase
        }

        switch phase {
        case .active:
            quietCandidateSamples = 0
            if maxSimSpeed
                <= configuration.settlingEntryMaximumSpeed {
                settlingCandidateSamples += 1
                if settlingCandidateSamples
                    >= configuration.settlingSamplesRequired {
                    phase = .settling
                    settlingCandidateSamples = 0
                }
            } else {
                settlingCandidateSamples = 0
            }

        case .settling:
            settlingCandidateSamples = 0
            if maxSimSpeed > configuration.activeReentrySpeed {
                resetToActive()
            } else if maxSimSpeed
                <= configuration.quietEntryMaximumSpeed {
                quietCandidateSamples += 1
                if quietCandidateSamples
                    >= configuration.quietSamplesRequired {
                    phase = .quiet
                    quietCandidateSamples = 0
                }
            } else {
                quietCandidateSamples = 0
            }

        case .quiet:
            settlingCandidateSamples = 0
            quietCandidateSamples = 0
            if maxSimSpeed > configuration.activeReentrySpeed {
                resetToActive()
            } else if maxSimSpeed > configuration.quietExitSpeed {
                phase = .settling
            }
        }

        return phase
    }
}

nonisolated enum GraphPhysicsForcedCommitReason:
    String,
    Equatable,
    Sendable
{
    case stop
    case sleep
    case externalInputChange
    case graphChange
    case dragEnd
    case beforeDiscard
}

nonisolated struct GraphPhysicsCommitPolicyInput:
    Equatable,
    Sendable
{
    let cadencePhase: GraphPhysicsCadencePhase
    let maximumCumulativePositionDelta: CGFloat
    let maxSimSpeed: CGFloat
    let ticksSinceLastCommit: Int
    let forcedReason: GraphPhysicsForcedCommitReason?
    let isDragging: Bool
}

nonisolated enum GraphPhysicsCommitPolicy {
    static func shouldCommit(
        _ input: GraphPhysicsCommitPolicyInput,
        configuration: GraphPhysicsAdaptiveConfiguration
    ) -> Bool {
        if input.forcedReason != nil {
            return true
        }
        if input.isDragging {
            return true
        }
        if input.cadencePhase == .active {
            return true
        }
        if input.maxSimSpeed > configuration.activeReentrySpeed {
            return true
        }
        if input.maximumCumulativePositionDelta
            >= configuration.visualCommitEpsilon {
            return true
        }
        return input.ticksSinceLastCommit
            >= configuration.maximumTicksWithoutCommit
    }
}

nonisolated struct GraphPhysicsStabilityPolicy:
    Equatable,
    Sendable
{
    private(set) var stableQuietSamples = 0

    mutating func reset() {
        stableQuietSamples = 0
    }

    @discardableResult
    mutating func observe(
        cadencePhase: GraphPhysicsCadencePhase,
        maxSimSpeed: CGFloat,
        maximumUnpublishedPositionDelta: CGFloat,
        isDragging: Bool,
        simulationAllowed: Bool,
        externalInputChangePending: Bool,
        configuration: GraphPhysicsAdaptiveConfiguration
    ) -> Bool {
        guard cadencePhase == .quiet,
              !isDragging,
              simulationAllowed,
              !externalInputChangePending,
              maxSimSpeed
                < configuration.quietEntryMaximumSpeed,
              maximumUnpublishedPositionDelta
                < configuration.visualCommitEpsilon else {
            stableQuietSamples = 0
            return false
        }

        stableQuietSamples += 1
        return stableQuietSamples
            >= configuration.stableQuietSamplesRequired
    }
}
