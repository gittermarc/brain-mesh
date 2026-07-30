import Foundation

@testable import BrainMesh

nonisolated struct GraphChatGroundingEntityDefinition:
    Hashable,
    Sendable
{
    let name: String
    let nodeNames: [String]
    let fieldNames: [String]

    init(
        name: String,
        nodeNames: [String],
        fieldNames: [String]
    ) {
        self.name = name
        self.nodeNames = nodeNames
        self.fieldNames = fieldNames
    }
}

nonisolated struct GraphChatGroundingFixture:
    Sendable
{
    let graphScope: GraphScope
    let context: GraphSchemaContext
    let entityIDsByName: [String: [UUID]]
    let nodesByName: [String: [GraphSchemaNodeResolution]]
    let fieldsByName: [String: [GraphSchemaFieldResolution]]

    static func medicine(
        graphID: UUID = UUID()
    ) -> GraphChatGroundingFixture {
        GraphChatGroundingFixture(
            graphID: graphID,
            graphName: "Medicine",
            entities: [
                GraphChatGroundingEntityDefinition(
                    name: "Patient",
                    nodeNames: ["Patient A"],
                    fieldNames: [
                        "Geburtsdatum",
                        "Straße",
                    ]
                ),
                GraphChatGroundingEntityDefinition(
                    name: "Behandlung",
                    nodeNames: ["Therapie Alpha"],
                    fieldNames: ["Straße"]
                ),
            ]
        )
    }

    static func library(
        graphID: UUID = UUID()
    ) -> GraphChatGroundingFixture {
        GraphChatGroundingFixture(
            graphID: graphID,
            graphName: "Library",
            entities: [
                GraphChatGroundingEntityDefinition(
                    name: "Autor",
                    nodeNames: ["Ursula Le Guin"],
                    fieldNames: ["Biografie"]
                ),
                GraphChatGroundingEntityDefinition(
                    name: "Buch",
                    nodeNames: ["Solaris"],
                    fieldNames: ["Titel"]
                ),
            ]
        )
    }

    static func itOperations(
        graphID: UUID = UUID()
    ) -> GraphChatGroundingFixture {
        GraphChatGroundingFixture(
            graphID: graphID,
            graphName: "IT Operations",
            entities: [
                GraphChatGroundingEntityDefinition(
                    name: "Incident Record",
                    nodeNames: ["Edge Gateway 07"],
                    fieldNames: [
                        "Severity Level",
                        "Owner Team",
                    ]
                ),
                GraphChatGroundingEntityDefinition(
                    name: "Service Window",
                    nodeNames: ["Core Maintenance"],
                    fieldNames: ["Owner Team"]
                ),
            ]
        )
    }

    static func beyondInterpreterCatalogLimits(
        graphID: UUID = UUID()
    ) -> GraphChatGroundingFixture {
        let filler: [GraphChatGroundingEntityDefinition] =
            (1...24).map { entityIndex in
                let fields =
                    entityIndex == 1
                    ? (
                        (1...12).map { fieldIndex in
                            "Catalog Field \(fieldIndex)"
                        }
                        + ["Late Field 13"]
                    )
                    : ["Catalog Field \(entityIndex)"]
                return GraphChatGroundingEntityDefinition(
                    name: "Catalog Entry \(entityIndex)",
                    nodeNames: ["Catalog Node \(entityIndex)"],
                    fieldNames: fields
                )
            }
        return GraphChatGroundingFixture(
            graphID: graphID,
            graphName: "Large Grounding Catalog",
            entities:
                filler
                + [
                    GraphChatGroundingEntityDefinition(
                        name: "Remote Workload",
                        nodeNames: ["Remote Edge 25"],
                        fieldNames: [
                            "Escalation Matrix",
                        ]
                    ),
                ],
            promptEntityCount: 24,
            promptFieldCountPerEntity: 12
        )
    }

    init(
        graphID: UUID = UUID(),
        graphName: String,
        entities:
            [GraphChatGroundingEntityDefinition],
        promptEntityCount: Int? = nil,
        promptFieldCountPerEntity: Int? = nil
    ) {
        let graphScope = GraphScope(
            graphID: graphID
        )
        var entityResolutions:
            [GraphEntityAlias:
                GraphSchemaEntityResolution] = [:]
        var fieldResolutions:
            [GraphFieldAlias:
                GraphSchemaFieldResolution] = [:]
        var nodeResolutions:
            [NodeRefKey:
                GraphSchemaNodeResolution] = [:]
        var nodeEntityIDs:
            [NodeRefKey: UUID] = [:]
        var entityIDsByName:
            [String: [UUID]] = [:]
        var nodesByName:
            [String:
                [GraphSchemaNodeResolution]] = [:]
        var fieldsByName:
            [String:
                [GraphSchemaFieldResolution]] = [:]
        var fieldIndex = 0

        for (
            entityIndex,
            definition
        ) in entities.enumerated() {
            let entityID = UUID()
            let entityAlias =
                GraphEntityAlias(
                    "E\(entityIndex + 1)"
                )
            let entity =
                GraphSchemaEntityResolution(
                    alias: entityAlias,
                    entityID: entityID,
                    name: definition.name
                )
            entityResolutions[entityAlias] =
                entity
            entityIDsByName[
                definition.name,
                default: []
            ].append(entityID)
            nodeEntityIDs[
                NodeRefKey(
                    kind: .entity,
                    id: entityID
                )
            ] = entityID

            for name in definition.nodeNames {
                let node = NodeRefKey(
                    kind: .attribute,
                    id: UUID()
                )
                let resolution =
                    GraphSchemaNodeResolution(
                        node: node,
                        ownerEntityID: entityID,
                        displayName: name
                    )
                nodeResolutions[node] =
                    resolution
                nodeEntityIDs[node] = entityID
                nodesByName[
                    name,
                    default: []
                ].append(resolution)
            }

            for (
                localFieldIndex,
                name
            ) in definition.fieldNames.enumerated() {
                fieldIndex += 1
                let alias =
                    GraphFieldAlias(
                        "F\(fieldIndex)"
                    )
                let resolution =
                    GraphSchemaFieldResolution(
                        alias: alias,
                        entityAlias:
                            entityAlias,
                        entityID: entityID,
                        fieldID: UUID(),
                        name: name,
                        type:
                            localFieldIndex
                                .isMultiple(of: 2)
                            ? .singleLineText
                            : .multiLineText,
                        unit: nil,
                        choiceOptions: [],
                        sortIndex:
                            localFieldIndex
                    )
                fieldResolutions[alias] =
                    resolution
                fieldsByName[
                    name,
                    default: []
                ].append(resolution)
            }
        }

        let completeAliases =
            GraphSchemaAliasMap(
                graphScope: graphScope,
                entitiesByAlias:
                    entityResolutions,
                fieldsByAlias:
                    fieldResolutions,
                nodeEntityIDs:
                    nodeEntityIDs,
                nodesByKey:
                    nodeResolutions
            )
        let promptEntityLimit = min(
            max(
                0,
                promptEntityCount
                    ?? entityResolutions.count
            ),
            entityResolutions.count
        )
        let allowedEntityAliases = Set(
            (0..<promptEntityLimit).map {
                GraphEntityAlias("E\($0 + 1)")
            }
        )
        let promptEntities =
            entityResolutions.filter {
                allowedEntityAliases.contains(
                    $0.key
                )
            }
        let promptFields = Dictionary(
            grouping:
                fieldResolutions.filter {
                    allowedEntityAliases.contains(
                        $0.value.entityAlias
                    )
                },
            by: { $0.value.entityAlias }
        ).values.flatMap { values in
            values.sorted {
                if $0.value.sortIndex
                    != $1.value.sortIndex {
                    return $0.value.sortIndex < $1.value.sortIndex
                }
                return $0.key.rawValue < $1.key.rawValue
            }.prefix(
                promptFieldCountPerEntity
                    ?? values.count
            )
        }.reduce(
            into:
                [GraphFieldAlias:
                    GraphSchemaFieldResolution]()
        ) {
            $0[$1.key] = $1.value
        }
        let promptEntityIDs = Set(
            promptEntities.values.map(\.entityID)
        )
        let promptNodes =
            nodeResolutions.filter {
                promptEntityIDs.contains(
                    $0.value.ownerEntityID
                )
            }
        let promptNodeEntityIDs =
            nodeEntityIDs.filter {
                promptEntityIDs.contains(
                    $0.value
                )
            }
        let promptAliases =
            GraphSchemaAliasMap(
                graphScope: graphScope,
                entitiesByAlias:
                    promptEntities,
                fieldsByAlias:
                    promptFields,
                nodeEntityIDs:
                    promptNodeEntityIDs,
                nodesByKey:
                    promptNodes
            )
        let snapshot =
            GraphSchemaSnapshot(
                graphName: graphName,
                entities: [],
                truncation:
                    GraphSchemaTruncation(
                        sourceEntityCount:
                            entityResolutions.count,
                        includedEntityCount:
                            promptEntities.count,
                        sourceFieldCount:
                            fieldResolutions.count,
                        includedFieldCount:
                            promptFields.count,
                        sourceChoiceOptionCount: 0,
                        includedChoiceOptionCount: 0,
                        sourceExampleValueCount: 0,
                        includedExampleValueCount: 0,
                        stringsWereTruncated:
                            false
                    )
            )

        self.graphScope = graphScope
        self.context = GraphSchemaContext(
            graphScope: graphScope,
            snapshot: snapshot,
            aliases: promptAliases,
            foundationalAliases:
                completeAliases
        )
        self.entityIDsByName =
            entityIDsByName
        self.nodesByName = nodesByName
        self.fieldsByName = fieldsByName
    }

    func entityID(
        named name: String,
        index: Int = 0
    ) -> UUID {
        entityIDsByName[name]![index]
    }

    func node(
        named name: String,
        index: Int = 0
    ) -> GraphSchemaNodeResolution {
        nodesByName[name]![index]
    }

    func field(
        named name: String,
        index: Int = 0
    ) -> GraphSchemaFieldResolution {
        fieldsByName[name]![index]
    }
}
