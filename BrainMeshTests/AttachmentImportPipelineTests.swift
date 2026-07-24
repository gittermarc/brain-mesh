import Foundation
import Testing
@testable import BrainMesh

struct AttachmentImportPipelineTests {

    @Test
    func fileAboveLimitIsRejectedDeterministically() async throws {
        let sourceData = Data(repeating: 0x41, count: 32)
        let sourceURL = try makeAttachmentImportTemporaryFile(
            fileExtension: "txt",
            data: sourceData
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let attachmentID = attachmentImportUUID(1)
        let expectedCachePath = AttachmentStore.makeLocalFilename(
            attachmentID: attachmentID,
            fileExtension: "txt"
        )
        AttachmentStore.delete(localPath: expectedCachePath)
        defer { AttachmentStore.delete(localPath: expectedCachePath) }

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try await AttachmentImportPipeline.prepareFileImport(
                    from: sourceURL,
                    attachmentID: attachmentID,
                    maxBytes: 8
                )
            }.value
            Issue.record("Expected the oversized file import to fail.")
        } catch let error as AttachmentImportPipelineError {
            #expect(error == .tooLarge(bytes: sourceData.count, maxBytes: 8))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(AttachmentStore.fileExists(localPath: expectedCachePath) == false)
    }

    @Test
    func cacheWriteFailureReturnsControlledErrorAndCleansExpectedPath() async throws {
        let sourceURL = try makeAttachmentImportTemporaryFile(
            fileExtension: "txt",
            data: Data([1, 2, 3])
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let attachmentID = attachmentImportUUID(10)
        let expectedCachePath = AttachmentStore.makeLocalFilename(
            attachmentID: attachmentID,
            fileExtension: "txt"
        )
        let cleanupProbe = AttachmentImportPathProbe()
        let operations = AttachmentImportCacheOperations(
            writeToCache: { _, _, _ in
                throw AttachmentImportPipelineTestError.injectedCacheWriteFailure
            },
            copyIntoCache: { _, _, _ in
                throw AttachmentImportPipelineTestError.injectedCacheWriteFailure
            },
            resolveURL: { _ in nil },
            readData: { _ in Data() },
            delete: { localPath in
                cleanupProbe.record(localPath)
            }
        )

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try await AttachmentImportPipeline.prepareFileImport(
                    from: sourceURL,
                    attachmentID: attachmentID,
                    maxBytes: 64,
                    cacheOperations: operations
                )
            }.value
            Issue.record("Expected the cache write to fail.")
        } catch let error as AttachmentImportPipelineError {
            #expect(error == .cacheWriteFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(cleanupProbe.paths == [expectedCachePath])
    }

    @Test
    func cacheResolutionFailureReturnsControlledErrorAndCleansPreparedPath() async throws {
        let sourceURL = try makeAttachmentImportTemporaryFile(
            fileExtension: "pdf",
            data: Data([4, 5, 6])
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let attachmentID = attachmentImportUUID(20)
        let expectedCachePath = AttachmentStore.makeLocalFilename(
            attachmentID: attachmentID,
            fileExtension: "pdf"
        )
        let cleanupProbe = AttachmentImportPathProbe()
        let operations = AttachmentImportCacheOperations(
            writeToCache: { _, _, _ in expectedCachePath },
            copyIntoCache: { _, _, _ in expectedCachePath },
            resolveURL: { _ in nil },
            readData: { _ in Data() },
            delete: { localPath in
                cleanupProbe.record(localPath)
            }
        )

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try await AttachmentImportPipeline.prepareFileImport(
                    from: sourceURL,
                    attachmentID: attachmentID,
                    maxBytes: 64,
                    cacheOperations: operations
                )
            }.value
            Issue.record("Expected cache URL resolution to fail.")
        } catch let error as AttachmentImportPipelineError {
            #expect(error == .cacheWriteFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(cleanupProbe.paths == [expectedCachePath])
    }

