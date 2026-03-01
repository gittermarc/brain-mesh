//
//  GraphCanvasDataLoader+Caches.swift
//  BrainMesh
//
//  Split from GraphCanvasDataLoader.swift (P0.x): Render caches helpers.
//

import Foundation
import SwiftData

extension GraphCanvasDataLoader {

    /// Build render caches once per load.
    ///
    /// Note: Internal (module-visible) so it can be reused across extension files.
    static func buildRenderCaches(
        entities: [MetaEntity],
        attributes: [MetaAttribute]
    ) throws -> (
        labelCache: [NodeKey: String],
        imagePathCache: [NodeKey: String],
        iconSymbolCache: [NodeKey: String]
    ) {
        var newLabelCache: [NodeKey: String] = [:]
        var newImagePathCache: [NodeKey: String] = [:]
        var newIconSymbolCache: [NodeKey: String] = [:]

        for e in entities {
            try Task.checkCancellation()
            let k = NodeKey(kind: .entity, uuid: e.id)
            newLabelCache[k] = e.name
            if let p = e.imagePath, !p.isEmpty { newImagePathCache[k] = p }
            if let s = e.iconSymbolName, !s.isEmpty { newIconSymbolCache[k] = s }
        }

        for a in attributes {
            try Task.checkCancellation()
            let k = NodeKey(kind: .attribute, uuid: a.id)
            newLabelCache[k] = a.displayName
            if let p = a.imagePath, !p.isEmpty { newImagePathCache[k] = p }
            if let s = a.iconSymbolName, !s.isEmpty { newIconSymbolCache[k] = s }
        }

        return (
            labelCache: newLabelCache,
            imagePathCache: newImagePathCache,
            iconSymbolCache: newIconSymbolCache
        )
    }
}
