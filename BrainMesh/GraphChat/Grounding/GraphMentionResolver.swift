//
//  GraphMentionResolver.swift
//  BrainMesh
//
//  Deterministic, app-owned grounding of user-visible graph mentions.
//

import Foundation

nonisolated enum GraphMentionResolverVersion:
    Int,
    CaseIterable,
    Hashable,
    Sendable
{
    case v1 = 1
}

nonisolated enum GraphMentionKind:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case entity
    case node
    case field
}

nonisolated enum GraphMentionAliasOrigin:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case displayName
    case appOwnedAlias
    case localizedFieldSynonym
}

nonisolated enum GraphMentionResolutionQuality:
    Int,
    CaseIterable,
    Hashable,
    Sendable
{
    case exact = 0
    case canonical = 1
    case umlautEquivalent = 2
    case languageVariant = 3
    case conservativeTypo = 4
}

nonisolated enum GraphMentionMatchingMode:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case completeMention
    case containedPhrase
}

nonisolated struct GraphMentionAlias:
    Hashable,
    Sendable
{
    let value: String
    let origin: GraphMentionAliasOrigin
    let language: GraphChatResponseLanguage?

    init(
        value: String,
        origin: GraphMentionAliasOrigin,
        language: GraphChatResponseLanguage? = nil
    ) {
        self.value = value
        self.origin = origin
        self.language = language
    }
}

nonisolated enum GraphMentionCandidateIdentity:
    Hashable,
    Sendable
{
    case entity(GraphSchemaEntityResolution)
    case node(GraphSchemaNodeResolution)
    case field(GraphSchemaFieldResolution)

    var kind: GraphMentionKind {
        switch self {
        case .entity:
            return .entity
        case .node:
            return .node
        case .field:
            return .field
        }
    }

    var displayName: String {
        switch self {
        case .entity(let value):
            return value.name
        case .node(let value):
            return value.displayName
        case .field(let value):
            return value.name
        }
    }

    var ownerEntityID: UUID {
        switch self {
        case .entity(let value):
            return value.entityID
        case .node(let value):
            return value.ownerEntityID
        case .field(let value):
            return value.entityID
        }
    }

    var stableKey: String {
        switch self {
        case .entity(let value):
            return "entity:\(value.entityID.uuidString)"
        case .node(let value):
            return
                "node:\(value.node.kind.rawValue):\(value.node.id.uuidString)"
        case .field(let value):
            return "field:\(value.fieldID.uuidString)"
        }
    }
}

nonisolated struct GraphMentionCandidate:
    Hashable,
    Sendable
{
    let graphScope: GraphScope
    let identity: GraphMentionCandidateIdentity
    let ownerDisplayName: String?
    let aliases: [GraphMentionAlias]

    var kind: GraphMentionKind {
        identity.kind
    }

    var displayName: String {
        identity.displayName
    }

    var ownerEntityID: UUID {
        identity.ownerEntityID
    }

    init(
        graphScope: GraphScope,
        identity: GraphMentionCandidateIdentity,
        ownerDisplayName: String? = nil,
        aliases: [GraphMentionAlias] = []
    ) {
        self.graphScope = graphScope
        self.identity = identity
        self.ownerDisplayName = ownerDisplayName
        self.aliases = aliases
    }
}

nonisolated struct GraphMentionLexiconTerm:
    Hashable,
    Sendable
{
    let value: String
    let language: GraphChatResponseLanguage
}

nonisolated struct GraphMentionAliasGroup:
    Hashable,
    Sendable
{
    let kind: GraphMentionKind
    let origin: GraphMentionAliasOrigin
    let terms: [GraphMentionLexiconTerm]
}

