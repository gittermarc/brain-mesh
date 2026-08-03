//
//  GraphChatComposableReadTextNormalizer.swift
//  BrainMesh
//
//  Conservative local normalization for explicit link-note text predicates.
//

import Foundation

nonisolated enum GraphChatComposableReadTextNormalizer {
    private static let frequencyWords: [String: Int] = [
        "once": 1,
        "twice": 2,
        "einmal": 1,
        "zweimal": 2,
        "dreimal": 3,
        "viermal": 4,
        "funfmal": 5,
        "sechsmal": 6,
        "siebenmal": 7,
        "achtmal": 8,
        "neunmal": 9,
        "zehnmal": 10,
        "elfmal": 11,
        "zwolfmal": 12,
    ]

    private static let numberWords: [String: Int] = [
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10,
        "eleven": 11,
        "twelve": 12,
        "ein": 1,
        "eins": 1,
        "zwei": 2,
        "drei": 3,
        "vier": 4,
        "funf": 5,
        "sechs": 6,
        "sieben": 7,
        "acht": 8,
        "neun": 9,
        "zehn": 10,
        "elf": 11,
        "zwolf": 12,
    ]

    static func normalized(_ source: String) -> String {
        let folded = source
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive,
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        let tokens = folded
            .components(
                separatedBy:
                    CharacterSet.alphanumerics
                        .union(CharacterSet(charactersIn: "×"))
                        .inverted
            )
            .filter { $0.isEmpty == false }

        var result: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let count = frequencyWords[token] {
                result.append("frequency\(count)")
                index += 1
                continue
            }
            if let count = numericFrequency(token) {
                result.append("frequency\(count)")
                index += 1
                continue
            }
            if let count = numberWords[token],
               index + 1 < tokens.count,
               ["mal", "time", "times"].contains(
                   tokens[index + 1]
               ) {
                result.append("frequency\(count)")
                index += 2
                continue
            }
            if let count = Int(token),
               index + 1 < tokens.count,
               ["x", "×", "mal", "time", "times"]
                .contains(tokens[index + 1]) {
                result.append("frequency\(count)")
                index += 2
                continue
            }
            result.append(token)
            index += 1
        }
        return result.joined(separator: " ")
    }

    static func contains(
        _ source: String,
        term: String
    ) -> Bool {
        let normalizedSource = normalized(source)
        let normalizedTerm = normalized(term)
        guard normalizedTerm.isEmpty == false else {
            return false
        }
        let sourceTokens = normalizedSource.split(
            separator: " "
        )
        let termTokens = normalizedTerm.split(
            separator: " "
        )
        guard termTokens.count <= sourceTokens.count else {
            return false
        }
        if termTokens.isEmpty {
            return false
        }
        for start in 0...(sourceTokens.count - termTokens.count) {
            if Array(
                sourceTokens[
                    start..<(start + termTokens.count)
                ]
            ) == termTokens {
                return true
            }
        }
        return false
    }

    static func frequencyLiteral(
        in source: String
    ) -> String? {
        let patterns = [
            #"(?i)(?<![\p{L}\p{N}])\d{1,3}\s*(?:x|×|mal|times?)(?![\p{L}\p{N}])"#,
            #"(?i)(?<![\p{L}\p{N}])(?:einmal|zweimal|dreimal|viermal|fünfmal|sechsmal|siebenmal|achtmal|neunmal|zehnmal|elfmal|zwölfmal|once|twice)(?![\p{L}\p{N}])"#,
            #"(?i)(?<![\p{L}\p{N}])(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+times?(?![\p{L}\p{N}])"#,
            #"(?i)(?<![\p{L}\p{N}])(?:ein|eins|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf)\s+mal(?![\p{L}\p{N}])"#,
        ]
        let fullRange = NSRange(
            source.startIndex..<source.endIndex,
            in: source
        )
        var matches: [(range: NSRange, literal: String)] = []
        for pattern in patterns {
            guard
                let expression = try? NSRegularExpression(
                    pattern: pattern
                )
            else {
                continue
            }
            for match in expression.matches(
                in: source,
                range: fullRange
            ) {
                guard let range = Range(
                    match.range,
                    in: source
                ) else {
                    continue
                }
                matches.append(
                    (
                        range: match.range,
                        literal: String(source[range])
                    )
                )
            }
        }
        let ordered = matches.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }
        guard
            let first = ordered.first,
            Set(ordered.map { normalized($0.literal) })
                .count == 1
        else {
            return nil
        }
        return first.literal
    }

    private static func numericFrequency(
        _ token: String
    ) -> Int? {
        let suffixes = ["times", "time", "mal", "x", "×"]
        for suffix in suffixes where token.hasSuffix(suffix) {
            let prefix = token.dropLast(suffix.count)
            guard prefix.isEmpty == false,
                  let count = Int(prefix) else {
                continue
            }
            return count
        }
        return nil
    }
}
