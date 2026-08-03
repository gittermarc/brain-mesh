import Foundation
import SwiftData
import Testing

@testable import BrainMesh

@Suite("Graph chat relationship intent end-to-end")
struct GraphChatRelationshipIntentEndToEndTests {
    @MainActor
    @Test
    func medicalLibraryAndOperationsFixturesUseOneLocalPipeline()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph =
            fixtures.makeGraph(
                name: "Beziehungswissen"
            )

        let patients =
            fixtures.makeEntity(
                name: "Patienten",
                in: graph
            )
        let medications =
            fixtures.makeEntity(
                name: "Medikamente",
                in: graph
            )
        let patient =
            fixtures.makeAttribute(
                name: "Patient A",
                owner: patients
            )
        let medication =
            fixtures.makeAttribute(
                name: "Medikament 3",
                owner: medications
            )
        fixtures.makeLink(
            source: .attribute(patient),
            target: .attribute(medication),
            note: "3× täglich"
        )

        let authors =
            fixtures.makeEntity(
                name: "Authors",
                in: graph
            )
        let books =
            fixtures.makeEntity(
                name: "Books",
                in: graph
            )
        let author =
            fixtures.makeAttribute(
                name: "Author Ada",
                owner: authors
            )
        let book =
            fixtures.makeAttribute(
                name: "Book North",
                owner: books
            )
        fixtures.makeLink(
            source: .attribute(author),
            target: .attribute(book),
            note: "first edition"
        )

        let services =
            fixtures.makeEntity(
                name: "Services",
                in: graph
            )
        let databases =
            fixtures.makeEntity(
                name: "Datenbanken",
                in: graph
            )
        let service =
            fixtures.makeAttribute(
                name: "Service Alpha",
                owner: services
            )
        let database =
            fixtures.makeAttribute(
                name: "Datenbank Nord",
                owner: databases
            )
        fixtures.makeLink(
            source: .attribute(service),
            target: .attribute(database),
            note: "primary writer"
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter()
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )

