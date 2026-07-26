//
//  GraphChatPresentationFirewall.swift
//  BrainMesh
//
//  Deterministic trust boundary for every model-generated visible string.
//

import Foundation

nonisolated enum GraphChatUnresolvedTechnicalContentKind: String, Hashable, Sendable {
    case alias
    case conversationReference
    case technicalIdentifier
}

nonisolated struct GraphChatUnresolvedTechnicalContent: Hashable, Sendable {
    let kind: GraphChatUnresolvedTechnicalContentKind
    let identifier: String
}

nonisolated enum GraphChatPresentationResult: Hashable, Sendable {
    case safe(String)
    case unsafe(GraphChatUnresolvedTechnicalContent)
}

nonisolated enum GraphChatAnswerFirewallResult: Hashable, Sendable {
    case safe(GraphChatAnswer)
    case unsafe(GraphChatUnresolvedTechnicalContent)
}

nonisolated struct GraphChatPresentationFirewall: Sendable {
    private static let technicalTokenExpression = try! NSRegularExpression(
        pattern:
            #"(?<![A-Za-z0-9_])(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[EFN][0-9]+|CURRENT(?:_[0-9]+)?|LAST_COMPARISON(?:_[0-9]+)?|C(?:R|I|G|N|E|F|C)_[A-Z0-9_]+)(?![A-Za-z0-9_])"#
    )

    func present(
        _ text: String,
        using registry: GraphChatValidatedPresentationRegistry
    ) -> GraphChatPresentationResult {
        present(
            text,
            using: registry,
            resolving: []
        )
    }

    private func present(
        _ text: String,
        using registry: GraphChatValidatedPresentationRegistry,
        resolving identifiersBeingResolved: Set<String>
    ) -> GraphChatPresentationResult {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = Self.technicalTokenExpression.matches(
            in: text,
            range: fullRange
        )
        guard matches.isEmpty == false else {
            return .safe(text)
        }

        var output = ""
        var previousUTF16Location = 0
        for match in matches {
            let prefixRange = NSRange(
                location: previousUTF16Location,
                length: match.range.location - previousUTF16Location
            )
            guard let swiftPrefixRange = Range(prefixRange, in: text),
                  let swiftMatchRange = Range(match.range, in: text) else {
                return .unsafe(
                    GraphChatUnresolvedTechnicalContent(
                        kind: .technicalIdentifier,
                        identifier: ""
                    )
                )
            }
            output.append(contentsOf: text[swiftPrefixRange])
            let identifier = String(text[swiftMatchRange])
            let normalizedIdentifier =
                GraphChatValidatedPresentationRegistry.normalizedIdentifier(
                    identifier
                )
            guard identifiersBeingResolved.contains(
                normalizedIdentifier
            ) == false else {
                return .unsafe(
                    GraphChatUnresolvedTechnicalContent(
                        kind: unresolvedKind(for: identifier),
                        identifier: identifier
                    )
                )
            }
            guard let displayName = registry.displayName(
                for: identifier
            ) else {
                return .unsafe(
                    GraphChatUnresolvedTechnicalContent(
                        kind: unresolvedKind(for: identifier),
                        identifier: identifier
                    )
                )
            }
            var nestedIdentifiers = identifiersBeingResolved
            nestedIdentifiers.insert(normalizedIdentifier)
            switch present(
                displayName,
                using: registry,
                resolving: nestedIdentifiers
            ) {
            case .safe(let safeDisplayName):
                output.append(safeDisplayName)
            case .unsafe(let content):
                return .unsafe(content)
            }
            previousUTF16Location = NSMaxRange(match.range)
        }

        let suffixRange = NSRange(
            location: previousUTF16Location,
            length: fullRange.length - previousUTF16Location
        )
        guard let swiftSuffixRange = Range(suffixRange, in: text) else {
            return .unsafe(
                GraphChatUnresolvedTechnicalContent(
                    kind: .technicalIdentifier,
                    identifier: ""
                )
            )
        }
        output.append(contentsOf: text[swiftSuffixRange])
        return .safe(output)
    }

    func present(
        _ answer: GraphChatAnswer,
        context: GraphChatPresentationContext
    ) -> GraphChatAnswerFirewallResult {
        let directAnswer: String
        switch present(answer.directAnswer, using: context.registry) {
        case .safe(let value):
            directAnswer = value
        case .unsafe(let content):
            return .unsafe(content)
        }

        var sections: [GraphChatAnswerSection] = []
        sections.reserveCapacity(answer.sections.count)
        for section in answer.sections {
            let title: String?
            if let rawTitle = section.title {
                switch present(rawTitle, using: context.registry) {
                case .safe(let value):
                    title = value
                case .unsafe(let content):
                    return .unsafe(content)
                }
            } else {
                title = nil
            }
            let text: String
            switch present(section.text, using: context.registry) {
            case .safe(let value):
                text = value
            case .unsafe(let content):
                return .unsafe(content)
            }
            sections.append(
                GraphChatAnswerSection(
                    id: section.id,
                    title: title,
                    text: text,
                    evidenceIDs: section.evidenceIDs,
                    artifactIDs: section.artifactIDs,
                    querySummary: section.querySummary,
                    state: section.state
                )
            )
        }

        var filters: [GraphChatAppliedFilter] = []
        filters.reserveCapacity(answer.appliedFilters.count)
        for filter in answer.appliedFilters {
            let fieldName: String
            switch present(
                filter.fieldName,
                using: context.registry
            ) {
            case .safe(let value):
                fieldName = value
            case .unsafe(let content):
                return .unsafe(content)
            }
            let operationDescription: String
            switch present(
                filter.operationDescription,
                using: context.registry
            ) {
            case .safe(let value):
                operationDescription = value
            case .unsafe(let content):
                return .unsafe(content)
            }
            let valueDescription: String?
            if let rawValue = filter.valueDescription {
                switch present(rawValue, using: context.registry) {
                case .safe(let value):
                    valueDescription = value
                case .unsafe(let content):
                    return .unsafe(content)
                }
            } else {
                valueDescription = nil
            }
            filters.append(
                GraphChatAppliedFilter(
                    id: filter.id,
                    fieldName: fieldName,
                    operationDescription: operationDescription,
                    valueDescription: valueDescription
                )
            )
        }

        var followUps: [GraphChatFollowUpSuggestion] = []
        followUps.reserveCapacity(answer.followUpSuggestions.count)
        for suggestion in answer.followUpSuggestions {
            let title: String
            switch present(suggestion.title, using: context.registry) {
            case .safe(let value):
                title = value
            case .unsafe(let content):
                return .unsafe(content)
            }
            let prompt: String
            switch present(suggestion.prompt, using: context.registry) {
            case .safe(let value):
                prompt = value
            case .unsafe(let content):
                return .unsafe(content)
            }
            followUps.append(
                GraphChatFollowUpSuggestion(
                    id: suggestion.id,
                    title: title,
                    prompt: prompt
                )
            )
        }

        let state: GraphChatAnswerState
        switch answer.state {
        case .answer:
            state = .answer
        case .noResults:
            state = .noResults
        case .unsupported(let capability):
            state = .unsupported(capability)
        case .clarification(let clarification):
            let question: String
            switch present(
                clarification.question,
                using: context.registry
            ) {
            case .safe(let value):
                question = value
            case .unsafe(let content):
                return .unsafe(content)
            }
            var options: [GraphChatClarificationOption] = []
            options.reserveCapacity(clarification.options.count)
            for option in clarification.options {
                switch present(
                    option.title,
                    using: context.registry
                ) {
                case .safe(let value):
                    options.append(
                        GraphChatClarificationOption(
                            id: option.id,
                            title: value
                        )
                    )
                case .unsafe(let content):
                    return .unsafe(content)
                }
            }
            state = .clarification(
                GraphChatClarification(
                    id: clarification.id,
                    question: question,
                    options: options
                )
            )
        }

        return .safe(
            GraphChatAnswer(
                state: state,
                directAnswer: directAnswer,
                sections: sections,
                evidence: answer.evidence,
                artifactIDs: answer.artifactIDs,
                appliedFilters: filters,
                followUpSuggestions: followUps,
                hasInsufficientEvidence: answer.hasInsufficientEvidence,
                presentationContext: context
            )
        )
    }

    func replacementAnswer(
        language: GraphChatResponseLanguage,
        registry: GraphChatValidatedPresentationRegistry
    ) -> GraphChatAnswer {
        let context = GraphChatPresentationContext(
            registry: registry,
            language: language
        )
        return GraphChatAnswer(
            state: .answer,
            directAnswer: GraphChatResponseLocalizer(
                language: language
            ).unsafePresentation(),
            hasInsufficientEvidence: true,
            presentationContext: context
        )
    }

    private func unresolvedKind(
        for identifier: String
    ) -> GraphChatUnresolvedTechnicalContentKind {
        if UUID(uuidString: identifier) != nil {
            return .technicalIdentifier
        }
        if identifier.hasPrefix("CURRENT")
            || identifier.hasPrefix("LAST_COMPARISON")
            || identifier.hasPrefix("C") {
            return .conversationReference
        }
        return .alias
    }
}

actor GraphChatPresentationStreamFirewall {
    private let registry: GraphChatPresentationRegistry
    private let language: GraphChatResponseLanguage
    private let firewall: GraphChatPresentationFirewall
    private var encounteredUnsafeContent = false

    init(
        registry: GraphChatPresentationRegistry,
        language: GraphChatResponseLanguage,
        firewall: GraphChatPresentationFirewall =
            GraphChatPresentationFirewall()
    ) {
        self.registry = registry
        self.language = language
        self.firewall = firewall
    }

    func presentCumulativeText(_ text: String) async -> String {
        guard encounteredUnsafeContent == false else {
            return fallback
        }
        let snapshot = await registry.snapshot()
        switch firewall.present(text, using: snapshot) {
        case .safe(let safeText):
            return safeText
        case .unsafe:
            encounteredUnsafeContent = true
            return fallback
        }
    }

    private var fallback: String {
        GraphChatResponseLocalizer(
            language: language
        ).unsafePresentation()
    }
}
