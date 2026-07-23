//
//  GetNodeTool.swift
//  BrainMesh
//
//  Read-only node details with typed fields and metadata-only attachments.
//

import Foundation

nonisolated protocol GraphChatNodeReading: Sendable {
    func entity(id: UUID, in scope: GraphScope) async throws -> GraphEntityDTO?
    func attribute(id: UUID, in scope: GraphScope) async throws -> GraphAttributeDTO?
    func links(connectedTo node: NodeRefKey, in scope: GraphScope) async throws -> [GraphLinkDTO]
    func detailValues(attributeID: UUID, in scope: GraphScope) async throws -> [GraphDetailValueDTO]
    func detailFieldDefinition(id: UUID, in scope: GraphScope) async throws -> GraphDetailFieldDefinitionDTO?
    func attachmentMetadata(owner: NodeRefKey, in scope: GraphScope) async throws -> [GraphAttachmentMetadataDTO]
}

extension GraphReadRepository: GraphChatNodeReading {}

nonisolated struct GetNodeInput: Sendable {
    let node: NodeRefKey
    let relatedLimit: Int

    init(node: NodeRefKey, relatedLimit: Int = 20) {
        self.node = node
        self.relatedLimit = relatedLimit
    }
}

nonisolated struct GraphChatNodeOwner: Hashable, Sendable {
    let entityID: UUID
    let label: String?
}

nonisolated struct GraphChatNodeDetailValue: Hashable, Sendable, Identifiable {
    let valueID: UUID
    let fieldID: UUID
    let fieldName: String
    let fieldType: DetailFieldType
    let unit: String?
    let value: GraphChatQueryCellValue
    let evidenceID: GraphEvidenceID

    var id: UUID {
        valueID
    }
}

nonisolated enum GraphChatLinkDirection: String, Hashable, Sendable {
    case incoming
    case outgoing
}

nonisolated struct GraphChatNodeLinkMetadata: Hashable, Sendable, Identifiable {
    let id: UUID
    let direction: GraphChatLinkDirection
    let source: NodeRefKey
    let sourceLabel: String
    let target: NodeRefKey
    let targetLabel: String
    let note: String?
    let evidenceID: GraphEvidenceID
}

nonisolated struct GraphChatAttachmentMetadata: Hashable, Sendable, Identifiable {
    let id: UUID
    let contentKind: AttachmentContentKind
    let title: String
    let originalFilename: String
    let contentTypeIdentifier: String
    let fileExtension: String
    let byteCount: Int
    let evidenceID: GraphEvidenceID
}

nonisolated struct GetNodeOutput: Sendable {
    let node: NodeRefKey
    let label: String
    let notes: String
    let owner: GraphChatNodeOwner?
    let detailValues: [GraphChatNodeDetailValue]
    let links: [GraphChatNodeLinkMetadata]
    let attachments: [GraphChatAttachmentMetadata]
    let evidenceIDs: [GraphEvidenceID]
    let detailValueWindow: GraphChatResultWindow

    init(
        node: NodeRefKey,
        label: String,
        notes: String,
        owner: GraphChatNodeOwner?,
        detailValues: [GraphChatNodeDetailValue],
        links: [GraphChatNodeLinkMetadata],
        attachments: [GraphChatAttachmentMetadata],
        evidenceIDs: [GraphEvidenceID],
        detailValueWindow: GraphChatResultWindow? = nil
    ) {
        self.node = node
        self.label = label
        self.notes = notes
        self.owner = owner
        self.detailValues = detailValues
        self.links = links
        self.attachments = attachments
        self.evidenceIDs = evidenceIDs
        self.detailValueWindow = detailValueWindow ?? .complete(totalCount: detailValues.count)
    }
}

