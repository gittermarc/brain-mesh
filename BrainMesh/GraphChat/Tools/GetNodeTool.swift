//
//  GetNodeTool.swift
//  BrainMesh
//
//  Read-only node details with typed fields and metadata-only attachments.
//

import Foundation

nonisolated struct GetNodeInput: Sendable {
    let node: NodeRefKey
    /// Compatibility cap applied independently to every profile area.
    /// Productive provider calls always use the app-owned default.
    let relatedLimit: Int
    let includeNotes: Bool

    init(
        node: NodeRefKey,
        relatedLimit: Int =
            GraphChatIntentLimitPolicy
                .default.nodeDetailRelatedItemCount,
        includeNotes: Bool = true
    ) {
        self.node = node
        self.relatedLimit = relatedLimit
        self.includeNotes = includeNotes
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
    let incomingLinkWindow: GraphChatResultWindow
    let outgoingLinkWindow: GraphChatResultWindow
    let attachmentWindow: GraphChatResultWindow
    let hasNotes: Bool
    let directLinkCount: Int
    let attachmentMetadataCount: Int
    let authoritativeDetailValueCount: Int
    let structureEvidenceID: GraphEvidenceID?

    init(
        node: NodeRefKey,
        label: String,
        notes: String,
        owner: GraphChatNodeOwner?,
        detailValues: [GraphChatNodeDetailValue],
        links: [GraphChatNodeLinkMetadata],
        attachments: [GraphChatAttachmentMetadata],
        evidenceIDs: [GraphEvidenceID],
        detailValueWindow: GraphChatResultWindow? = nil,
        incomingLinkWindow: GraphChatResultWindow? = nil,
        outgoingLinkWindow: GraphChatResultWindow? = nil,
        attachmentWindow: GraphChatResultWindow? = nil,
        hasNotes: Bool? = nil,
        directLinkCount: Int? = nil,
        attachmentMetadataCount: Int? = nil,
        authoritativeDetailValueCount: Int? = nil,
        structureEvidenceID: GraphEvidenceID? = nil
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
        self.incomingLinkWindow =
            incomingLinkWindow
            ?? .complete(
                totalCount:
                    links.filter {
                        $0.direction == .incoming
                    }.count
            )
        self.outgoingLinkWindow =
            outgoingLinkWindow
            ?? .complete(
                totalCount:
                    links.filter {
                        $0.direction == .outgoing
                    }.count
            )
        self.attachmentWindow =
            attachmentWindow
            ?? .complete(
                totalCount: attachments.count
            )
        self.hasNotes =
            hasNotes
            ?? notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false
        self.directLinkCount =
            directLinkCount ?? links.count
        self.attachmentMetadataCount =
            attachmentMetadataCount
            ?? attachments.count
        self.authoritativeDetailValueCount =
            authoritativeDetailValueCount
            ?? detailValues.count
        self.structureEvidenceID =
            structureEvidenceID
    }
}

nonisolated struct GetNodeTool: GraphChatTool {
    let kind = GraphChatToolKind.getNode
    static let maximumRelatedItemCount =
        GraphChatIntentLimitPolicy
            .default.maximumNodeRelatedItemCount

    private struct PreparedOutput: Sendable {
        let output: GetNodeOutput
        let evidence: [GraphEvidence]
    }

    private let repository:
        any GraphNodeProfileReading
    private let evidenceValidator: any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        repository: any GraphNodeProfileReading = GraphReadRepository.shared,
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
                    message: "GetNode erlaubt höchstens \(Self.maximumRelatedItemCount) Ergebnisse je Profilbereich."
                )
            }
            _ = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: 1,
                toolMaximumResultCount: 1
            )
            let profileLimits =
                GraphChatIntentLimitPolicy
                    .default.nodeProfileLimits(
                        compatibilityLimit:
                            input.relatedLimit
                    )
            try Task.checkCancellation()
            guard let prepared = try await prepare(
                node: input.node,
                limits: profileLimits,
                includeNotes: input.includeNotes,
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
            let validatedLinks =
                prepared.output.links.filter {
                    validIDs.contains($0.evidenceID)
                }
            let validatedAttachments =
                prepared.output.attachments.filter {
                    validIDs.contains($0.evidenceID)
                }
            let output = GetNodeOutput(
                node: prepared.output.node,
                label: prepared.output.label,
                notes: prepared.output.notes,
                owner: prepared.output.owner,
                detailValues: validatedDetailValues,
                links: validatedLinks,
                attachments: validatedAttachments,
                evidenceIDs: prepared.output.evidenceIDs.filter {
                    validIDs.contains($0)
                },
                detailValueWindow:
                    Self.validatedWindow(
                        prepared.output
                            .detailValueWindow,
                        returnedCount:
                            validatedDetailValues.count
                    ),
                incomingLinkWindow:
                    Self.validatedWindow(
                        prepared.output
                            .incomingLinkWindow,
                        returnedCount:
                            validatedLinks.filter {
                                $0.direction
                                    == .incoming
                            }.count
                    ),
                outgoingLinkWindow:
                    Self.validatedWindow(
                        prepared.output
                            .outgoingLinkWindow,
                        returnedCount:
                            validatedLinks.filter {
                                $0.direction
                                    == .outgoing
                            }.count
                    ),
                attachmentWindow:
                    Self.validatedWindow(
                        prepared.output
                            .attachmentWindow,
                        returnedCount:
                            validatedAttachments.count
                    ),
                hasNotes:
                    prepared.output.hasNotes,
                directLinkCount:
                    prepared.output
                        .directLinkCount,
                attachmentMetadataCount:
                    prepared.output
                        .attachmentMetadataCount,
                authoritativeDetailValueCount:
                    prepared.output
                        .authoritativeDetailValueCount,
                structureEvidenceID:
                    prepared.output.structureEvidenceID
                        .flatMap { evidenceID in
                            validIDs.contains(evidenceID)
                                ? evidenceID
                                : nil
                        }
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
        limits: GraphNodeProfileLimits,
        includeNotes: Bool,
        graphScope: GraphScope
    ) async throws -> PreparedOutput? {
        guard
            let profile = try await repository.nodeProfile(
                node,
                in: graphScope,
                limits: limits
            ),
            profile.scope == graphScope,
            profile.nodeKey == node
        else {
            return nil
        }
        try Task.checkCancellation()

        let label = profile.displayName
        let notes = profile.notes
        let owner = profile.ownerEntity.map {
            GraphChatNodeOwner(
                entityID: $0.entityID,
                label: $0.visibleName
            )
        }
        let baseReference = GraphSourceReference(
            graphID: graphScope.graphID,
            sourceKind:
                node.kind == .entity
                ? .entity
                : .attribute,
            sourceID: node.id,
            node: GraphSourceNodeReference(
                kind: node.kind,
                id: node.id
            ),
            owner: profile.ownerEntity.map {
                GraphSourceNodeReference(
                    kind: .entity,
                    id: $0.entityID
                )
            }
        )
        var baseFields: [GraphEvidenceFieldValue] = []
        if profile.hasNotes {
            baseFields.append(
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Notizen",
                    value: .text(notes),
                    unit: nil
                )
            )
        }
        let visibleNotes = includeNotes ? notes : ""
        let baseEvidence = GraphEvidence(
            sourceReference: baseReference,
            summary: label,
            fieldValues:
                includeNotes ? baseFields : [],
            navigationTitle: label,
            identitySuffix: "node-detail"
        )
        var evidence = [baseEvidence]

        var detailItems: [GraphChatNodeDetailValue] = []
        detailItems.reserveCapacity(
            profile.detailValues.count
        )
        for detailValue in profile.detailValues {
            try Task.checkCancellation()
            let itemEvidence = GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .detailValue,
                    sourceID: detailValue.valueID,
                    node: GraphSourceNodeReference(
                        kind: .attribute,
                        id: node.id
                    ),
                    owner: profile.ownerEntity.map {
                        GraphSourceNodeReference(
                            kind: .entity,
                            id: $0.entityID
                        )
                    },
                    fieldID: detailValue.fieldID
                ),
                summary:
                    "\(label): \(detailValue.fieldName)",
                fieldValues: [
                    GraphEvidenceFieldValue(
                        fieldID:
                            detailValue.fieldID,
                        fieldName:
                            detailValue.fieldName,
                        value:
                            detailValue.value
                                .graphEvidenceValue,
                        unit: detailValue.unit
                    ),
                ],
                navigationTitle: label,
                identitySuffix: "node-field"
            )
            evidence.append(itemEvidence)
            detailItems.append(
                GraphChatNodeDetailValue(
                    valueID: detailValue.valueID,
                    fieldID: detailValue.fieldID,
                    fieldName:
                        detailValue.fieldName,
                    fieldType:
                        detailValue.fieldType,
                    unit: detailValue.unit,
                    value:
                        detailValue.value
                            .graphChatCellValue,
                    evidenceID: itemEvidence.id
                )
            )
        }

        var linkItems: [GraphChatNodeLinkMetadata] = []
        let connections =
            profile.outgoingConnections
            + profile.incomingConnections
        linkItems.reserveCapacity(connections.count)
        for connection in connections {
            try Task.checkCancellation()
            let direction: GraphChatLinkDirection
            let sourceDirection:
                GraphSourceLinkDirection
            switch connection.direction {
            case .incoming:
                direction = .incoming
                sourceDirection = .incoming
            case .outgoing:
                direction = .outgoing
                sourceDirection = .outgoing
            }
            let itemEvidence = GraphEvidence(
                sourceReference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .link,
                    sourceID: connection.linkID,
                    node: GraphSourceNodeReference(
                        kind: node.kind,
                        id: node.id
                    ),
                    linkID: connection.linkID,
                    linkBinding:
                        GraphSourceLinkBinding(
                            linkID:
                                connection.linkID,
                            source:
                                GraphSourceNodeReference(
                                    kind:
                                        connection
                                            .source.kind,
                                    id:
                                        connection
                                            .source
                                            .nodeKey.id
                                ),
                            target:
                                GraphSourceNodeReference(
                                    kind:
                                        connection
                                            .target.kind,
                                    id:
                                        connection
                                            .target
                                            .nodeKey.id
                                ),
                            direction:
                                sourceDirection,
                            note: connection.note
                        )
                ),
                summary:
                    "\(connection.source.displayName) → \(connection.target.displayName)",
                fieldValues: connection.note.map {
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
                    id: connection.linkID,
                    direction: direction,
                    source:
                        connection.source.nodeKey,
                    sourceLabel:
                        connection.source.displayName,
                    target:
                        connection.target.nodeKey,
                    targetLabel:
                        connection.target.displayName,
                    note: connection.note,
                    evidenceID: itemEvidence.id
                )
            )
        }

        var attachmentItems: [GraphChatAttachmentMetadata] = []
        attachmentItems.reserveCapacity(
            profile.attachments.count
        )
        for attachment in profile.attachments {
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
                        value:
                            .integer(
                                attachment.byteCount
                            ),
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

        var structureFields: [GraphEvidenceFieldValue] = [
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Node-Art",
                value: .text(
                    node.kind == .entity
                    ? "entity"
                    : "attribute"
                ),
                unit: nil
            ),
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Direkte Verbindungen",
                value: .integer(
                    profile.directLinkCount
                ),
                unit: nil
            ),
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Attachment-Metadaten",
                value: .integer(
                    profile.attachmentWindow
                        .totalCount
                ),
                unit: nil
            ),
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Notizen vorhanden",
                value: .boolean(
                    profile.hasNotes
                ),
                unit: nil
            ),
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Autoritative Detailwerte",
                value: .integer(
                    profile.detailValueWindow
                        .totalCount
                ),
                unit: nil
            ),
        ]
        if let ownerLabel = owner?.label {
            structureFields.append(
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Owner",
                    value: .text(ownerLabel),
                    unit: nil
                )
            )
        }
        let structureEvidence = GraphEvidence(
            sourceReference: baseReference,
            summary: label,
            fieldValues: structureFields,
            navigationTitle: label,
            identitySuffix: "node-structure"
        )
        evidence.append(structureEvidence)

        let output = GetNodeOutput(
            node: node,
            label: label,
            notes: visibleNotes,
            owner: owner,
            detailValues: detailItems,
            links: linkItems,
            attachments: attachmentItems,
            evidenceIDs: evidence.map(\.id),
            detailValueWindow:
                Self.chatWindow(
                    profile.detailValueWindow
                ),
            incomingLinkWindow:
                Self.chatWindow(
                    profile
                        .incomingConnectionWindow
                ),
            outgoingLinkWindow:
                Self.chatWindow(
                    profile
                        .outgoingConnectionWindow
                ),
            attachmentWindow:
                Self.chatWindow(
                    profile.attachmentWindow
                ),
            hasNotes: profile.hasNotes,
            directLinkCount:
                profile.directLinkCount,
            attachmentMetadataCount:
                profile.attachmentWindow
                    .totalCount,
            authoritativeDetailValueCount:
                profile.detailValueWindow
                    .totalCount,
            structureEvidenceID:
                structureEvidence.id
        )
        return PreparedOutput(output: output, evidence: GraphEvidenceCollection(evidence).values)
    }

    private nonisolated static func chatWindow(
        _ window: GraphNodeProfileResultWindow
    ) -> GraphChatResultWindow {
        GraphChatResultWindow(
            totalCount: window.totalCount,
            returnedCount: window.returnedCount,
            limit: window.limit,
            limitReached: window.limitReached,
            limitSources:
                window.limitReached
                ? [.tool]
                : []
        )
    }

    private nonisolated static func validatedWindow(
        _ source: GraphChatResultWindow,
        returnedCount: Int
    ) -> GraphChatResultWindow {
        let evidenceWasRemoved =
            returnedCount < source.returnedCount
        return GraphChatResultWindow(
            totalCount:
                evidenceWasRemoved
                ? nil
                : source.totalCount,
            returnedCount: returnedCount,
            limit: source.limit,
            limitReached:
                source.limitReached
                || evidenceWasRemoved,
            limitSources:
                source.limitSources
                + (
                    evidenceWasRemoved
                    ? [.source]
                    : []
                )
        )
    }
}
