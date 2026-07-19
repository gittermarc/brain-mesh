import Foundation
import Testing
@testable import BrainMesh

struct BrainMeshSearchCandidateProviderTests {

    @Test
    func providerRegistryUsesDeterministicSourceOrder() {
        let sources = BrainMeshSearchCandidateProviders.ordered.map { $0.source }

        #expect(sources == [.entity, .attribute, .link, .detail, .attachment])
    }

    @Test
    func entityProviderRespectsGraphScopeAndFindsNameAndNotes() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let nameMatch = fixtures.makeEntity(name: "Atlas", in: primaryGraph)
        let noteMatch = fixtures.makeEntity(
            name: "Beacon",
            in: primaryGraph,
            notes: "Atlas appears in this note"
        )
        let secondaryMatch = fixtures.makeEntity(name: "Atlas", in: secondaryGraph)
        try fixtures.save()

        let candidates = try providerCandidates(
            EntitySearchCandidateProvider(),
            in: store,
            graphID: primaryGraph.id,
            term: "atlas"
        )

        #expect(Set(candidates.map(\.result.id)) == Set([nameMatch.id, noteMatch.id]))
        #expect(candidates.allSatisfy { $0.result.graphID == primaryGraph.id })
        #expect(candidates.contains { $0.result.id == nameMatch.id && $0.result.matchReason == "Name" })
        #expect(candidates.contains { $0.result.id == noteMatch.id && $0.result.matchReason == "Notiz" })
        #expect(candidates.contains { $0.result.id == secondaryMatch.id } == false)
    }

    @Test
    func attributeProviderRespectsGraphScopeAndFindsOwnerLabelAndNotes() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let primaryOwner = fixtures.makeEntity(name: "Project Orion", in: primaryGraph)
        let noteOwner = fixtures.makeEntity(name: "Project Vega", in: primaryGraph)
        let secondaryOwner = fixtures.makeEntity(name: "Project Orion", in: secondaryGraph)
        let ownerLabelMatch = fixtures.makeAttribute(name: "Launch Date", owner: primaryOwner)
        let noteMatch = fixtures.makeAttribute(
            name: "Budget",
            owner: noteOwner,
            notes: "Orbit marker"
        )
        let secondaryMatch = fixtures.makeAttribute(name: "Launch Date", owner: secondaryOwner)
        try fixtures.save()

        let ownerCandidates = try providerCandidates(
            AttributeSearchCandidateProvider(),
            in: store,
            graphID: primaryGraph.id,
            term: "orion"
        )
        let noteCandidates = try providerCandidates(
            AttributeSearchCandidateProvider(),
            in: store,
            graphID: primaryGraph.id,
            term: "orbit"
        )

        #expect(ownerCandidates.map(\.result.id) == [ownerLabelMatch.id])
        #expect(ownerCandidates.first?.result.subtitle == "Project Orion")
        #expect(ownerCandidates.first?.result.ownerNodeKey == NodeKey(kind: .entity, uuid: primaryOwner.id))
        #expect(noteCandidates.map(\.result.id) == [noteMatch.id])
        #expect(noteCandidates.first?.result.matchReason == "Notiz")
        #expect(ownerCandidates.contains { $0.result.id == secondaryMatch.id } == false)
    }

    @Test
    func linkProviderFindsSourceTargetAndNoteWithinGraphScope() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let source = fixtures.makeEntity(name: "Atlas", in: primaryGraph)
        let target = fixtures.makeEntity(name: "Beacon", in: primaryGraph)
        let link = fixtures.makeLink(
            source: .entity(source),
            target: .entity(target),
            note: "Orbit marker"
        )
        let secondarySource = fixtures.makeEntity(name: "Atlas", in: secondaryGraph)
        let secondaryTarget = fixtures.makeEntity(name: "Beacon", in: secondaryGraph)
        let secondaryLink = fixtures.makeLink(
            source: .entity(secondarySource),
            target: .entity(secondaryTarget),
            note: "Orbit marker"
        )
        try fixtures.save()

        let sourceCandidates = try providerCandidates(
            LinkSearchCandidateProvider(),
            in: store,
            graphID: primaryGraph.id,
            term: "atlas"
        )
        let targetCandidates = try providerCandidates(
            LinkSearchCandidateProvider(),
            in: store,
            graphID: primaryGraph.id,
            term: "beacon"
        )
        let noteCandidates = try providerCandidates(
            LinkSearchCandidateProvider(),
            in: store,
            graphID: primaryGraph.id,
            term: "orbit"
        )

        #expect(sourceCandidates.map(\.result.id) == [link.id])
        #expect(sourceCandidates.first?.result.matchReason == "Quell-Label")
        #expect(targetCandidates.map(\.result.id) == [link.id])
        #expect(targetCandidates.first?.result.matchReason == "Ziel-Label")
        #expect(noteCandidates.map(\.result.id) == [link.id])
        #expect(noteCandidates.first?.result.matchReason == "Link-Notiz")
        #expect(sourceCandidates.contains { $0.result.id == secondaryLink.id } == false)
    }

    @Test
    func detailProviderFindsDefinitionsAndEveryTypedValue() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: primaryGraph)
        let attribute = fixtures.makeAttribute(name: "Plan", owner: owner)

        let definition = fixtures.makeDetailField(
            owner: owner,
            name: "Risk Level",
            type: .singleLineText,
            sortIndex: 0
        )
        let stringField = fixtures.makeDetailField(
            owner: owner,
            name: "Status",
            type: .singleLineText,
            sortIndex: 1
        )
        let intField = fixtures.makeDetailField(
            owner: owner,
            name: "Count",
            type: .numberInt,
            sortIndex: 2
        )
        let doubleField = fixtures.makeDetailField(
            owner: owner,
            name: "Ratio",
            type: .numberDouble,
            sortIndex: 3
        )
        let dateField = fixtures.makeDetailField(
            owner: owner,
            name: "Milestone",
            type: .date,
            sortIndex: 4
        )
        let boolField = fixtures.makeDetailField(
            owner: owner,
            name: "Approved",
            type: .toggle,
            sortIndex: 5
        )
        let choiceField = fixtures.makeDetailField(
            owner: owner,
            name: "Priority",
            type: .singleChoice,
            sortIndex: 6,
            options: ["Urgent", "Normal"]
        )

        let stringValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: stringField,
            stringValue: "Gold rollout"
        )
        let intValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: intField,
            intValue: 42
        )
        let doubleValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: doubleField,
            doubleValue: 12.5
        )
        let date = Date(timeIntervalSince1970: 1_772_841_600)
        let dateValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: dateField,
            dateValue: date
        )
        let boolValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: boolField,
            boolValue: true
        )
        let choiceValue = fixtures.makeDetailValue(
            attribute: attribute,
            field: choiceField,
            stringValue: "Urgent"
        )

        let secondaryOwner = fixtures.makeEntity(name: "Secondary Owner", in: secondaryGraph)
        let secondaryDefinition = fixtures.makeDetailField(
            owner: secondaryOwner,
            name: "Risk Level",
            type: .singleLineText,
            sortIndex: 0
        )
        try fixtures.save()

        let provider = DetailSearchCandidateProvider()
        let definitionCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "risk"
        )
        let stringCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "gold"
        )
        let intCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "42"
        )
        let doubleCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "12.5"
        )
        let dateCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: BrainMeshSearchDetailValueFormatter.isoDateText(date)
        )
        let boolCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "true"
        )
        let choiceCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "urgent"
        )

        #expect(definitionCandidates.contains { $0.result.id == definition.id })
        #expect(definitionCandidates.contains { $0.result.id == secondaryDefinition.id } == false)
        #expect(stringCandidates.contains { $0.result.id == stringValue.id })
        #expect(intCandidates.contains { $0.result.id == intValue.id })
        #expect(doubleCandidates.contains { $0.result.id == doubleValue.id })
        #expect(dateCandidates.contains { $0.result.id == dateValue.id })
        #expect(boolCandidates.contains { $0.result.id == boolValue.id })
        #expect(choiceCandidates.contains { $0.result.id == choiceValue.id })
        #expect(boolCandidates.first { $0.result.id == boolValue.id }?.result.title == "Approved: Ja")
    }

    @Test
    func detailValueFormatterPreservesDateBoolAndDisplaySemantics() {
        let date = Date(timeIntervalSince1970: 1_772_841_600)
        let components = BrainMeshSearchDetailValueContent(
            dateValue: date,
            boolValue: false
        )
        let rankingFields = BrainMeshSearchDetailValueFormatter.rankingFields(for: components)

        #expect(BrainMeshSearchDetailValueFormatter.localizedBoolText(true) == "Ja")
        #expect(BrainMeshSearchDetailValueFormatter.localizedBoolText(false) == "Nein")
        #expect(BrainMeshSearchDetailValueFormatter.metadataBoolText(true) == "true")
        #expect(BrainMeshSearchDetailValueFormatter.metadataBoolText(false) == "false")
        #expect(
            rankingFields.contains {
                $0.text == BrainMeshSearchDetailValueFormatter.localizedDateText(date)
                    && $0.priority == .primaryLabel
            }
        )
        #expect(
            rankingFields.contains {
                $0.text == BrainMeshSearchDetailValueFormatter.isoDateText(date)
                    && $0.priority == .metadata
            }
        )
        #expect(rankingFields.contains { $0.text == "Nein" && $0.priority == .primaryLabel })
        #expect(rankingFields.contains { $0.text == "false" && $0.priority == .metadata })
        #expect(
            BrainMeshSearchDetailValueFormatter.displayText(for: components)
                == BrainMeshSearchDetailValueFormatter.localizedDateText(date)
        )
    }

    @Test
    func attachmentProviderSearchesOnlyMetadataAndRespectsGraphScope() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let primaryOwner = fixtures.makeEntity(name: "Primary Owner", in: primaryGraph)
        let secondaryOwner = fixtures.makeEntity(name: "Secondary Owner", in: secondaryGraph)
        let attachment = fixtures.makeAttachment(
            owner: .entity(primaryOwner),
            contentKind: .video,
            title: "Launch Blueprint",
            originalFilename: "orbital-manifest",
            contentTypeIdentifier: "com.brainmesh.specialtype",
            fileExtension: "bmxarchive",
            fileData: Data("payloadonlyneedle".utf8)
        )
        let secondaryAttachment = fixtures.makeAttachment(
            owner: .entity(secondaryOwner),
            title: "Launch Blueprint",
            originalFilename: "orbital-manifest",
            contentTypeIdentifier: "com.brainmesh.specialtype",
            fileExtension: "bmxarchive"
        )
        try fixtures.save()

        let provider = AttachmentSearchCandidateProvider()
        let titleCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "launch"
        )
        let filenameCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "orbital"
        )
        let extensionCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "bmxarchive"
        )
        let typeCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "specialtype"
        )
        let payloadCandidates = try providerCandidates(
            provider,
            in: store,
            graphID: primaryGraph.id,
            term: "payloadonlyneedle"
        )

        #expect(titleCandidates.map(\.result.id) == [attachment.id])
        #expect(filenameCandidates.map(\.result.id) == [attachment.id])
        #expect(extensionCandidates.map(\.result.id) == [attachment.id])
        #expect(typeCandidates.map(\.result.id) == [attachment.id])
        #expect(payloadCandidates.isEmpty)
        #expect(titleCandidates.first?.result.iconSymbolName == "video")
        #expect(titleCandidates.first?.result.ownerNodeKey == NodeKey(kind: .entity, uuid: primaryOwner.id))
        #expect(titleCandidates.contains { $0.result.id == secondaryAttachment.id } == false)
    }

    @Test
    func providersRejectCancellationWithoutReturningPartialResults() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)
        let attribute = fixtures.makeAttribute(name: "Atlas", owner: owner)
        let field = fixtures.makeDetailField(
            owner: owner,
            name: "Atlas",
            type: .singleLineText,
            sortIndex: 0
        )
        let _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Atlas"
        )
        let _ = fixtures.makeLink(source: .entity(owner), target: .attribute(attribute))
        let _ = fixtures.makeAttachment(owner: .entity(owner), title: "Atlas")
        try fixtures.save()

        for provider in BrainMeshSearchCandidateProviders.ordered {
            let request = BrainMeshSearchCandidateRequest(
                modelContext: store.context,
                graphID: graph.id,
                foldedQuery: BMSearch.fold("atlas"),
                cancellationCheck: {
                    throw CancellationError()
                }
            )

            do {
                _ = try provider.candidates(for: request)
                Issue.record("Expected cancellation from \(provider.source.rawValue) provider")
            } catch is CancellationError {
            } catch {
                Issue.record("Unexpected cancellation error: \(error)")
            }
        }
    }

    @Test
    func orchestratorKeepsRankingKindOrderAndAppliesLimitAfterRanking() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph)
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let attribute = fixtures.makeAttribute(name: "Atlas", owner: owner)
        let target = fixtures.makeEntity(name: "Beacon", in: graph)
        let link = fixtures.makeLink(source: .entity(entity), target: .entity(target))
        let detail = fixtures.makeDetailField(
            owner: owner,
            name: "Atlas",
            type: .singleLineText,
            sortIndex: 0
        )
        let attachment = fixtures.makeAttachment(owner: .entity(owner), title: "Atlas")
        try fixtures.save()

        let fullSnapshot = try await search(
            in: store,
            graphID: graph.id,
            term: "atlas",
            limit: 20
        )
        let limitedSnapshot = try await search(
            in: store,
            graphID: graph.id,
            term: "atlas",
            limit: 3
        )

        #expect(
            fullSnapshot.results.prefix(5).map(\.id)
                == [entity.id, attribute.id, link.id, detail.id, attachment.id]
        )
        #expect(limitedSnapshot.results.map(\.id) == [entity.id, attribute.id, link.id])
    }

    @Test
    func orchestratorSearchWithNilGraphIDRemainsCompatible() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let firstGraph = fixtures.makeGraph(name: "First")
        let secondGraph = fixtures.makeGraph(name: "Second")
        let first = fixtures.makeEntity(name: "Atlas First", in: firstGraph)
        let second = fixtures.makeEntity(name: "Atlas Second", in: secondGraph)
        try fixtures.save()

        let snapshot = try await search(
            in: store,
            graphID: nil,
            term: "atlas",
            limit: 20
        )

        #expect(Set(snapshot.entityResults.map(\.id)) == Set([first.id, second.id]))
        #expect(Set(snapshot.entityResults.compactMap(\.graphID)) == Set([firstGraph.id, secondGraph.id]))
    }

    @Test
    func orchestratorPreservesDuplicateCandidates() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let firstGraph = fixtures.makeGraph(name: "First")
        let secondGraph = fixtures.makeGraph(name: "Second")
        let sharedID = UUID()
        let _ = fixtures.makeEntity(name: "Atlas", in: firstGraph, id: sharedID)
        let _ = fixtures.makeEntity(name: "Atlas", in: secondGraph, id: sharedID)
        try fixtures.save()

        let snapshot = try await search(
            in: store,
            graphID: nil,
            term: "atlas",
            limit: 20
        )
        let duplicates = snapshot.entityResults.filter { $0.id == sharedID }

        #expect(duplicates.count == 2)
        #expect(Set(duplicates.compactMap(\.graphID)) == Set([firstGraph.id, secondGraph.id]))
    }

    private func providerCandidates<Provider: BrainMeshSearchCandidateProvider>(
        _ provider: Provider,
        in store: BrainMeshTestStore,
        graphID: UUID?,
        term: String
    ) throws -> [BrainMeshSearchCandidate] {
        let request = BrainMeshSearchCandidateRequest(
            modelContext: store.context,
            graphID: graphID,
            foldedQuery: BMSearch.fold(term)
        )
        return try provider.candidates(for: request)
    }

    private func search(
        in store: BrainMeshTestStore,
        graphID: UUID?,
        term: String,
        limit: Int
    ) async throws -> BrainMeshSearchSnapshot {
        let service = BrainMeshSearchService()
        await service.configure(container: AnyModelContainer(store.container))
        return try await service.search(
            graphID: graphID,
            foldedQuery: BMSearch.fold(term),
            limit: limit
        )
    }
}
