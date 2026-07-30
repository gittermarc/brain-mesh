import Foundation
import Testing

@testable import BrainMesh
import SwiftData

@Suite("Graph chat link-note authority")
struct GraphChatLinkNoteAuthorityTests {
    @Test
    func linkNoteEvidenceBindsGraphEndpointsDirectionAndAuthoritativeValue()
        async throws
    {
        let fixture = try makeMedicalFixture()
        let result = try await fixture.tool.execute(
            GetNodeInput(
                node: fixture.patientNode,
                relatedLimit: 10
            ),
            context: fixture.toolContext
        )
        let output = try #require(result.payload)
        let connection = try #require(
            output.links.first
        )
        let evidence = try #require(
            result.evidence.first {
                $0.sourceReference
                    .sourceKind == .link
            }
        )
        let binding = try #require(
            evidence.sourceReference
                .linkBinding
        )

        #expect(connection.note == "3× täglich")
        #expect(
            binding.linkID == fixture.link.id
        )
        #expect(
            binding.source.nodeKey
                == fixture.patientNode
        )
        #expect(
            binding.target.nodeKey
                == fixture.medicationNode
        )
        #expect(binding.direction == .outgoing)
        #expect(binding.note == "3× täglich")
        #expect(
            evidence.fieldValues
                == [
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Link-Notiz",
                        value:
                            .text("3× täglich"),
                        unit: nil
                    ),
                ]
        )
    }

    @Test
    func changingOrRemovingLinkNoteInvalidatesOldEvidence()
        async throws
    {
        let fixture = try makeMedicalFixture()
        let result = try await fixture.tool.execute(
            GetNodeInput(
                node: fixture.patientNode,
                relatedLimit: 10
            ),
            context: fixture.toolContext
        )
        let oldEvidence = try #require(
            result.evidence.first {
                $0.sourceReference
                    .sourceKind == .link
            }
        )

        fixture.link.note = "2× täglich"
        try fixture.store.context.save()
        let changedValidation =
            try await fixture.validator
                .validatedEvidence(
                    [oldEvidence],
                    in: fixture.chatScope
                )
        #expect(changedValidation.isEmpty)

        fixture.link.note = nil
        try fixture.store.context.save()
        let removedValidation =
            try await fixture.validator
                .validatedEvidence(
                    [oldEvidence],
                    in: fixture.chatScope
                )
        #expect(removedValidation.isEmpty)
    }

    @Test
    func noteFactWithoutAuthoritativeLinkBindingIsRejected()
        async throws
    {
        let fixture = try makeMedicalFixture()
        let unboundEvidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID:
                    fixture.chatScope
                        .graphScope.graphID,
                sourceKind: .link,
                sourceID: fixture.link.id,
                node: GraphSourceNodeReference(
                    kind: fixture.patientNode.kind,
                    id: fixture.patientNode.id
                ),
                linkID: fixture.link.id
            ),
            summary: "Ungebundene Link-Notiz",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Link-Notiz",
                    value: .text("3× täglich"),
                    unit: nil
                ),
            ]
        )

        let validation =
            try await fixture.validator
                .validatedEvidence(
                    [unboundEvidence],
                    in: fixture.chatScope
                )

        #expect(validation.isEmpty)
    }

    @Test
    func deletingLinkInvalidatesLinkAndNoteEvidence()
        async throws
    {
        let fixture = try makeMedicalFixture()
        let result = try await fixture.tool.execute(
            GetNodeInput(
                node: fixture.patientNode,
                relatedLimit: 10
            ),
            context: fixture.toolContext
        )
        let oldEvidence = result.evidence.filter {
            $0.sourceReference.sourceKind == .link
        }
        #expect(oldEvidence.isEmpty == false)

        fixture.store.context.delete(fixture.link)
        try fixture.store.context.save()
        let validation =
            try await fixture.validator
                .validatedEvidence(
                    oldEvidence,
                    in: fixture.chatScope
                )

        #expect(validation.isEmpty)
    }

    @Test
    func identicalLinkIDInAnotherGraphCannotRevalidateEvidence()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let firstGraph = fixtures.makeGraph(
            name: "Medizin"
        )
        let secondGraph = fixtures.makeGraph(
            name: "Bibliothek"
        )
        let sharedLinkID = UUID()

        let firstSource = fixtures.makeEntity(
            name: "Patient",
            in: firstGraph
        )
        let firstTarget = fixtures.makeEntity(
            name: "Medikament",
            in: firstGraph
        )
        fixtures.makeLink(
            source: .entity(firstSource),
            target: .entity(firstTarget),
            note: "3× täglich",
            id: sharedLinkID
        )

        let secondSource = fixtures.makeEntity(
            name: "Buch",
            in: secondGraph
        )
        let secondTarget = fixtures.makeEntity(
            name: "Autor",
            in: secondGraph
        )
        fixtures.makeLink(
            source: .entity(secondSource),
            target: .entity(secondTarget),
            note: "geschrieben von",
            id: sharedLinkID
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let validator =
            GraphEvidenceSourceValidator(
                repository: repository
            )
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: firstGraph.id,
                sourceKind: .link,
                sourceID: sharedLinkID,
                node: GraphSourceNodeReference(
                    kind: .entity,
                    id: firstSource.id
                ),
                linkID: sharedLinkID,
                linkBinding:
                    GraphSourceLinkBinding(
                        linkID: sharedLinkID,
                        source:
                            GraphSourceNodeReference(
                                kind: .entity,
                                id: firstSource.id
                            ),
                        target:
                            GraphSourceNodeReference(
                                kind: .entity,
                                id: firstTarget.id
                            ),
                        direction: .outgoing,
                        note: "3× täglich"
                    )
            ),
            summary: "Patient → Medikament",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Link-Notiz",
                    value: .text("3× täglich"),
                    unit: nil
                ),
            ]
        )

        let firstGraphResult =
            try await validator.validatedEvidence(
                [evidence],
                in: .entireGraph(
                    GraphScope(
                        graphID: firstGraph.id
                    )
                )
            )
        let result =
            try await validator.validatedEvidence(
                [evidence],
                in: .entireGraph(
                    GraphScope(
                        graphID: secondGraph.id
                    )
                )
            )
        #expect(firstGraphResult == [evidence])
        #expect(result.isEmpty)
    }

    private func makeMedicalFixture()
        throws -> MedicalLinkFixture
    {
        let store =
            try BrainMeshTestContainer
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
        let patient = fixtures.makeAttribute(
            name: "Mara König",
            owner: patients
        )
        let medications = fixtures.makeEntity(
            name: "Medikamente",
            in: graph
        )
        let medication = fixtures.makeAttribute(
            name: "Amoxicillin",
            owner: medications
        )
        let link = fixtures.makeLink(
            source: .attribute(patient),
            target: .attribute(medication),
            note: "3× täglich"
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let validator =
            GraphEvidenceSourceValidator(
                repository: repository
            )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(graphScope)
        return MedicalLinkFixture(
            store: store,
            link: link,
            patientNode: NodeRefKey(
                kind: .attribute,
                id: patient.id
            ),
            medicationNode: NodeRefKey(
                kind: .attribute,
                id: medication.id
            ),
            validator: validator,
            tool: GetNodeTool(
                repository: repository,
                evidenceValidator: validator,
                logger:
                    NoOpGraphChatToolLogger()
            ),
            chatScope: chatScope,
            toolContext:
                GraphChatToolContext(
                    scope: chatScope,
                    budget:
                        GraphChatToolBudget()
                )
        )
    }
}

private struct MedicalLinkFixture {
    let store: BrainMeshTestStore
    let link: MetaLink
    let patientNode: NodeRefKey
    let medicationNode: NodeRefKey
    let validator: GraphEvidenceSourceValidator
    let tool: GetNodeTool
    let chatScope: GraphChatScope
    let toolContext: GraphChatToolContext
}
