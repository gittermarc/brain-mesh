//
//  SFSymbolsCatalog.swift
//  BrainMesh
//
//  Created by Marc Fechner on 18.02.26.
//

import Foundation
import OSLog

nonisolated enum SFSymbolsCatalog {

    private static let log = Logger(subsystem: "BrainMesh", category: "SFSymbolsCatalog")

    enum CatalogError: Error, LocalizedError {
        case coreGlyphsBundleNotFound
        case catalogPlistNotFound
        case catalogPlistUnreadable
        case catalogFormatUnexpected

        var errorDescription: String? {
            switch self {
            case .coreGlyphsBundleNotFound:
                return "CoreGlyphs-Bundle konnte nicht gefunden werden."
            case .catalogPlistNotFound:
                return "SF-Symbol-Katalogdatei konnte nicht gefunden werden."
            case .catalogPlistUnreadable:
                return "SF-Symbol-Katalogdatei konnte nicht gelesen werden."
            case .catalogFormatUnexpected:
                return "SF-Symbol-Katalog hat ein unerwartetes Format."
            }
        }
    }

    /// Loads *all* SF Symbol names from the system CoreGlyphs bundle.
    ///
    /// This is intentionally **not** prewarmed on app startup.
    /// Call this only when needed (e.g. when opening the "Alle SF Symbols" browser).
    static func loadAllSymbolNames() throws -> [String] {
        guard let bundle = resolveCoreGlyphsBundle() else {
            log.error("CoreGlyphs bundle not found")
            throw CatalogError.coreGlyphsBundleNotFound
        }

        // Primary source (commonly available): name_availability.plist
        if let names = try? loadNamesFromNameAvailability(bundle: bundle), !names.isEmpty {
            return names
        }

        // Fallback: symbol_order.plist (often contains a simple array of names)
        if let names = try? loadNamesFromSymbolOrder(bundle: bundle), !names.isEmpty {
            return names
        }

        log.error("No usable plist found in CoreGlyphs bundle")
        throw CatalogError.catalogPlistNotFound
    }

    // MARK: - Bundle resolution

    private static func resolveCoreGlyphsBundle() -> Bundle? {
        // Preferred: bundle identifier
        if let b = Bundle(identifier: "com.apple.CoreGlyphs") {
            return b
        }

        // Known on-device locations (best-effort)
        let candidatePaths: [String] = [
            "/System/Library/CoreServices/CoreGlyphs.bundle",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/CoreGlyphs.bundle"
        ]

        for p in candidatePaths {
            if let b = Bundle(path: p) {
                return b
            }
        }

        return nil
    }

    // MARK: - Parsers

    private static func loadNamesFromNameAvailability(bundle: Bundle) throws -> [String] {
        guard let url = bundle.url(forResource: "name_availability", withExtension: "plist") else {
            throw CatalogError.catalogPlistNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error("Failed to read name_availability.plist: \(String(describing: error), privacy: .public)")
            throw CatalogError.catalogPlistUnreadable
        }

        let plistAny: Any
        do {
            plistAny = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            log.error("Failed to decode name_availability.plist: \(String(describing: error), privacy: .public)")
            throw CatalogError.catalogPlistUnreadable
        }

        // Expected format (observed): { "symbols": { "star": "..." , ... } }
        if let dict = plistAny as? [String: Any] {
            if let symbols = dict["symbols"] as? [String: Any] {
                return symbols.keys.sorted()
            }
            if let symbols = dict["symbols"] as? [String: String] {
                return symbols.keys.sorted()
            }
        }

        throw CatalogError.catalogFormatUnexpected
    }

    private static func loadNamesFromSymbolOrder(bundle: Bundle) throws -> [String] {
        guard let url = bundle.url(forResource: "symbol_order", withExtension: "plist") else {
            throw CatalogError.catalogPlistNotFound
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error("Failed to read symbol_order.plist: \(String(describing: error), privacy: .public)")
            throw CatalogError.catalogPlistUnreadable
        }

        let plistAny: Any
        do {
            plistAny = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            log.error("Failed to decode symbol_order.plist: \(String(describing: error), privacy: .public)")
            throw CatalogError.catalogPlistUnreadable
        }

        if let arr = plistAny as? [String] {
            return arr
        }

        if let dict = plistAny as? [String: Any] {
            if let arr = dict["symbols"] as? [String] {
                return arr
            }
        }

        throw CatalogError.catalogFormatUnexpected
    }
}
