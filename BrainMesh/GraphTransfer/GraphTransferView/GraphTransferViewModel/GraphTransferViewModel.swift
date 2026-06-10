//
//  GraphTransferViewModel.swift
//  BrainMesh
//

import Foundation
import Combine
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class GraphTransferViewModel: ObservableObject, @unchecked Sendable {

    enum ExportState {
        case idle
        case exporting(label: String)
        case ready(url: URL, summary: ExportSummary)
        case failed(message: String)
    }

    enum ImportState {
        case idle
        case inspecting(label: String)
        case ready(preview: ImportPreview)
        case importing(progress: GraphTransferProgress)
        case finished(result: ImportResult)
        case failed(message: String)
    }

    struct ExportSummary {
        var kind: GraphTransferExportKind
        var counts: CountsDTO
        var attachmentCount: Int
        var attachmentBytes: Int64
        var warningCount: Int

        init(
            kind: GraphTransferExportKind,
            counts: CountsDTO,
            attachmentCount: Int = 0,
            attachmentBytes: Int64 = 0,
            warningCount: Int = 0
        ) {
            self.kind = kind
            self.counts = counts
            self.attachmentCount = attachmentCount
            self.attachmentBytes = attachmentBytes
            self.warningCount = warningCount
        }

        var summaryText: String? {
            GraphTransferExportCopy.readySummary(
                kind: kind,
                counts: counts,
                attachmentCount: attachmentCount,
                attachmentBytes: attachmentBytes,
                warningCount: warningCount
            )
        }
    }

    struct AlertState: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    struct ReplaceCandidate: Identifiable, Hashable {
        var id: UUID
        var name: String
        var createdAt: Date
    }

    @Published var activeGraphName: String = "—"
    @Published var activeGraphAttachmentEstimate: GraphTransferAttachmentEstimate = .empty

    @Published var exportKind: GraphTransferExportKind = .graphStructure
    @Published var includeNotes: Bool = true
    @Published var includeIcons: Bool = true
    @Published var includeImages: Bool = false
    @Published var includeAttachments: Bool = true

    @Published var exportState: ExportState = .idle
    @Published var importState: ImportState = .idle

    @Published var isShowingExportConfirm: Bool = false
    @Published var isShowingFileImporter: Bool = false
    @Published var isShowingShareSheet: Bool = false

    @Published var isShowingImportLimitAlert: Bool = false
    @Published var isShowingReplaceSheet: Bool = false
    @Published var isShowingProPaywall: Bool = false

    @Published var isShowingFileExporter: Bool = false
    @Published var exportDocument: BMGraphFileDocument = BMGraphFileDocument(data: Data(), contentType: UTType.brainMeshGraph)

    @Published var exportedFileURL: URL? = nil
    @Published var selectedImportURL: URL? = nil

    @Published var alertState: AlertState? = nil

    @Published var replaceCandidates: [ReplaceCandidate] = []

    var didConfigure: Bool = false

    var isBusy: Bool {
        if case .exporting = exportState { return true }
        if case .inspecting = importState { return true }
        if case .importing = importState { return true }
        return false
    }
}
