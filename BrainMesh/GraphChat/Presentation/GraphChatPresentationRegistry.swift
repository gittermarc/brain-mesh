//
//  GraphChatPresentationRegistry.swift
//  BrainMesh
//
//  Turn-bound registry populated exclusively from app-validated graph-chat data.
//

import Foundation

nonisolated enum GraphChatPresentationIdentifierKind: String, Hashable, Sendable {
    case entityAlias
    case fieldAlias
    case nodeAlias
    case conversationAlias
    case nodeIdentifier
    case evidenceIdentifier
    case artifactIdentifier
    case technicalIdentifier
}

nonisolated struct GraphChatValidatedPresentationEntry: Hashable, Sendable {
    let identifier: String
    let displayName: String
    let kind: GraphChatPresentationIdentifierKind
}

nonisolated struct GraphChatPresentationRegistryRevision:
    RawRepresentable,
    Hashable,
    Sendable
{
    let rawValue: UInt64
}

nonisolated struct GraphChatValidatedPresentationRegistry: Hashable, Sendable {
    let revision: GraphChatPresentationRegistryRevision
    let entries: [GraphChatValidatedPresentationEntry]
    let conflictingIdentifiers: [String]
    private let entriesByIdentifier: [
        String: GraphChatValidatedPresentationEntry
    ]
    private let conflictingIdentifierSet: Set<String>

    static let empty = GraphChatValidatedPresentationRegistry(
        revision: GraphChatPresentationRegistryRevision(rawValue: 0),
        entries: [],
        conflictingIdentifiers: []
    )

    init(
        schemaContext: GraphSchemaContext? = nil,
        conversationContext: GraphChatConversationContextSnapshot? = nil,
        evidence: [GraphEvidence] = [],
        artifacts: [GraphChatAnswerArtifact] = [],
        language: GraphChatResponseLanguage
    ) {
        var builder = GraphChatValidatedPresentationRegistryBuilder(
            language: language
        )
        if let schemaContext {
            builder.register(schemaContext)
        }
        if let conversationContext {
            builder.register(conversationContext)
        }
        builder.register(evidence)
        builder.register(artifacts)
        self = builder.snapshot()
    }

    fileprivate init(
        revision: GraphChatPresentationRegistryRevision =
            GraphChatPresentationRegistryRevision(rawValue: 0),
        entries: [GraphChatValidatedPresentationEntry],
        conflictingIdentifiers: [String]
    ) {
        self.revision = revision
        self.entries = entries
        self.conflictingIdentifiers = conflictingIdentifiers
        self.entriesByIdentifier = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.identifier, $0) }
        )
        self.conflictingIdentifierSet = Set(conflictingIdentifiers)
    }

    func displayName(for identifier: String) -> String? {
        let normalized = Self.normalizedIdentifier(identifier)
        guard conflictingIdentifierSet.contains(normalized) == false else {
            return nil
        }
        return entriesByIdentifier[normalized]?.displayName
    }

    func containsConflict(for identifier: String) -> Bool {
        conflictingIdentifierSet.contains(
            Self.normalizedIdentifier(identifier)
        )
    }

    static func == (
        lhs: GraphChatValidatedPresentationRegistry,
        rhs: GraphChatValidatedPresentationRegistry
    ) -> Bool {
        lhs.revision == rhs.revision
            && lhs.entries == rhs.entries
            && lhs.conflictingIdentifiers == rhs.conflictingIdentifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(revision)
        hasher.combine(entries)
        hasher.combine(conflictingIdentifiers)
    }

    static func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

nonisolated struct GraphChatPresentationRegistryCacheDiagnostics:
    Hashable,
    Sendable
{
    let revision: GraphChatPresentationRegistryRevision
    let snapshotBuildCount: Int
}

nonisolated struct GraphChatPresentationContext: Hashable, Sendable {
    let registry: GraphChatValidatedPresentationRegistry
    let language: GraphChatResponseLanguage
}

