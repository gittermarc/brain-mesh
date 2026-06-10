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
                return "BrainMesh hat keinen Zugriff auf die ausgewählte Datei. Wähle sie direkt aus der Dateien-App oder teile sie erneut in BrainMesh."
            case .invalidFormat:
                return "Diese Datei ist keine gültige BrainMesh-.bmgraph-Datei. Wähle bitte einen Struktur-Export aus BrainMesh."
            case .unsupportedVersion:
                return "Diese .bmgraph-Datei wurde mit einer neueren BrainMesh-Version erstellt. Aktualisiere BrainMesh und versuche es danach erneut."
            case .decodeFailed:
                return "Die .bmgraph-Datei konnte nicht gelesen werden. Sie ist möglicherweise unvollständig oder beschädigt."
            case .readFailed:
                return "Die Datei konnte nicht gelesen werden. Prüfe, ob sie noch vorhanden ist und BrainMesh Zugriff darauf hat."
            case .saveFailed:
                return "Der Import konnte nicht gespeichert werden. Prüfe deinen freien Speicherplatz und versuche es erneut."
            case .writeFailed:
                return "Die Exportdatei konnte nicht erstellt werden. Prüfe deinen freien Speicherplatz und versuche es erneut."
            case .backupPackageWriteFailed:
                return "Das Full-Backup-Paket konnte nicht erstellt werden. Prüfe deinen freien Speicherplatz und versuche es erneut."
            case .backupAttachmentReadFailed:
                return "Ein Anhang konnte nicht für das Full Backup gelesen werden. Prüfe, ob die Daten vollständig synchronisiert sind, und versuche es erneut."
            case .backupAttachmentWriteFailed:
                return "Ein Anhang konnte nicht in das Full Backup geschrieben werden. Prüfe deinen freien Speicherplatz und versuche es erneut."
            case .backupManifestWriteFailed:
                return "Das Full-Backup-Manifest konnte nicht geschrieben werden. Prüfe deinen freien Speicherplatz und versuche es erneut."
            case .backupManifestReadFailed:
                return "Das Full-Backup-Manifest konnte nicht gelesen werden. Wähle ein vollständiges .bmbackup-Paket aus BrainMesh."
            case .backupCoreGraphMissing:
                return "Im Full Backup fehlt die Graph-Struktur. Dieses Paket kann so nicht importiert werden."
            case .backupCoreGraphInvalid:
                return "Die Graph-Struktur im Full Backup konnte nicht geprüft werden. Das Paket ist möglicherweise beschädigt."
            case .backupCoreGraphMismatch:
                return "Manifest und Graph-Struktur im Full Backup passen nicht zusammen. Exportiere das Backup erneut oder wähle eine andere Datei."
            case .backupAttachmentMissing:
                return "Ein Anhang fehlt im Full Backup. Die übrigen Daten können weiter importiert werden."
            case .backupAttachmentSizeMismatch:
                return "Ein Anhang im Full Backup hat eine unerwartete Dateigröße und wurde übersprungen."
            case .backupAttachmentChecksumMismatch:
                return "Ein Anhang im Full Backup wirkt beschädigt und wurde übersprungen."
            case .invalidBackupFormat:
                return "Diese Datei ist kein gültiges BrainMesh-Full-Backup. Wähle bitte ein .bmbackup-Paket aus BrainMesh."
            case .unsupportedBackupVersion:
                return "Dieses Full Backup wurde mit einer neueren BrainMesh-Version erstellt. Aktualisiere BrainMesh und versuche es danach erneut."
            case .fullBackupImportNotAvailable:
                return "Full-Backup-Import ist für diese Datei nicht möglich. Prüfe die Hinweise und wähle bei Bedarf eine andere Datei."
            case .graphNotFound:
                return "Der gewählte Graph wurde nicht gefunden. Wähle einen vorhandenen Graph aus und starte den Export erneut."
            case .notConfigured:
                return "Export & Import ist noch nicht bereit. Starte BrainMesh neu und versuche es danach erneut."
            case .notImplemented:
                return "Diese Transfer-Funktion ist in dieser Version nicht verfügbar."
            }
        }

        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, (ns.code == 257 || ns.code == 513) {
            return "BrainMesh hat keinen Zugriff auf die ausgewählte Datei. Wähle sie direkt aus der Dateien-App oder teile sie erneut in BrainMesh."
        }

        return "Es ist ein unerwarteter Fehler aufgetreten. Bitte versuche es erneut."
    }
}
