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

    static func hydrateAll(using modelContext: ModelContext) async {
        var changed = false

        // Entities
        do {
            let ents = try modelContext.fetch(FetchDescriptor<MetaEntity>())
            for e in ents {
                let did = hydrateOne(stableID: e.id, imageData: e.imageData, imagePath: &e.imagePath)
                if did { changed = true }
            }
        } catch {
            // ignore
        }

        // Attributes
        do {
            let attrs = try modelContext.fetch(FetchDescriptor<MetaAttribute>())
            for a in attrs {
                let did = hydrateOne(stableID: a.id, imageData: a.imageData, imagePath: &a.imagePath)
                if did { changed = true }
            }
        } catch {
            // ignore
        }

        if changed {
            try? modelContext.save()
        }
    }

    private static func hydrateOne(stableID: UUID, imageData: Data?, imagePath: inout String?) -> Bool {
        guard let d = imageData, !d.isEmpty else { return false }

        let filename = "\(stableID.uuidString).jpg"

        var didChange = false
        if imagePath != filename {
            imagePath = filename
            didChange = true
        }

        if ImageStore.fileExists(path: imagePath) {
            return didChange
        }

        do {
            _ = try ImageStore.saveJPEG(d, preferredName: filename)
        } catch {
            // not fatal
        }

        return true
    }
}