actor GraphChatPresentationRegistry {
    private let language: GraphChatResponseLanguage
    private var builder: GraphChatValidatedPresentationRegistryBuilder
    private var revision = GraphChatPresentationRegistryRevision(rawValue: 0)
    private var cachedSnapshot: GraphChatValidatedPresentationRegistry?
    private var snapshotBuildCount = 0

    init(
        schemaContext: GraphSchemaContext,
        conversationContext: GraphChatConversationContextSnapshot,
        language: GraphChatResponseLanguage
    ) {
        self.language = language
        var builder = GraphChatValidatedPresentationRegistryBuilder(
            language: language
        )
        builder.register(schemaContext)
        builder.register(conversationContext)
        self.builder = builder
    }

    func registerValidatedNode(
        alias: String,
        node: NodeRefKey,
        displayName: String
    ) {
        let previousMutationCount = builder.mutationCount
        builder.registerValidatedNode(
            alias: alias,
            node: node,
            displayName: displayName
        )
        registerMutationIfNeeded(previousMutationCount)
    }

    func registerValidatedEvidence(_ evidence: [GraphEvidence]) {
        let previousMutationCount = builder.mutationCount
        builder.register(evidence)
        registerMutationIfNeeded(previousMutationCount)
    }

    func registerValidatedArtifact(
        id: GraphChatAnswerArtifactID,
        title: String
    ) {
        let previousMutationCount = builder.mutationCount
        builder.registerValidatedArtifact(id: id, title: title)
        registerMutationIfNeeded(previousMutationCount)
    }

    func registerValidatedArtifacts(
        _ artifacts: [GraphChatAnswerArtifact]
    ) {
        let previousMutationCount = builder.mutationCount
        builder.register(artifacts)
        registerMutationIfNeeded(previousMutationCount)
    }

    func snapshot() -> GraphChatValidatedPresentationRegistry {
        if let cachedSnapshot,
           cachedSnapshot.revision == revision {
            return cachedSnapshot
        }
        let snapshot = builder.snapshot(revision: revision)
        cachedSnapshot = snapshot
        snapshotBuildCount += 1
        return snapshot
    }

    func removeAll() {
        guard builder.isEmpty == false else {
            return
        }
        builder = GraphChatValidatedPresentationRegistryBuilder(
            language: language
        )
        advanceRevision()
    }

    func cacheDiagnosticsForTesting() ->
        GraphChatPresentationRegistryCacheDiagnostics
    {
        GraphChatPresentationRegistryCacheDiagnostics(
            revision: revision,
            snapshotBuildCount: snapshotBuildCount
        )
    }

    private func registerMutationIfNeeded(
        _ previousMutationCount: UInt64
    ) {
        guard builder.mutationCount != previousMutationCount else {
            return
        }
        advanceRevision()
    }

    private func advanceRevision() {
        revision = GraphChatPresentationRegistryRevision(
            rawValue: revision.rawValue &+ 1
        )
        cachedSnapshot = nil
    }
}