        let medicalEvents = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Was steht auf der Verbindung zwischen Patient A und Medikament 3?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let medical = try await relationshipPayload(
            events: medicalEvents,
            runtime: runtime,
            graphScope: graphScope,
            chatScope: chatScope
        )
        #expect(
            medical.connections.map(\.counterpartLabel)
                == ["Medikament 3"]
        )
        #expect(
            medical.connections.compactMap(\.note)
                == ["3× täglich"]
        )
        #expect(medical.resultWindow.totalCount == 1)
        #expect(
            terminalEventCount(medicalEvents)
                == 1
        )

        let libraryEvents = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Which Books belong to Author Ada?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let library = try await relationshipPayload(
            events: libraryEvents,
            runtime: runtime,
            graphScope: graphScope,
            chatScope: chatScope
        )
        #expect(
            library.connections.map(\.counterpartLabel)
                == ["Book North"]
        )
        #expect(
            library.counterpartEntityLabel
                == "Books"
        )
        #expect(
            terminalEventCount(libraryEvents)
                == 1
        )

        let operationsEvents = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Welche Services zeigen auf Datenbank Nord?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let operations = try await relationshipPayload(
            events: operationsEvents,
            runtime: runtime,
            graphScope: graphScope,
            chatScope: chatScope
        )
        #expect(
            operations.connections.map(\.counterpartLabel)
                == ["Service Alpha"]
        )
        #expect(
            operations.connections.map(\.direction)
                == [.incoming]
        )
        #expect(
            operations.counterpartEntityLabel
                == "Services"
        )
        #expect(
            terminalEventCount(operationsEvents)
                == 1
        )

        let interpreterSnapshot =
            await interpreter.snapshot()
        let providerSnapshot =
            await runtime.provider.snapshot()
        let visible = [
            visibleText(medicalEvents),
            visibleText(libraryEvents),
            visibleText(operationsEvents),
        ].joined(separator: "\n")

        #expect(interpreterSnapshot.requests.isEmpty)
        #expect(providerSnapshot.createdSessions.isEmpty)
        #expect(providerSnapshot.streamedSessions.isEmpty)
        #expect(
            visible.contains(
                patient.id.uuidString
            ) == false
        )
        #expect(
            visible.contains(
                medication.id.uuidString
            ) == false
        )
        #expect(
            visible.contains("N_")
                == false
        )
        #expect(
            visible.contains("E_")
                == false
        )
    }

    @MainActor
    @Test
    func composableMedicalFastPathCompilesLocallyAndCurrentOnlyRefinesItsResult()
        async throws
    {
        let store = try BrainMeshTestContainer
            .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Medizin"
        )
        let patients = fixtures.makeEntity(
            name: "Patienten",
            in: graph
        )
        let medications = fixtures.makeEntity(
            name: "Medikamente",
            in: graph
        )
        let services = fixtures.makeEntity(
            name: "Services",
            in: graph
        )
        let status = fixtures.makeDetailField(
            owner: patients,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Offen", "Geschlossen"]
        )
        let patientA = fixtures.makeAttribute(
            name: "Patient A",
            owner: patients
        )
        let patientB = fixtures.makeAttribute(
            name: "Patient B",
            owner: patients
        )
        let patientC = fixtures.makeAttribute(
            name: "Patient C",
            owner: patients
        )
        let medicationA = fixtures.makeAttribute(
            name: "Medikament A",
            owner: medications
        )
        let medicationB = fixtures.makeAttribute(
            name: "Medikament B",
            owner: medications
        )
        let foreignService = fixtures.makeAttribute(
            name: "Service Fremd",
            owner: services
        )
        fixtures.makeDetailValue(
            attribute: patientA,
            field: status,
            stringValue: "Offen"
        )
        fixtures.makeDetailValue(
            attribute: patientB,
            field: status,
            stringValue: "Geschlossen"
        )
        fixtures.makeDetailValue(
            attribute: patientC,
            field: status,
            stringValue: "Offen"
        )
        fixtures.makeLink(
            source: .attribute(patientA),
            target: .attribute(medicationA),
            note: "3× täglich"
        )
        fixtures.makeLink(
            source: .attribute(patientA),
            target: .attribute(medicationB),
            note: "dreimal täglich"
        )
        fixtures.makeLink(
            source: .attribute(patientB),
            target: .attribute(medicationB),
            note: "three times daily"
        )
        fixtures.makeLink(
            source: .attribute(patientC),
            target: .attribute(medicationA),
            note: "einmal täglich"
        )
        fixtures.makeLink(
            source: .attribute(foreignService),
            target: .attribute(medicationA),
            note: "3x täglich"
        )
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .refinement,
                        conversationReference:
                            .currentSelection,
                        filters: [
                            GraphChatSemanticFilterDraft(
                                fieldTerm: "Status",
                                relation: .equals,
                                values: ["Offen"]
                            ),
                        ],
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let chatScope = GraphChatScope
            .entireGraph(graphScope)

        let firstEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Welche Patienten nehmen ein Medikament dreimal täglich?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let firstAnswer = try completedAnswer(
            firstEvents
        )
        let firstInterpretation = try #require(
            firstAnswer.interpretation
        )
        let firstPresentation = await runtime
            .orchestrator.resolveAnswerPresentation(
                artifactIDs:
                    firstAnswer.artifactIDs,
                evidence: firstAnswer.evidence,
                graphScope: graphScope,
                chatScope: chatScope
            )
        let firstResolved = try #require(
            firstPresentation.artifacts.first
        )
        guard case .resultList(let firstList) =
                firstResolved.artifact.payload else {
            Issue.record(
                "Expected a composable result-list artifact."
            )
            return
        }
        let firstState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let initialNodes = Set(
            firstState.resultContexts.last?
                .references.compactMap {
                    reference -> NodeRefKey? in
                    guard case .node(let node) =
                            reference.reference else {
                        return nil
                    }
                    return node
                } ?? []
        )
        let drawer = GraphChatEvidenceDrawerPresentation(
            resolved: firstResolved,
            availableEvidence:
                firstPresentation.evidence,
            language: .german
        )

        #expect(
            firstList.rows.map(\.primaryText)
                == ["Patient A", "Patient B"]
        )
        #expect(
            firstInterpretation.entities.map(\.displayName)
                == ["Patienten", "Medikamente"]
        )
        #expect(
            firstInterpretation.presentation.title
                .contains("Patienten → Medikamente")
        )
        #expect(firstInterpretation.isCorrectionEditable == false)
        #expect(
            initialNodes == Set([
                NodeRefKey(
                    kind: .attribute,
                    id: patientA.id
                ),
                NodeRefKey(
                    kind: .attribute,
                    id: patientB.id
                ),
            ])
        )
        #expect(
            drawer.visibleTextForTesting
                .contains("Link-Notiz enthält dreimal")
        )
        #expect(
            drawer.visibleTextForTesting
                .contains("Budgets: Startnodes")
        )
        #expect(
            firstPresentation.evidence.contains {
                $0.sourceReference.sourceKind == .link
                    && $0.fieldValues.contains {
                        $0.fieldName == "Link-Notiz"
                    }
            }
        )

        let secondEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Und davon nur die mit Status offen?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let secondAnswer = try completedAnswer(
            secondEvents
        )
        let secondPresentation = await runtime
            .orchestrator.resolveAnswerPresentation(
                artifactIDs:
                    secondAnswer.artifactIDs,
                evidence: secondAnswer.evidence,
                graphScope: graphScope,
                chatScope: chatScope
            )
        let secondArtifact = try #require(
            secondPresentation.artifacts.first?
                .artifact
        )
        guard case .resultList(let secondList) =
                secondArtifact.payload else {
            Issue.record(
                "Expected a refined result-list artifact."
            )
            return
        }
        let secondState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let refinementPlan = try #require(
            secondState.lastValidatedQueryPlan
        )
        guard case .selection(let refinementScope) =
                refinementPlan.scope else {
            Issue.record(
                "Expected CURRENT to compile to an exact selection."
            )
            return
        }
        let provider = await runtime.provider.snapshot()
        let interpreterSnapshot = await interpreter.snapshot()
        let visible = drawer.visibleTextForTesting
            + visibleText(firstEvents + secondEvents)

        #expect(
            secondList.rows.map(\.primaryText)
                == ["Patient A"]
        )
        #expect(Set(refinementScope) == initialNodes)
        #expect(
            refinementScope.contains(
                NodeRefKey(
                    kind: .attribute,
                    id: patientC.id
                )
            ) == false
        )
        #expect(
            refinementScope.contains(
                NodeRefKey(
                    kind: .attribute,
                    id: foreignService.id
                )
            ) == false
        )
        #expect(
            refinementPlan.filters.map(\.operation)
                == [.equals]
        )
        #expect(interpreterSnapshot.requests.count == 1)
        #expect(provider.createdSessions.isEmpty)
        #expect(provider.streamedSessions.isEmpty)
        #expect(terminalEventCount(firstEvents) == 1)
        #expect(terminalEventCount(secondEvents) == 1)
        #expect(visible.contains(patientA.id.uuidString) == false)
        #expect(visible.contains("E_") == false)
        #expect(visible.contains("F_") == false)
    }

    @MainActor
    @Test
    func currentContinuationOnlyRefinesTheRevalidatedRelationshipSelection()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph =
            fixtures.makeGraph(
                name: "Versorgung"
            )
        let patients =
            fixtures.makeEntity(
                name: "Patienten",
                in: graph
            )
        let medications =
            fixtures.makeEntity(
                name: "Medikamente",
                in: graph
            )
        let services =
            fixtures.makeEntity(
                name: "Services",
                in: graph
            )
        let patient =
            fixtures.makeAttribute(
                name: "Patient A",
                owner: patients
            )
        let medication =
            fixtures.makeAttribute(
                name: "Medikament 3",
                owner: medications
            )
        let service =
            fixtures.makeAttribute(
                name: "Service Alpha",
                owner: services
            )
        fixtures.makeLink(
            source: .attribute(patient),
            target: .attribute(medication),
            note: "3× täglich"
        )
        fixtures.makeLink(
            source: .attribute(service),
            target: .attribute(patient),
            note: "betreut"
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter()
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )

        let initialEvents = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Welche Medikamente gehören zu Patient A?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let initial = try await relationshipPayload(
            events: initialEvents,
            runtime: runtime,
            graphScope: graphScope,
            chatScope: chatScope
        )
        #expect(
            initial.connections.map(\.counterpartLabel)
                == ["Medikament 3"]
        )

        let continuationEvents = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Und nur die eingehenden?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let continuation =
            try await relationshipPayload(
                events: continuationEvents,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let relationship = try #require(
            state.lastRelationship
        )

        #expect(continuation.connections.isEmpty)
        #expect(
            continuation.counterpartEntityLabel
                == "Medikamente"
        )
        #expect(
            relationship.plan.direction
                == .incoming
        )
        #expect(
            relationship.plan
                .counterpartEntity?.id
                == medications.id
        )
        #expect(
            relationship.plan
                .sourceRelationshipContextID
                != nil
        )
        #expect(
            state.resultContexts.last?.kind
                == .relationship
        )
        #expect(
            terminalEventCount(continuationEvents)
                == 1
        )
        #expect(
            await interpreter.snapshot()
                .requests.isEmpty
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func genuineNodeAmbiguityCommitsOnlyAPendingClarification()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph =
            fixtures.makeGraph(
                name: "Mehrdeutig"
            )
        let firstOwner =
            fixtures.makeEntity(
                name: "Gruppe Eins",
                in: graph
            )
        let secondOwner =
            fixtures.makeEntity(
                name: "Gruppe Zwei",
                in: graph
            )
        fixtures.makeAttribute(
            name: "Knoten Mitte",
            owner: firstOwner
        )
        fixtures.makeAttribute(
            name: "Knoten Mitte",
            owner: secondOwner
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter()
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let events = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Womit ist Knoten Mitte verbunden?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let answer =
            try completedAnswer(events)
        guard case .clarification(
            let clarification
        ) = answer.state else {
            Issue.record(
                "Expected a relationship clarification."
            )
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )

        #expect(clarification.options.count == 2)
        #expect(
            state.pendingClarification?
                .options.count == 2
        )
        #expect(state.lastRelationship == nil)
        #expect(state.resultContexts.isEmpty)
        #expect(terminalEventCount(events) == 1)
        #expect(
            await interpreter.snapshot()
                .requests.isEmpty
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func semanticInterpreterCompilationStillExecutesWithoutAnswerProvider()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph =
            fixtures.makeGraph(
                name: "Semantische Beziehungen"
            )
        let nodes =
            fixtures.makeEntity(
                name: "Knoten",
                in: graph
            )
        let center =
            fixtures.makeAttribute(
                name: "Knoten A",
                owner: nodes
            )
        let counterpart =
            fixtures.makeAttribute(
                name: "Knoten B",
                owner: nodes
            )
        fixtures.makeLink(
            source: .attribute(center),
            target: .attribute(counterpart),
            note: "direkt"
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .relationships,
                            nodeTerms:
                                ["Knoten A"],
                            relationshipDirection:
                                .both,
                            responseLanguage:
                                .german
                        )
                    ),
                ]
            )
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let events = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Bitte ermittle die unmittelbare Nachbarschaft von Knoten A.",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let payload =
            try await relationshipPayload(
                events: events,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )

        #expect(
            payload.connections
                .map(\.counterpartLabel)
                == ["Knoten B"]
        )
        #expect(
            await interpreter.snapshot()
                .requests.count == 1
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func nodeScopedChatCannotBindACenterOutsideItsScope()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph =
            fixtures.makeGraph(
                name: "Scope"
            )
        let nodes =
            fixtures.makeEntity(
                name: "Knoten",
                in: graph
            )
        let allowed =
            fixtures.makeAttribute(
                name: "Knoten Erlaubt",
                owner: nodes
            )
        fixtures.makeAttribute(
            name: "Knoten Außerhalb",
            owner: nodes
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter()
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.node(
                NodeRefKey(
                    kind: .attribute,
                    id: allowed.id
                ),
                in: graphScope
            )
        let events = await collect(
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Womit ist Knoten Außerhalb verbunden?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        )
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()

        #expect(
            events.contains {
                if case .failure = $0 {
                    return true
                }
                return false
            }
        )
        #expect(terminalEventCount(events) == 1)
        #expect(
            state?.turnContexts.isEmpty
                != false
        )
        #expect(
            state?.resultContexts.isEmpty
                != false
        )
        #expect(state?.lastRelationship == nil)
        #expect(
            await interpreter.snapshot()
                .requests.isEmpty
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func cancellationProducesOneTerminalEventAndAtomicRollback()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph =
            fixtures.makeGraph(
                name: "Abbruch"
            )
        let nodes =
            fixtures.makeEntity(
                name: "Knoten",
                in: graph
            )
        fixtures.makeAttribute(
            name: "Knoten A",
            owner: nodes
        )
        try fixtures.save()

        let blocker =
            BlockingRelationshipExecutor()
        let interpreter =
            FakeGraphChatIntentInterpreter()
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter,
            relationshipExecutor: blocker
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let stream =
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Womit ist Knoten A verbunden?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let collector = Task {
            await collect(stream)
        }
        await blocker.waitUntilStarted()
        await runtime.orchestrator
            .cancelCurrentGeneration()
        let events = await collector.value
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()

        #expect(events.last == .cancelled)
        #expect(terminalEventCount(events) == 1)
        #expect(
            state?.turnContexts.isEmpty
                != false
        )
        #expect(
            state?.resultContexts.isEmpty
                != false
        )
        #expect(state?.lastRelationship == nil)
        #expect(
            await interpreter.snapshot()
                .requests.isEmpty
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func composableCancellationProducesOneTerminalEventAndAtomicRollback()
        async throws
    {
        let store = try BrainMeshTestContainer
            .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Composable-Abbruch"
        )
        let patients = fixtures.makeEntity(
            name: "Patienten",
            in: graph
        )
        let medications = fixtures.makeEntity(
            name: "Medikamente",
            in: graph
        )
        let patient = fixtures.makeAttribute(
            name: "Patient A",
            owner: patients
        )
        let medication = fixtures.makeAttribute(
            name: "Medikament A",
            owner: medications
        )
        fixtures.makeLink(
            source: .attribute(patient),
            target: .attribute(medication),
            note: "dreimal täglich"
        )
        try fixtures.save()

        let blocker = BlockingComposableReadExecutor()
        let interpreter = FakeGraphChatIntentInterpreter()
        let runtime = makeRuntime(
            store: store,
            interpreter: interpreter,
            composableReadExecutor: blocker
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope
            .entireGraph(graphScope)
        let stream = await runtime.orchestrator
            .streamAnswer(
                question:
                    "Welche Patienten nehmen ein Medikament dreimal täglich?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        let collector = Task {
            await collect(stream)
        }
        await blocker.waitUntilStarted()
        await runtime.orchestrator
            .cancelCurrentGeneration()
        let events = await collector.value
        let state = await runtime.orchestrator
            .conversationStateSnapshot()

        #expect(events.last == .cancelled)
        #expect(terminalEventCount(events) == 1)
        #expect(state?.turnContexts.isEmpty != false)
        #expect(state?.resultContexts.isEmpty != false)
        #expect(state?.lastValidatedQueryPlan == nil)
        #expect(
            await interpreter.snapshot().requests.isEmpty
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    private struct Runtime {
        let orchestrator: GraphChatOrchestrator
        let provider: FakeGraphChatModelProvider
    }

    @MainActor
    private func makeRuntime(
        store: BrainMeshTestStore,
        interpreter:
            FakeGraphChatIntentInterpreter,
        relationshipExecutor:
            (any GraphChatLocalIntentRelationshipExecuting)? =
                nil,
        composableReadExecutor:
            (any GraphChatLocalIntentComposableReadExecuting)? =
                nil
    ) -> Runtime {
        let container =
            AnyModelContainer(
                store.container
            )
        let repository =
            GraphReadRepository(
                container: container
            )
        let nodeRepository =
            NodeRepository(
                container: container
            )
        let evidenceValidator =
            GraphEvidenceSourceValidator(
                repository: repository
            )
        let queryEngine =
            GraphChatQueryEngine(
                repository: repository,
                evidenceValidator:
                    evidenceValidator
            )
        let referenceResolver =
            GraphChatConversationReferenceResolver(
                revalidator:
                    GraphChatRepositoryConversationReferenceRevalidator(
                        repository:
                            repository,
                        queryEngine:
                            queryEngine
                    )
            )
        let provider =
            FakeGraphChatModelProvider()
        let localRelationshipExecutor =
            relationshipExecutor
            ?? GraphChatRelationshipExecutor(
                repository: nodeRepository,
                evidenceValidator:
                    evidenceValidator,
                logger:
                    NoOpGraphChatToolLogger()
            )
        let localComposableReadExecutor =
            composableReadExecutor
            ?? GraphChatComposableReadExecutor(
                repository: repository,
                evidenceValidator:
                    evidenceValidator
            )
        let orchestrator =
            GraphChatOrchestrator(
                provider: provider,
                intentInterpreter:
                    interpreter,
                schemaProvider:
                    GraphSchemaService(
                        repository: repository
                    ),
                foundationalQueryExecutor:
                    queryEngine,
                semanticRelationshipExecutor:
                    localRelationshipExecutor,
                semanticComposableReadExecutor:
                    localComposableReadExecutor,
                toolRunnerFactory:
                    EvidenceRegisteringFakeToolRunnerFactory(),
                referenceResolver:
                    referenceResolver,
                responseLanguageSelector:
                    GraphChatResponseLanguageSelector(
                        fallback: .german
                    ),
                artifactRevalidator:
                    GraphChatLiveAnswerArtifactRevalidator(
                        evidenceValidator:
                            evidenceValidator,
                        sourceRepository:
                            repository
                    ),
                evidenceValidator:
                    evidenceValidator,
                referenceDate: {
                    Date(
                        timeIntervalSince1970:
                            1_768_413_600
                    )
                },
                calendar:
                    Calendar(
                        identifier: .gregorian
                    ),
                timeZone:
                    TimeZone(
                        identifier:
                            "Europe/Berlin"
                    )!
            )
        return Runtime(
            orchestrator: orchestrator,
            provider: provider
        )
    }

    private func collect(
        _ stream: GraphChatEventStream
    ) async -> [GraphChatStreamEvent] {
        await GraphChatProviderTestSupport
            .collect(stream)
    }

    private func completedAnswer(
        _ events: [GraphChatStreamEvent]
    ) throws -> GraphChatAnswer {
        try #require(
            events.compactMap {
                if case .completed(
                    let answer
                ) = $0 {
                    return answer
                }
                return nil
            }.last
        )
    }

    private func relationshipPayload(
        events: [GraphChatStreamEvent],
        runtime: Runtime,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async throws
        -> GraphChatAnswerArtifactRelationshipPayload
    {
        let answer =
            try completedAnswer(events)
        let presentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs:
                        answer.artifactIDs,
                    evidence:
                        answer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let artifact = try #require(
            presentation.artifacts.first?
                .artifact
        )
        guard case .relationship(
            let payload
        ) = artifact.payload else {
            Issue.record(
                "Expected a relationship artifact."
            )
            throw RelationshipEndToEndError
                .missingRelationshipArtifact
        }
        return payload
    }

    private func terminalEventCount(
        _ events: [GraphChatStreamEvent]
    ) -> Int {
        events.filter {
            switch $0 {
            case .completed,
                    .cancelled,
                    .failure:
                return true
            case .started,
                    .toolActivity,
                    .partialAnswer:
                return false
            }
        }.count
    }

    private func visibleText(
        _ events: [GraphChatStreamEvent]
    ) -> String {
        events.compactMap {
            switch $0 {
            case .partialAnswer(let text):
                return text
            case .completed(let answer):
                return answer.directAnswer
            case .started,
                    .toolActivity,
                    .cancelled,
                    .failure:
                return nil
            }
        }.joined(separator: "\n")
    }
}

