//
//  ImageHydrator.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import Foundation
import SwiftData
import os

/// Progressive hydration for the local image cache.
///
/// Why this exists:
/// - Records can sync to a device with `imageData` / `imagePath`, while the deterministic JPEG
///   file is not yet cached locally.
/// - Creating those cache files (and setting `imagePath`) must not block the UI.
///
/// Design:
/// - Uses a background `ModelContext` created from a configured `ModelContainer`.
/// - Runs hydration passes serialized via a tiny async semaphore.
/// - Keeps a run-once-per-launch guard for the incremental pass.
actor ImageHydrator {

    static let shared = ImageHydrator()

    private var container: AnyModelContainer? = nil
    private var didRunIncrementalThisLaunch: Bool = false

    /// Serialize passes so we don't compete on disk work.
    private let passLimiter = AsyncLimiter(maxConcurrent: 1)

    private let log = Logger(subsystem: "BrainMesh", category: "ImageHydrator")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    /// Incremental hydration (cheap): only scans records where `imageData != nil`.
    /// Additionally, this method is guarded to run at most once per app launch by default.
    /// - Returns: `true` if a hydration pass was executed (i.e. not skipped by the run-once guard).
    func hydrateIncremental(runOncePerLaunch: Bool = true) async -> Bool {
        guard container != nil else {
            #if DEBUG
            log.debug("⚠️ skipped incremental hydration (not configured)")
            #endif
            return false
        }

        if runOncePerLaunch {
            guard didRunIncrementalThisLaunch == false else { return false }
            didRunIncrementalThisLaunch = true
        }

        await hydrate(mode: .incremental)
        return true
    }

    /// Manual repair/rebuild: rewrites cached JPEGs for all records with `imageData != nil`.
    /// Intended to be triggered from Settings.
    func forceRebuild() async {
        guard container != nil else {
            #if DEBUG
            log.debug("⚠️ skipped rebuild (not configured)")
            #endif
            return
        }
        await hydrate(mode: .forceRebuild)
    }

    /// On-demand hydration (Selection): ensures the deterministic cached JPEG exists locally.
    /// Returns the deterministic filename if the cache file exists (after the operation).
    ///
    /// This does not touch SwiftData and is safe to call from any context.
    static func ensureCachedJPEGExists(stableID: UUID, jpegData: Data?) async -> String? {
        guard let d = jpegData, !d.isEmpty else { return nil }

        let filename = "\(stableID.uuidString).jpg"

        if ImageStore.fileExists(path: filename) {
            return filename
        }

        do {
            _ = try await ImageStore.saveJPEGAsync(d, preferredName: filename)
        } catch {
            // ignore
        }

        return ImageStore.fileExists(path: filename) ? filename : nil
    }

    private enum HydrationMode {
        case incremental
        case forceRebuild
    }

    private func hydrate(mode: HydrationMode) async {
        // IMPORTANT:
        // The closure passed to `passLimiter.withPermit { ... }` executes in the limiter actor's isolation.
        // It must NOT access `ImageHydrator` actor-isolated state (like `self.container`).
        // So we copy what we need *here* and use only the copy inside the limiter.
        let configuredContainer = self.container
        let limiter = self.passLimiter

        guard let configuredContainer else { return }

        await limiter.withPermit {
            await Task.detached(priority: .utility) {
                let forceWrite = (mode == .forceRebuild)

                let context = ModelContext(configuredContainer.container)
                context.autosaveEnabled = false

                // Entities (only those with imageData)
                do {
                    let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { e in
                        e.imageData != nil
                    })
                    let ents = try context.fetch(fd)
                    for e in ents {
                        await ImageHydrator.hydrateEntity(e, forceWrite: forceWrite)
                    }
                } catch {
                    // ignore
                }

                // Attributes (only those with imageData)
                do {
                    let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { a in
                        a.imageData != nil
                    })
                    let attrs = try context.fetch(fd)
                    for a in attrs {
                        await ImageHydrator.hydrateAttribute(a, forceWrite: forceWrite)
                    }
                } catch {
                    // ignore
                }

                // Only save if we actually changed SwiftData records.
                // Writing cache files does not require a save.
                if context.hasChanges {
                    try? context.save()
                }
            }.value
        }
    }

    private static func hydrateEntity(_ e: MetaEntity, forceWrite: Bool) async {
        guard let d = e.imageData, !d.isEmpty else { return }

        let filename = "\(e.id.uuidString).jpg"

        if e.imagePath != filename {
            e.imagePath = filename
        }

        if !forceWrite, ImageStore.fileExists(path: filename) {
            return
        }

        do {
            _ = try await ImageStore.saveJPEGAsync(d, preferredName: filename)
        } catch {
            return
        }
    }

    private static func hydrateAttribute(_ a: MetaAttribute, forceWrite: Bool) async {
        guard let d = a.imageData, !d.isEmpty else { return }

        let filename = "\(a.id.uuidString).jpg"

        if a.imagePath != filename {
            a.imagePath = filename
        }

        if !forceWrite, ImageStore.fileExists(path: filename) {
            return
        }

        do {
            _ = try await ImageStore.saveJPEGAsync(d, preferredName: filename)
        } catch {
            return
        }
    }
}
