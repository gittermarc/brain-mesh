//
//  GraphChatNodeProfilePresentation.swift
//  BrainMesh
//
//  Shared localized projection used by deterministic answers and profile UI.
//

import Foundation

nonisolated enum GraphChatNodeProfilePresentationSectionKind:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case notes
    case detailValues
    case incomingConnections
    case outgoingConnections
    case attachments
}

nonisolated struct GraphChatNodeProfilePresentationRow:
    Hashable,
    Sendable,
    Identifiable
{
    let id: String
    let text: String
    let navigationTarget:
        GraphChatAnswerArtifactNavigationTarget?
    let evidenceIDs: [GraphEvidenceID]
}

nonisolated struct GraphChatNodeProfilePresentationSection:
    Hashable,
    Sendable,
    Identifiable
{
    let kind:
        GraphChatNodeProfilePresentationSectionKind
    let title: String
    let rows:
        [GraphChatNodeProfilePresentationRow]
    let limitationText: String?

    var id:
        GraphChatNodeProfilePresentationSectionKind
    {
        kind
    }
}

nonisolated struct GraphChatNodeProfilePresentation:
    Hashable,
    Sendable
{
    let title: String
    let nameLine: String?
    let ownerLine: String?
    let nodeNavigationTarget:
        GraphChatAnswerArtifactNavigationTarget?
    let identityEvidenceIDs:
        [GraphEvidenceID]
    let sections:
        [GraphChatNodeProfilePresentationSection]

    init(
        payload:
            GraphChatAnswerArtifactNodeProfilePayload,
        language:
            GraphChatResponseLanguage
    ) {
        let strings = Strings(language)
        let valueFormatter =
            ValueFormatter(language)
        title = strings.profile(
            payload.displayName
        )
        nameLine =
            payload.visibleName
                == payload.displayName
            ? nil
            : strings.name(
                payload.visibleName
            )
        ownerLine =
            payload.owner.map {
                strings.owner($0.label)
            }
        nodeNavigationTarget =
            payload.nodeNavigationTarget
        identityEvidenceIDs =
            payload.identityEvidence
                .evidenceIDs

        var result: [
            GraphChatNodeProfilePresentationSection
        ] = []
        if let notes = payload.notes,
            notes.text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty == false
        {
            result.append(
                GraphChatNodeProfilePresentationSection(
                    kind: .notes,
                    title: strings.notes,
                    rows: [
                        GraphChatNodeProfilePresentationRow(
                            id: "notes",
                            text: notes.text,
                            navigationTarget: nil,
                            evidenceIDs:
                                notes.evidence
                                    .evidenceIDs
                        ),
                    ],
                    limitationText: nil
                )
            )
        }

        if payload.detailValues.isEmpty == false {
            result.append(
                GraphChatNodeProfilePresentationSection(
                    kind: .detailValues,
                    title:
                        strings.detailValues,
                    rows:
                        payload.detailValues
                        .map {
                            GraphChatNodeProfilePresentationRow(
                                id:
                                    $0.id.rawValue
                                        .uuidString,
                                text:
                                    "\($0.fieldName): \(valueFormatter.string(for: $0.value, unit: $0.unit))",
                                navigationTarget:
                                    nil,
                                evidenceIDs:
                                    $0.evidence
                                        .evidenceIDs
                            )
                        },
                    limitationText:
                        strings.limitation(
                            payload
                                .detailValueMetadata,
                            section:
                                .detailValues
                        )
                )
            )
        }

        if
            payload.incomingConnections
                .isEmpty == false
        {
            result.append(
                GraphChatNodeProfilePresentationSection(
                    kind:
                        .incomingConnections,
                    title:
                        strings.incomingConnections,
                    rows:
                        payload
                        .incomingConnections
                        .map {
                            Self.connectionRow(
                                $0,
                                strings:
                                    strings
                            )
                        },
                    limitationText:
                        strings.limitation(
                            payload
                                .incomingConnectionMetadata,
                            section:
                                .incomingConnections
                        )
                )
            )
        }

        if
            payload.outgoingConnections
                .isEmpty == false
        {
            result.append(
                GraphChatNodeProfilePresentationSection(
                    kind:
                        .outgoingConnections,
                    title:
                        strings.outgoingConnections,
                    rows:
                        payload
                        .outgoingConnections
                        .map {
                            Self.connectionRow(
                                $0,
                                strings:
                                    strings
                            )
                        },
                    limitationText:
                        strings.limitation(
                            payload
                                .outgoingConnectionMetadata,
                            section:
                                .outgoingConnections
                        )
                )
            )
        }

        if payload.attachments.isEmpty == false {
            result.append(
                GraphChatNodeProfilePresentationSection(
                    kind: .attachments,
                    title: strings.attachments,
                    rows:
                        payload.attachments
                        .map {
                            GraphChatNodeProfilePresentationRow(
                                id:
                                    $0.id.rawValue
                                        .uuidString,
                                text:
                                    strings.attachment(
                                        $0,
                                        byteCount:
                                            valueFormatter
                                            .byteCount(
                                                $0.byteCount
                                            )
                                    ),
                                navigationTarget:
                                    nil,
                                evidenceIDs:
                                    $0.evidence
                                        .evidenceIDs
                            )
                        },
                    limitationText:
                        strings.limitation(
                            payload
                                .attachmentMetadata,
                            section:
                                .attachments
                        )
                )
            )
        }
        sections = result
    }

    var plainText: String {
        var blocks = [title]
        if let nameLine {
            blocks.append(nameLine)
        }
        if let ownerLine {
            blocks.append(ownerLine)
        }
        for section in sections {
            var lines = [section.title]
            lines.append(
                contentsOf:
                    section.rows.map {
                        "• \($0.text)"
                    }
            )
            if let limitationText =
                section.limitationText
            {
                lines.append(limitationText)
            }
            blocks.append(
                lines.joined(
                    separator: "\n"
                )
            )
        }
        return blocks.joined(
            separator: "\n\n"
        )
    }

    private static func connectionRow(
        _ connection:
            GraphChatAnswerArtifactNodeProfileConnection,
        strings: Strings
    ) -> GraphChatNodeProfilePresentationRow {
        var text =
            "\(connection.sourceLabel) → \(connection.targetLabel)"
        if let note =
            connection.note?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            note.isEmpty == false
        {
            text +=
                " — \(strings.linkNote): \(note)"
        }
        return GraphChatNodeProfilePresentationRow(
            id:
                connection.id.rawValue
                    .uuidString,
            text: text,
            navigationTarget:
                connection
                    .counterpartNavigationTarget,
            evidenceIDs:
                connection.evidence
                    .evidenceIDs
        )
    }
}

