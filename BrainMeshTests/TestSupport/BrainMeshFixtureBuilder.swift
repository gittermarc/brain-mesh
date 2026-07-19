import Foundation
import SwiftData
@testable import BrainMesh

enum BrainMeshFixtureNode {
    case entity(MetaEntity)
    case attribute(MetaAttribute)

    var kind: NodeKind {
        switch self {
        case .entity:
            return .entity
        case .attribute:
            return .attribute
        }
    }

    var id: UUID {
        switch self {
        case .entity(let entity):
            return entity.id
        case .attribute(let attribute):
            return attribute.id
        }
    }

    var label: String {
        switch self {
        case .entity(let entity):
            return entity.name
        case .attribute(let attribute):
            return attribute.displayName
        }
    }

    var graphID: UUID? {
        switch self {
        case .entity(let entity):
            return entity.graphID
        case .attribute(let attribute):
            return attribute.graphID
        }
    }
}

struct BrainMeshFixtureBuilder {
    let context: ModelContext

    @discardableResult
    func makeGraph(
        name: String = "TestGraph",
        id: UUID = UUID()
    ) -> MetaGraph {
        let graph = MetaGraph(name: name)
        graph.id = id
        context.insert(graph)
        return graph
    }

    @discardableResult
    func makeEntity(
        name: String,
        in graph: MetaGraph? = nil,
        notes: String = "",
        iconSymbolName: String? = nil,
        imageData: Data? = nil,
        id: UUID = UUID()
    ) -> MetaEntity {
        let entity = MetaEntity(name: name, graphID: graph?.id, iconSymbolName: iconSymbolName)
        entity.id = id
        entity.notes = notes
        entity.nameFolded = BMSearch.fold(entity.name)
        entity.notesFolded = BMSearch.fold(entity.notes)
        entity.imageData = imageData
        context.insert(entity)
        return entity
    }

    @discardableResult
    func makeAttribute(
        name: String,
        owner: MetaEntity,
        notes: String = "",
        iconSymbolName: String? = nil,
        imageData: Data? = nil,
        id: UUID = UUID()
    ) -> MetaAttribute {
        let attribute = MetaAttribute(name: name, owner: owner, graphID: owner.graphID, iconSymbolName: iconSymbolName)
        attribute.id = id
        attribute.notes = notes
        attribute.nameFolded = BMSearch.fold(attribute.name)
        attribute.notesFolded = BMSearch.fold(attribute.notes)
        attribute.recomputeSearchLabelFolded()
        attribute.imageData = imageData
        owner.addAttribute(attribute)
        context.insert(attribute)
        return attribute
    }

    @discardableResult
    func makeDetailField(
        owner: MetaEntity,
        name: String,
        type: DetailFieldType,
        sortIndex: Int,
        unit: String? = nil,
        options: [String] = [],
        isPinned: Bool = false,
        id: UUID = UUID()
    ) -> MetaDetailFieldDefinition {
        let field = MetaDetailFieldDefinition(
            owner: owner,
            name: name,
            type: type,
            sortIndex: sortIndex,
            unit: unit,
            options: options,
            isPinned: isPinned
        )
        field.id = id
        owner.addDetailField(field)
        context.insert(field)
        return field
    }

    @discardableResult
    func makeDetailValue(
        attribute: MetaAttribute,
        field: MetaDetailFieldDefinition,
        stringValue: String? = nil,
        intValue: Int? = nil,
        doubleValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil,
        id: UUID = UUID()
    ) -> MetaDetailFieldValue {
        let value = MetaDetailFieldValue(attribute: attribute, fieldID: field.id)
        value.id = id
        value.stringValue = stringValue
        value.intValue = intValue
        value.doubleValue = doubleValue
        value.dateValue = dateValue
        value.boolValue = boolValue

        if attribute.detailValues == nil {
            attribute.detailValues = []
        }
        if attribute.detailValues?.contains(where: { $0.id == value.id }) != true {
            attribute.detailValues?.append(value)
        }

        context.insert(value)
        return value
    }

    @discardableResult
    func makeLink(
        source: BrainMeshFixtureNode,
        target: BrainMeshFixtureNode,
        note: String? = nil,
        graphID: UUID? = nil,
        id: UUID = UUID()
    ) -> MetaLink {
        let link = MetaLink(
            sourceKind: source.kind,
            sourceID: source.id,
            sourceLabel: source.label,
            targetKind: target.kind,
            targetID: target.id,
            targetLabel: target.label,
            note: note,
            graphID: graphID ?? source.graphID ?? target.graphID
        )
        link.id = id
        link.noteFolded = BMSearch.fold(link.note ?? "")
        context.insert(link)
        return link
    }

    @discardableResult
    func makeAttachment(
        owner: BrainMeshFixtureNode,
        contentKind: AttachmentContentKind = .file,
        title: String = "Attachment",
        originalFilename: String = "attachment.bin",
        contentTypeIdentifier: String = "application/octet-stream",
        fileExtension: String = "bin",
        byteCount: Int? = nil,
        fileData: Data? = nil,
        localPath: String? = nil,
        id: UUID = UUID()
    ) -> MetaAttachment {
        let attachment = MetaAttachment(
            id: id,
            ownerKind: owner.kind,
            ownerID: owner.id,
            graphID: owner.graphID,
            contentKind: contentKind,
            title: title,
            originalFilename: originalFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            fileExtension: fileExtension,
            byteCount: byteCount ?? fileData?.count ?? 0,
            fileData: fileData,
            localPath: localPath
        )
        context.insert(attachment)
        return attachment
    }

    func save() throws {
        try context.save()
    }
}
