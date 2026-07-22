import Foundation
import SwiftData
@testable import BrainMesh

struct GraphChatTravelFixture {
    let graph: MetaGraph
    let entity: MetaEntity
    let startDateField: MetaDetailFieldDefinition
    let endDateField: MetaDetailFieldDefinition
    let countryField: MetaDetailFieldDefinition
    let notesField: MetaDetailFieldDefinition
    let tripsByName: [String: MetaAttribute]
}

struct GraphChatProjectFixture {
    let graph: MetaGraph
    let entity: MetaEntity
    let statusField: MetaDetailFieldDefinition
    let priorityField: MetaDetailFieldDefinition
    let deadlineField: MetaDetailFieldDefinition
    let tasksByName: [String: MetaAttribute]
}

extension BrainMeshFixtureBuilder {
    func makeGraphChatTravelFixture(
        calendar: Calendar,
        timeZone: TimeZone
    ) -> GraphChatTravelFixture {
        let graph = makeGraph(name: "Reiseplanung")
        let entity = makeEntity(name: "Reisen", in: graph)
        let startDate = makeDetailField(
            owner: entity,
            name: "Startdatum",
            type: .date,
            sortIndex: 0,
            isPinned: true
        )
        let endDate = makeDetailField(
            owner: entity,
            name: "Enddatum",
            type: .date,
            sortIndex: 1,
            isPinned: true
        )
        let country = makeDetailField(
            owner: entity,
            name: "Land",
            type: .singleChoice,
            sortIndex: 2,
            options: ["Deutschland", "Frankreich", "USA", "Japan"]
        )
        let notes = makeDetailField(
            owner: entity,
            name: "Notizen",
            type: .multiLineText,
            sortIndex: 3
        )

        let rows: [(String, Date, Date, String, String)] = [
            (
                "Berlin 2023",
                fixtureDate(2023, 12, 20, calendar: calendar, timeZone: timeZone),
                fixtureDate(2023, 12, 23, calendar: calendar, timeZone: timeZone),
                "Deutschland",
                "Weihnachtsmarkt"
            ),
            (
                "Paris Neujahr",
                fixtureDate(2024, 1, 1, calendar: calendar, timeZone: timeZone),
                fixtureDate(2024, 1, 5, calendar: calendar, timeZone: timeZone),
                "Frankreich",
                "Jahresanfang"
            ),
            (
                "New York Sommer",
                fixtureDate(2024, 7, 10, calendar: calendar, timeZone: timeZone),
                fixtureDate(2024, 7, 18, calendar: calendar, timeZone: timeZone),
                "USA",
                "Museen und Brooklyn"
            ),
            (
                "Tokio 2025",
                fixtureDate(2025, 1, 1, calendar: calendar, timeZone: timeZone),
                fixtureDate(2025, 1, 12, calendar: calendar, timeZone: timeZone),
                "Japan",
                "Halb-offene Jahresgrenze"
            )
        ]

        var trips: [String: MetaAttribute] = [:]
        for row in rows {
            let attribute = makeAttribute(name: row.0, owner: entity, notes: row.4)
            trips[row.0] = attribute
            makeDetailValue(attribute: attribute, field: startDate, dateValue: row.1)
            makeDetailValue(attribute: attribute, field: endDate, dateValue: row.2)
            makeDetailValue(attribute: attribute, field: country, stringValue: row.3)
            makeDetailValue(attribute: attribute, field: notes, stringValue: row.4)
        }

        return GraphChatTravelFixture(
            graph: graph,
            entity: entity,
            startDateField: startDate,
            endDateField: endDate,
            countryField: country,
            notesField: notes,
            tripsByName: trips
        )
    }

    func makeGraphChatProjectFixture(
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate: Date
    ) -> GraphChatProjectFixture {
        let graph = makeGraph(name: "Projektportfolio")
        let entity = makeEntity(name: "Aufgaben", in: graph)
        let status = makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Offen", "In Arbeit", "Fertig"],
            isPinned: true
        )
        let priority = makeDetailField(
            owner: entity,
            name: "Priorität",
            type: .singleChoice,
            sortIndex: 1,
            options: ["Niedrig", "Mittel", "Hoch"],
            isPinned: true
        )
        let deadline = makeDetailField(
            owner: entity,
            name: "Deadline",
            type: .date,
            sortIndex: 2,
            isPinned: true
        )

        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        let dayStart = configuredCalendar.startOfDay(for: referenceDate)
        let rows: [(String, String, String, Date)] = [
            ("Security Review", "Offen", "Hoch", configuredCalendar.date(byAdding: .day, value: -2, to: dayStart)!),
            ("API Migration", "In Arbeit", "Hoch", configuredCalendar.date(byAdding: .day, value: -1, to: dayStart)!),
            ("Release Notes", "Fertig", "Hoch", configuredCalendar.date(byAdding: .day, value: -3, to: dayStart)!),
            ("Backlog Pflege", "Offen", "Niedrig", configuredCalendar.date(byAdding: .day, value: -4, to: dayStart)!),
            ("Roadmap Workshop", "Offen", "Hoch", configuredCalendar.date(byAdding: .day, value: 2, to: dayStart)!)
        ]

        var tasks: [String: MetaAttribute] = [:]
        for row in rows {
            let attribute = makeAttribute(name: row.0, owner: entity)
            tasks[row.0] = attribute
            makeDetailValue(attribute: attribute, field: status, stringValue: row.1)
            makeDetailValue(attribute: attribute, field: priority, stringValue: row.2)
            makeDetailValue(attribute: attribute, field: deadline, dateValue: row.3)
        }