private nonisolated extension
    GraphChatNodeProfilePresentation
{
    struct ValueFormatter: Sendable {
        let language:
            GraphChatResponseLanguage

        private var locale: Locale {
            Locale(
                identifier:
                    language.localeIdentifier
            )
        }

        init(
            _ language:
                GraphChatResponseLanguage
        ) {
            self.language = language
        }

        func string(
            for value:
                GraphChatAnswerArtifactValue,
            unit: String?
        ) -> String {
            let base: String
            switch value {
            case .text(let value):
                base = value
            case .integer(let value):
                base = value.formatted(
                    .number.locale(locale)
                )
            case .decimal(let value):
                base =
                    NSDecimalNumber(
                        decimal: value
                    ).doubleValue.formatted(
                        .number
                        .precision(
                            .fractionLength(
                                0...3
                            )
                        )
                        .locale(locale)
                    )
            case .boolean(let value):
                switch (
                    language,
                    value
                ) {
                case (.german, true):
                    base = "Ja"
                case (.german, false):
                    base = "Nein"
                case (.english, true):
                    base = "Yes"
                case (.english, false):
                    base = "No"
                }
            case .date(let value):
                base = date(value)
            case .dateTime(let value):
                base = value.formatted(
                    .dateTime
                    .locale(locale)
                    .year()
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
                )
            case .duration(let value):
                let seconds =
                    max(
                        0,
                        Int(value.rounded())
                    )
                base =
                    language == .german
                    ? "\(seconds) Sek."
                    : "\(seconds) sec"
            case .percentage(let value):
                base =
                    NSDecimalNumber(
                        decimal: value
                    ).doubleValue.formatted(
                        .percent
                        .precision(
                            .fractionLength(
                                0...1
                            )
                        )
                        .locale(locale)
                    )
            case .choice(let value):
                base = value.label
            case .missing:
                base =
                    language == .german
                    ? "Nicht vorhanden"
                    : "Missing"
            }
            guard
                let unit =
                    unit?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
                unit.isEmpty == false
            else {
                return base
            }
            return "\(base) \(unit)"
        }

        func byteCount(_ value: Int) -> String {
            let number =
                max(0, value).formatted(
                    .number.locale(locale)
                )
            return language == .german
                ? "\(number) Byte"
                : "\(number) bytes"
        }

        private func date(_ value: Date) -> String {
            value.formatted(
                .dateTime
                .locale(locale)
                .year()
                .month(.abbreviated)
                .day()
            )
        }
    }

    struct Strings: Sendable {
        let language:
            GraphChatResponseLanguage

        init(
            _ language:
                GraphChatResponseLanguage
        ) {
            self.language = language
        }

        var notes: String {
            localized("Notizen", "Notes")
        }
        var detailValues: String {
            localized(
                "Detailwerte",
                "Detail values"
            )
        }
        var incomingConnections: String {
            localized(
                "Eingehende Verbindungen",
                "Incoming links"
            )
        }
        var outgoingConnections: String {
            localized(
                "Ausgehende Verbindungen",
                "Outgoing links"
            )
        }
        var attachments: String {
            localized(
                "Attachments",
                "Attachments"
            )
        }
        var linkNote: String {
            localized(
                "Link-Notiz",
                "Link note"
            )
        }

        func profile(_ name: String) -> String {
            localized(
                "Profil: \(name)",
                "Profile: \(name)"
            )
        }

        func name(_ value: String) -> String {
            localized(
                "Name: \(value)",
                "Name: \(value)"
            )
        }

        func owner(_ value: String) -> String {
            localized(
                "Owner: \(value)",
                "Owner: \(value)"
            )
        }

        func limitation(
            _ metadata:
                GraphChatAnswerArtifactResultMetadata,
            section:
                GraphChatNodeProfilePresentationSectionKind
        ) -> String? {
            guard
                metadata.truncation
                    .isTruncated
            else {
                return nil
            }
            let noun = sectionNoun(
                section
            )
            if let total =
                metadata.totalCount
            {
                return localized(
                    "\(metadata.returnedCount) von \(total) \(noun) angezeigt.",
                    "\(metadata.returnedCount) of \(total) \(noun) shown."
                )
            }
            return localized(
                "\(metadata.returnedCount) \(noun) angezeigt; die Gesamtzahl ist nach der Revalidierung unbekannt.",
                "\(metadata.returnedCount) \(noun) shown; the total is unknown after revalidation."
            )
        }

        func attachment(
            _ value:
                GraphChatAnswerArtifactNodeProfileAttachment,
            byteCount: String
        ) -> String {
            var metadata = [
                attachmentKind(
                    value.contentKind
                ),
                localized(
                    "Dateiname: \(value.originalFilename)",
                    "Filename: \(value.originalFilename)"
                ),
            ]
            let fileExtension =
                value.fileExtension
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            if fileExtension.isEmpty == false {
                metadata.append(
                    localized(
                        "Format: \(fileExtension.uppercased())",
                        "Format: \(fileExtension.uppercased())"
                    )
                )
            }
            metadata.append(
                localized(
                    "Größe: \(byteCount)",
                    "Size: \(byteCount)"
                )
            )
            return "\(value.title) — \(metadata.joined(separator: "; "))"
        }

        private func sectionNoun(
            _ section:
                GraphChatNodeProfilePresentationSectionKind
        ) -> String {
            switch (
                language,
                section
            ) {
            case (.german, .detailValues):
                return "Detailwerten"
            case (
                .german,
                .incomingConnections
            ):
                return "eingehenden Verbindungen"
            case (
                .german,
                .outgoingConnections
            ):
                return "ausgehenden Verbindungen"
            case (.german, .attachments):
                return "Attachments"
            case (.english, .detailValues):
                return "detail values"
            case (
                .english,
                .incomingConnections
            ):
                return "incoming links"
            case (
                .english,
                .outgoingConnections
            ):
                return "outgoing links"
            case (.english, .attachments):
                return "attachments"
            case (.german, .notes):
                return "Notizen"
            case (.english, .notes):
                return "notes"
            }
        }

        private func attachmentKind(
            _ kind: AttachmentContentKind
        ) -> String {
            switch (
                language,
                kind
            ) {
            case (.german, .file):
                return "Datei"
            case (.english, .file):
                return "File"
            case (.german, .video),
                (.english, .video):
                return "Video"
            case (.german, .galleryImage):
                return "Galeriebild"
            case (.english, .galleryImage):
                return "Gallery image"
            }
        }

        private func localized(
            _ german: String,
            _ english: String
        ) -> String {
            language == .german
                ? german
                : english
        }
    }
}
