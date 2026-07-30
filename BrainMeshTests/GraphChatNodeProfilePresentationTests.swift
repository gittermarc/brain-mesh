import Foundation
import SwiftData
import Testing

@testable import BrainMesh

@Suite("Graph chat node profile presentation")
struct GraphChatNodeProfilePresentationTests {
    @Test
    func factoryPreservesEveryProfileAreaAndIndependentWindow()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let draft = try #require(
            fixture.draft(
                output: fixture.fullOutput()
            )
        )
        guard
            case .nodeProfile(let payload) =
                draft.payload
        else {
            Issue.record(
                "Expected node profile payload"
            )
            return
        }

        #expect(payload.visibleName == "Patient A")
        #expect(
            payload.displayName
                == "Patient • Patient A"
        )
        #expect(payload.owner?.label == "Patient")
        #expect(
            payload.notes?.text
                == "Kontrolltermin geplant"
        )
        #expect(payload.detailValues.count == 2)
        #expect(
            payload.detailValues.map(
                \.fieldName
            ) == [
                "Versorgungsstatus",
                "Ruhepuls",
            ]
        )
        #expect(
            payload.incomingConnections
                .count == 1
        )
        #expect(
            payload.outgoingConnections
                .count == 1
        )
        #expect(
            payload.outgoingConnections
                .first?.note
                == "3× täglich"
        )
        #expect(payload.attachments.count == 1)
        #expect(
            payload.attachments.first?
                .contentTypeIdentifier
                == "com.adobe.pdf"
        )
        #expect(
            payload.detailValueMetadata
                .totalCount == 2
        )
        #expect(
            payload.incomingConnectionMetadata
                .totalCount == 1
        )
        #expect(
            payload.outgoingConnectionMetadata
                .totalCount == 1
        )
        #expect(
            payload.attachmentMetadata
                .totalCount == 1
        )
        #expect(
            payload.attachments.allSatisfy {
                $0.evidence.evidenceIDs
                    .isEmpty == false
            }
        )
        #expect(
            payload.attachments
                .flatMap {
                    $0.evidence.evidenceIDs
                }
                .allSatisfy {
                    draft.evidence
                        .evidenceIDs
                        .contains($0)
                }
        )
        #expect(
            draft.allNavigationTargets
                .allSatisfy {
                    $0.graphScope
                        == fixture.graphScope
                }
        )
        #expect(
            draft.allNavigationTargets
                .flatMap(
                    \.nodeReferences
                )
                .contains {
                    $0.id
                        == fixture.uuid(26)
                } == false
        )
    }

    @Test
    func germanAndEnglishPresentAllMedicalFactsWithoutTechnicalIdentifiers()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let payload = try fixture.payload(
            output: fixture.fullOutput()
        )
        let german =
            GraphChatNodeProfilePresentation(
                payload: payload,
                language: .german
            ).plainText
        let english =
            GraphChatNodeProfilePresentation(
                payload: payload,
                language: .english
            ).plainText

        for required in [
            "Patient A",
            "Kontrolltermin geplant",
            "Versorgungsstatus: Aktiv",
            "Ruhepuls: 72 bpm",
            "Medikament 3",
            "3× täglich",
            "Laborbericht",
            "patient-a-labor.pdf",
            "PDF",
        ] {
            #expect(german.contains(required))
            #expect(english.contains(required))
        }
        #expect(
            german.contains(
                "Link-Notiz: 3× täglich"
            )
        )
        #expect(
            english.contains(
                "Link note: 3× täglich"
            )
        )
        #expect(german.contains("Detailwerte"))
        #expect(
            english.contains("Detail values")
        )
        #expect(
            english.contains("Incoming links")
        )
        #expect(
            english.contains("Outgoing links")
        )
        for forbidden in [
            fixture.graphScope.graphID
                .uuidString,
            fixture.center.id.uuidString,
            "com.adobe.pdf",
            "E1",
            "F1",
            "CURRENT",
        ] {
            #expect(
                german.contains(forbidden)
                    == false
            )
            #expect(
                english.contains(forbidden)
                    == false
            )
        }
    }

    @Test
    func noteLinkAndAttachmentOnlyProfilesRemainSuccessful()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let notePayload = try fixture.payload(
            output: fixture.output(
                includesNotes: true,
                includesDetails: false,
                includesIncoming: false,
                includesOutgoing: false,
                includesAttachment: false
            )
        )
        let linkPayload = try fixture.payload(
            output: fixture.output(
                includesNotes: false,
                includesDetails: false,
                includesIncoming: false,
                includesOutgoing: true,
                includesAttachment: false
            )
        )
        let attachmentPayload =
            try fixture.payload(
                output: fixture.output(
                    includesNotes: false,
                    includesDetails: false,
                    includesIncoming: false,
                    includesOutgoing: false,
                    includesAttachment: true
                )
            )

        #expect(notePayload.notes != nil)
        #expect(
            notePayload.detailValues.isEmpty
        )
        #expect(
            linkPayload.outgoingConnections
                .first?.note
                == "3× täglich"
        )
        #expect(
            attachmentPayload.attachments
                .first?.title
                == "Laborbericht"
        )
        #expect(
            GraphChatNodeProfilePresentation(
                payload: notePayload,
                language: .german
            ).plainText.contains(
                "Kontrolltermin geplant"
            )
        )
        #expect(
            GraphChatNodeProfilePresentation(
                payload: linkPayload,
                language: .german
            ).plainText.contains(
                "Medikament 3"
            )
        )
        #expect(
            GraphChatNodeProfilePresentation(
                payload: attachmentPayload,
                language: .german
            ).plainText.contains(
                "patient-a-labor.pdf"
            )
        )
    }

    @Test
    func copyUsesTheSameFinalAnswerAndKeepsTheLinkNote()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let payload = try fixture.payload(
            output: fixture.fullOutput()
        )
        let finalText =
            GraphChatNodeProfilePresentation(
                payload: payload,
                language: .german
            ).plainText
        let answer = GraphChatAnswer(
            directAnswer: finalText,
            hasInsufficientEvidence: false
        )
        var state =
            GraphChatAssistantMessageState(
                question:
                    "Nenne mir Details zu Patient A"
            )
        state.apply(.completed(answer))
        let copy = try #require(
            GraphChatCopyContentBuilder.payload(
                for: state,
                sourcePolicy: .none
            )
        )

        #expect(copy.text == finalText)
        #expect(
            copy.text.contains(
                "Link-Notiz: 3× täglich"
            )
        )
    }

    @Test
    func truncationNoticesRemainVisibleAndSeparatedByProfileArea()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let output = fixture.output(
            detailWindow:
                fixture.window(
                    total: 47,
                    returned: 2
                ),
            incomingWindow:
                fixture.window(
                    total: 31,
                    returned: 1
                ),
            outgoingWindow:
                fixture.window(
                    total: 29,
                    returned: 1
                ),
            attachmentWindow:
                fixture.window(
                    total: 8,
                    returned: 1
                )
        )
        let payload = try fixture.payload(
            output: output
        )
        let german =
            GraphChatNodeProfilePresentation(
                payload: payload,
                language: .german
            ).plainText
        let english =
            GraphChatNodeProfilePresentation(
                payload: payload,
                language: .english
            ).plainText

        #expect(
            german.contains(
                "2 von 47 Detailwerten angezeigt"
            )
        )
        #expect(
            german.contains(
                "1 von 31 eingehenden Verbindungen angezeigt"
            )
        )
        #expect(
            german.contains(
                "1 von 29 ausgehenden Verbindungen angezeigt"
            )
        )
        #expect(
            german.contains(
                "1 von 8 Attachments angezeigt"
            )
        )
        #expect(
            english.contains(
                "2 of 47 detail values shown"
            )
        )
        #expect(
            english.contains(
                "1 of 31 incoming links shown"
            )
        )
        #expect(
            english.contains(
                "1 of 29 outgoing links shown"
            )
        )
        #expect(
            english.contains(
                "1 of 8 attachments shown"
            )
        )
    }

    @Test
    func evidenceProjectionRevalidatesEveryProfileAreaIndependently()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let artifact = try fixture.artifact(
            output: fixture.fullOutput()
        )
        let original = try fixture.profile(
            artifact
        )

        let withoutNotes = try fixture.profile(
            fixture.project(
                artifact,
                removing:
                    fixture.notesEvidenceID
            )
        )
        #expect(withoutNotes.notes == nil)
        #expect(
            withoutNotes.detailValues.count
                == original.detailValues.count
        )

        let withoutDetail = try fixture.profile(
            fixture.project(
                artifact,
                removing:
                    fixture.detailEvidenceIDs[0]
            )
        )
        #expect(
            withoutDetail.detailValues.count
                == original.detailValues.count - 1
        )
        #expect(
            withoutDetail
                .detailValueMetadata
                .truncation.reasons
                .contains(.sourceLimited)
        )

        let withoutIncoming =
            try fixture.profile(
                fixture.project(
                    artifact,
                    removing:
                        fixture
                        .incomingEvidenceID
                )
            )
        #expect(
            withoutIncoming
                .incomingConnections
                .isEmpty
        )
        #expect(
            withoutIncoming
                .outgoingConnections
                .count == 1
        )

        let withoutOutgoing =
            try fixture.profile(
                fixture.project(
                    artifact,
                    removing:
                        fixture
                        .outgoingEvidenceID
                )
            )
        #expect(
            withoutOutgoing
                .outgoingConnections
                .isEmpty
        )
        #expect(
            withoutOutgoing
                .incomingConnections
                .count == 1
        )

        let withoutAttachment =
            try fixture.profile(
                fixture.project(
                    artifact,
                    removing:
                        fixture
                        .attachmentEvidenceID
                )
            )
        #expect(
            withoutAttachment
                .attachments.isEmpty
        )
        #expect(
            withoutAttachment
                .attachmentMetadata
                .truncation.reasons
                .contains(.sourceLimited)
        )

        let retainedIdentity =
            Set(
                artifact.allEvidenceIDs
            ).subtracting([
                fixture.identityEvidenceID,
            ])
        #expect(
            GraphChatNodeProfileArtifactEvidenceProjector
                .revalidatedArtifact(
                    artifact,
                    availableEvidenceIDs:
                        retainedIdentity
                ) == nil
        )
    }

    @MainActor
    @Test
    func liveRevalidationDropsChangedAreasAndKeepsTheValidProfileRemainder()
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
                name: "Medizin"
            )
        let patients =
            fixtures.makeEntity(
                name: "Patient",
                in: graph
            )
        let patient =
            fixtures.makeAttribute(
                name: "Patient A",
                owner: patients,
                notes: "Alte Notiz"
            )
        let status =
            fixtures.makeDetailField(
                owner: patients,
                name: "Status",
                type: .singleLineText,
                sortIndex: 0
            )
        fixtures.makeDetailValue(
            attribute: patient,
            field: status,
            stringValue: "Aktiv"
        )
        let medications =
            fixtures.makeEntity(
                name: "Medikament",
                in: graph
            )
        let medication =
            fixtures.makeAttribute(
                name: "Medikament 3",
                owner: medications
            )
        fixtures.makeLink(
            source: .attribute(patient),
            target:
                .attribute(medication),
            note: "3× täglich"
        )
        let attachment =
            fixtures.makeAttachment(
                owner:
                    .attribute(patient),
                title: "Alter Bericht",
                originalFilename:
                    "bericht.pdf",
                contentTypeIdentifier:
                    "com.adobe.pdf",
                fileExtension: "pdf",
                byteCount: 2_048
            )
        try fixtures.save()

        let graphScope =
            GraphScope(graphID: graph.id)
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let repository =
            GraphReadRepository(
                container:
                    AnyModelContainer(
                        store.container
                    )
            )
        let validator =
            GraphEvidenceSourceValidator(
                repository: repository
            )
        let result =
            try await GetNodeTool(
                repository: repository,
                evidenceValidator:
                    validator,
                logger:
                    NoOpGraphChatToolLogger()
            ).execute(
                GetNodeInput(
                    node:
                        NodeRefKey(
                            kind: .attribute,
                            id: patient.id
                        ),
                    relatedLimit: 20
                ),
                context:
                    GraphChatToolContext(
                        scope: chatScope,
                        budget:
                            GraphChatToolBudget()
                    )
            )
        let output = try #require(
            result.payload
        )
        let draft = try #require(
            GraphChatAnswerArtifactFactory
                .nodeDetails(
                    output: output,
                    graphScope: graphScope,
                    language: .german
                )
        )
        let artifact =
            GraphChatAnswerArtifact(
                id:
                    GraphChatAnswerArtifactID(),
                sessionID:
                    GraphChatAnswerArtifactSessionID(),
                graphScope: graphScope,
                title: draft.title,
                payload: draft.payload,
                evidence: draft.evidence,
                navigationTargets:
                    draft.navigationTargets
            )

        patient.notes = "Neue Notiz"
        attachment.title = "Neuer Bericht"
        try store.context.save()

        let revalidated = try #require(
            try await GraphChatLiveAnswerArtifactRevalidator(
                evidenceValidator:
                    validator,
                sourceRepository:
                    repository
            ).revalidatedArtifact(
                artifact,
                evidence: result.evidence,
                in: chatScope
            )
        )
        let payload = try #require({
            if case .nodeProfile(let value) =
                revalidated.payload
            {
                return value
            }
            return nil
        }())
        #expect(payload.notes == nil)
        #expect(payload.attachments.isEmpty)
        #expect(payload.detailValues.count == 1)
        #expect(
            payload.outgoingConnections
                .count == 1
        )
        let text =
            GraphChatNodeProfilePresentation(
                payload: payload,
                language: .german
            ).plainText
        #expect(
            text.contains("Alte Notiz")
                == false
        )
        #expect(
            text.contains("Alter Bericht")
                == false
        )
        #expect(text.contains("Status: Aktiv"))
        #expect(text.contains("3× täglich"))
    }

    @Test
    func medicalLibraryAndTechnicalFixturesUseTheSameGenericFactory()
        throws
    {
        let fixture = NodeProfilePresentationFixture()
        let values = [
            (
                "Patient A",
                "Patient",
                "Nenne mir Details zu Patient A."
            ),
            (
                "Autorin Müller",
                "Autorinnen",
                "Beschreibe Autorin Müller vollständig."
            ),
            (
                "Service Gateway",
                "Services",
                "Was weißt du über Service Gateway?"
            ),
        ]

        for (
            name,
            owner,
            _
        ) in values {
            let output = fixture.output(
                name: name,
                owner: owner
            )
            let draft = try #require(
                fixture.draft(
                    output: output
                )
            )
            guard
                case .nodeProfile(let payload) =
                    draft.payload
            else {
                Issue.record(
                    "Expected the generic profile artifact"
                )
                continue
            }
            let text =
                GraphChatNodeProfilePresentation(
                    payload: payload,
                    language: .german
                ).plainText
            #expect(text.contains(name))
            #expect(text.contains(owner))
        }
    }
}

