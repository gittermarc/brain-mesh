//
//  GraphChatCapabilityCatalog.swift
//  BrainMesh
//
//  Authoritative, app-owned capabilities for stable graph-chat guidance.
//

import Foundation

nonisolated enum GraphChatCapabilityID:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case entityEntries = "entity-entries"
    case nodeProfile = "node-profile"
    case directRelationships = "direct-relationships"
    case frequencyRelationshipChain = "frequency-relationship-chain"
}

nonisolated enum GraphChatCapabilityCategory:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case collections
    case profiles
    case directRelationships
    case relationshipChains
}

nonisolated enum GraphChatCapabilityPlacement:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case starterQuestion
    case generalHelp
}

nonisolated enum GraphChatCapabilityPrerequisite:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case activeGraph
    case matchingChatScope
    case uniquelyBoundEntity
    case uniquelyBoundNode
    case oneOrTwoUniquelyBoundNodes
    case entireGraphScope
    case twoOrThreeUniquelyBoundEntities
    case explicitFrequencyInLinkNote
}

nonisolated enum GraphChatCapabilityCompilerFamily:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case foundationalEntityCollection
    case foundationalNodeProfile
    case deterministicDirectRelationship
    case deterministicFrequencyRelationship
}

nonisolated enum GraphChatCapabilityReadPlanFamily:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case entityCollection
    case nodeProfile
    case directRelationships
    case composableNodeCollection
}

nonisolated enum GraphChatCapabilityStarterRule:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case entityCollectionQuestion
    case nodeProfileQuestion
    case directRelationshipQuestion
    case explicitFrequencyRelationshipQuestion
}

nonisolated struct GraphChatCapabilityProductionPath:
    Hashable,
    Sendable
{
    let compilerFamily: GraphChatCapabilityCompilerFamily
    let typedIntentKind: GraphChatTypedIntentKind
    let readPlanFamily: GraphChatCapabilityReadPlanFamily
    let requiredTools: Set<GraphChatToolKind>
}

nonisolated struct GraphChatCapabilityPresentation:
    Hashable,
    Sendable
{
    let title: String
    let summary: String
    let genericExample: String
}

nonisolated struct GraphChatCapability:
    Hashable,
    Sendable,
    Identifiable
{
    let id: GraphChatCapabilityID
    let category: GraphChatCapabilityCategory
    let german: GraphChatCapabilityPresentation
    let english: GraphChatCapabilityPresentation
    let prerequisites: [GraphChatCapabilityPrerequisite]
    let productionPath: GraphChatCapabilityProductionPath
    let starterRule: GraphChatCapabilityStarterRule
    let placements: Set<GraphChatCapabilityPlacement>

    func presentation(
        for language: GraphChatResponseLanguage
    ) -> GraphChatCapabilityPresentation {
        language == .german ? german : english
    }
}

