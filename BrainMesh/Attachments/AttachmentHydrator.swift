//
//  AttachmentHydrator.swift
//  BrainMesh
//
//  Patch 4: Progressive hydration for attachment cache files.
//  Goal: Avoid cache-miss stampedes (especially on new devices / cleared cache)
//  by ensuring cached file URLs only for visible items and doing heavy work
//  off the UI thread with strict global throttling.
//

import Foundation
import SwiftData
import os

actor AttachmentHydrator {

    static let shared = AttachmentHydrator()

    private var container: AnyModelContainer? = nil

    /// Global throttle for "fetch external data + write cache" work.
    /// Keep this low – the whole point is that *opening* a screen must stay responsive.
    private let hydrateLimiter = AsyncLimiter(maxConcurrent: 2)

    /// Dedupe per attachment id.
    private var inFlight: [UUID: Task<URL?, Never>] = [:]

    private let log = Logger(subsystem: "BrainMesh", category: "AttachmentHydrator")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    /// Ensures the cached file exists for a given attachment.
    ///
    /// - First: cheap disk check (localPath or deterministic filename).
    /// - If missing: fetch `fileData` in a background `ModelContext` and write it into Application Support.
    ///
    /// This method is designed to be called from SwiftUI cells as they appear.
    func ensureFileURL(attachmentID: UUID, fileExtension: String, localPath: String?) async -> URL? {
        if let existing = AttachmentStore.existingCachedFileURL(
            localPath: localPath,
            attachmentID: attachmentID,
            fileExtension: fileExtension
        ) {
            return existing
        }

        if let task = inFlight[attachmentID] {
            return await task.value
        }

	        // IMPORTANT:
	        // The closure passed to `hydrateLimiter.withPermit { ... }` executes in the limiter actor's isolation.
	        // It must NOT access `AttachmentHydrator` actor-isolated state (like `self.container`).
	        // So we copy what we need *here* (inside the hydrator actor) and use only the copy inside the limiter.
	        let configuredContainer = self.container
	        let limiter = self.hydrateLimiter

	        let task = Task<URL?, Never> { [configuredContainer, limiter, attachmentID, fileExtension, localPath] in
	            guard let configuredContainer else {
	                return nil
	            }

	            return await limiter.withPermit {
	                return await Task.detached(priority: .utility) { [configuredContainer, attachmentID, fileExtension, localPath] in
	                    // Race-safe re-check.
	                    if let existing = AttachmentStore.existingCachedFileURL(
	                        localPath: localPath,
	                        attachmentID: attachmentID,
	                        fileExtension: fileExtension
	                    ) {
	                        return existing
	                    }

	                    // Fetch attachment bytes off-main.
	                    let context = ModelContext(configuredContainer.container)
	                    context.autosaveEnabled = false

	                    var fd = FetchDescriptor<MetaAttachment>(
	                        predicate: #Predicate { a in
	                            a.id == attachmentID
	                        }
	                    )
	                    fd.fetchLimit = 1

	                    guard let record = try? context.fetch(fd).first else {
	                        return nil
	                    }
	                    guard let data = record.fileData else {
	                        return nil
	                    }

	                    do {
	                        let filename = try AttachmentStore.writeToCache(
	                            data: data,
	                            attachmentID: attachmentID,
	                            fileExtension: fileExtension
	                        )
	                        return AttachmentStore.url(forLocalPath: filename)
	                    } catch {
	                        return nil
	                    }
	                }.value
	            }
	        }

	        inFlight[attachmentID] = task
	        let url = await task.value
	        inFlight[attachmentID] = nil
	        return url
    }
}
