//
//  GraphTransferViewModel+Alerts.swift
//  BrainMesh
//

import Foundation

extension GraphTransferViewModel {

    func userFacingMessage(for error: Error) -> String {
        #if DEBUG
        print("⚠️ GraphTransfer error: \(error)")
        #endif

        if let error = error as? GraphTransferError {
            switch error {
            case .fileAccessDenied:
                return "Kein Zugriff auf die ausgewählte Datei. Bitte wähle eine Datei aus der Dateien-App oder teile sie erneut in BrainMesh."
            case .invalidFormat:
                return "Diese Datei ist keine BrainMesh-Exportdatei."
            case .unsupportedVersion:
                return "Diese Exportdatei wurde mit einer neueren Version erstellt und kann aktuell nicht importiert werden."
            case .decodeFailed:
                return "Die Exportdatei ist beschädigt oder kann nicht gelesen werden."
            case .readFailed:
                return "Die Datei konnte nicht gelesen werden."
            case .saveFailed:
                return "Beim Speichern der importierten Daten ist ein Fehler aufgetreten."
            case .writeFailed:
                return "Die Exportdatei konnte nicht geschrieben werden."
            case .graphNotFound:
                return "Der gewählte Graph wurde nicht gefunden."
            case .notConfigured:
                return "Export/Import ist noch nicht bereit. Bitte starte die App neu und versuche es erneut."
            case .notImplemented:
                return "Diese Funktion ist noch nicht verfügbar."
            }
        }

        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, (ns.code == 257 || ns.code == 513) {
            return "Kein Zugriff auf die ausgewählte Datei."
        }

        return "Es ist ein unerwarteter Fehler aufgetreten."
    }
}