nonisolated struct GetNodeTool: GraphChatTool {
    let kind = GraphChatToolKind.getNode
    static let maximumRelatedItemCount = 30

    private struct PreparedOutput: Sendable {
        let output: GetNodeOutput
        let evidence: [GraphEvidence]
    }

    private let repository: any GraphChatNodeReading
    private let evidenceValidator: any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        repository: any GraphChatNodeReading = GraphReadRepository.shared,
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        logger: any GraphChatToolLogging = GraphChatTechnicalLogger()
    ) {
        self.repository = repository
        self.evidenceValidator = evidenceValidator
        self.logger = logger
    }

    func execute(
        _ input: GetNodeInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GetNodeOutput> {
        let timer = GraphChatToolTimer()
        do {
            guard (0...Self.maximumRelatedItemCount).contains(input.relatedLimit) else {
                throw GraphChatToolError(
                    code: .budgetExceeded,
                    message: "GetNode erlaubt höchstens \(Self.maximumRelatedItemCount) Detailergebnisse."
                )
            }
            let totalResultLimit = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: input.relatedLimit + 1,
                toolMaximumResultCount: Self.maximumRelatedItemCount + 1
            )
            let relatedLimit = totalResultLimit - 1
            try Task.checkCancellation()
            guard let prepared = try await prepare(
                node: input.node,
                relatedLimit: relatedLimit,
                graphScope: context.scope.graphScope
            ) else {
                logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
                return .noResults()
            }

            let evidence = try await evidenceValidator.validatedEvidence(
                prepared.evidence,
                in: context.scope
            )
            let validIDs = Set(evidence.map(\.id))
            guard let baseID = prepared.output.evidenceIDs.first,
                  validIDs.contains(baseID) else {
                logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
                return .noEvidence()
            }

            let validatedDetailValues = prepared.output.detailValues.filter {
                validIDs.contains($0.evidenceID)
            }
            let detailEvidenceWasRemoved = validatedDetailValues.count
                < prepared.output.detailValueWindow.returnedCount
            let output = GetNodeOutput(
                node: prepared.output.node,
                label: prepared.output.label,
                notes: prepared.output.notes,
                owner: prepared.output.owner,
                detailValues: validatedDetailValues,
                links: prepared.output.links.filter {
                    validIDs.contains($0.evidenceID)
                },
                attachments: prepared.output.attachments.filter {
                    validIDs.contains($0.evidenceID)
                },
                evidenceIDs: prepared.output.evidenceIDs.filter {
                    validIDs.contains($0)
                },
                detailValueWindow: GraphChatResultWindow(
                    totalCount: detailEvidenceWasRemoved
                        ? nil
                        : prepared.output.detailValueWindow.totalCount,
                    returnedCount: validatedDetailValues.count,
                    limit: prepared.output.detailValueWindow.limit,
                    limitReached: prepared.output.detailValueWindow.limitReached
                        || detailEvidenceWasRemoved,
                    limitSources: prepared.output.detailValueWindow.limitSources
                        + (detailEvidenceWasRemoved ? [.source] : [])
                )
            )
            try await context.budget.consumeEvidence(evidence.count)
            let resultCount = 1 + output.detailValues.count + output.links.count + output.attachments.count
            logger.record(timer.metric(tool: kind, resultCount: resultCount, wasCancelled: false))
            return .success(output, evidence: evidence)
        } catch is CancellationError {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: true))
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
            throw error
        }
    }

    private func prepare(
        node: NodeRefKey,
        relatedLimit: Int,
        graphScope: GraphScope
    ) async throws -> PreparedOutput? {
        let label: String
        let notes: String
        let owner: GraphChatNodeOwner?
        let baseReference: GraphSourceReference

        switch node.kind {
        case .entity:
            guard let entity = try await repository.entity(id: node.id, in: graphScope) else {
                return nil
            }
            label = entity.name
            notes = entity.notes
            owner = nil
            baseReference = GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: entity.id,
                node: GraphSourceNodeReference(kind: .entity, id: entity.id)
            )
        case .attribute:
            guard let attribute = try await repository.attribute(id: node.id, in: graphScope) else {
                return nil
            }
            label = attribute.displayLabel
            notes = attribute.notes
            owner = attribute.ownerEntityID.map {
                GraphChatNodeOwner(entityID: $0, label: attribute.ownerLabel)
            }
            baseReference = GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .attribute,
                sourceID: attribute.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                owner: attribute.ownerEntityID.map {
                    GraphSourceNodeReference(kind: .entity, id: $0)
                }
            )
        }

        var baseFields: [GraphEvidenceFieldValue] = []
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            baseFields.append(
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Notizen",
                    value: .text(notes),
                    unit: nil
                )
            )
        }
        let baseEvidence = GraphEvidence(
            sourceReference: baseReference,
            summary: label,
            fieldValues: baseFields,
            navigationTitle: label,
            identitySuffix: "node-detail"
        )
        var evidence = [baseEvidence]

        var remainingRelatedItems = relatedLimit
        var detailItems: [GraphChatNodeDetailValue] = []
        var detailValueTotalCount = 0
        var detailValueToolLimitReached = false
        var detailValueSourceLimited = false
        if node.kind == .attribute {
            let values = try await repository.detailValues(attributeID: node.id, in: graphScope)
            detailValueTotalCount = values.count
            let availableDetailLimit = remainingRelatedItems
            detailValueToolLimitReached = values.count > availableDetailLimit
            for value in values.prefix(availableDetailLimit) {
                try Task.checkCancellation()
                guard let field = try await repository.detailFieldDefinition(
                    id: value.fieldID,
                    in: graphScope
                ) else {
                    detailValueSourceLimited = true
                    continue
                }
                let itemEvidence = GraphEvidence(
                    sourceReference: GraphSourceReference(
                        graphID: graphScope.graphID,
                        sourceKind: .detailValue,
                        sourceID: value.id,
                        node: GraphSourceNodeReference(kind: .attribute, id: node.id),
                        owner: owner.map {
                            GraphSourceNodeReference(kind: .entity, id: $0.entityID)
                        },
                        fieldID: field.id
                    ),
                    summary: "\(label): \(field.name)",
                    fieldValues: [
                        GraphEvidenceFieldValue(
                            fieldID: field.id,
                            fieldName: field.name,
                            value: value.value.graphEvidenceValue,
                            unit: field.unit
                        )
                    ],
                    navigationTitle: label,
                    identitySuffix: "node-field"
                )
                evidence.append(itemEvidence)
                detailItems.append(
                    GraphChatNodeDetailValue(
                        valueID: value.id,
                        fieldID: field.id,
                        fieldName: field.name,
                        fieldType: field.type,
                        unit: field.unit,
                        value: value.value.graphChatCellValue,
                        evidenceID: itemEvidence.id
                    )
                )
                remainingRelatedItems -= 1
            }
        }

        let links = remainingRelatedItems > 0
            ? try await repository.links(connectedTo: node, in: graphScope)
            : []
        var linkItems: [GraphChatNodeLinkMetadata] = []
        for link in links.prefix(remainingRelatedItems) {
            try Task.checkCancellation()
            guard let source = link.sourceNodeKey, let target = link.targetNodeKey else {
                continue
            }
            let direction: GraphChatLinkDirection = source == node ? .outgoing : .incoming
            let itemEvidence = GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .link,
                    sourceID: link.id,
                    node: GraphSourceNodeReference(kind: node.kind, id: node.id),
                    linkID: link.id
                ),
                summary: "\(link.sourceLabel) → \(link.targetLabel)",
                fieldValues: link.note.map {
                    [
                        GraphEvidenceFieldValue(
                            fieldID: nil,
                            fieldName: "Link-Notiz",
                            value: .text($0),
                            unit: nil
                        )
                    ]
                } ?? [],
                navigationTitle: label,
                identitySuffix: "node-link"
            )
            evidence.append(itemEvidence)
            linkItems.append(
                GraphChatNodeLinkMetadata(
                    id: link.id,
                    direction: direction,
                    source: source,
                    sourceLabel: link.sourceLabel,
                    target: target,
                    targetLabel: link.targetLabel,
                    note: link.note,
                    evidenceID: itemEvidence.id
                )
            )
            remainingRelatedItems -= 1
        }

        let attachments = remainingRelatedItems > 0
            ? try await repository.attachmentMetadata(owner: node, in: graphScope)
            : []
        var attachmentItems: [GraphChatAttachmentMetadata] = []
        for attachment in attachments.prefix(remainingRelatedItems) {
            try Task.checkCancellation()
            guard let contentKind = attachment.contentKind else {
                continue
            }
            let itemEvidence = GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .attachment,
                    sourceID: attachment.id,
                    owner: GraphSourceNodeReference(kind: node.kind, id: node.id),
                    attachmentID: attachment.id
                ),
                summary: attachment.title,
                fieldValues: [
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Dateiname",
                        value: .text(attachment.originalFilename),
                        unit: nil
                    ),
                    GraphEvidenceFieldValue(
                        fieldID: nil,
                        fieldName: "Dateigröße",
                        value: .integer(attachment.byteCount),
                        unit: "Bytes"
                    )
                ],
                navigationTitle: label,
                identitySuffix: "attachment-metadata"
            )
            evidence.append(itemEvidence)
            attachmentItems.append(
                GraphChatAttachmentMetadata(
                    id: attachment.id,
                    contentKind: contentKind,
                    title: attachment.title,
                    originalFilename: attachment.originalFilename,
                    contentTypeIdentifier: attachment.contentTypeIdentifier,
                    fileExtension: attachment.fileExtension,
                    byteCount: attachment.byteCount,
                    evidenceID: itemEvidence.id
                )
            )
        }

        let output = GetNodeOutput(
            node: node,
            label: label,
            notes: notes,
            owner: owner,
            detailValues: detailItems,
            links: linkItems,
            attachments: attachmentItems,
            evidenceIDs: evidence.map(\.id),
            detailValueWindow: GraphChatResultWindow(
                totalCount: detailValueSourceLimited ? nil : detailValueTotalCount,
                returnedCount: detailItems.count,
                limit: relatedLimit,
                limitReached: detailValueToolLimitReached || detailValueSourceLimited,
                limitSources: (detailValueToolLimitReached ? [.tool] : [])
                    + (detailValueSourceLimited ? [.source] : [])
            )
        )
        return PreparedOutput(output: output, evidence: GraphEvidenceCollection(evidence).values)
    }
}