private nonisolated struct GraphChatValidatedPresentationRegistryBuilder {
    private static let maximumDisplayNameLength = 240

    private let language: GraphChatResponseLanguage
    private var entriesByIdentifier: [
        String: GraphChatValidatedPresentationEntry
    ] = [:]
    private var conflictingIdentifiers = Set<String>()
    private(set) var mutationCount: UInt64 = 0

    var isEmpty: Bool {
        entriesByIdentifier.isEmpty && conflictingIdentifiers.isEmpty
    }

    init(language: GraphChatResponseLanguage) {
        self.language = language
    }

    mutating func register(_ schemaContext: GraphSchemaContext) {
        for resolution in schemaContext.aliases.entitiesByAlias.values {
            register(
                identifier: resolution.alias.rawValue,
                displayName: resolution.name,
                kind: .entityAlias
            )
        }
        for resolution in schemaContext.aliases.fieldsByAlias.values {
            register(
                identifier: resolution.alias.rawValue,
                displayName: resolution.name,
                kind: .fieldAlias
            )
        }
    }

    mutating func register(
        _ conversationContext: GraphChatConversationContextSnapshot
    ) {
        for alias in conversationContext.aliases {
            register(
                identifier: alias.alias,
                displayName: conversationDisplayName(for: alias),
                kind: .conversationAlias
            )
        }
    }

    mutating func register(_ evidence: [GraphEvidence]) {
        for item in evidence {
            let displayName = evidenceDisplayName(for: item)
            register(
                identifier: item.id.rawValue.uuidString,
                displayName: displayName,
                kind: .evidenceIdentifier
            )
            registerTechnicalIdentifiers(
                in: item,
                displayName: displayName
            )
        }
    }

    mutating func register(_ artifacts: [GraphChatAnswerArtifact]) {
        for artifact in artifacts {
            registerValidatedArtifact(
                id: artifact.id,
                title: artifact.title
            )
        }
    }

    mutating func registerValidatedNode(
        alias: String,
        node: NodeRefKey,
        displayName: String
    ) {
        register(
            identifier: alias,
            displayName: displayName,
            kind: .nodeAlias
        )
        register(
            identifier: node.id.uuidString,
            displayName: displayName,
            kind: .nodeIdentifier
        )
    }

    mutating func registerValidatedArtifact(
        id: GraphChatAnswerArtifactID,
        title: String
    ) {
        register(
            identifier: id.rawValue.uuidString,
            displayName: title,
            kind: .artifactIdentifier
        )
    }

    func snapshot(
        revision: GraphChatPresentationRegistryRevision =
            GraphChatPresentationRegistryRevision(rawValue: 0)
    ) -> GraphChatValidatedPresentationRegistry {
        GraphChatValidatedPresentationRegistry(
            revision: revision,
            entries: entriesByIdentifier.values.sorted { lhs, rhs in
                if lhs.identifier != rhs.identifier {
                    return lhs.identifier < rhs.identifier
                }
                if lhs.kind != rhs.kind {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.displayName < rhs.displayName
            },
            conflictingIdentifiers: conflictingIdentifiers.sorted()
        )
    }

    private mutating func registerTechnicalIdentifiers(
        in evidence: GraphEvidence,
        displayName: String
    ) {
        let source = evidence.sourceReference
        var values = [
            source.graphID,
            source.sourceID,
        ]
        if let nodeID = source.nodeID {
            values.append(nodeID)
        }
        if let ownerID = source.ownerID {
            values.append(ownerID)
        }
        if let fieldID = source.fieldID {
            values.append(fieldID)
        }
        if let linkID = source.linkID {
            values.append(linkID)
        }
        if let attachmentID = source.attachmentID {
            values.append(attachmentID)
        }
        values.append(
            contentsOf: evidence.fieldValues.compactMap(\.fieldID)
        )
        for value in values {
            register(
                identifier: value.uuidString,
                displayName: displayName,
                kind: .technicalIdentifier
            )
        }
    }

    private mutating func register(
        identifier: String,
        displayName: String,
        kind: GraphChatPresentationIdentifierKind
    ) {
        let normalizedIdentifier =
            GraphChatValidatedPresentationRegistry.normalizedIdentifier(
                identifier
            )
        let normalizedDisplayName = Self.boundedDisplayName(displayName)
        guard normalizedIdentifier.isEmpty == false,
              normalizedDisplayName.isEmpty == false,
              conflictingIdentifiers.contains(normalizedIdentifier) == false else {
            return
        }

        let entry = GraphChatValidatedPresentationEntry(
            identifier: normalizedIdentifier,
            displayName: normalizedDisplayName,
            kind: kind
        )
        if let existing = entriesByIdentifier[normalizedIdentifier] {
            guard existing.displayName == entry.displayName else {
                if priority(of: entry.kind) > priority(of: existing.kind) {
                    entriesByIdentifier[normalizedIdentifier] = entry
                    mutationCount &+= 1
                    return
                }
                if priority(of: entry.kind) < priority(of: existing.kind) {
                    return
                }
                entriesByIdentifier[normalizedIdentifier] = nil
                conflictingIdentifiers.insert(normalizedIdentifier)
                mutationCount &+= 1
                return
            }
            return
        }
        entriesByIdentifier[normalizedIdentifier] = entry
        mutationCount &+= 1
    }

    private func priority(
        of kind: GraphChatPresentationIdentifierKind
    ) -> Int {
        switch kind {
        case .nodeIdentifier:
            return 3
        case .artifactIdentifier, .evidenceIdentifier:
            return 2
        case .entityAlias, .fieldAlias, .nodeAlias,
            .conversationAlias, .technicalIdentifier:
            return 1
        }
    }

    private func conversationDisplayName(
        for alias: GraphChatConversationContextAlias
    ) -> String {
        if alias.alias == "CURRENT" {
            return alias.label
        }
        switch alias.target {
        case .node, .entity, .field:
            return alias.label
        case .resultSet:
            switch language {
            case .german:
                return "die vorherigen Ergebnisse"
            case .english:
                return "the previous results"
            }
        case .group:
            return alias.label
        case .comparison:
            switch language {
            case .german:
                return "der vorherige Vergleich"
            case .english:
                return "the previous comparison"
            }
        }
    }

    private func evidenceDisplayName(
        for evidence: GraphEvidence
    ) -> String {
        if let navigationTitle = evidence.navigationTitle,
           navigationTitle.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty == false {
            return navigationTitle
        }
        switch language {
        case .german:
            return "Graphquelle"
        case .english:
            return "graph source"
        }
    }

    private static func boundedDisplayName(_ value: String) -> String {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalized.count > maximumDisplayNameLength else {
            return normalized
        }
        return String(normalized.prefix(maximumDisplayNameLength))
    }
}