/// App-owned aliases are data, not resolver branches. The resolver itself
/// remains independent of every graph's entities, nodes and fields.
nonisolated struct GraphMentionLexicon:
    Hashable,
    Sendable
{
    let groups: [GraphMentionAliasGroup]

    func aliases(
        for displayName: String,
        kind: GraphMentionKind
    ) -> [GraphMentionAlias] {
        var result: [GraphMentionAlias] = []
        var seen = Set<String>()

        for group in groups where group.kind == kind {
            for source in group.terms {
                for target in group.terms {
                    guard source != target,
                          let value =
                            GraphMentionTextNormalization
                                .replacingPhrase(
                                    source.value,
                                    with: target.value,
                                    in: displayName
                                )
                    else {
                        continue
                    }
                    let key =
                        "\(target.language.rawValue):\(GraphMentionTextNormalization.canonical(value))"
                    guard seen.insert(key).inserted else {
                        continue
                    }
                    result.append(
                        GraphMentionAlias(
                            value: value,
                            origin: group.origin,
                            language: target.language
                        )
                    )
                }
            }
        }
        return result
    }
}

nonisolated struct GraphMentionCatalog:
    Hashable,
    Sendable
{
    let graphScope: GraphScope
    let candidates: [GraphMentionCandidate]

    init(
        graphScope: GraphScope,
        candidates: [GraphMentionCandidate]
    ) {
        self.graphScope = graphScope
        self.candidates = candidates
    }

    init(
        schemaContext: GraphSchemaContext,
        lexicon: GraphMentionLexicon = .appOwned
    ) {
        let aliases = schemaContext.foundationalAliases
        var candidates: [GraphMentionCandidate] = []
        candidates.reserveCapacity(
            aliases.entitiesByAlias.count
                + aliases.nodesByKey.count
                + aliases.fieldsByAlias.count
        )

        for value in aliases.entitiesByAlias.values {
            candidates.append(
                GraphMentionCandidate(
                    graphScope:
                        aliases.graphScope,
                    identity: .entity(value),
                    aliases: lexicon.aliases(
                        for: value.name,
                        kind: .entity
                    )
                )
            )
        }
        for value in aliases.nodesByKey.values {
            candidates.append(
                GraphMentionCandidate(
                    graphScope:
                        aliases.graphScope,
                    identity: .node(value),
                    ownerDisplayName:
                        aliases.entity(
                            id: value.ownerEntityID
                        )?.name,
                    aliases: lexicon.aliases(
                        for: value.displayName,
                        kind: .node
                    )
                )
            )
        }
        for value in aliases.fieldsByAlias.values {
            candidates.append(
                GraphMentionCandidate(
                    graphScope:
                        aliases.graphScope,
                    identity: .field(value),
                    ownerDisplayName:
                        aliases.entity(
                            id: value.entityID
                        )?.name,
                    aliases: lexicon.aliases(
                        for: value.name,
                        kind: .field
                    )
                )
            )
        }
        self.init(
            graphScope: aliases.graphScope,
            candidates: candidates
        )
    }
}

nonisolated struct GraphMentionResolutionConstraints:
    Hashable,
    Sendable
{
    let chatScope: GraphChatScope
    let ownerEntityID: UUID?
    let allowedEntityIDs: Set<UUID>?
    let allowedNodes: Set<NodeRefKey>?
    let allowedFieldIDs: Set<UUID>?
    let conversationEntityID: UUID?
    let conversationNodes: Set<NodeRefKey>?

    init(
        chatScope: GraphChatScope,
        ownerEntityID: UUID? = nil,
        allowedEntityIDs: Set<UUID>? = nil,
        allowedNodes: Set<NodeRefKey>? = nil,
        allowedFieldIDs: Set<UUID>? = nil,
        conversationEntityID: UUID? = nil,
        conversationNodes: Set<NodeRefKey>? = nil
    ) {
        self.chatScope = chatScope
        self.ownerEntityID = ownerEntityID
        self.allowedEntityIDs = allowedEntityIDs
        self.allowedNodes = allowedNodes
        self.allowedFieldIDs = allowedFieldIDs
        self.conversationEntityID = conversationEntityID
        self.conversationNodes = conversationNodes
    }
}

nonisolated struct GraphMentionResolverInput:
    Hashable,
    Sendable
{
    let mention: String
    let kind: GraphMentionKind
    let language: GraphChatResponseLanguage
    let graphScope: GraphScope
    let catalog: GraphMentionCatalog
    let constraints: GraphMentionResolutionConstraints
    let matchingMode: GraphMentionMatchingMode

    init(
        mention: String,
        kind: GraphMentionKind,
        language: GraphChatResponseLanguage,
        graphScope: GraphScope,
        catalog: GraphMentionCatalog,
        constraints: GraphMentionResolutionConstraints,
        matchingMode: GraphMentionMatchingMode = .completeMention
    ) {
        self.mention = mention
        self.kind = kind
        self.language = language
        self.graphScope = graphScope
        self.catalog = catalog
        self.constraints = constraints
        self.matchingMode = matchingMode
    }
}

