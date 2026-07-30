import Foundation
import Testing

@testable import BrainMesh

@Suite("Authoritative graph node profiles")
struct GraphNodeProfileRepositoryTests {
    @Test
    func smallEntityAndAttributeProfilesAreCompleteAcrossDomainFixtures()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Fachdomänen"
        )

        let patients = fixtures.makeEntity(
            name: "Patienten",
            in: graph,
            notes: "Medizin"
        )
        let patient = fixtures.makeAttribute(
            name: "Mara König",
            owner: patients,
            notes: "Stationär"
        )
        let medication = fixtures.makeDetailField(
            owner: patients,
            name: "Medikation",
            type: .singleLineText,
            sortIndex: 0
        )
        fixtures.makeDetailValue(
            attribute: patient,
            field: medication,
            stringValue: "Amoxicillin"
        )

        let books = fixtures.makeEntity(
            name: "Bücher",
            in: graph
        )
        let book = fixtures.makeAttribute(
            name: "Der Name der Rose",
            owner: books
        )
        let author = fixtures.makeDetailField(
            owner: books,
            name: "Autor",
            type: .singleLineText,
            sortIndex: 0
        )
        fixtures.makeDetailValue(
            attribute: book,
            field: author,
            stringValue: "Umberto Eco"
        )

        let services = fixtures.makeEntity(
            name: "Services",
            in: graph
        )
        let service = fixtures.makeAttribute(
            name: "Checkout API",
            owner: services
        )
        let status = fixtures.makeDetailField(
            owner: services,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Operational", "Degraded"]
        )
        fixtures.makeDetailValue(
            attribute: service,
            field: status,
            stringValue: "Operational"
        )
        let entityLink = fixtures.makeLink(
            source: .entity(patients),
            target: .entity(services),
            note: "Klinischer Service"
        )
        let attributeLink = fixtures.makeLink(
            source: .attribute(patient),
            target: .attribute(service),
            note: "Überwacht"
        )
        let entityAttachment =
            fixtures.makeAttachment(
                owner: .entity(patients),
                title: "Stationsübersicht",
                originalFilename: "station.pdf",
                contentTypeIdentifier:
                    "com.adobe.pdf",
                fileExtension: "pdf",
                byteCount: 12
            )
        let attributeAttachment =
            fixtures.makeAttachment(
                owner: .attribute(patient),
                title: "Medikationsplan",
                originalFilename:
                    "medikationsplan.pdf",
                contentTypeIdentifier:
                    "com.adobe.pdf",
                fileExtension: "pdf",
                byteCount: 24
            )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let scope = GraphScope(graphID: graph.id)
        let limits = GraphNodeProfileLimits(
            detailValueLimit: 10,
            incomingConnectionLimit: 10,
            outgoingConnectionLimit: 10,
            attachmentLimit: 10
        )

        let entityProfile = try #require(
            try await repository.nodeProfile(
                patients.nodeKey,
                in: scope,
                limits: limits
            )
        )
        let medicineProfile = try #require(
            try await repository.nodeProfile(
                patient.nodeKey,
                in: scope,
                limits: limits
            )
        )
        let libraryProfile = try #require(
            try await repository.nodeProfile(
                book.nodeKey,
                in: scope,
                limits: limits
            )
        )
        let operationsProfile = try #require(
            try await repository.nodeProfile(
                service.nodeKey,
                in: scope,
                limits: limits
            )
        )

        #expect(entityProfile.scope == scope)
        #expect(entityProfile.kind == .entity)
        #expect(entityProfile.visibleName == "Patienten")
        #expect(entityProfile.ownerEntity == nil)
        #expect(entityProfile.notes == "Medizin")
        #expect(
            entityProfile.outgoingConnections
                .map(\.linkID) == [entityLink.id]
        )
        #expect(
            entityProfile.attachments.map(\.id)
                == [entityAttachment.id]
        )
        #expect(
            entityProfile.detailValueWindow
                .totalCount == 0
        )

        #expect(medicineProfile.kind == .attribute)
        #expect(
            medicineProfile.ownerEntity
                == GraphNodeProfileOwner(
                    entityID: patients.id,
                    visibleName: "Patienten"
                )
        )
        #expect(
            medicineProfile.detailValues
                .map(\.value)
                == [.text("Amoxicillin")]
        )
        #expect(
            medicineProfile.outgoingConnections
                .map(\.linkID) == [attributeLink.id]
        )
        #expect(
            medicineProfile.attachments.map(\.id)
                == [attributeAttachment.id]
        )
        #expect(
            libraryProfile.detailValues
                .map(\.value)
                == [.text("Umberto Eco")]
        )
        #expect(
            operationsProfile.detailValues
                .map(\.value)
                == [.choice("Operational")]
        )
        #expect(
            [
                medicineProfile,
                libraryProfile,
                operationsProfile,
            ].allSatisfy {
                $0.detailValueWindow
                    .limitReached == false
                    && $0.incomingConnectionWindow
                        .limitReached == false
                    && $0.outgoingConnectionWindow
                        .limitReached == false
                    && $0.attachmentWindow
                        .limitReached == false
            }
        )
    }

    @Test
    func independentWindowsPreventDetailsOrLinksFromDisplacingOtherAreas()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "IT Operations"
        )
        let services = fixtures.makeEntity(
            name: "Services",
            in: graph
        )
        let center = fixtures.makeAttribute(
            name: "Checkout API",
            owner: services
        )

        for index in 0..<5 {
            let field = fixtures.makeDetailField(
                owner: services,
                name: "Signal \(index)",
                type: .numberInt,
                sortIndex: index
            )
            fixtures.makeDetailValue(
                attribute: center,
                field: field,
                intValue: index
            )
        }
        for index in 0..<4 {
            let incoming = fixtures.makeEntity(
                name: "Incoming \(index)",
                in: graph
            )
            fixtures.makeLink(
                source: .entity(incoming),
                target: .attribute(center)
            )
            let outgoing = fixtures.makeEntity(
                name: "Outgoing \(index)",
                in: graph
            )
            fixtures.makeLink(
                source: .attribute(center),
                target: .entity(outgoing)
            )
        }
        for index in 0..<3 {
            fixtures.makeAttachment(
                owner: .attribute(center),
                title: "Runbook \(index)",
                originalFilename:
                    "runbook-\(index).pdf",
                contentTypeIdentifier:
                    "com.adobe.pdf",
                fileExtension: "pdf",
                byteCount: index + 1,
                fileData: Data(
                    repeating: UInt8(index),
                    count: index + 1
                )
            )
        }
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let profile = try #require(
            try await repository.nodeProfile(
                center.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits: GraphNodeProfileLimits(
                    detailValueLimit: 1,
                    incomingConnectionLimit: 2,
                    outgoingConnectionLimit: 3,
                    attachmentLimit: 2
                )
            )
        )

        #expect(profile.detailValues.count == 1)
        #expect(profile.incomingConnections.count == 2)
        #expect(profile.outgoingConnections.count == 3)
        #expect(profile.attachments.count == 2)
        #expect(
            profile.detailValueWindow
                == GraphNodeProfileResultWindow(
                    totalCount: 5,
                    returnedCount: 1,
                    limit: 1
                )
        )
        #expect(
            profile.incomingConnectionWindow
                == GraphNodeProfileResultWindow(
                    totalCount: 4,
                    returnedCount: 2,
                    limit: 2
                )
        )
        #expect(
            profile.outgoingConnectionWindow
                == GraphNodeProfileResultWindow(
                    totalCount: 4,
                    returnedCount: 3,
                    limit: 3
                )
        )
        #expect(
            profile.attachmentWindow
                == GraphNodeProfileResultWindow(
                    totalCount: 3,
                    returnedCount: 2,
                    limit: 2
                )
        )
        #expect(
            profile.detailValueWindow.limitSource
                == .appPolicy
        )
        #expect(
            profile.incomingConnectionWindow
                .limitSource == .appPolicy
        )
        #expect(
            profile.outgoingConnectionWindow
                .limitSource == .appPolicy
        )
        #expect(
            profile.attachmentWindow.limitSource
                == .appPolicy
        )
        #expect(profile.directLinkCount == 8)
    }

    @Test
    func connectionsCarryAuthoritativeEndpointsCounterpartsDirectionsAndNote()
        async throws
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
        let plans = fixtures.makeEntity(
            name: "Therapiepläne",
            in: graph
        )
        let plan = fixtures.makeAttribute(
            name: "Plan A",
            owner: plans
        )
        let outgoing = fixtures.makeLink(
            source: .attribute(patient),
            target: .attribute(medication),
            note: "3× täglich"
        )
        let incoming = fixtures.makeLink(
            source: .attribute(plan),
            target: .attribute(patient),
            note: "Freigabe erforderlich"
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let profile = try #require(
            try await repository.nodeProfile(
                patient.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits:
                    GraphChatIntentLimitPolicy
                        .default
                        .defaultNodeProfileLimits
            )
        )
        let outgoingConnection = try #require(
            profile.outgoingConnections.first
        )
        let incomingConnection = try #require(
            profile.incomingConnections.first
        )

        #expect(
            outgoingConnection.linkID
                == outgoing.id
        )
        #expect(
            outgoingConnection.direction
                == .outgoing
        )
        #expect(
            outgoingConnection.sourceReference
                == patient.nodeKey
        )
        #expect(
            outgoingConnection.targetReference
                == medication.nodeKey
        )
        #expect(
            outgoingConnection.counterpart
                .nodeKey == medication.nodeKey
        )
        #expect(
            outgoingConnection.counterpart
                .ownerEntity?.visibleName
                == "Medikamente"
        )
        #expect(
            outgoingConnection.note
                == "3× täglich"
        )

        #expect(
            incomingConnection.linkID
                == incoming.id
        )
        #expect(
            incomingConnection.direction
                == .incoming
        )
        #expect(
            incomingConnection.sourceReference
                == plan.nodeKey
        )
        #expect(
            incomingConnection.targetReference
                == patient.nodeKey
        )
        #expect(
            incomingConnection.counterpart
                .nodeKey == plan.nodeKey
        )
        #expect(
            incomingConnection.counterpart
                .ownerEntity?.visibleName
                == "Therapiepläne"
        )
    }

    @Test
    func integrityConflictsAndWrongTypedSlotsNeverBecomeProfileFacts()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Bibliothek"
        )
        let books = fixtures.makeEntity(
            name: "Bücher",
            in: graph
        )
        let book = fixtures.makeAttribute(
            name: "Der Name der Rose",
            owner: books
        )
        let status = fixtures.makeDetailField(
            owner: books,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Gelesen", "Offen"]
        )
        fixtures.makeDetailValue(
            attribute: book,
            field: status,
            stringValue: "Gelesen",
            id: profileTestUUID(1)
        )
        fixtures.makeDetailValue(
            attribute: book,
            field: status,
            stringValue: "Offen",
            id: profileTestUUID(2)
        )
        let pages = fixtures.makeDetailField(
            owner: books,
            name: "Seiten",
            type: .numberInt,
            sortIndex: 1
        )
        fixtures.makeDetailValue(
            attribute: book,
            field: pages,
            stringValue: "falsch",
            intValue: 536
        )
        let author = fixtures.makeDetailField(
            owner: books,
            name: "Autor",
            type: .singleLineText,
            sortIndex: 2
        )
        fixtures.makeDetailValue(
            attribute: book,
            field: author,
            stringValue: "Umberto Eco"
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let profile = try #require(
            try await repository.nodeProfile(
                book.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits:
                    GraphChatIntentLimitPolicy
                        .default
                        .defaultNodeProfileLimits
            )
        )

        #expect(
            profile.detailValues.map(\.fieldID)
                == [author.id]
        )
        #expect(
            profile.detailValues.map(\.value)
                == [.text("Umberto Eco")]
        )
        #expect(
            profile.detailValues.contains {
                $0.fieldID == status.id
                    || $0.fieldID == pages.id
            } == false
        )
    }

    @Test
    func attachmentProfileContainsMetadataButNoBinaryOrLocalContent()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "IT Operations"
        )
        let services = fixtures.makeEntity(
            name: "Services",
            in: graph
        )
        let service = fixtures.makeAttribute(
            name: "Payments API",
            owner: services
        )
        let secret = "BINARY-NOT-FOR-GRAPH-CHAT"
        fixtures.makeAttachment(
            owner: .attribute(service),
            contentKind: .file,
            title: "Runbook",
            originalFilename: "runbook.pdf",
            contentTypeIdentifier:
                "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: secret.utf8.count,
            fileData: Data(secret.utf8),
            localPath: "private-cache/runbook.pdf"
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let profile = try #require(
            try await repository.nodeProfile(
                service.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits:
                    GraphChatIntentLimitPolicy
                        .default
                        .defaultNodeProfileLimits
            )
        )
        let metadata = try #require(
            profile.attachments.first
        )
        let children = Mirror(
            reflecting: metadata
        ).children

        #expect(metadata.title == "Runbook")
        #expect(
            metadata.originalFilename
                == "runbook.pdf"
        )
        #expect(
            children.contains {
                $0.label == "fileData"
                    || $0.label == "localPath"
                    || $0.value is Data
            } == false
        )
        #expect(
            String(describing: profile)
                .contains(secret) == false
        )
        #expect(
            String(describing: profile)
                .contains("private-cache")
                == false
        )
    }

    @Test
    func emptyNodeAreasRemainCompleteAndExplicit()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Leerer Graph"
        )
        let entity = fixtures.makeEntity(
            name: "Leer",
            in: graph
        )
        let attribute = fixtures.makeAttribute(
            name: "Ohne Details",
            owner: entity
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let limits =
            GraphChatIntentLimitPolicy
                .default
                .defaultNodeProfileLimits
        let entityProfile = try #require(
            try await repository.nodeProfile(
                entity.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits: limits
            )
        )
        let attributeProfile = try #require(
            try await repository.nodeProfile(
                attribute.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits: limits
            )
        )

        for profile in [
            entityProfile,
            attributeProfile,
        ] {
            #expect(profile.notes.isEmpty)
            #expect(profile.hasNotes == false)
            #expect(profile.detailValues.isEmpty)
            #expect(
                profile.incomingConnections.isEmpty
            )
            #expect(
                profile.outgoingConnections.isEmpty
            )
            #expect(profile.attachments.isEmpty)
            #expect(
                profile.detailValueWindow.totalCount
                    == 0
            )
            #expect(
                profile.incomingConnectionWindow
                    .totalCount == 0
            )
            #expect(
                profile.outgoingConnectionWindow
                    .totalCount == 0
            )
            #expect(
                profile.attachmentWindow.totalCount
                    == 0
            )
        }
    }

    @Test
    func profileOrderingUsesStableDomainAndUUIDTieBreakers()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Deterministisch"
        )
        let entities = fixtures.makeEntity(
            name: "Einträge",
            in: graph
        )
        let center = fixtures.makeAttribute(
            name: "Zentrum",
            owner: entities
        )
        let firstField = fixtures.makeDetailField(
            owner: entities,
            name: "Gleich",
            type: .singleLineText,
            sortIndex: 0,
            id: profileTestUUID(11)
        )
        let secondField = fixtures.makeDetailField(
            owner: entities,
            name: "Gleich",
            type: .singleLineText,
            sortIndex: 0,
            id: profileTestUUID(12)
        )
        fixtures.makeDetailValue(
            attribute: center,
            field: secondField,
            stringValue: "Zwei",
            id: profileTestUUID(22)
        )
        fixtures.makeDetailValue(
            attribute: center,
            field: firstField,
            stringValue: "Eins",
            id: profileTestUUID(21)
        )

        let targetA = fixtures.makeEntity(
            name: "A",
            in: graph
        )
        let targetB = fixtures.makeEntity(
            name: "B",
            in: graph
        )
        let sharedDate = Date(
            timeIntervalSince1970: 1_700_000_000
        )
        let secondLink = fixtures.makeLink(
            source: .attribute(center),
            target: .entity(targetB),
            id: profileTestUUID(32)
        )
        secondLink.createdAt = sharedDate
        let firstLink = fixtures.makeLink(
            source: .attribute(center),
            target: .entity(targetA),
            id: profileTestUUID(31)
        )
        firstLink.createdAt = sharedDate

        let secondAttachment = fixtures.makeAttachment(
            owner: .attribute(center),
            title: "B",
            id: profileTestUUID(42)
        )
        secondAttachment.createdAt = sharedDate
        let firstAttachment = fixtures.makeAttachment(
            owner: .attribute(center),
            title: "A",
            id: profileTestUUID(41)
        )
        firstAttachment.createdAt = sharedDate
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let profile = try #require(
            try await repository.nodeProfile(
                center.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits:
                    GraphChatIntentLimitPolicy
                        .default
                        .defaultNodeProfileLimits
            )
        )

        #expect(
            profile.detailValues.map(\.fieldID)
                == [
                    firstField.id,
                    secondField.id,
                ]
        )
        #expect(
            profile.outgoingConnections
                .map(\.linkID)
                == [
                    firstLink.id,
                    secondLink.id,
                ]
        )
        #expect(
            profile.attachments.map(\.id)
                == [
                    firstAttachment.id,
                    secondAttachment.id,
                ]
        )
    }

    @Test
    func repositoryRejectsLimitsOutsideCentralAppPolicy()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Policy"
        )
        let entity = fixtures.makeEntity(
            name: "Entity",
            in: graph
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container)
        )
        let policy =
            GraphChatIntentLimitPolicy.default

        await #expect(
            throws:
                GraphNodeProfileReadError
                    .invalidLimits
        ) {
            _ = try await repository.nodeProfile(
                entity.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits: GraphNodeProfileLimits(
                    detailValueLimit:
                        policy
                            .nodeProfileDetailValueCount
                        + 1,
                    incomingConnectionLimit: 0,
                    outgoingConnectionLimit: 0,
                    attachmentLimit: 0
                )
            )
        }
    }

    @Test
    func cancellationDuringMultipartProfileLoadReturnsNoPartialProfile()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Cancellation"
        )
        let entity = fixtures.makeEntity(
            name: "Messwerte",
            in: graph
        )
        let attribute = fixtures.makeAttribute(
            name: "Großer Node",
            owner: entity
        )
        for index in 0..<128 {
            let field = fixtures.makeDetailField(
                owner: entity,
                name: "Feld \(index)",
                type: .numberInt,
                sortIndex: index
            )
            fixtures.makeDetailValue(
                attribute: attribute,
                field: field,
                intValue: index
            )
        }
        let peer = fixtures.makeEntity(
            name: "Peer",
            in: graph
        )
        fixtures.makeLink(
            source: .attribute(attribute),
            target: .entity(peer)
        )
        fixtures.makeAttachment(
            owner: .attribute(attribute)
        )
        try fixtures.save()

        let trigger =
            GraphNodeProfileCancellationTrigger(
                triggerAtCheck: 15
            )
        let repository = GraphReadRepository(
            container:
                AnyModelContainer(store.container),
            cancellationCheck: {
                try trigger.check()
            }
        )

        var receivedCancellation = false
        do {
            _ = try await repository.nodeProfile(
                attribute.nodeKey,
                in: GraphScope(graphID: graph.id),
                limits:
                    GraphChatIntentLimitPolicy
                        .default
                        .defaultNodeProfileLimits
            )
        } catch is CancellationError {
            receivedCancellation = true
        }

        #expect(receivedCancellation)
        #expect(trigger.checkCount >= 15)
    }
}

private nonisolated func profileTestUUID(
    _ value: Int
) -> UUID {
    UUID(
        uuidString: String(
            format:
                "A1000000-0000-0000-0000-%012d",
            value
        )
    )!
}

private extension MetaEntity {
    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .entity, id: id)
    }
}

private extension MetaAttribute {
    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .attribute, id: id)
    }
}

private nonisolated final class
    GraphNodeProfileCancellationTrigger:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let triggerAtCheck: Int
    private var storedCheckCount = 0

    init(triggerAtCheck: Int) {
        self.triggerAtCheck = triggerAtCheck
    }

    var checkCount: Int {
        lock.withLock {
            storedCheckCount
        }
    }

    func check() throws {
        let shouldCancel = lock.withLock {
            storedCheckCount += 1
            return storedCheckCount
                == triggerAtCheck
        }
        if shouldCancel {
            throw CancellationError()
        }
    }
}
