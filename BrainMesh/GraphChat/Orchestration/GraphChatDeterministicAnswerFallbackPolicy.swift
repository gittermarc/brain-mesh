//
//  GraphChatDeterministicAnswerFallbackPolicy.swift
//  BrainMesh
//
//  Authoritative source projection and deterministic fallback triggers.
//

import Foundation

nonisolated struct GraphChatDeterministicAnswerFallbackSource:
    Hashable,
    Sendable
{
    private nonisolated struct AppliedFilterKey: Hashable, Sendable {
        let fieldName: String
        let operationDescription: String
        let valueDescription: String?
    }

    let kind: GraphChatPrimaryResultKind
    let completionStatus: GraphChatToolExecutionCompletionStatus
    let evidence: [GraphEvidence]
    let artifacts: [GraphChatAnswerArtifact]
    let appliedFilters: [GraphChatAppliedFilter]

    init(
        kind: GraphChatPrimaryResultKind,
        completionStatus: GraphChatToolExecutionCompletionStatus,
        evidence: [GraphEvidence],
        artifacts: [GraphChatAnswerArtifact],
        appliedFilters: [GraphChatAppliedFilter] = []
    ) {
        self.kind = kind
        self.completionStatus = completionStatus
        self.evidence = GraphEvidenceCollection(evidence).values
        var seenArtifactIDs = Set<GraphChatAnswerArtifactID>()
        self.artifacts = artifacts.filter {
            seenArtifactIDs.insert($0.id).inserted
        }
        self.appliedFilters = Self.deduplicatedFilters(appliedFilters)
    }

    init?(
        primaryResult: GraphChatToolExecutionLedgerEntry?,
        retaining answer: GraphChatAnswer
    ) {
        guard let primaryResult,
              primaryResult.isEligibleAsPrimary,
              primaryResult.completionStatus != .unverified else {
            return nil
        }
        let retainedEvidenceIDs = Set(answer.evidenceIDs)
        let retainedArtifactIDs = Set(answer.artifactIDs)
        self.kind = primaryResult.kind
        self.completionStatus = primaryResult.completionStatus
        self.evidence = primaryResult.evidence.filter {
            retainedEvidenceIDs.contains($0.id)
        }
        let retainedArtifacts =
            primaryResult.artifacts
            .filter {
                retainedArtifactIDs
                    .contains($0.id)
            }
            .compactMap { artifact in
                switch artifact.payload {
                case .nodeProfile:
                    return GraphChatNodeProfileArtifactEvidenceProjector
                        .revalidatedArtifact(
                            artifact,
                            availableEvidenceIDs:
                                retainedEvidenceIDs
                        )
                case .relationship:
                    return GraphChatRelationshipArtifactEvidenceProjector
                        .revalidatedArtifact(
                            artifact,
                            availableEvidenceIDs:
                                retainedEvidenceIDs
                        )
                default:
                    return artifact
                }
            }
        self.artifacts = retainedArtifacts
        self.appliedFilters = Self.filters(in: retainedArtifacts)
    }

    private static func filters(
        in artifacts: [GraphChatAnswerArtifact]
    ) -> [GraphChatAppliedFilter] {
        let filters = artifacts.flatMap { artifact in
            artifact.querySummary?.filters.map { filter in
                GraphChatAppliedFilter(
                    id: GraphEvidenceStableIdentity.deterministicUUID(
                        for: "fallback-filter|\(filter.id)"
                    ),
                    fieldName: filter.field.label,
                    operationDescription: filter.operationLabel,
                    valueDescription: filter.valueDescription
                )
            } ?? []
        }
        return deduplicatedFilters(filters)
    }

    private static func deduplicatedFilters(
        _ filters: [GraphChatAppliedFilter]
    ) -> [GraphChatAppliedFilter] {
        var seen = Set<AppliedFilterKey>()
        return filters.filter { filter in
            seen.insert(
                AppliedFilterKey(
                    fieldName: filter.fieldName,
                    operationDescription: filter.operationDescription,
                    valueDescription: filter.valueDescription
                )
            ).inserted
        }
    }

    var hasAuthoritativeReferences: Bool {
        evidence.isEmpty == false || artifacts.isEmpty == false
    }

    var authoritativeCount: Int? {
        for artifact in artifacts {
            switch artifact.payload {
            case .nodeProfile:
                return 1
            case .relationship(let payload):
                return payload
                    .resultMetadata.totalCount
                    ?? payload
                        .resultMetadata
                        .returnedCount

            case .metric(let payload):
                guard let aggregation = artifact.querySummary?.aggregation,
                      case .count = aggregation,
                      case .integer(let value) = payload.value else {
                    continue
                }
                return value

            case .resultList(let payload):
                return payload.resultMetadata.totalCount
                    ?? payload.resultMetadata.returnedCount

            case .table(let payload):
                return payload.resultMetadata.totalCount
                    ?? payload.resultMetadata.returnedCount

            case .ranking(let payload):
                return payload.resultMetadata.totalCount
                    ?? payload.resultMetadata.returnedCount

            case .grouping(let payload):
                return payload.groups.reduce(0) { $0 + $1.count }

            case .comparison(let payload):
                return payload.subjects.count

            case .healthFinding(let payload):
                return payload.affectedElementCount

            case .timeline(let payload):
                return payload.resultMetadata.totalCount
                    ?? payload.resultMetadata.returnedCount
            }
        }
        return nil
    }
}