nonisolated struct GraphMentionTextRange:
    Hashable,
    Sendable
{
    let startToken: Int
    let tokenCount: Int
}

nonisolated struct GraphMentionResolutionAlternative:
    Hashable,
    Sendable
{
    let candidate: GraphMentionCandidate
    let aliasOrigin: GraphMentionAliasOrigin
    let quality: GraphMentionResolutionQuality
    let matchedRange: GraphMentionTextRange
    let editDistance: Int?
}

nonisolated struct GraphMentionResolution:
    Hashable,
    Sendable
{
    let version: GraphMentionResolverVersion
    let candidate: GraphMentionCandidate
    let aliasOrigin: GraphMentionAliasOrigin
    let quality: GraphMentionResolutionQuality
    let matchedRange: GraphMentionTextRange
    let editDistance: Int?

    var isDirectDisplayBinding: Bool {
        guard aliasOrigin == .displayName else {
            return false
        }
        switch quality {
        case .exact, .canonical:
            return true
        case .umlautEquivalent,
            .languageVariant,
            .conservativeTypo:
            return false
        }
    }
}

nonisolated enum GraphMentionResolutionFailure:
    Error,
    Hashable,
    Sendable
{
    case emptyMention
    case graphScopeMismatch
    case noCandidates
    case notFound
    case ambiguous([GraphMentionResolutionAlternative])
    case scopeViolation
    case ownerEntityMismatch
    case staleSelection
}

nonisolated struct GraphMentionResolverPolicy:
    Hashable,
    Sendable
{
    let minimumFuzzyLength: Int
    let maximumShortEditDistance: Int
    let maximumMediumEditDistance: Int
    let maximumLongEditDistance: Int
    let minimumSecondCandidateDistanceGap: Int
    let maximumEditRatio: Double

    static let `default` = GraphMentionResolverPolicy(
        minimumFuzzyLength: 5,
        maximumShortEditDistance: 1,
        maximumMediumEditDistance: 2,
        maximumLongEditDistance: 3,
        minimumSecondCandidateDistanceGap: 2,
        maximumEditRatio: 0.18
    )
}

