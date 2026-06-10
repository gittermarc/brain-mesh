import Foundation

nonisolated struct GraphDetailsPreparedField: Equatable, Sendable {
    let id: UUID
    let entityID: UUID
    let name: String
    let type: DetailFieldType
    let sortIndex: Int
    let isPinned: Bool
    let unit: String?
    let options: [String]

    nonisolated init(
        id: UUID,
        entityID: UUID,
        name: String,
        type: DetailFieldType,
        sortIndex: Int,
        isPinned: Bool,
        unit: String?,
        options: [String]
    ) {
        self.id = id
        self.entityID = entityID
        self.name = name
        self.type = type
        self.sortIndex = sortIndex
        self.isPinned = isPinned
        self.unit = unit
        self.options = options
    }

    nonisolated init(field: MetaDetailFieldDefinition) {
        self.id = field.id
        self.entityID = field.entityID
        self.name = field.name
        self.type = field.type
        self.sortIndex = field.sortIndex
        self.isPinned = field.isPinned
        self.unit = field.unit
        self.options = field.options
    }
}

nonisolated struct GraphDetailsPreparedValue: Equatable, Sendable {
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let dateValue: Date?
    let boolValue: Bool?

    nonisolated init(
        stringValue: String?,
        intValue: Int?,
        doubleValue: Double?,
        dateValue: Date?,
        boolValue: Bool?
    ) {
        self.stringValue = stringValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }

    nonisolated init(value: MetaDetailFieldValue) {
        self.stringValue = value.stringValue
        self.intValue = value.intValue
        self.doubleValue = value.doubleValue
        self.dateValue = value.dateValue
        self.boolValue = value.boolValue
    }
}

nonisolated struct GraphDetailsPreparedAttribute: Equatable, Sendable {
    let nodeKey: NodeKey
    let attributeID: UUID
    let entityID: UUID
    let valuesByFieldID: [UUID: GraphDetailsPreparedValue]

    nonisolated init(
        nodeKey: NodeKey,
        attributeID: UUID,
        entityID: UUID,
        valuesByFieldID: [UUID: GraphDetailsPreparedValue]
    ) {
        self.nodeKey = nodeKey
        self.attributeID = attributeID
        self.entityID = entityID
        self.valuesByFieldID = valuesByFieldID
    }
}

nonisolated struct GraphDetailsPreparedState: Equatable, Sendable {
    let attributes: [GraphDetailsPreparedAttribute]
    let fieldsByEntityID: [UUID: [GraphDetailsPreparedField]]

    nonisolated static let empty = GraphDetailsPreparedState(attributes: [], fieldsByEntityID: [:])

    nonisolated init(
        attributes: [GraphDetailsPreparedAttribute],
        fieldsByEntityID: [UUID: [GraphDetailsPreparedField]]
    ) {
        self.attributes = attributes
        self.fieldsByEntityID = fieldsByEntityID
    }

    nonisolated var visibleAttributeNodeKeys: Set<NodeKey> {
        Set(attributes.map(\.nodeKey))
    }

    nonisolated func fields(for entityID: UUID) -> [GraphDetailsPreparedField] {
        fieldsByEntityID[entityID] ?? []
    }

    nonisolated func field(entityID: UUID, fieldID: UUID) -> GraphDetailsPreparedField? {
        fields(for: entityID).first(where: { $0.id == fieldID })
    }

    nonisolated static func build(
        entities: [MetaEntity],
        attributes: [MetaAttribute]
    ) -> GraphDetailsPreparedState {
        guard !attributes.isEmpty else {
            return .empty
        }

        let visibleEntityIDs = Set(attributes.compactMap { $0.owner?.id })

        var fieldsByEntityID: [UUID: [GraphDetailsPreparedField]] = [:]
        for entity in entities where visibleEntityIDs.contains(entity.id) {
            let fields = entity.detailFieldsList
                .filter { $0.type.supportsGraphDetailsFocus }
                .map { GraphDetailsPreparedField(field: $0) }
            if !fields.isEmpty {
                fieldsByEntityID[entity.id] = fields
            }
        }

        let preparedAttributes = attributes
            .compactMap { attribute -> GraphDetailsPreparedAttribute? in
                guard let owner = attribute.owner else { return nil }

                var valuesByFieldID: [UUID: GraphDetailsPreparedValue] = [:]
                valuesByFieldID.reserveCapacity(attribute.detailValuesList.count)
                for value in attribute.detailValuesList {
                    if valuesByFieldID[value.fieldID] == nil {
                        valuesByFieldID[value.fieldID] = GraphDetailsPreparedValue(value: value)
                    }
                }

                return GraphDetailsPreparedAttribute(
                    nodeKey: NodeKey(kind: .attribute, uuid: attribute.id),
                    attributeID: attribute.id,
                    entityID: owner.id,
                    valuesByFieldID: valuesByFieldID
                )
            }
            .sorted { $0.nodeKey.identifier < $1.nodeKey.identifier }

        guard !preparedAttributes.isEmpty else {
            return .empty
        }

        return GraphDetailsPreparedState(
            attributes: preparedAttributes,
            fieldsByEntityID: fieldsByEntityID
        )
    }
}

extension GraphDetailsPreparedField {
    var supportedComparisonOperators: [GraphDetailsComparisonOperator] {
        GraphDetailsComparisonOperator.supported(for: type)
    }
}
