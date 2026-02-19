//
//  MarkdownCommands.swift
//  BrainMesh
//
//  Lightweight Markdown editing helpers (String-based).
//  Designed to work with UITextView selection ranges (UTF-16 / NSRange).
//

import Foundation

enum MarkdownCommands {

    // MARK: - Inline wrappers

    static func bold(text: inout String, selection: inout NSRange) {
        wrap(text: &text, selection: &selection, prefix: "**", suffix: "**")
    }

    static func italic(text: inout String, selection: inout NSRange) {
        wrap(text: &text, selection: &selection, prefix: "*", suffix: "*")
    }

    static func inlineCode(text: inout String, selection: inout NSRange) {
        wrap(text: &text, selection: &selection, prefix: "`", suffix: "`")
    }

    static func link(text: inout String, selection: inout NSRange) {
        let ns = NSMutableString(string: text)
        let safeSel = clamped(selection, maxLength: ns.length)

        if safeSel.length > 0 {
            let selected = ns.substring(with: safeSel)
            let inserted = "[" + selected + "]()"
            ns.replaceCharacters(in: safeSel, with: inserted)

            // Cursor inside parentheses
            let cursor = safeSel.location + 1 + (selected as NSString).length + 2
            selection = NSRange(location: cursor, length: 0)
        } else {
            ns.insert("[]()", at: safeSel.location)
            // Cursor inside brackets
            selection = NSRange(location: safeSel.location + 1, length: 0)
        }

        text = ns as String
    }

    private static func wrap(text: inout String, selection: inout NSRange, prefix: String, suffix: String) {
        let ns = NSMutableString(string: text)
        let safeSel = clamped(selection, maxLength: ns.length)

        if safeSel.length > 0 {
            ns.insert(suffix, at: safeSel.location + safeSel.length)
            ns.insert(prefix, at: safeSel.location)

            selection = NSRange(location: safeSel.location + (prefix as NSString).length, length: safeSel.length)
        } else {
            let insertion = prefix + suffix
            ns.insert(insertion, at: safeSel.location)

            selection = NSRange(location: safeSel.location + (prefix as NSString).length, length: 0)
        }

        text = ns as String
    }

    // MARK: - Line toggles

    static func heading1(text: inout String, selection: inout NSRange) {
        toggleLinePrefix(text: &text, selection: &selection, mode: .fixed(prefix: "# "))
    }

    static func quote(text: inout String, selection: inout NSRange) {
        toggleLinePrefix(text: &text, selection: &selection, mode: .fixed(prefix: "> "))
    }

    static func bulletList(text: inout String, selection: inout NSRange) {
        toggleLinePrefix(text: &text, selection: &selection, mode: .fixed(prefix: "- "))
    }

    static func numberedList(text: inout String, selection: inout NSRange) {
        toggleLinePrefix(text: &text, selection: &selection, mode: .numbered)
    }

    private enum LineToggleMode {
        case fixed(prefix: String)
        case numbered
    }

    private static func toggleLinePrefix(text: inout String, selection: inout NSRange, mode: LineToggleMode) {
        let original = text as NSString
        let maxLen = original.length
        let safeSel = clamped(selection, maxLength: maxLen)

        let affectedRange: NSRange
        if safeSel.length == 0 {
            affectedRange = original.lineRange(for: NSRange(location: safeSel.location, length: 0))
        } else {
            affectedRange = original.lineRange(for: safeSel)
        }

        let block = original.substring(with: affectedRange)
        let hasTrailingNewline = block.hasSuffix("\n")

        // Note: components(separatedBy:) preserves empty lines in the middle.
        var lines = block.components(separatedBy: "\n")
        if hasTrailingNewline {
            // components() will add an extra empty string at end; keep it so we can restore trailing newline via join.
        } else {
            // No-op
        }

        let shouldRemove: Bool
        switch mode {
        case .fixed(let prefix):
            let nonEmpty = lines.filter { !$0.isEmpty }
            shouldRemove = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.hasPrefix(prefix) }

        case .numbered:
            let nonEmpty = lines.filter { !$0.isEmpty }
            let regex = try? NSRegularExpression(pattern: "^\\d+\\. ", options: [])
            shouldRemove = !nonEmpty.isEmpty && nonEmpty.allSatisfy { line in
                guard let regex else { return false }
                let range = NSRange(location: 0, length: (line as NSString).length)
                return regex.firstMatch(in: line, options: [], range: range) != nil
            }
        }

        var newLines: [String] = []
        newLines.reserveCapacity(lines.count)

        switch mode {
        case .fixed(let prefix):
            for line in lines {
                if line.isEmpty {
                    newLines.append(line)
                    continue
                }
                if shouldRemove {
                    if line.hasPrefix(prefix) {
                        newLines.append(String(line.dropFirst(prefix.count)))
                    } else {
                        newLines.append(line)
                    }
                } else {
                    newLines.append(prefix + line)
                }
            }

        case .numbered:
            let regex = try? NSRegularExpression(pattern: "^\\d+\\. ", options: [])
            var counter = 1
            for line in lines {
                if line.isEmpty {
                    newLines.append(line)
                    continue
                }

                if shouldRemove {
                    if let regex {
                        let range = NSRange(location: 0, length: (line as NSString).length)
                        if let match = regex.firstMatch(in: line, options: [], range: range) {
                            let after = (line as NSString).substring(from: match.range.length)
                            newLines.append(after)
                        } else {
                            newLines.append(line)
                        }
                    } else {
                        newLines.append(line)
                    }
                } else {
                    newLines.append("\(counter). \(line)")
                    counter += 1
                }
            }
        }

        var newBlock = newLines.joined(separator: "\n")
        if hasTrailingNewline && !newBlock.hasSuffix("\n") {
            newBlock += "\n"
        }

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: affectedRange, with: newBlock)
        text = mutable as String

        // Keep selection stable-ish by selecting the transformed block.
        selection = NSRange(location: affectedRange.location, length: (newBlock as NSString).length)
    }

    // MARK: - Helpers

    private static func clamped(_ range: NSRange, maxLength: Int) -> NSRange {
        let safeLocation = Swift.max(0, Swift.min(range.location, maxLength))
        let safeLength = Swift.max(0, Swift.min(range.length, maxLength - safeLocation))
        return NSRange(location: safeLocation, length: safeLength)
    }
}
