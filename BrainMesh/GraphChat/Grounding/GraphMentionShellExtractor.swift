//
//  GraphMentionShellExtractor.swift
//  BrainMesh
//
//  Bounded bilingual extraction of domain text from provider-free shells.
//

import Foundation

nonisolated enum GraphMentionFastPathFamily:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case entityCollection
    case nodeDetails
}

nonisolated struct GraphMentionShellExtraction:
    Hashable,
    Sendable
{
    let family: GraphMentionFastPathFamily
    let mention: String
}

nonisolated struct GraphMentionShellExtractor:
    Hashable,
    Sendable
{
    private struct Shell: Hashable {
        let prefix: [String]
        let suffixes: [[String]]
    }

    func extract(
        from question: String,
        family: GraphMentionFastPathFamily,
        language: GraphChatResponseLanguage
    ) -> GraphMentionShellExtraction? {
        let tokens =
            GraphMentionTextNormalization.tokens(question)
        guard tokens.isEmpty == false else {
            return nil
        }
        for shell in shells(
            for: family,
            language: language
        ).sorted(by: shellSort) {
            guard tokens.starts(with: shell.prefix) else {
                continue
            }
            let remainder = Array(
                tokens.dropFirst(shell.prefix.count)
            )
            for suffix in shell.suffixes.sorted(
                by: suffixSort
            ) {
                guard remainder.count > suffix.count,
                      suffix.isEmpty
                        || Array(
                            remainder.suffix(suffix.count)
                        ) == suffix else {
                    continue
                }
                let mentionTokens = suffix.isEmpty
                    ? remainder
                    : Array(
                        remainder.dropLast(suffix.count)
                    )
                guard mentionTokens.isEmpty == false else {
                    continue
                }
                return GraphMentionShellExtraction(
                    family: family,
                    mention:
                        mentionTokens.joined(
                            separator: " "
                        )
                )
            }
        }
        return nil
    }

    private func shells(
        for family: GraphMentionFastPathFamily,
        language: GraphChatResponseLanguage
    ) -> [Shell] {
        switch (family, language) {
        case (.entityCollection, .german):
            return [
                shell(
                    "welche",
                    suffixes: [
                        "habe ich gemacht",
                        "habe ich",
                        "gibt es",
                        "sind vorhanden",
                        "existieren",
                        "",
                    ]
                ),
                shell(
                    "zeige mir alle",
                    suffixes: ["", "auf"]
                ),
                shell(
                    "zeig mir alle",
                    suffixes: ["", "auf"]
                ),
                shell(
                    "liste mir alle",
                    suffixes: ["", "auf"]
                ),
                shell(
                    "liste alle",
                    suffixes: ["", "auf"]
                ),
                shell(
                    "nenne mir alle",
                    suffixes: [""]
                ),
                shell(
                    "alle",
                    suffixes: [""]
                ),
            ]

        case (.entityCollection, .english):
            return [
                shell(
                    "which",
                    suffixes: [
                        "have i taken",
                        "do i have",
                        "are there",
                        "have i",
                        "exist",
                        "",
                    ]
                ),
                shell(
                    "what",
                    suffixes: [
                        "do i have",
                        "are there",
                    ]
                ),
                shell(
                    "show me all",
                    suffixes: [""]
                ),
                shell(
                    "list all",
                    suffixes: [""]
                ),
                shell(
                    "list me all",
                    suffixes: [""]
                ),
                shell(
                    "all",
                    suffixes: [""]
                ),
            ]

        case (.nodeDetails, .german):
            return [
                shell(
                    "nenne mir details zu",
                    suffixes: [""]
                ),
                shell(
                    "nenn mir details zu",
                    suffixes: [""]
                ),
                shell(
                    "zeige mir details zu",
                    suffixes: [""]
                ),
                shell(
                    "zeig mir details zu",
                    suffixes: [""]
                ),
                shell(
                    "gib mir details zu",
                    suffixes: [""]
                ),
                shell(
                    "beschreibe",
                    suffixes: [
                        "vollständig",
                        "im detail",
                        "",
                    ]
                ),
                shell(
                    "erzähle mir alles über",
                    suffixes: [""]
                ),
                shell(
                    "erzähl mir alles über",
                    suffixes: [""]
                ),
            ]

        case (.nodeDetails, .english):
            return [
                shell(
                    "show me details about",
                    suffixes: [""]
                ),
                shell(
                    "show me details for",
                    suffixes: [""]
                ),
                shell(
                    "give me details about",
                    suffixes: [""]
                ),
                shell(
                    "give me details on",
                    suffixes: [""]
                ),
                shell(
                    "describe",
                    suffixes: [
                        "completely",
                        "in detail",
                        "",
                    ]
                ),
                shell(
                    "tell me everything about",
                    suffixes: [""]
                ),
            ]
        }
    }

    private func shell(
        _ prefix: String,
        suffixes: [String]
    ) -> Shell {
        Shell(
            prefix:
                GraphMentionTextNormalization
                    .tokens(prefix),
            suffixes: suffixes.map {
                GraphMentionTextNormalization
                    .tokens($0)
            }
        )
    }

    private func shellSort(
        _ lhs: Shell,
        _ rhs: Shell
    ) -> Bool {
        if lhs.prefix.count != rhs.prefix.count {
            return lhs.prefix.count >
                rhs.prefix.count
        }
        return lhs.prefix
            .lexicographicallyPrecedes(rhs.prefix)
    }

    private func suffixSort(
        _ lhs: [String],
        _ rhs: [String]
    ) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs.lexicographicallyPrecedes(rhs)
    }
}