nonisolated enum GraphChatCapabilityCatalog {
    /// Stable order is part of the presentation contract. New capabilities
    /// are appended only after their complete production path is proven.
    static let stable: [GraphChatCapability] = [
        GraphChatCapability(
            id: .entityEntries,
            category: .collections,
            german: GraphChatCapabilityPresentation(
                title: "Einträge auflisten",
                summary:
                    "Listet die vorhandenen Einträge einer eindeutig erkannten Entity auf.",
                genericExample: "Zeige mir alle <Entity>."
            ),
            english: GraphChatCapabilityPresentation(
                title: "List entries",
                summary:
                    "Lists the available entries of one unambiguously recognized entity.",
                genericExample: "Show me all <entity>."
            ),
            prerequisites: [
                .activeGraph,
                .matchingChatScope,
                .uniquelyBoundEntity,
            ],
            productionPath: GraphChatCapabilityProductionPath(
                compilerFamily: .foundationalEntityCollection,
                typedIntentKind: .entityCollection,
                readPlanFamily: .entityCollection,
                requiredTools: [.queryDetailValues]
            ),
            starterRule: .entityCollectionQuestion,
            placements: [
                .starterQuestion,
                .generalHelp,
            ]
        ),
        GraphChatCapability(
            id: .nodeProfile,
            category: .profiles,
            german: GraphChatCapabilityPresentation(
                title: "Profil anzeigen",
                summary:
                    "Zeigt das vollständige belegbare Profil eines eindeutig erkannten Nodes.",
                genericExample: "Zeige mir Details zu <Node>."
            ),
            english: GraphChatCapabilityPresentation(
                title: "Show profile",
                summary:
                    "Shows all available profile information for one unambiguously recognized node.",
                genericExample: "Show me details about <node>."
            ),
            prerequisites: [
                .activeGraph,
                .matchingChatScope,
                .uniquelyBoundNode,
            ],
            productionPath: GraphChatCapabilityProductionPath(
                compilerFamily: .foundationalNodeProfile,
                typedIntentKind: .nodeDetails,
                readPlanFamily: .nodeProfile,
                requiredTools: [.getNode]
            ),
            starterRule: .nodeProfileQuestion,
            placements: [
                .starterQuestion,
                .generalHelp,
            ]
        ),
        GraphChatCapability(
            id: .directRelationships,
            category: .directRelationships,
            german: GraphChatCapabilityPresentation(
                title: "Direkte Verbindungen",
                summary:
                    "Zeigt direkte Verbindungen eines eindeutig erkannten Nodes oder zwischen zwei eindeutig erkannten Nodes.",
                genericExample: "Zeige alle direkten Verbindungen von <Node>."
            ),
            english: GraphChatCapabilityPresentation(
                title: "Direct connections",
                summary:
                    "Shows direct connections of one unambiguously recognized node or between two unambiguously recognized nodes.",
                genericExample: "Show all direct links for <node>."
            ),
            prerequisites: [
                .activeGraph,
                .matchingChatScope,
                .oneOrTwoUniquelyBoundNodes,
            ],
            productionPath: GraphChatCapabilityProductionPath(
                compilerFamily: .deterministicDirectRelationship,
                typedIntentKind: .relationships,
                readPlanFamily: .directRelationships,
                requiredTools: [.getNeighbors]
            ),
            starterRule: .directRelationshipQuestion,
            placements: [
                .starterQuestion,
                .generalHelp,
            ]
        ),
        GraphChatCapability(
            id: .frequencyRelationshipChain,
            category: .relationshipChains,
            german: GraphChatCapabilityPresentation(
                title: "Einfache Beziehungsketten",
                summary:
                    "Findet Einträge über eine oder zwei Verbindungsstufen, wenn eine eindeutige Häufigkeit aus einer Verbindungsnotiz genannt wird.",
                genericExample:
                    "Welche <Entity A> sind mit <Entity B> über eine mit „dreimal“ markierte Verbindung verknüpft?"
            ),
            english: GraphChatCapabilityPresentation(
                title: "Simple relationship chains",
                summary:
                    "Finds entries across one or two connection stages when an explicit frequency from a link note is named.",
                genericExample:
                    "Which <entity A> are linked to <entity B> by a connection marked “three times”?"
            ),
            prerequisites: [
                .activeGraph,
                .entireGraphScope,
                .twoOrThreeUniquelyBoundEntities,
                .explicitFrequencyInLinkNote,
            ],
            productionPath: GraphChatCapabilityProductionPath(
                compilerFamily: .deterministicFrequencyRelationship,
                typedIntentKind: .entityCollection,
                readPlanFamily: .composableNodeCollection,
                requiredTools: [.getNeighbors]
            ),
            starterRule: .explicitFrequencyRelationshipQuestion,
            placements: [.generalHelp]
        ),
    ]

    static func capability(
        withID id: GraphChatCapabilityID
    ) -> GraphChatCapability? {
        stable.first { $0.id == id }
    }
}