nonisolated enum GraphChatDeterministicAnswerFallbackReason:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case emptyAnswer
    case technicalText
    case contradictoryNoResults
    case contradictoryCount
    case contradictoryState
}

nonisolated struct GraphChatDeterministicAnswerFallbackPolicy: Sendable {
    private static let technicalMarkers = [
        "toolerror",
        "tool error",
        "tool call failed",
        "failed to execute tool",
        "resolvererror",
        "resolver error",
        "resolver failed",
        "providererror",
        "provider error",
        "provider failed",
        "repositoryerror",
        "repository error",
        "repository failed",
        "validationerror",
        "validation error",
        "error domain",
        "localizeddescription",
        "stacktrace",
        "stack trace",
        "exception:",
        "status code:",
        "unknown alias",
        "querydetailvaluestool",
        "graphchattool",
        "tool-fehler",
        "tool-aufruf fehlgeschlagen",
        "resolver-fehler",
        "resolver fehlgeschlagen",
        "provider-fehler",
        "provider fehlgeschlagen",
        "repository-fehler",
        "repository fehlgeschlagen",
        "validierungsfehler",
    ]

    private static let noResultClaims = [
        "no results",
        "no matches",
        "nothing was found",
        "nothing found",
        "could not find any results",
        "couldn't find any results",
        "did not find any results",
        "didn't find any results",
        "0 results",
        "0 matches",
        "keine ergebnisse",
        "kein ergebnis",
        "keine treffer",
        "nichts gefunden",
        "konnte keine ergebnisse finden",
        "habe keine ergebnisse gefunden",
        "0 ergebnisse",
        "0 treffer",
    ]

    private static let inconsistentStateClaims = [
        "this is not supported",
        "this request is not supported",
        "that is not supported",
        "unsupported request",
        "cannot access the requested data",
        "can't access the requested data",
        "please clarify the request",
        "i need more information before",
        "das wird nicht unterstützt",
        "diese anfrage wird nicht unterstützt",
        "kann auf die angefragten daten nicht zugreifen",
        "bitte präzisiere die anfrage",
        "benötige weitere informationen, bevor",
    ]

    private static let claimedCountExpressions = [
        try! NSRegularExpression(
            pattern:
                #"(?i)\b(?:i\s+found|we\s+found|found|returned)\s+([0-9]+)\b"#
        ),
        try! NSRegularExpression(
            pattern:
                #"(?i)\b([0-9]+)\s+(?:results?|matches?)\s+(?:were\s+)?found\b"#
        ),
        try! NSRegularExpression(
            pattern:
                #"(?i)\b(?:ich\s+habe|wir\s+haben)\s+([0-9]+)\s+(?:Ergebnisse?|Treffer)\s+gefunden\b"#
        ),
        try! NSRegularExpression(
            pattern:
                #"(?i)\b([0-9]+)\s+(?:Ergebnisse?|Treffer)\s+(?:wurden\s+)?gefunden\b"#
        ),
    ]

    func fallbackReason(
        for answer: GraphChatAnswer,
        source: GraphChatDeterministicAnswerFallbackSource
    ) -> GraphChatDeterministicAnswerFallbackReason? {
        guard answer.state == .answer,
              source.completionStatus == .succeeded else {
            return nil
        }
        let text = answer.directAnswer.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard text.isEmpty == false else {
            return .emptyAnswer
        }

        let visibleText = Self.visibleText(in: answer)
        if containsTechnicalPresentation(visibleText) {
            return .technicalText
        }

        let normalized = Self.normalized(visibleText)
        if Self.inconsistentStateClaims.contains(
            where: { normalized.contains($0) }
        ) {
            return .contradictoryState
        }

        guard let authoritativeCount = source.authoritativeCount else {
            return nil
        }
        if authoritativeCount > 0,
           Self.noResultClaims.contains(where: { normalized.contains($0) }) {
            return .contradictoryNoResults
        }
        if let claimedCount = Self.claimedCount(in: text),
           claimedCount != authoritativeCount {
            return .contradictoryCount
        }
        return nil
    }

    func containsTechnicalPresentation(_ text: String) -> Bool {
        let normalized = Self.normalized(text)
        return Self.technicalMarkers.contains(
            where: { normalized.contains($0) }
        )
    }

    private static func visibleText(in answer: GraphChatAnswer) -> String {
        var values = [answer.directAnswer]
        for section in answer.sections {
            if let title = section.title {
                values.append(title)
            }
            values.append(section.text)
        }
        for filter in answer.appliedFilters {
            values.append(filter.fieldName)
            values.append(filter.operationDescription)
            if let value = filter.valueDescription {
                values.append(value)
            }
        }
        for followUp in answer.followUpSuggestions {
            values.append(followUp.title)
            values.append(followUp.prompt)
        }
        return values.joined(separator: "\n")
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }

    private static func claimedCount(in text: String) -> Int? {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for expression in claimedCountExpressions {
            guard let match = expression.firstMatch(
                in: text,
                range: fullRange
            ),
                match.numberOfRanges > 1,
                let captureRange = Range(match.range(at: 1), in: text),
                let count = Int(text[captureRange])
            else {
                continue
            }
            return count
        }
        return nil
    }
}
