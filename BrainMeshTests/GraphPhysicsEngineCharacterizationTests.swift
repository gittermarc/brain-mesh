import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics engine legacy characterization")
struct GraphPhysicsEngineCharacterizationTests {
    private let tolerance: CGFloat = 1e-12

    @Test
    func deterministicFixturesMatchTheFormerViewAlgorithm() {
        for fixture in GraphPhysicsFixtures.characterization {
            let expected = LegacyGraphPhysicsReference.step(
                input: fixture.input
            )
            let actual = GraphPhysicsEngine.step(input: fixture.input)

            expectEqual(
                actual,
                expected,
                fixtureName: fixture.name
            )
        }
    }

    private func expectEqual(
        _ actual: GraphPhysicsStepResult,
        _ expected: GraphPhysicsStepResult,
        fixtureName: String
    ) {
        let positionComment = Comment(
            rawValue: "\(fixtureName): position keys"
        )
        let velocityComment = Comment(
            rawValue: "\(fixtureName): velocity keys"
        )
        #expect(
            Set(actual.positions.keys) == Set(expected.positions.keys),
            positionComment
        )
        #expect(
            Set(actual.velocities.keys) == Set(expected.velocities.keys),
            velocityComment
        )

        for key in expected.positions.keys.sorted(
            by: { $0.identifier < $1.identifier }
        ) {
            guard let actualPosition = actual.positions[key],
                  let expectedPosition = expected.positions[key] else {
                Issue.record(
                    "\(fixtureName): missing position for \(key.identifier)"
                )
                continue
            }
            expectClose(
                actualPosition.x,
                expectedPosition.x,
                message: "\(fixtureName): position.x \(key.identifier)"
            )
            expectClose(
                actualPosition.y,
                expectedPosition.y,
                message: "\(fixtureName): position.y \(key.identifier)"
            )
        }

        for key in expected.velocities.keys.sorted(
            by: { $0.identifier < $1.identifier }
        ) {
            guard let actualVelocity = actual.velocities[key],
                  let expectedVelocity = expected.velocities[key] else {
                Issue.record(
                    "\(fixtureName): missing velocity for \(key.identifier)"
                )
                continue
            }
            expectClose(
                actualVelocity.dx,
                expectedVelocity.dx,
                message: "\(fixtureName): velocity.dx \(key.identifier)"
            )
            expectClose(
                actualVelocity.dy,
                expectedVelocity.dy,
                message: "\(fixtureName): velocity.dy \(key.identifier)"
            )
        }

        expectClose(
            actual.maxSimSpeed,
            expected.maxSimSpeed,
            message: "\(fixtureName): maxSimSpeed"
        )
        #expect(
            actual.metrics.simulatedNodeCount
                == expected.metrics.simulatedNodeCount,
            Comment(rawValue: "\(fixtureName): simulated node count")
        )
        #expect(
            actual.metrics.pairCount == expected.metrics.pairCount,
            Comment(rawValue: "\(fixtureName): pair count")
        )
        #expect(
            actual.metrics.springCount == expected.metrics.springCount,
            Comment(rawValue: "\(fixtureName): spring count")
        )
        #expect(
            actual.metrics == expected.metrics,
            Comment(rawValue: "\(fixtureName): complete metrics")
        )
    }

    private func expectClose(
        _ actual: CGFloat,
        _ expected: CGFloat,
        message: String
    ) {
        #expect(
            abs(actual - expected) <= tolerance,
            Comment(rawValue: message)
        )
    }
}