    @Test
    func videoPreparationNormalizesDottedExtensionAndPreservesVideoKind() async throws {
        let sourceData = Data([11, 12, 13])
        let sourceURL = try makeAttachmentImportTemporaryFile(
            fileExtension: "mov",
            data: sourceData
        )
        let cachedURL = try makeAttachmentImportTemporaryFile(
            fileExtension: "cache",
            data: Data()
        )
        try FileManager.default.removeItem(at: cachedURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: cachedURL)
        }

        let localPath = "prepared.mov"
        let operations = AttachmentImportCacheOperations(
            writeToCache: { data, _, _ in
                try data.write(to: cachedURL, options: [.atomic])
                return localPath
            },
            copyIntoCache: { source, _, _ in
                try FileManager.default.copyItem(at: source, to: cachedURL)
                return localPath
            },
            resolveURL: { _ in cachedURL },
            readData: { url in
                try Data(contentsOf: url, options: [.mappedIfSafe])
            },
            delete: { _ in
                try? FileManager.default.removeItem(at: cachedURL)
            }
        )

        let prepared = try await Task.detached(priority: .userInitiated) {
            try await AttachmentImportPipeline.prepareVideoImport(
                from: sourceURL,
                attachmentID: attachmentImportUUID(40),
                suggestedFilename: "Holiday.mov",
                contentTypeIdentifier: "public.movie",
                fileExtension: ".mov",
                maxBytes: 64,
                cacheOperations: operations
            )
        }.value

        #expect(prepared.title == "Holiday")
        #expect(prepared.originalFilename == "Holiday.mov")
        #expect(prepared.fileExtension == "mov")
        #expect(prepared.contentTypeIdentifier == "public.movie")
        #expect(prepared.inferredKind == .video)
        #expect(prepared.fileData == sourceData)
    }

    @Test
    func temporaryPickerFileIsRemovedBestEffortAfterSuccess() async throws {
        let temporaryURL = try makeAttachmentImportTemporaryFile(
            fileExtension: "mov",
            data: Data([21, 22, 23])
        )
        #expect(FileManager.default.fileExists(atPath: temporaryURL.path))

        await AttachmentImportFileCleanup
            .removeTemporaryPickerFileBestEffort(at: temporaryURL)

        #expect(FileManager.default.fileExists(atPath: temporaryURL.path) == false)

        // A missing picker file is intentionally silent and must not turn a successful import
        // into a later error state.
        await AttachmentImportFileCleanup
            .removeTemporaryPickerFileBestEffort(at: temporaryURL)
    }
}

@MainActor
struct AttachmentImportPresentationPolicyTests {

    @Test
    func cancelledVideoPickerProducesNoErrorMessage() {
        #expect(
            AttachmentImportPresentationPolicy.videoPickerErrorMessage(
                for: VideoPickerError.cancelled
            ) == nil
        )
    }
}

private nonisolated enum AttachmentImportPipelineTestError: Error {
    case injectedCacheWriteFailure
}

private nonisolated final class AttachmentImportPathProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPaths: [String] = []

    var paths: [String] {
        lock.withLock { storedPaths }
    }

    func record(_ localPath: String?) {
        guard let localPath else { return }
        lock.withLock {
            storedPaths.append(localPath)
        }
    }
}

private nonisolated func makeAttachmentImportTemporaryFile(
    fileExtension: String,
    data: Data
) throws -> URL {
    let normalizedExtension = fileExtension.trimmingCharacters(
        in: CharacterSet(charactersIn: ".")
    )
    var url = FileManager.default.temporaryDirectory
        .appendingPathComponent("brainmesh-attachment-import-\(UUID().uuidString)")
    if normalizedExtension.isEmpty == false {
        url = url.appendingPathExtension(normalizedExtension)
    }
    try data.write(to: url, options: [.atomic])
    return url
}

private nonisolated func attachmentImportUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
