//
//  GraphStatsUserFacingErrorMessage.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.06.26.
//

import Foundation

struct GraphStatsUserFacingErrorMessage: Equatable, Sendable {
    enum Context: Sendable {
        case dashboard
        case perGraph
    }

    let title: String
    let message: String
    let recoverySuggestion: String
    let systemImage: String

    static func make(for error: Error, context: Context) -> GraphStatsUserFacingErrorMessage? {
        if error is CancellationError {
            return nil
        }

        let nsError = error as NSError
        if isStorageRelated(nsError) {
            return storageMessage(context: context)
        }

        return genericMessage(context: context)
    }

    private static func isStorageRelated(_ error: NSError) -> Bool {
        let domain = error.domain.lowercased()
        return domain == NSCocoaErrorDomain.lowercased()
            || domain.contains("swiftdata")
            || domain.contains("coredata")
            || domain.contains("sqlite")
            || domain.contains("modelcontext")
            || domain.contains("persistentstore")
    }

    private static func storageMessage(context: Context) -> GraphStatsUserFacingErrorMessage {
        switch context {
        case .dashboard:
            return GraphStatsUserFacingErrorMessage(
                title: "Statistiken konnten nicht geladen werden",
                message: "BrainMesh konnte die Übersicht gerade nicht aus dem lokalen Datenspeicher berechnen. Deine Graph-Daten wurden dadurch nicht verändert.",
                recoverySuggestion: "Tippe auf Erneut laden. Wenn der Hinweis bleibt, öffne Sync & Wartung und prüfe den Speicherstatus.",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        case .perGraph:
            return GraphStatsUserFacingErrorMessage(
                title: "Graph-Zahlen konnten nicht geladen werden",
                message: "BrainMesh konnte die Zahlen pro Graph gerade nicht vollständig aus dem lokalen Datenspeicher lesen.",
                recoverySuggestion: "Tippe auf Erneut laden oder schließe den Bereich kurz und öffne ihn erneut.",
                systemImage: "externaldrive.badge.exclamationmark"
            )
        }
    }

    private static func genericMessage(context: Context) -> GraphStatsUserFacingErrorMessage {
        switch context {
        case .dashboard:
            return GraphStatsUserFacingErrorMessage(
                title: "Statistiken konnten nicht geladen werden",
                message: "Beim Berechnen der Statistik ist etwas Unerwartetes passiert. Deine Daten bleiben erhalten.",
                recoverySuggestion: "Tippe auf Erneut laden oder ziehe die Ansicht nach unten, um die Statistik erneut zu berechnen.",
                systemImage: "exclamationmark.triangle"
            )
        case .perGraph:
            return GraphStatsUserFacingErrorMessage(
                title: "Graph-Zahlen konnten nicht geladen werden",
                message: "Die Detailzahlen pro Graph konnten gerade nicht berechnet werden. Das Dashboard bleibt weiter nutzbar.",
                recoverySuggestion: "Tippe auf Erneut laden und versuche es erneut.",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}