private nonisolated enum
    RelationshipEndToEndError: Error
{
    case missingRelationshipArtifact
}

private actor BlockingRelationshipExecutor:
    GraphChatLocalIntentRelationshipExecuting
{
    private var started = false
    private var waiters:
        [CheckedContinuation<Void, Never>] =
            []

    func execute(
        _ plan: GraphChatRelationshipPlan,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<
            GraphChatRelationshipOutput
        >
    {
        _ = plan
        _ = context
        started = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach {
            $0.resume()
        }
        try await Task.sleep(
            nanoseconds: UInt64.max
        )
        throw CancellationError()
    }

    func waitUntilStarted() async {
        guard started == false else {
            return
        }
        await withCheckedContinuation {
            waiters.append($0)
        }
    }
}

private actor BlockingComposableReadExecutor:
    GraphChatLocalIntentComposableReadExecuting
{
    private var started = false
    private var waiters:
        [CheckedContinuation<Void, Never>] = []

    func execute(
        _ plan: ValidatedGraphChatComposableReadPlan,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<
            GraphChatComposableReadExecutionOutput
        >
    {
        _ = plan
        _ = context
        started = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
        try await Task.sleep(
            nanoseconds: UInt64.max
        )
        throw CancellationError()
    }

    func waitUntilStarted() async {
        guard started == false else {
            return
        }
        await withCheckedContinuation {
            waiters.append($0)
        }
    }
}
