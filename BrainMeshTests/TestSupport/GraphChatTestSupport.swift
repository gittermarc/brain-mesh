import Foundation
@testable import BrainMesh

nonisolated enum GraphChatTestSupport {
    static let graphID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let otherGraphID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let projectEntityID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let personEntityID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let projectAttributeID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let personAttributeID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!

    static func makeSchemaContext(
        graphID requestedGraphID: UUID = graphID,
        choiceOptions: [String] = ["Offen", "In Arbeit", "Fertig"]
    ) -> GraphSchemaContext {
        let graphScope = GraphScope(graphID: requestedGraphID)
        let fieldSpecifications: [(
            GraphFieldAlias,
            UUID,
            String,
            DetailFieldType,
            String?,
            [String]
        )] = [
            (GraphFieldAlias("F1"), uuid(1), "Titel", .singleLineText, nil, []),
            (GraphFieldAlias("F2"), uuid(2), "Beschreibung", .multiLineText, nil, []),
            (GraphFieldAlias("F3"), uuid(3), "Aufwand", .numberInt, "h", []),
            (GraphFieldAlias("F4"), uuid(4), "Budget", .numberDouble, "EUR", []),
            (GraphFieldAlias("F5"), uuid(5), "Fällig", .date, nil, []),
            (GraphFieldAlias("F6"), uuid(6), "Kritisch", .toggle, nil, []),
            (GraphFieldAlias("F7"), uuid(7), "Status", .singleChoice, nil, choiceOptions)
        ]
        let secondaryFieldAlias = GraphFieldAlias("F8")
        let secondaryFieldID = uuid(8)

        let projectFields = fieldSpecifications.enumerated().map { index, specification in
            GraphSchemaField(
                alias: specification.0,
                name: specification.2,
                type: specification.3,
                unit: specification.4,
                choiceOptions: specification.5,
                isPinned: index < 2,
                sortIndex: index,
                exampleValues: [],
                optionsWereTruncated: false,
                examplesWereTruncated: false
            )
        }
        let personField = GraphSchemaField(
            alias: secondaryFieldAlias,
            name: "Rolle",
            type: .singleLineText,
            unit: nil,
            choiceOptions: [],
            isPinned: false,
            sortIndex: 0,
            exampleValues: [],
            optionsWereTruncated: false,
            examplesWereTruncated: false
        )
        let snapshot = GraphSchemaSnapshot(
            graphName: "Test Graph",
            entities: [
                GraphSchemaEntity(
                    alias: GraphEntityAlias("E1"),
                    name: "Projekte",
                    attributeCount: 1,
                    fields: projectFields,
                    fieldsWereTruncated: false
                ),
                GraphSchemaEntity(
                    alias: GraphEntityAlias("E2"),
                    name: "Personen",
                    attributeCount: 1,
                    fields: [personField],
                    fieldsWereTruncated: false
                )
            ],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 2,
                includedEntityCount: 2,
                sourceFieldCount: 8,
                includedFieldCount: 8,
                sourceChoiceOptionCount: choiceOptions.count,
                includedChoiceOptionCount: choiceOptions.count,
                sourceExampleValueCount: 0,
                includedExampleValueCount: 0,
                stringsWereTruncated: false
            )
        )

        var fieldResolutions: [GraphFieldAlias: GraphSchemaFieldResolution] = [:]
        for specification in fieldSpecifications {
            fieldResolutions[specification.0] = GraphSchemaFieldResolution(
                alias: specification.0,
                entityAlias: GraphEntityAlias("E1"),
                entityID: projectEntityID,
                fieldID: specification.1,
                name: specification.2,
                type: specification.3,
                unit: specification.4,
                choiceOptions: specification.5
            )
        }
        fieldResolutions[secondaryFieldAlias] = GraphSchemaFieldResolution(
            alias: secondaryFieldAlias,
            entityAlias: GraphEntityAlias("E2"),
            entityID: personEntityID,
            fieldID: secondaryFieldID,
            name: "Rolle",
            type: .singleLineText,
            unit: nil,
            choiceOptions: []
        )

        let aliasMap = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [
                GraphEntityAlias("E1"): GraphSchemaEntityResolution(
                    alias: GraphEntityAlias("E1"),
                    entityID: projectEntityID,
                    name: "Projekte"
                ),
                GraphEntityAlias("E2"): GraphSchemaEntityResolution(
                    alias: GraphEntityAlias("E2"),
                    entityID: personEntityID,
                    name: "Personen"
                )
            ],
            fieldsByAlias: fieldResolutions,
            nodeEntityIDs: [
                NodeRefKey(kind: .entity, id: projectEntityID): projectEntityID,
                NodeRefKey(kind: .attribute, id: projectAttributeID): projectEntityID,
                NodeRefKey(kind: .entity, id: personEntityID): personEntityID,
                NodeRefKey(kind: .attribute, id: personAttributeID): personEntityID
            ]
        )
        return GraphSchemaContext(
            graphScope: graphScope,
            snapshot: snapshot,
            aliases: aliasMap
        )
    }

    static func makeValidator(
        timeZoneIdentifier: String = "Europe/Berlin",
        referenceDate: Date = Date(timeIntervalSince1970: 1_735_732_800)
    ) -> GraphQueryPlanValidator {
        GraphQueryPlanValidator(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: timeZoneIdentifier)!,
            referenceDate: referenceDate
        )
    }

    static func validationError(
        for plan: GraphQueryPlan,
        context: GraphSchemaContext = makeSchemaContext(),
        validator: GraphQueryPlanValidator = makeValidator()
    ) -> GraphQueryPlanValidationError? {
        do {
            _ = try validator.validate(plan, against: context)
            return nil
        } catch let error as GraphQueryPlanValidationError {
            return error
        } catch {
            return GraphQueryPlanValidationError(
                issues: [
                    GraphQueryPlanValidationIssue(
                        code: .invalidValueType,
                        path: "unexpected",
                        message: String(describing: error)
                    )
                ]
            )
        }
    }

    private static func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "40000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    }
}
