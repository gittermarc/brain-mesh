import CoreGraphics
import Testing

@testable import BrainMesh

@Suite("Graph physics cadence policy")
struct GraphPhysicsCadencePolicyTests {
    private let configuration =
        GraphPhysicsAdaptiveConfiguration.production

    @Test
    func productionCadenceAndThresholdsAreNamedAndStable() {
        #expect(GraphPhysicsCadencePhase.active.framesPerSecond == 30)
        #expect(
            GraphPhysicsCadencePhase.settling.framesPerSecond == 20
        )
        #expect(GraphPhysicsCadencePhase.quiet.framesPerSecond == 12)
        #expect(configuration.quietEntryMaximumSpeed == 0.03)
        #expect(configuration.quietExitSpeed == 0.045)
        #expect(configuration.settlingEntryMaximumSpeed == 0.12)
        #expect(configuration.activeReentrySpeed == 0.15)
        #expect(configuration.settlingSamplesRequired == 6)
        #expect(configuration.quietSamplesRequired == 8)
        #expect(configuration.stableQuietSamplesRequired == 24)
    }

    @Test
    func wakeAlwaysResetsToActive() {
        var policy = makeQuietPolicy()
        policy.resetToActive()

        #expect(policy.phase == .active)
        #expect(policy.settlingCandidateSamples == 0)
        #expect(policy.quietCandidateSamples == 0)
    }

    @Test
    func highEnergyStaysAtThirtyFramesPerSecond() {
        var policy = GraphPhysicsCadencePolicy()
        for _ in 0..<20 {
            _ = policy.observe(
                maxSimSpeed: 1,
                isDragging: false,
                configuration: configuration
            )
        }

        #expect(policy.phase == .active)
    }

    @Test
    func multipleSettlingSamplesSwitchToTwentyFramesPerSecond() {
        var policy = GraphPhysicsCadencePolicy()
        for _ in
            0..<(configuration.settlingSamplesRequired - 1) {
            _ = policy.observe(
                maxSimSpeed: 0.08,
                isDragging: false,
                configuration: configuration
            )
        }
        #expect(policy.phase == .active)

        _ = policy.observe(
            maxSimSpeed: 0.08,
            isDragging: false,
            configuration: configuration
        )
        #expect(policy.phase == .settling)
    }

    @Test
    func multipleQuietSamplesSwitchToTwelveFramesPerSecond() {
        var policy = makeSettlingPolicy()
        for _ in
            0..<configuration.quietSamplesRequired {
            _ = policy.observe(
                maxSimSpeed: 0.01,
                isDragging: false,
                configuration: configuration
            )
        }

        #expect(policy.phase == .quiet)
    }

    @Test
    func oneQuietSampleDoesNotReduceCadence() {
        var policy = makeSettlingPolicy()
        _ = policy.observe(
            maxSimSpeed: 0.01,
            isDragging: false,
            configuration: configuration
        )

        #expect(policy.phase == .settling)
        #expect(policy.quietCandidateSamples == 1)
    }

    @Test
    func speedIncreaseImmediatelySelectsFasterCadence() {
        var quiet = makeQuietPolicy()
        _ = quiet.observe(
            maxSimSpeed: 0.08,
            isDragging: false,
            configuration: configuration
        )
        #expect(quiet.phase == .settling)

        _ = quiet.observe(
            maxSimSpeed: 0.20,
            isDragging: false,
            configuration: configuration
        )
        #expect(quiet.phase == .active)
    }

    @Test
    func hysteresisPreventsThresholdOscillation() {
        var settling = makeSettlingPolicy()
        let settlingSpeeds: [CGFloat] = [
            0.121,
            0.130,
            0.149,
            0.121
        ]
        for speed in settlingSpeeds {
            _ = settling.observe(
                maxSimSpeed: speed,
                isDragging: false,
                configuration: configuration
            )
            #expect(settling.phase == .settling)
        }

        var quiet = makeQuietPolicy()
        let quietSpeeds: [CGFloat] = [
            0.031,
            0.040,
            0.044,
            0.031
        ]
        for speed in quietSpeeds {
            _ = quiet.observe(
                maxSimSpeed: speed,
                isDragging: false,
                configuration: configuration
            )
            #expect(quiet.phase == .quiet)
        }
    }

    @Test
    func draggingPreventsSettlingAndQuiet() {
        var policy = makeQuietPolicy()
        _ = policy.observe(
            maxSimSpeed: 0,
            isDragging: true,
            configuration: configuration
        )

        #expect(policy.phase == .active)
    }

    private func makeSettlingPolicy()
        -> GraphPhysicsCadencePolicy {
        var policy = GraphPhysicsCadencePolicy()
        for _ in
            0..<configuration.settlingSamplesRequired {
            _ = policy.observe(
                maxSimSpeed: 0.08,
                isDragging: false,
                configuration: configuration
            )
        }
        return policy
    }

    private func makeQuietPolicy()
        -> GraphPhysicsCadencePolicy {
        var policy = makeSettlingPolicy()
        for _ in
            0..<configuration.quietSamplesRequired {
            _ = policy.observe(
                maxSimSpeed: 0.01,
                isDragging: false,
                configuration: configuration
            )
        }
        return policy
    }
}