private struct NodeProfilePresentationFixture {
    let graphScope =
        GraphScope(
            graphID:
                UUID(
                    uuidString:
                        "C1000000-0000-0000-0000-000000000001"
                )!
        )
    let center =
        NodeRefKey(
            kind: .attribute,
            id:
                UUID(
                    uuidString:
                        "C1000000-0000-0000-0000-000000000002"
                )!
        )
    let patientOwnerID =
        UUID(
            uuidString:
                "C1000000-0000-0000-0000-000000000003"
        )!
    let incomingNode =
        NodeRefKey(
            kind: .attribute,
            id:
                UUID(
                    uuidString:
                        "C1000000-0000-0000-0000-000000000004"
                )!
        )
    let medicationNode =
        NodeRefKey(
            kind: .attribute,
            id:
                UUID(
                    uuidString:
                        "C1000000-0000-0000-0000-000000000005"
                )!
        )

    var identityEvidenceID: GraphEvidenceID {
        evidenceID(10)
    }
    var notesEvidenceID: GraphEvidenceID {
        evidenceID(11)
    }
    var detailEvidenceIDs:
        [GraphEvidenceID]
    {
        [
            evidenceID(12),
            evidenceID(13),
        ]
    }
    var incomingEvidenceID: GraphEvidenceID {
        evidenceID(14)
    }
    var outgoingEvidenceID: GraphEvidenceID {
        evidenceID(15)
    }
    var attachmentEvidenceID:
        GraphEvidenceID
    {
        evidenceID(16)
    }

