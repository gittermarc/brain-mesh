import Foundation
import Testing
@testable import BrainMesh

private actor GraphChatThrowingSchemaProvider: GraphSchemaSnapshotProviding {
    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) throws -> GraphSchemaContext {
        throw GraphChatError(
            code: .toolFailure,
            message: "Synthetic schema failure"
        )
    }
}

private actor GraphChatForeignSchemaProvider: GraphSchemaSnapshotProviding {
    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) -> GraphSchemaContext {
        GraphChatTestSupport.makeSchemaContext(
            graphID: GraphChatTestSupport.otherGraphID
        )
    }
}

struct GraphChatProviderSessionFactoryTests {
    @Test
    func unavailableModelKeepsTheExistingAvailabilityMapping() async throws {
        let provider = FakeGraphChatModelProvider(
            availability: .unavailable(.appleIntelligenceNotEnabled)
        )
        let factory = makeFactory(provider: provider)

        do {
            _ = try await GraphChatProviderTestSupport.makeInitialProviderResources(
                sessionFactory: factory
            )
            Issue.record("Expected model availability failure.")
        } catch let error as GraphChatError {
            #expect(error.code == .modelUnavailable)
            #expect(error.message == "Apple Intelligence ist deaktiviert.")
            #expect(
                error.recoverySuggestion
                    == "Aktiviere Apple Intelligence in den Systemeinstellungen."
            )
        }
    }

    @Test
    func schemaFailureRemainsSchemaUnavailable() async throws {
        let provider = FakeGraphChatModelProvider()
        let factory = GraphChatProviderTestSupport.makeProviderSessionFactory(
            provider: provider,
            schemaProvider: GraphChatThrowingSchemaProvider(),
            toolRunnerFactory: EvidenceRegisteringFakeToolRunnerFactory()
        )

        do {
            _ = try await GraphChatProviderTestSupport.makeInitialProviderResources(
                sessionFactory: factory
            )
            Issue.record("Expected schema failure.")
        } catch let error as GraphChatError {
            #expect(error.code == .schemaUnavailable)
            #expect(
                error.message
                    == "Das Schema des aktiven Graphen konnte nicht geladen werden."
            )
            #expect(
                error.recoverySuggestion
                    == "Öffne den Graphen erneut und versuche es noch einmal."
            )
        }
    }

    @Test
    func foreignSchemaIsRejectedBeforeSessionCreation() async throws {
        let provider = FakeGraphChatModelProvider()
        let factory = GraphChatProviderTestSupport.makeProviderSessionFactory(
            provider: provider,
            schemaProvider: GraphChatForeignSchemaProvider(),
            toolRunnerFactory: EvidenceRegisteringFakeToolRunnerFactory()
        )

        do {
            _ = try await GraphChatProviderTestSupport.makeInitialProviderResources(
                sessionFactory: factory
            )
            Issue.record("Expected foreign schema rejection.")
        } catch let error as GraphChatError {
            #expect(error.code == .schemaUnavailable)
            #expect(
                error.message
                    == "Das geladene Schema gehört nicht zum aktiven Graphen."
            )
        }
        #expect(await provider.snapshot().createdSessions.isEmpty)
    }

    @Test
    func exactlySixControlledToolsAreRequired() async throws {
        let provider = FakeGraphChatModelProvider()
        let factory = makeFactory(provider: provider)
        let resources = try await GraphChatProviderTestSupport
            .makeInitialProviderResources(sessionFactory: factory)

        #expect(GraphChatProviderSessionFactory.controlledToolKinds.count == 6)
        #expect(
            await resources.toolRunner.registeredToolKinds()
                == GraphChatProviderSessionFactory.controlledToolKinds
        )
        await factory.cleanupFailedAttempt(
            resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func missingControlledToolIsRejected() async throws {
        let provider = FakeGraphChatModelProvider()
        var toolKinds = GraphChatProviderSessionFactory.controlledToolKinds
        toolKinds.remove(.graphStats)
        let factory = makeFactory(
            provider: provider,
            runnerFactory: EvidenceRegisteringFakeToolRunnerFactory(
                registeredKinds: toolKinds
            )
        )

        do {
            _ = try await GraphChatProviderTestSupport.makeInitialProviderResources(
                sessionFactory: factory
            )
            Issue.record("Expected missing tool rejection.")
        } catch let error as GraphChatError {
            #expect(error.code == .invalidRequest)
        }
        #expect(await provider.snapshot().createdSessions.isEmpty)
    }

    @Test
    func additionalToolIdentifierIsRejected() async throws {
        let provider = FakeGraphChatModelProvider()
        var identifiers = Set(
            GraphChatProviderSessionFactory.controlledToolKinds.map(\.rawValue)
        )
        identifiers.insert("unexpectedWriteTool")
        let factory = makeFactory(
            provider: provider,
            runnerFactory: EvidenceRegisteringFakeToolRunnerFactory(
                registeredIdentifiers: identifiers
            )
        )

        do {
            _ = try await GraphChatProviderTestSupport.makeInitialProviderResources(
                sessionFactory: factory
            )
            Issue.record("Expected additional tool rejection.")
        } catch let error as GraphChatError {
            #expect(error.code == .invalidRequest)
        }
        #expect(await provider.snapshot().createdSessions.isEmpty)
    }

    @Test
    func standardAndRecoveryBudgetsPreserveTheirPolicies() async throws {
        let provider = FakeGraphChatModelProvider()
        let policy = GraphChatToolBudgetPolicy(
            maximumCalls: 8,
            maximumResultCountPerTool: 50,
            maximumEvidenceCount: 200
        )
        let factory = makeFactory(
            provider: provider,
            budgetPolicy: policy
        )
        let standard = try await GraphChatProviderTestSupport
            .makeInitialProviderResources(sessionFactory: factory)
        await factory.cleanupFailedAttempt(
            standard,
            requestProviderCancellation: false
        )
        let recovery = try await factory.makeRecoverySession(
            replacing: standard
        )

        #expect(await standard.toolBudget.policyForTesting() == policy)
        #expect(
            await recovery.toolBudget.policyForTesting()
                == GraphChatToolBudgetPolicy(
                    maximumCalls: 3,
                    maximumResultCountPerTool: 12,
                    maximumEvidenceCount: 40
                )
        )
        await factory.cleanupFailedAttempt(
            recovery,
            requestProviderCancellation: false
        )
    }

    @Test
    func recoveryBudgetNeverWidensTheOriginalPolicy() {
        let provider = FakeGraphChatModelProvider()
        let original = GraphChatToolBudgetPolicy(
            maximumCalls: 2,
            maximumResultCountPerTool: 7,
            maximumEvidenceCount: 19
        )
        let factory = makeFactory(
            provider: provider,
            budgetPolicy: original
        )

        #expect(factory.budgetPolicy(for: .standard) == original)
        #expect(factory.budgetPolicy(for: .recovery) == original)
    }

    @Test
    func recoveryCarryingPendingRepairPreservesOriginalOutputLimits() async throws {
        let provider = FakeGraphChatModelProvider()
        let policy = GraphChatToolBudgetPolicy(
            maximumCalls: 8,
            maximumResultCountPerTool: 50,
            maximumEvidenceCount: 200
        )
        let factory = makeFactory(
            provider: provider,
            budgetPolicy: policy
        )
        let standard = try await GraphChatProviderTestSupport
            .makeInitialProviderResources(sessionFactory: factory)
        let repair = GraphChatToolRepairResult(
            reason: .unknownEntityAlias,
            argumentPath: "entityAlias",
            expectedCategory: .entityAlias,
            expectedDataType: nil,
            allowedCandidates: [],
            allowedOperators: [],
            validatedCurrent: nil
        )
        #expect(
            await standard.recoveryCoordinator.offerRepair(
                repair,
                for: .queryDetailValues
            )
        )
        await factory.cleanupFailedAttempt(
            standard,
            requestProviderCancellation: false
        )

        let recovery = try await factory.makeRecoverySession(
            replacing: standard
        )

        #expect(
            await recovery.toolBudget.policyForTesting()
                == GraphChatToolBudgetPolicy(
                    maximumCalls: 3,
                    maximumResultCountPerTool: 50,
                    maximumEvidenceCount: 200
                )
        )
        await factory.cleanupFailedAttempt(
            recovery,
            requestProviderCancellation: false
        )
    }

    @Test
    func sessionConfigurationRemainsGraphAndScopeBound() async throws {
        let provider = FakeGraphChatModelProvider()
        let factory = makeFactory(provider: provider)
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entity(
            GraphChatTestSupport.projectEntityID,
            in: graphScope
        )
        let resources = try await GraphChatProviderTestSupport
            .makeInitialProviderResources(
                sessionFactory: factory,
                chatScope: chatScope
            )
        let snapshot = await provider.snapshot()
        let configuration = try #require(
            snapshot.sessionConfigurations[resources.sessionID]
        )

        #expect(configuration.graphScope == graphScope)
        #expect(configuration.chatScope == chatScope)
        #expect(configuration.schemaContext.graphScope == graphScope)
        await factory.cleanupFailedAttempt(
            resources,
            requestProviderCancellation: false
        )
    }

    private func makeFactory(
        provider: FakeGraphChatModelProvider,
        runnerFactory: any GraphChatModelToolRunnerFactory =
            EvidenceRegisteringFakeToolRunnerFactory(),
        budgetPolicy: GraphChatToolBudgetPolicy = .default
    ) -> GraphChatProviderSessionFactory {
        GraphChatProviderTestSupport.makeProviderSessionFactory(
            provider: provider,
            schemaProvider: FakeGraphSchemaSnapshotProvider(
                contexts: [
                    GraphChatTestSupport.makeSchemaContext(
                        graphID: GraphChatTestSupport.graphID
                    )
                ]
            ),
            toolRunnerFactory: runnerFactory,
            budgetPolicy: budgetPolicy
        )
    }
}
