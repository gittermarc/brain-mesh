//
//  ImageHydrator.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import Foundation
import SwiftData

@MainActor
enum ImageHydrator {

    private static var didRunIncrementalThisLaunch: Bool = false

    /// Incremental hydration (cheap): only scans records where `imageData != nil`.
    /// Additionally, this method is guarded to run at most once per app launch by default.
    /// - Returns: `true` if a hydration pass was executed (i.e. not skipped by the run-once guard).
    static func hydrateIncremental(using modelContext: ModelContext, runOncePerLaunch: Bool = true) async -> Bool {
        if runOncePerLaunch {
            guard didRunIncrementalThisLaunch == false else { return false }
            didRunIncrementalThisLaunch = true
        }

        await hydrate(using: modelContext, mode: .incremental)
        return true
    }

    /// Manual repair/rebuild: rewrites cached JPEGs for all records with `imageData != nil`.
    /// Intended to be triggered from Settings.
    static func forceRebuild(using modelContext: ModelContext) async {
        await hydrate(using: modelContext, mode: .forceRebuild)
    }

    /// On-demand hydration (Selection): ensures the deterministic cached JPEG exists locally.
    /// Returns the deterministic filename if the cache file exists (after the operation).
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

    private static func hydrate(using modelContext: ModelContext, mode: HydrationMode) async {
        var changed = false
        let forceWrite = (mode == .forceRebuild)

        // Entities (only those with imageData)
        do {
            let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { e in
                e.imageData != nil
            })
            let ents = try modelContext.fetch(fd)
            for e in ents {
                let did = await hydrateEntity(e, forceWrite: forceWrite)
                if did { changed = true }
            }
        } catch {
            // ignore
        }

        // Attributes (only those with imageData)
        do {
            let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { a in
                a.imageData != nil
            })
            let attrs = try modelContext.fetch(fd)
            for a in attrs {
                let did = await hydrateAttribute(a, forceWrite: forceWrite)
                if did { changed = true }
            }
        } catch {
            // ignore
        }

        if changed {
            try? modelContext.save()
        }
    }

    private static func hydrateEntity(_ e: MetaEntity, forceWrite: Bool) async -> Bool {
        guard let d = e.imageData, !d.isEmpty else { return false }

        let filename = "\(e.id.uuidString).jpg"
        var didChange = false

        if e.imagePath != filename {
            e.imagePath = filename
            didChange = true
        }

        if !forceWrite, ImageStore.fileExists(path: filename) {
            return didChange
        }

        do {
            _ = try await ImageStore.saveJPEGAsync(d, preferredName: filename)
            return true
        } catch {
            return didChange
        }
    }

    private static func hydrateAttribute(_ a: MetaAttribute, forceWrite: Bool) async -> Bool {
        guard let d = a.imageData, !d.isEmpty else { return false }

        let filename = "\(a.id.uuidString).jpg"
        var didChange = false

        if a.imagePath != filename {
            a.imagePath = filename
            didChange = true
        }

        if !forceWrite, ImageStore.fileExists(path: filename) {
            return didChange
        }

        do {
            _ = try await ImageStore.saveJPEGAsync(d, preferredName: filename)
            return true
        } catch {
            return didChange
        }
    }
}
