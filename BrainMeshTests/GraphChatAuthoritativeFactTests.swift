import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph chat authoritative facts")
struct GraphChatAuthoritativeFactTests {
    private let renderer = GraphChatAuthoritativeFactRenderer()

    @Test
    func dateUsesExplicitGermanAndEnglishCalendarFormatting()
        throws
    {
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let date = try calendarDate(
            year: 1985,
            month: 10,
            day: 27,
            timeZone: timeZone
        )
        let fact = makeFact(
            fieldName: "Geburtsdatum",
            fieldType: .date,
            value: .date(date),
            timeZone: timeZone
        )

        #expect(
            renderer.render(fact, language: .german)
                == "Geburtsdatum von Person X: 27.10.1985."
        )
        #expect(
            renderer.render(fact, language: .english)
                == "Geburtsdatum of Person X: 10/27/1985."
        )
    }

    @Test
    func storedCalendarDayIsStableAcrossSourceTimeZones() throws {
        let berlin = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let losAngeles = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )
        let berlinDate = try calendarDate(
            year: 1990,
            month: 5,
            day: 17,
            timeZone: berlin
        )
        let losAngelesDate = try calendarDate(
            year: 1990,
            month: 5,
            day: 17,
            timeZone: losAngeles
        )

        let berlinFact = makeFact(
            fieldName: "Geburtsdatum",
            fieldType: .date,
            value: .date(berlinDate),
            timeZone: berlin
        )
        let losAngelesFact = makeFact(
            fieldName: "Geburtsdatum",
            fieldType: .date,
            value: .date(losAngelesDate),
            timeZone: losAngeles
        )

        #expect(
            renderer.render(berlinFact, language: .german)
                == renderer.render(
                    losAngelesFact,
                    language: .german
                )
        )
        #expect(
            renderer.render(berlinFact, language: .english)
                == renderer.render(
                    losAngelesFact,
                    language: .english
                )
        )
    }

    @Test
    func singleAndMultilineTextPreserveAuthoritativeContent() {
        let singleLine = makeFact(
            fieldName: "Statusnotiz",
            fieldType: .singleLineText,
            value: .text("  Freigabe\t steht   aus  ")
        )
        let multiLine = makeFact(
            fieldName: "Beschreibung",
            fieldType: .multiLineText,
            value: .text("  Erste Zeile\r\nZweite Zeile\n\nDritte Zeile  ")
        )

        #expect(
            renderer.render(singleLine, language: .german)
                == "Statusnotiz von Person X: Freigabe steht aus."
        )
        #expect(
            renderer.render(multiLine, language: .german)
                == "Beschreibung von Person X:\nErste Zeile\nZweite Zeile\n\nDritte Zeile"
        )
    }

    @Test
    func integerDoubleAndUnitUseLocalizedExactDigits() {
        let integer = makeFact(
            fieldName: "Budget",
            fieldType: .numberInt,
            value: .integer(125_000),
            unit: "€"
        )
        let decimal = makeFact(
            fieldName: "Messwert",
            fieldType: .numberDouble,
            value: .decimal(
                Decimal(
                    string: "123456.789012",
                    locale: Locale(identifier: "en_US_POSIX")
                )!
            )
        )

        #expect(
            renderer.render(integer, language: .german)
                == "Budget von Person X: 125.000 €."
        )
        #expect(
            renderer.render(integer, language: .english)
                == "Budget of Person X: 125,000 €."
        )
        #expect(
            renderer.render(decimal, language: .german)
                == "Messwert von Person X: 123.456,789012."
        )
        #expect(
            renderer.render(decimal, language: .english)
                == "Messwert of Person X: 123,456.789012."
        )
    }

    @Test
    func booleanAndChoiceUseLocalizedBusinessLabels() {
        let trueFact = makeFact(
            fieldName: "Aktiv",
            fieldType: .toggle,
            value: .boolean(true)
        )
        let falseFact = makeFact(
            fieldName: "Aktiv",
            fieldType: .toggle,
            value: .boolean(false)
        )
        let choice = makeFact(
            fieldName: "Status",
            fieldType: .singleChoice,
            value: .choice(
                GraphChatAnswerArtifactChoiceValue(
                    value: "OPEN_INTERNAL",
                    label: "Offen"
                )
            )
        )

        #expect(
            renderer.render(trueFact, language: .german)
                == "Aktiv von Person X: Ja."
        )
        #expect(
            renderer.render(falseFact, language: .german)
                == "Aktiv von Person X: Nein."
        )
        #expect(
            renderer.render(trueFact, language: .english)
                == "Aktiv of Person X: Yes."
        )
        #expect(
            renderer.render(falseFact, language: .english)
                == "Aktiv of Person X: No."
        )
        #expect(
            renderer.render(choice, language: .german)
                == "Status von Person X: Offen."
        )
        #expect(
            renderer.render(choice, language: .german)
                .contains("OPEN_INTERNAL") == false
        )
    }

    @Test
    func factDomainRemainsSendableAndExactlyOne() {
        let fact = makeFact(
            fieldName: "Status",
            fieldType: .singleLineText,
            value: .text("Offen")
        )

        acceptSendable(fact)
        #expect(fact.hasExactlyOneValue)
        #expect(fact.cardinality == .exactlyOne)
        #expect(fact.evidenceIDs.count == 1)
        #expect(fact.artifactIDs.count == 1)
    }

    private func makeFact(
        fieldName: String,
        fieldType: DetailFieldType,
        value: GraphChatAnswerArtifactValue,
        unit: String? = nil,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) -> GraphChatAuthoritativeFact {
        let graphScope = GraphScope(
            graphID: UUID(
                uuidString:
                    "A3000000-0000-0000-0000-000000000001"
            )!
        )
        return GraphChatAuthoritativeFact(
            binding: GraphChatAuthoritativeFactBinding(
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope),
                requestID: UUID(
                    uuidString:
                        "A3000000-0000-0000-0000-000000000002"
                )!,
                sessionID: GraphChatAnswerArtifactSessionID(
                    rawValue: UUID(
                        uuidString:
                            "A3000000-0000-0000-0000-000000000003"
                    )!
                ),
                transactionID: GraphChatAnswerArtifactTransactionID(
                    rawValue: UUID(
                        uuidString:
                            "A3000000-0000-0000-0000-000000000004"
                    )!
                ),
                turnID: UUID(
                    uuidString:
                        "A3000000-0000-0000-0000-000000000002"
                )!
            ),
            node: NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        "A3000000-0000-0000-0000-000000000005"
                )!
            ),
            nodeDisplayName: "Person X",
            entityID: UUID(
                uuidString:
                    "A3000000-0000-0000-0000-000000000006"
            )!,
            entityDisplayName: "Personen",
            fieldID: UUID(
                uuidString:
                    "A3000000-0000-0000-0000-000000000007"
            )!,
            fieldDisplayName: fieldName,
            fieldType: fieldType,
            value: value,
            unit: unit,
            evidenceIDs: [
                GraphEvidenceID(
                    rawValue: UUID(
                        uuidString:
                            "A3000000-0000-0000-0000-000000000008"
                    )!
                )
            ],
            artifactIDs: [
                GraphChatAnswerArtifactID(
                    rawValue: UUID(
                        uuidString:
                            "A3000000-0000-0000-0000-000000000009"
                    )!
                )
            ],
            cardinality: .exactlyOne,
            dateTimeZoneIdentifier: timeZone.identifier
        )
    }

    private func calendarDate(
        year: Int,
        month: Int,
        day: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: year,
                    month: month,
                    day: day
                )
            )
        )
    }

    private func acceptSendable<T: Sendable>(_ value: T) {}
}
