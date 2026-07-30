//
//  GraphMentionLexiconResource.swift
//  BrainMesh
//
//  Loads versioned, app-owned mention aliases without embedding graph-domain
//  vocabulary in matching code.
//

import Foundation

nonisolated extension GraphMentionLexicon {
    static let appOwned =
        GraphMentionLexiconResource.load()
}

private nonisolated enum GraphMentionLexiconResource {
    private static let supportedVersion = 1

    private final class BundleToken {}

    private struct Payload: Decodable {
        let version: Int
        let groups: [Group]
    }

    private struct Group: Decodable {
        let kind: String
        let origin: String
        let terms: [Term]
    }

    private struct Term: Decodable {
        let value: String
        let language: String
    }

    static func load() -> GraphMentionLexicon {
        let bundles = [
            Bundle.main,
            Bundle(for: BundleToken.self),
        ]
        guard
            let url = bundles.compactMap({
                $0.url(
                    forResource: "GraphMentionAliases",
                    withExtension: "json"
                )
            }).first,
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(
                Payload.self,
                from: data
            ),
            payload.version == supportedVersion
        else {
            return GraphMentionLexicon(groups: [])
        }

        var groups: [GraphMentionAliasGroup] = []
        for group in payload.groups {
            guard
                let kind =
                    GraphMentionKind(
                        rawValue: group.kind
                    ),
                let origin =
                    GraphMentionAliasOrigin(
                        rawValue: group.origin
                    ),
                origin != .displayName
            else {
                continue
            }
            let terms = group.terms.compactMap {
                term -> GraphMentionLexiconTerm? in
                guard
                    let language =
                        GraphChatResponseLanguage(
                            rawValue: term.language
                        ),
                    GraphMentionTextNormalization
                        .canonical(term.value)
                        .isEmpty == false
                else {
                    return nil
                }
                return GraphMentionLexiconTerm(
                    value: term.value,
                    language: language
                )
            }
            guard terms.count >= 2 else {
                continue
            }
            groups.append(
                GraphMentionAliasGroup(
                    kind: kind,
                    origin: origin,
                    terms: terms
                )
            )
        }
        return GraphMentionLexicon(groups: groups)
    }
}