        return GraphChatProjectFixture(
            graph: graph,
            entity: entity,
            statusField: status,
            priorityField: priority,
            deadlineField: deadline,
            tasksByName: tasks
        )
    }

    private func fixtureDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        return configuredCalendar.date(
            from: DateComponents(
                calendar: configuredCalendar,
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )!
    }
}

extension GraphSchemaContext {
    func entityAlias(named name: String) -> GraphEntityAlias? {
        snapshot.entities.first(where: { $0.name == name })?.alias
    }

    func fieldAlias(named name: String, in entityAlias: GraphEntityAlias) -> GraphFieldAlias? {
        snapshot.entities
            .first(where: { $0.alias == entityAlias })?
            .fields
            .first(where: { $0.name == name })?
            .alias
    }
}

struct GraphChatMixedKnowledgeFixture {
    let graph: MetaGraph
    let peopleEntity: MetaEntity
    let topicsEntity: MetaEntity
    let person: MetaAttribute
    let topic: MetaAttribute
    let link: MetaLink
    let attachment: MetaAttachment
    let attachmentPayload: Data
}

struct GraphChatLargeGraphFixture {
    let graph: MetaGraph
    let entity: MetaEntity
    let statusField: MetaDetailFieldDefinition
    let sequenceField: MetaDetailFieldDefinition
    let firstAttribute: MetaAttribute
    let lastAttribute: MetaAttribute
    let attributeCount: Int
    let detailValueCount: Int
    let linkCount: Int
}

extension BrainMeshFixtureBuilder {
    func makeGraphChatMixedKnowledgeFixture() -> GraphChatMixedKnowledgeFixture {
        let graph = makeGraph(name: "Gemischtes Wissen")
        let people = makeEntity(
            name: "Personen",
            in: graph,
            notes: "Verantwortlichkeiten und dokumentierte Zuständigkeiten"
        )
        let topics = makeEntity(
            name: "Themen",
            in: graph,
            notes: "Dokumentierte Wissensgebiete"
        )
        let role = makeDetailField(
            owner: people,
            name: "Rolle",
            type: .singleLineText,
            sortIndex: 0,
            isPinned: true
        )
        let classification = makeDetailField(
            owner: topics,
            name: "Klassifikation",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Intern", "Vertraulich"],
            isPinned: true
        )
        let person = makeAttribute(
            name: "Ada Lovelace",
            owner: people,
            notes: "Pflegt die dokumentierten Modellierungsregeln."
        )
        let topic = makeAttribute(
            name: "Graph Governance",
            owner: topics,
            notes: "Regeln für Ownership, Links und Re-Zertifizierung."
        )
        makeDetailValue(attribute: person, field: role, stringValue: "Owner")
        makeDetailValue(attribute: topic, field: classification, stringValue: "Intern")
        let link = makeLink(
            source: .attribute(person),
            target: .attribute(topic),
            note: "Ist fachlich verantwortlich",
            graphID: graph.id
        )
        let payload = Data([0x42, 0x4D, 0x00, 0xFF, 0x13, 0x37, 0xA5, 0x5A])
        let attachment = makeAttachment(
            owner: .attribute(topic),
            contentKind: .file,
            title: "Governance-Handbuch",
            originalFilename: "governance-private.bin",
            contentTypeIdentifier: "application/octet-stream",
            fileExtension: "bin",
            fileData: payload
        )
        return GraphChatMixedKnowledgeFixture(
            graph: graph,
            peopleEntity: people,
            topicsEntity: topics,
            person: person,
            topic: topic,
            link: link,
            attachment: attachment,
            attachmentPayload: payload
        )
    }

    func makeGraphChatLargeGraphFixture(
        attributeCount: Int = 2_400
    ) -> GraphChatLargeGraphFixture {
        precondition(attributeCount >= 2_000)
        let graph = makeGraph(name: "Large Graph Release Fixture")
        let entity = makeEntity(name: "Large Items", in: graph)
        let status = makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Open", "Closed"],
            isPinned: true
        )
        let sequence = makeDetailField(
            owner: entity,
            name: "Sequence",
            type: .numberInt,
            sortIndex: 1,
            isPinned: true
        )

        var first: MetaAttribute?
        var previous: MetaAttribute?
        var last: MetaAttribute?
        for index in 0..<attributeCount {
            let attribute = makeAttribute(
                name: String(format: "Large Item %04d", index),
                owner: entity,
                notes: "Documented large-graph fixture row \(index)"
            )
            makeDetailValue(
                attribute: attribute,
                field: status,
                stringValue: index.isMultiple(of: 2) ? "Open" : "Closed"
            )
            makeDetailValue(
                attribute: attribute,
                field: sequence,
                intValue: index
            )
            if let previous {
                makeLink(
                    source: .attribute(previous),
                    target: .attribute(attribute),
                    graphID: graph.id
                )
            }
            first = first ?? attribute
            previous = attribute
            last = attribute
        }

        return GraphChatLargeGraphFixture(
            graph: graph,
            entity: entity,
            statusField: status,
            sequenceField: sequence,
            firstAttribute: first!,
            lastAttribute: last!,
            attributeCount: attributeCount,
            detailValueCount: attributeCount * 2,
            linkCount: attributeCount - 1
        )
    }
}