    func fullOutput() -> GetNodeOutput {
        output()
    }

    func output(
        name: String = "Patient A",
        owner: String = "Patient",
        includesNotes: Bool = true,
        includesDetails: Bool = true,
        includesIncoming: Bool = true,
        includesOutgoing: Bool = true,
        includesAttachment: Bool = true,
        detailWindow:
            GraphChatResultWindow? = nil,
        incomingWindow:
            GraphChatResultWindow? = nil,
        outgoingWindow:
            GraphChatResultWindow? = nil,
        attachmentWindow:
            GraphChatResultWindow? = nil
    ) -> GetNodeOutput {
        let label = "\(owner) • \(name)"
        let details:
            [GraphChatNodeDetailValue]
        if includesDetails {
            details = [
                GraphChatNodeDetailValue(
                    valueID: uuid(20),
                    fieldID: uuid(21),
                    fieldName:
                        "Versorgungsstatus",
                    fieldType:
                        .singleLineText,
                    unit: nil,
                    value: .text("Aktiv"),
                    evidenceID:
                        detailEvidenceIDs[0]
                ),
                GraphChatNodeDetailValue(
                    valueID: uuid(22),
                    fieldID: uuid(23),
                    fieldName: "Ruhepuls",
                    fieldType:
                        .numberInt,
                    unit: "bpm",
                    value: .integer(72),
                    evidenceID:
                        detailEvidenceIDs[1]
                ),
            ]
        } else {
            details = []
        }

        var links:
            [GraphChatNodeLinkMetadata] = []
        if includesIncoming {
            links.append(
                GraphChatNodeLinkMetadata(
                    id: uuid(24),
                    direction: .incoming,
                    source: incomingNode,
                    sourceLabel:
                        "Praxis Nord",
                    target: center,
                    targetLabel: label,
                    note:
                        "behandelt",
                    evidenceID:
                        incomingEvidenceID
                )
            )
        }
        if includesOutgoing {
            links.append(
                GraphChatNodeLinkMetadata(
                    id: uuid(25),
                    direction: .outgoing,
                    source: center,
                    sourceLabel: label,
                    target: medicationNode,
                    targetLabel:
                        "Medikament 3",
                    note: "3× täglich",
                    evidenceID:
                        outgoingEvidenceID
                )
            )
        }

        let attachments:
            [GraphChatAttachmentMetadata]
        if includesAttachment {
            attachments = [
                GraphChatAttachmentMetadata(
                    id: uuid(26),
                    contentKind: .file,
                    title: "Laborbericht",
                    originalFilename:
                        "patient-a-labor.pdf",
                    contentTypeIdentifier:
                        "com.adobe.pdf",
                    fileExtension: "pdf",
                    byteCount: 4_096,
                    evidenceID:
                        attachmentEvidenceID
                ),
            ]
        } else {
            attachments = []
        }

        var evidenceIDs = [
            identityEvidenceID,
        ]
        if includesNotes {
            evidenceIDs.append(
                notesEvidenceID
            )
        }
        evidenceIDs.append(
            contentsOf:
                details.map(\.evidenceID)
        )
        evidenceIDs.append(
            contentsOf:
                links.map(\.evidenceID)
        )
        evidenceIDs.append(
            contentsOf:
                attachments.map(
                    \.evidenceID
                )
        )
        return GetNodeOutput(
            node: center,
            label: label,
            notes:
                includesNotes
                ? "Kontrolltermin geplant"
                : "",
            owner:
                GraphChatNodeOwner(
                    entityID:
                        patientOwnerID,
                    label: owner
                ),
            detailValues: details,
            links: links,
            attachments: attachments,
            evidenceIDs: evidenceIDs,
            visibleName: name,
            notesEvidenceID:
                includesNotes
                ? notesEvidenceID
                : nil,
            detailValueWindow:
                detailWindow
                ?? .complete(
                    totalCount:
                        details.count
                ),
            incomingLinkWindow:
                incomingWindow
                ?? .complete(
                    totalCount:
                        links.filter {
                            $0.direction
                                == .incoming
                        }.count
                ),
            outgoingLinkWindow:
                outgoingWindow
                ?? .complete(
                    totalCount:
                        links.filter {
                            $0.direction
                                == .outgoing
                        }.count
                ),
            attachmentWindow:
                attachmentWindow
                ?? .complete(
                    totalCount:
                        attachments.count
                ),
            hasNotes: includesNotes
        )
    }