nonisolated struct GraphMentionResolver:
    Hashable,
    Sendable
{
    private struct Match: Hashable {
        let candidate: GraphMentionCandidate
        let aliasOrigin: GraphMentionAliasOrigin
        let quality: GraphMentionResolutionQuality
        let range: GraphMentionTextRange
        let editDistance: Int?

        var alternative: GraphMentionResolutionAlternative {
            GraphMentionResolutionAlternative(
                candidate: candidate,
                aliasOrigin: aliasOrigin,
                quality: quality,
                matchedRange: range,
                editDistance: editDistance
            )
        }

        var resolution: GraphMentionResolution {
            GraphMentionResolution(
                version: .v1,
                candidate: candidate,
                aliasOrigin: aliasOrigin,
                quality: quality,
                matchedRange: range,
                editDistance: editDistance
            )
        }
    }

    private enum MatchResult {
        case resolved(Match)
        case ambiguous([Match])
        case notFound
    }

    private struct CandidateName {
        let value: String
        let origin: GraphMentionAliasOrigin
    }

    private let policy: GraphMentionResolverPolicy

    init(
        policy: GraphMentionResolverPolicy = .default
    ) {
        self.policy = policy
    }

    func resolve(
        _ input: GraphMentionResolverInput
    ) -> Result<
        GraphMentionResolution,
        GraphMentionResolutionFailure
    > {
        guard input.graphScope == input.catalog.graphScope,
              input.constraints.chatScope.graphScope
                == input.graphScope,
              input.catalog.candidates.allSatisfy({
                $0.graphScope
                    == input.catalog.graphScope
              })
        else {
            return .failure(.graphScopeMismatch)
        }
        guard
            GraphMentionTextNormalization
                .canonical(input.mention)
                .isEmpty == false
        else {
            return .failure(.emptyMention)
        }

        let all = sorted(
            input.catalog.candidates.filter {
                $0.kind == input.kind
            }
        )
        guard all.isEmpty == false else {
            return .failure(.noCandidates)
        }

        let scopeEligible = all.filter {
            isAllowedByChatScope(
                $0,
                scope: input.constraints.chatScope,
                catalog: input.catalog
            )
        }
        let ownerEligible = scopeEligible.filter {
            isAllowedByOwner(
                $0,
                constraints: input.constraints
            )
        }
        let selectedEligible = ownerEligible.filter {
            isAllowedBySelections(
                $0,
                constraints: input.constraints
            )
        }

        switch match(
            mention: input.mention,
            candidates: selectedEligible,
            language: input.language,
            mode: input.matchingMode
        ) {
        case .resolved(let value):
            return .success(value.resolution)
        case .ambiguous(let values):
            return .failure(
                .ambiguous(
                    values.map(\.alternative)
                )
            )
        case .notFound:
            break
        }

        if hasMatch(
            input.mention,
            in: ownerEligible,
            language: input.language,
            mode: input.matchingMode
        ) {
            return .failure(.staleSelection)
        }
        if hasMatch(
            input.mention,
            in: scopeEligible,
            language: input.language,
            mode: input.matchingMode
        ) {
            return .failure(.ownerEntityMismatch)
        }
        if hasMatch(
            input.mention,
            in: all,
            language: input.language,
            mode: input.matchingMode
        ) {
            return .failure(.scopeViolation)
        }
        return .failure(.notFound)
    }

    private func match(
        mention: String,
        candidates: [GraphMentionCandidate],
        language: GraphChatResponseLanguage,
        mode: GraphMentionMatchingMode
    ) -> MatchResult {
        guard candidates.isEmpty == false else {
            return .notFound
        }
        switch mode {
        case .completeMention:
            let tokenCount =
                GraphMentionTextNormalization
                    .tokens(mention).count
            return completeMatch(
                mention: mention,
                candidates: candidates,
                language: language,
                range: GraphMentionTextRange(
                    startToken: 0,
                    tokenCount: tokenCount
                ),
                allowsExact: true
            )
        case .containedPhrase:
            return containedMatch(
                text: mention,
                candidates: candidates,
                language: language
            )
        }
    }

    private func containedMatch(
        text: String,
        candidates: [GraphMentionCandidate],
        language: GraphChatResponseLanguage
    ) -> MatchResult {
        let tokens =
            GraphMentionTextNormalization.tokens(text)
        guard tokens.isEmpty == false else {
            return .notFound
        }
        let maximumNameTokenCount =
            candidates.flatMap {
                names(for: $0, language: language)
            }
            .map {
                GraphMentionTextNormalization
                    .tokens($0.value).count
            }
            .max() ?? 1
        let maximumSpan = min(
            tokens.count,
            max(1, maximumNameTokenCount)
        )
        var matches: [Match] = []

        for start in tokens.indices {
            let available = tokens.count - start
            for length in 1...min(maximumSpan, available) {
                let range = GraphMentionTextRange(
                    startToken: start,
                    tokenCount: length
                )
                let phrase = tokens[
                    start..<(start + length)
                ].joined(separator: " ")
                switch completeMatch(
                    mention: phrase,
                    candidates: candidates,
                    language: language,
                    range: range,
                    allowsExact: false
                ) {
                case .resolved(let value):
                    matches.append(value)
                case .ambiguous(let values):
                    matches.append(contentsOf: values)
                case .notFound:
                    break
                }
            }
        }

        let bestByCandidate = Dictionary(
            grouping: matches,
            by: { $0.candidate.identity.stableKey }
        ).compactMap { _, values in
            values.sorted(by: containedMatchSort).first
        }
        let ranked = bestByCandidate.sorted(
            by: containedMatchSort
        )
        guard let first = ranked.first else {
            return .notFound
        }
        let bestScore = containedScore(first)
        let best = ranked.filter {
            containedScore($0) == bestScore
        }.sorted(by: stableMatchSort)
        return best.count == 1
            ? .resolved(best[0])
            : .ambiguous(best)
    }

    private func completeMatch(
        mention: String,
        candidates: [GraphMentionCandidate],
        language: GraphChatResponseLanguage,
        range: GraphMentionTextRange,
        allowsExact: Bool
    ) -> MatchResult {
        let stages: [
            (
                GraphMentionResolutionQuality,
                (String, String) -> Bool
            )
        ] = [
            (
                .exact,
                {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                        == $1.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                }
            ),
            (
                .canonical,
                {
                    GraphMentionTextNormalization.canonical($0)
                        == GraphMentionTextNormalization.canonical($1)
                }
            ),
            (
                .umlautEquivalent,
                {
                    GraphMentionTextNormalization.umlautKey($0)
                        == GraphMentionTextNormalization.umlautKey($1)
                }
            ),
            (
                .languageVariant,
                {
                    limitedInflectionEquivalent(
                        $0,
                        $1,
                        language: language
                    )
                }
            ),
        ]

        for (quality, predicate) in stages {
            if quality == .exact, allowsExact == false {
                continue
            }
            let matches = matches(
                mention: mention,
                candidates: candidates,
                language: language,
                quality: quality,
                range: range,
                predicate: predicate
            )
            if matches.isEmpty == false {
                return matches.count == 1
                    ? .resolved(matches[0])
                    : .ambiguous(matches)
            }
        }
        return fuzzyMatch(
            mention: mention,
            candidates: candidates,
            language: language,
            range: range
        )
    }

    private func matches(
        mention: String,
        candidates: [GraphMentionCandidate],
        language: GraphChatResponseLanguage,
        quality: GraphMentionResolutionQuality,
        range: GraphMentionTextRange,
        predicate: (String, String) -> Bool
    ) -> [Match] {
        var result: [Match] = []
        for candidate in candidates {
            let matchingNames = names(
                for: candidate,
                language: language
            ).filter {
                predicate(mention, $0.value)
            }.sorted(by: candidateNameSort)
            guard let name = matchingNames.first else {
                continue
            }
            result.append(
                Match(
                    candidate: candidate,
                    aliasOrigin: name.origin,
                    quality: quality,
                    range: range,
                    editDistance: nil
                )
            )
        }
        return result.sorted(by: stableMatchSort)
    }

    private func fuzzyMatch(
        mention: String,
        candidates: [GraphMentionCandidate],
        language: GraphChatResponseLanguage,
        range: GraphMentionTextRange
    ) -> MatchResult {
        let mentionKey =
            GraphMentionTextNormalization.fuzzyKey(mention)
        guard
            mentionKey.count
                >= policy.minimumFuzzyLength
        else {
            return .notFound
        }
        let maximumDistance =
            maximumEditDistance(
                for: mentionKey.count
            )
        var matches: [Match] = []

        for candidate in candidates {
            let scored = names(
                for: candidate,
                language: language
            ).compactMap { name
                -> (CandidateName, Int, Double)? in
                let key =
                    GraphMentionTextNormalization
                        .fuzzyKey(name.value)
                guard key.count
                        >= policy.minimumFuzzyLength else {
                    return nil
                }
                guard
                    abs(
                        mentionKey.count
                            - key.count
                    ) <= maximumDistance
                else {
                    return nil
                }
                let distance = Self.editDistance(
                    mentionKey,
                    key
                )
                let denominator = max(
                    mentionKey.count,
                    key.count
                )
                let ratio =
                    Double(distance)
                    / Double(max(1, denominator))
                guard distance <= maximumDistance,
                      ratio <= policy.maximumEditRatio else {
                    return nil
                }
                return (name, distance, ratio)
            }.sorted {
                if $0.1 != $1.1 {
                    return $0.1 < $1.1
                }
                if $0.2 != $1.2 {
                    return $0.2 < $1.2
                }
                return candidateNameSort(
                    $0.0,
                    $1.0
                )
            }
            guard let best = scored.first else {
                continue
            }
            matches.append(
                Match(
                    candidate: candidate,
                    aliasOrigin: best.0.origin,
                    quality: .conservativeTypo,
                    range: range,
                    editDistance: best.1
                )
            )
        }
        let sortedMatches = matches.sorted {
            let left = $0.editDistance ?? .max
            let right = $1.editDistance ?? .max
            if left != right {
                return left < right
            }
            return stableMatchSort($0, $1)
        }
        guard let best = sortedMatches.first else {
            return .notFound
        }
        let bestDistance = best.editDistance ?? .max
        let tied = sortedMatches.filter {
            $0.editDistance == best.editDistance
        }
        if tied.count > 1 {
            return .ambiguous(tied)
        }
        if sortedMatches.count > 1 {
            let secondDistance =
                sortedMatches[1].editDistance ?? .max
            guard
                secondDistance - bestDistance
                    >= policy
                        .minimumSecondCandidateDistanceGap
            else {
                return .ambiguous(
                    Array(
                        sortedMatches.prefix(2)
                    )
                )
            }
        }
        return .resolved(best)
    }

    private func names(
        for candidate: GraphMentionCandidate,
        language: GraphChatResponseLanguage
    ) -> [CandidateName] {
        var result = [
            CandidateName(
                value: candidate.displayName,
                origin: .displayName
            ),
        ]
        result.append(
            contentsOf: candidate.aliases.compactMap {
                alias in
                guard alias.language == nil
                        || alias.language == language else {
                    return nil
                }
                return CandidateName(
                    value: alias.value,
                    origin: alias.origin
                )
            }
        )
        return result
    }

    private func hasMatch(
        _ mention: String,
        in candidates: [GraphMentionCandidate],
        language: GraphChatResponseLanguage,
        mode: GraphMentionMatchingMode
    ) -> Bool {
        switch match(
            mention: mention,
            candidates: candidates,
            language: language,
            mode: mode
        ) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    private func isAllowedByChatScope(
        _ candidate: GraphMentionCandidate,
        scope: GraphChatScope,
        catalog: GraphMentionCatalog
    ) -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let entityID):
            return candidate.ownerEntityID == entityID
        case .node(let node):
            if case .node(let value) = candidate.identity {
                return value.node == node
            }
            let owner = ownerEntityID(
                for: node,
                catalog: catalog
            )
            return owner == candidate.ownerEntityID
        case .selection(let nodes):
            if case .node(let value) = candidate.identity {
                return Set(nodes).contains(value.node)
            }
            let owners = Set(
                nodes.compactMap {
                    ownerEntityID(
                        for: $0,
                        catalog: catalog
                    )
                }
            )
            return owners.contains(
                candidate.ownerEntityID
            )
        }
    }

    private func isAllowedByOwner(
        _ candidate: GraphMentionCandidate,
        constraints: GraphMentionResolutionConstraints
    ) -> Bool {
        if let ownerEntityID =
                constraints.ownerEntityID,
           candidate.ownerEntityID
                != ownerEntityID {
            return false
        }
        if let conversationEntityID =
                constraints.conversationEntityID,
           candidate.ownerEntityID
                != conversationEntityID {
            return false
        }
        if case .node(let value) = candidate.identity,
           let conversationNodes =
                constraints.conversationNodes,
           conversationNodes.contains(value.node)
                == false {
            return false
        }
        return true
    }

    private func isAllowedBySelections(
        _ candidate: GraphMentionCandidate,
        constraints: GraphMentionResolutionConstraints
    ) -> Bool {
        switch candidate.identity {
        case .entity(let value):
            return constraints.allowedEntityIDs?
                .contains(value.entityID) ?? true
        case .node(let value):
            return constraints.allowedNodes?
                .contains(value.node) ?? true
        case .field(let value):
            return constraints.allowedFieldIDs?
                .contains(value.fieldID) ?? true
        }
    }

    private func ownerEntityID(
        for node: NodeRefKey,
        catalog: GraphMentionCatalog
    ) -> UUID? {
        if node.kind == .entity {
            return node.id
        }
        for candidate in catalog.candidates {
            guard case .node(let value) =
                    candidate.identity,
                  value.node == node else {
                continue
            }
            return value.ownerEntityID
        }
        return nil
    }

    private func maximumEditDistance(
        for length: Int
    ) -> Int {
        switch length {
        case ...7:
            return policy.maximumShortEditDistance
        case 8...14:
            return policy.maximumMediumEditDistance
        default:
            return policy.maximumLongEditDistance
        }
    }

    private func sorted(
        _ candidates: [GraphMentionCandidate]
    ) -> [GraphMentionCandidate] {
        candidates.sorted(by: stableCandidateSort)
    }

    private func containedScore(
        _ value: Match
    ) -> [Int] {
        [
            value.quality.rawValue,
            -value.range.tokenCount,
            value.editDistance ?? 0,
        ]
    }

    private func containedMatchSort(
        _ lhs: Match,
        _ rhs: Match
    ) -> Bool {
        let left = containedScore(lhs)
        let right = containedScore(rhs)
        if left != right {
            return left.lexicographicallyPrecedes(right)
        }
        return stableMatchSort(lhs, rhs)
    }

    private func stableMatchSort(
        _ lhs: Match,
        _ rhs: Match
    ) -> Bool {
        stableCandidateSort(
            lhs.candidate,
            rhs.candidate
        )
    }

    private func stableCandidateSort(
        _ lhs: GraphMentionCandidate,
        _ rhs: GraphMentionCandidate
    ) -> Bool {
        let leftDisplayName =
            GraphMentionTextNormalization
                .canonical(lhs.displayName)
        let rightDisplayName =
            GraphMentionTextNormalization
                .canonical(rhs.displayName)
        if leftDisplayName != rightDisplayName {
            return leftDisplayName < rightDisplayName
        }

        let leftOwnerDisplayName =
            lhs.ownerDisplayName.map {
                GraphMentionTextNormalization
                    .canonical($0)
            } ?? ""
        let rightOwnerDisplayName =
            rhs.ownerDisplayName.map {
                GraphMentionTextNormalization
                    .canonical($0)
            } ?? ""
        if leftOwnerDisplayName
            != rightOwnerDisplayName
        {
            return leftOwnerDisplayName <
                rightOwnerDisplayName
        }

        return lhs.identity.stableKey <
            rhs.identity.stableKey
    }

    private func candidateNameSort(
        _ lhs: CandidateName,
        _ rhs: CandidateName
    ) -> Bool {
        if lhs.origin != rhs.origin {
            return aliasOriginRank(lhs.origin) <
                aliasOriginRank(rhs.origin)
        }
        return GraphMentionTextNormalization
            .canonical(lhs.value) <
            GraphMentionTextNormalization
                .canonical(rhs.value)
    }

    private func aliasOriginRank(
        _ value: GraphMentionAliasOrigin
    ) -> Int {
        switch value {
        case .displayName:
            return 0
        case .appOwnedAlias:
            return 1
        case .localizedFieldSynonym:
            return 2
        }
    }

    private func limitedInflectionEquivalent(
        _ lhs: String,
        _ rhs: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        let left =
            GraphMentionTextNormalization.tokens(lhs)
        let right =
            GraphMentionTextNormalization.tokens(rhs)
        guard left.count == right.count,
              let leftLast = left.last,
              let rightLast = right.last else {
            return false
        }
        for index in 0..<(left.count - 1) {
            guard
                GraphMentionTextNormalization
                    .umlautKey(left[index])
                == GraphMentionTextNormalization
                    .umlautKey(right[index])
            else {
                return false
            }
        }
        let leftRoots = inflectionRoots(
            leftLast,
            language: language
        )
        let rightRoots = inflectionRoots(
            rightLast,
            language: language
        )
        return leftRoots.isDisjoint(
            with: rightRoots
        ) == false
    }

    private func inflectionRoots(
        _ value: String,
        language: GraphChatResponseLanguage
    ) -> Set<String> {
        var forms = Set([
            GraphMentionTextNormalization
                .diacriticKey(value),
        ])
        if language == .german {
            forms.insert(
                GraphMentionTextNormalization
                    .collapsedUmlautKey(value)
            )
        }
        var roots = forms
        for form in forms {
            switch language {
            case .german:
                for suffix in [
                    "en", "er", "es", "em",
                    "e", "n", "s",
                ] where form.hasSuffix(suffix) {
                    let root = String(
                        form.dropLast(suffix.count)
                    )
                    if root.count >= 4 {
                        roots.insert(root)
                    }
                }
            case .english:
                if form.hasSuffix("ies"),
                   form.count > 4 {
                    roots.insert(
                        String(form.dropLast(3)) + "y"
                    )
                }
                for suffix in ["es", "s"]
                where form.hasSuffix(suffix)
                    && form.hasSuffix("ss") == false {
                    let root = String(
                        form.dropLast(suffix.count)
                    )
                    if root.count >= 4 {
                        roots.insert(root)
                    }
                }
            }
        }
        return roots
    }

    private static func editDistance(
        _ lhs: String,
        _ rhs: String
    ) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty {
            return right.count
        }
        if right.isEmpty {
            return left.count
        }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in
            left.enumerated()
        {
            var current = Array(
                repeating: 0,
                count: right.count + 1
            )
            current[0] = leftIndex + 1
            for (
                rightIndex,
                rightCharacter
            ) in right.enumerated() {
                let substitution =
                    previous[rightIndex]
                    + (
                        leftCharacter
                            == rightCharacter
                        ? 0
                        : 1
                    )
                current[rightIndex + 1] = Swift.min(
                    Swift.min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1
                    ),
                    substitution
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}

nonisolated enum GraphMentionTextNormalization {
    static func replacingPhrase(
        _ source: String,
        with target: String,
        in value: String
    ) -> String? {
        let sourceTokens = tokens(source)
        let targetTokens = tokens(target)
        let valueTokens = tokens(value)
        guard sourceTokens.isEmpty == false,
              targetTokens.isEmpty == false,
              sourceTokens.count <= valueTokens.count else {
            return nil
        }
        for start in 0...(
            valueTokens.count - sourceTokens.count
        ) {
            let end = start + sourceTokens.count
            guard Array(valueTokens[start..<end])
                    == sourceTokens else {
                continue
            }
            var replaced =
                Array(valueTokens[..<start])
            replaced.append(contentsOf: targetTokens)
            replaced.append(
                contentsOf: valueTokens[end...]
            )
            let result =
                replaced.joined(separator: " ")
            return result == canonical(value)
                ? nil
                : result
        }
        return nil
    }

    static func tokens(
        _ value: String
    ) -> [String] {
        canonical(value)
            .split(separator: " ")
            .map(String.init)
    }

    static func canonical(
        _ value: String
    ) -> String {
        let normalized = value
            .precomposedStringWithCanonicalMapping
            .lowercased(
                with: Locale(
                    identifier: "en_US_POSIX"
                )
            )
        var tokens: [String] = []
        var current = ""
        for character in normalized {
            if character.isLetter
                || character.isNumber {
                current.append(character)
            } else if current.isEmpty == false {
                tokens.append(current)
                current = ""
            }
        }
        if current.isEmpty == false {
            tokens.append(current)
        }
        return tokens.joined(separator: " ")
    }

    static func umlautKey(
        _ value: String
    ) -> String {
        canonical(value)
            .replacingOccurrences(
                of: "ä",
                with: "ae"
            )
            .replacingOccurrences(
                of: "ö",
                with: "oe"
            )
            .replacingOccurrences(
                of: "ü",
                with: "ue"
            )
            .replacingOccurrences(
                of: "ß",
                with: "ss"
            )
    }

    static func collapsedUmlautKey(
        _ value: String
    ) -> String {
        umlautKey(value)
            .replacingOccurrences(
                of: "ae",
                with: "a"
            )
            .replacingOccurrences(
                of: "oe",
                with: "o"
            )
            .replacingOccurrences(
                of: "ue",
                with: "u"
            )
    }

    static func diacriticKey(
        _ value: String
    ) -> String {
        canonical(value)
            .folding(
                options: [.diacriticInsensitive],
                locale: Locale(
                    identifier: "en_US_POSIX"
                )
            )
            .replacingOccurrences(
                of: "ß",
                with: "ss"
            )
    }

    static func fuzzyKey(
        _ value: String
    ) -> String {
        umlautKey(value)
            .filter {
                $0.isLetter || $0.isNumber
            }
    }
}