    func window(
        total: Int,
        returned: Int
    ) -> GraphChatResultWindow {
        GraphChatResultWindow(
            totalCount: total,
            returnedCount: returned,
            limit: returned,
            limitReached: true,
            limitSource: .tool
        )
    }

    func draft(
        output: GetNodeOutput
    ) -> GraphChatAnswerArtifactDraft? {
        GraphChatAnswerArtifactFactory
            .nodeDetails(
                output: output,
                graphScope: graphScope,
                language: .german
            )
    }

    func payload(
        output: GetNodeOutput
    ) throws ->
        GraphChatAnswerArtifactNodeProfilePayload
    {
        let artifactDraft = try #require(
            draft(output: output)
        )
        guard
            case .nodeProfile(let payload) =
                artifactDraft.payload
        else {
            throw NodeProfileFixtureError
                .unexpectedPayload
        }
        return payload
    }

    func artifact(
        output: GetNodeOutput
    ) throws -> GraphChatAnswerArtifact {
        let artifactDraft = try #require(
            draft(output: output)
        )
        return GraphChatAnswerArtifact(
            id:
                GraphChatAnswerArtifactID(
                    rawValue: uuid(30)
                ),
            sessionID:
                GraphChatAnswerArtifactSessionID(
                    rawValue: uuid(31)
                ),
            graphScope: graphScope,
            title: artifactDraft.title,
            payload: artifactDraft.payload,
            evidence: artifactDraft.evidence,
            navigationTargets:
                artifactDraft.navigationTargets,
            querySummary:
                artifactDraft.querySummary
        )
    }

    func project(
        _ artifact: GraphChatAnswerArtifact,
        removing evidenceID: GraphEvidenceID
    ) throws -> GraphChatAnswerArtifact {
        let available =
            Set(
                artifact.allEvidenceIDs
            ).subtracting([
                evidenceID,
            ])
        return try #require(
            GraphChatNodeProfileArtifactEvidenceProjector
                .revalidatedArtifact(
                    artifact,
                    availableEvidenceIDs:
                        available
                )
        )
    }

    func profile(
        _ artifact: GraphChatAnswerArtifact
    ) throws ->
        GraphChatAnswerArtifactNodeProfilePayload
    {
        guard
            case .nodeProfile(let payload) =
                artifact.payload
        else {
            throw NodeProfileFixtureError
                .unexpectedPayload
        }
        return payload
    }

    func evidenceID(_ value: Int)
        -> GraphEvidenceID
    {
        GraphEvidenceID(
            rawValue: uuid(value)
        )
    }

    func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format:
                    "C1000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}

private enum NodeProfileFixtureError:
    Error
{
    case unexpectedPayload
}
