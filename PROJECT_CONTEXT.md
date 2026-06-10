# PROJECT_CONTEXT.md

## TL;DR

BrainMesh ist eine iOS- und iPadOS-App zum Modellieren und Erkunden von Wissens- bzw. Metadaten-Graphen. Die Kernobjekte sind Graphen, Entitäten, Attribute, Links, frei definierbare Detailfelder und Medien/Anhänge. Persistenz läuft über SwiftData; in regulärem Betrieb ist CloudKit-Sync für die private iCloud-Datenbank aktiviert, mit lokalem Fallback in Release-Builds bei Container-Problemen. Mindest-Deployment-Target ist **iOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj`).

## Key Concepts / Domänenbegriffe

- **Graph**  
  Benutzer-sichtbarer Workspace. Ein Graph kapselt Entitäten, Attribute, Links, Templates und Attachments logisch über `graphID`, nicht über vollständige SwiftData-Relationships (`BrainMesh/Models/MetaGraph.swift`).

- **Entity**  
  Primärer Knoten im Modell, z. B. ein Objekt, System, Datensatz oder Konzept (`BrainMesh/Models/MetaEntity.swift`).

- **Attribute**  
  Sekundärer Knoten, der einer Entity gehört und zusätzliche Merkmale oder Ausprägungen beschreibt (`BrainMesh/Models/MetaAttribute.swift`).

- **Link**  
  Gerichtete Verbindung zwischen zwei Knoten. Links können Entity→Entity, Entity→Attribute, Attribute→Entity oder Attribute→Attribute repräsentieren, technisch über `(sourceKindRaw, sourceID, targetKindRaw, targetID)` (`BrainMesh/Models/MetaLink.swift`).

- **Detail Field Definition**  
  Frei definierbares Schema pro Entity-Typ, das festlegt, welche strukturierten Felder Attribute dieser Entity besitzen dürfen (`BrainMesh/Models/DetailsModels.swift`).

- **Detail Field Value**  
  Typisierter Wert eines Detailfelds für ein konkretes Attribut (`BrainMesh/Models/DetailsModels.swift`).

- **Details Template**  
  Wiederverwendbares Set von Detailfeld-Definitionen, als JSON gespeichert (`BrainMesh/Models/MetaDetailsTemplate.swift`).

- **Attachment**  
  Datei-, Video- oder Galerie-Bild-Anhang, owner-basiert über `(ownerKindRaw, ownerID)` statt Relationship-Makros (`BrainMesh/Attachments/MetaAttachment.swift`).

- **Active Graph**  
  Aktuell ausgewählter Graph. Wird per `@AppStorage(BMAppStorageKeys.activeGraphID)` gehalten und von fast allen Features als Scope benutzt (`BrainMesh/Support/BMAppStorageKeys.swift`).

- **Graph Lock**  
  Zugriffsschutz pro Graph mit Biometrie und/oder Passwort (`BrainMesh/Models/MetaGraph.swift`, `BrainMesh/Security/GraphLock/*`, `BrainMesh/Security/GraphUnlock/*`).

- **Loader / Snapshot**  
  Schwerere SwiftData-Abfragen laufen bevorzugt off-main in Actor-Loadern und liefern Value-Snapshots/DTOs an die UI zurück (`BrainMesh/Support/AppLoadersConfigurator.swift`, z. B. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`).

- **Hydrator**  
  Repariert/erzeugt lokale Cache-Dateien für Bilder und Attachments, ohne die UI zu blockieren (`BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`).

## Architecture Map

### Layer / Module Map

- **App Shell**
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/AppRoot/*`
  - `BrainMesh/ContentView.swift`
  - Aufgabe: App-Start, `ModelContainer`, globale `EnvironmentObject`s, Tab-Shell, Lock-/Onboarding-/Startup-Orchestrierung.

- **Persistence + Sync**
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/Settings/SyncRuntime.swift`
  - `BrainMesh/Bootstrap/*`
  - Aufgabe: SwiftData-Schema, CloudKit-Konfiguration, Legacy-Backfills, Storage-Mode, iCloud-Status.

- **Domain Models**
  - `BrainMesh/Models/*`
  - `BrainMesh/Attachments/MetaAttachment.swift`
  - Aufgabe: Persistente Modelle, Such-Indizes, graph-scope Felder, typed values, optionale Sicherheitsfelder.

- **Feature UI**
  - `BrainMesh/Mainscreen/*`
  - `BrainMesh/GraphCanvas/*`
  - `BrainMesh/Stats/*`
  - `BrainMesh/Settings/*`
  - `BrainMesh/GraphPicker/*`
  - `BrainMesh/GraphTransfer/*`
  - Aufgabe: Listen, Detail-Screens, Canvas, Stats, Graph-Verwaltung, Import/Export, Einstellungen.

- **Feature Services / Loaders**
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
  - `BrainMesh/Stats/GraphStatsService/*`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader*`
  - Aufgabe: Off-main Abfragen, Snapshot-Bildung, Cache-/Throttle-Strategien.

- **Local Cache / Media Infra**
  - `BrainMesh/ImageStore.swift`
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/*`
  - `BrainMesh/PhotoGallery/*`
  - Aufgabe: Application-Support-Dateien, Dedupe, Preview, Kompression, Video-/Bild-Import.

- **Security / Pro / Onboarding**
  - `BrainMesh/Security/*`
  - `BrainMesh/Pro/*`
  - `BrainMesh/Onboarding/*`
  - Aufgabe: Locking, Paywall/StoreKit, Erstnutzungshilfe.

### Abhängigkeitsrichtung

- SwiftUI-Views lesen meist nur UI-State und stoßen Loader/Services an.
- Off-main Loader erzeugen eigene `ModelContext`-Instanzen aus `AnyModelContainer` (`BrainMesh/Support/AnyModelContainer.swift`).
- Zwischen Concurrency-Grenzen sollen **keine** SwiftData-`@Model`-Instanzen transportiert werden; stattdessen DTOs/Snapshots (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeDTO.swift`, `BrainMesh/Mainscreen/BulkLink/BulkLinkSnapshot.swift`).
- Lokale Medien-Caches sind sekundär; Source of Truth bleibt SwiftData (`imageData`, `fileData`).

## Folder Map

- `BrainMesh/AppRoot`  
  Startup, Scene-Phase-Handling, Lock-/Onboarding-Präsentation.

- `BrainMesh/Attachments`  
  Attachment-Modell, Cache, Import, Hydration, Cleanup, Preview.

- `BrainMesh/Bootstrap`  
  Graph-Bootstrap, Legacy-Migrationen, Backfills.

- `BrainMesh/GraphCanvas`  
  Canvas-Typen, Loader, Screen-Orchestrierung, Rendering, Focus-Logik.

- `BrainMesh/GraphPicker`  
  Graph-Umschaltung, Graph-Verwaltung, Security Sheet, Deletion, Dedupe.

- `BrainMesh/GraphTransfer`  
  `.bmgraph` Import/Export, DTOs, Validierung, View.

- `BrainMesh/Icons`  
  SF-Symbol-Picker und Hilfslogik.

- `BrainMesh/ImportProgress`  
  Wiederverwendbarer Fortschrittszustand und Progress-Card.

- `BrainMesh/Mainscreen`  
  Entitäten-Home, Entity-/Attribute-Details, Bulk-Link, Detail-Editoren, Shared Sections.

- `BrainMesh/Models`  
  SwiftData-Modelle und Such-Hilfen.

- `BrainMesh/Observability`  
  Mikro-Logging und Timing-Helfer.

- `BrainMesh/Onboarding`  
  Onboarding-Flows und Progress-Berechnung.

- `BrainMesh/PhotoGallery`  
  Galerie-Viewer und gallery-bezogene UI.

- `BrainMesh/Pro`  
  Pro-Features, Paywall, Entitlement-Store.

- `BrainMesh/Security`  
  Graph-Lock, Unlock-Flow, Passwort/Biometrie.

- `BrainMesh/Settings`  
  Settings-Hub, Display, Appearance, Sync/Wartung, Hilfe.

- `BrainMesh/Stats`  
  Stats-Dashboard, Service-Schicht, Loader, Komponenten.

- `BrainMesh/Support`  
  `AppStorage`-Keys, Container-Wrapper, allgemeine Hilfstypen.

## Data Model Map

### Persistente Hauptmodelle

- `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`)
  - Wichtige Felder: `id`, `createdAt`, `name`, `nameFolded`
  - Sicherheit: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
  - Beziehungsmuster: Keine großen Child-Relationships; Scoping läuft überwiegend über `graphID` auf den Child-Modellen.

- `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`)
  - Wichtige Felder: `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `notes`, `notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
  - Relationships:
    - `attributes` → `MetaAttribute` (cascade)
    - `detailFields` → `MetaDetailFieldDefinition` (cascade)

- `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`)
  - Wichtige Felder: `id`, `graphID`, `name`, `nameFolded`, `notes`, `notesFolded`, `iconSymbolName`, `imageData`, `imagePath`, `searchLabelFolded`
  - Relationships:
    - `owner` → `MetaEntity`
    - `detailValues` → `MetaDetailFieldValue` (cascade)

- `MetaLink` (`BrainMesh/Models/MetaLink.swift`)
  - Wichtige Felder: `id`, `createdAt`, `graphID`, `note`, `noteFolded`, `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`, `sourceLabel`, `targetLabel`
  - Besonderheit: Keine Model-Relationships; reine scalar endpoints.

- `MetaDetailFieldDefinition` (`BrainMesh/Models/DetailsModels.swift`)
  - Wichtige Felder: `id`, `graphID`, `entityID`, `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Beziehung: `owner` → `MetaEntity` (nullify)

- `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`)
  - Wichtige Felder: `id`, `graphID`, `attributeID`, `fieldID`, `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - Beziehung: `attribute` → `MetaAttribute`

- `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`)
  - Wichtige Felder: `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `fieldsJSON`

- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - Wichtige Felder: `id`, `createdAt`, `graphID`, `ownerKindRaw`, `ownerID`, `contentKindRaw`, `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`, `fileData`, `localPath`
  - Storage: `fileData` als `@Attribute(.externalStorage)`

### Such- und Denormalisierungsfelder

- `nameFolded`, `notesFolded`, `noteFolded`, `searchLabelFolded` werden aktiv mitgeführt, um case-/diacritic-insensitive Suchen zu vereinfachen (`BrainMesh/Models/BMSearch.swift`).
- Link-Endpunkt-Labels sind denormalisiert in `MetaLink.sourceLabel` / `MetaLink.targetLabel`. Renames benötigen daher Relabeling-Service (`BrainMesh/Support/AppLoadersConfigurator.swift` konfiguriert `NodeRenameService`).

## Sync / Storage

### Persistenz

- SwiftData-Modellcontainer wird in `BrainMesh/BrainMeshApp.swift` erstellt.
- Schema enthält:
  - `MetaGraph`
  - `MetaEntity`
  - `MetaAttribute`
  - `MetaLink`
  - `MetaAttachment`
  - `MetaDetailFieldDefinition`
  - `MetaDetailFieldValue`
  - `MetaDetailsTemplate`

### CloudKit

- CloudKit ist per `ModelConfiguration(schema: cloudKitDatabase: .automatic)` aktiviert (`BrainMesh/BrainMeshApp.swift`).
- Container-ID: `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/Settings/SyncRuntime.swift`, `BrainMesh/BrainMesh.entitlements`).
- In Debug wird ein Container-Fehler absichtlich per `fatalError` hart sichtbar gemacht.
- In Release fällt die App auf lokalen SwiftData-Betrieb zurück (`BrainMesh/BrainMeshApp.swift`).

### Legacy / Backfills

- Default-Graph-Anlage und Legacy-Migration: `BrainMesh/Bootstrap/GraphBootstrap.swift`
- Legacy-Records mit `graphID == nil` werden beim Bootstrap in den Default-Graph geschoben.
- Gespeicherte Such-Indizes für Notizen werden nachträglich aufgefüllt.
- Attachment-spezifische `graphID`-Migration existiert separat, um teure OR-Predicates auf externen Blobs zu vermeiden (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).

### Lokale Caches

- Bilder: deterministische JPEG-Dateien im App-Support, verwaltet über `ImageStore` / `ImageHydrator` (`BrainMesh/ImageHydrator.swift`).
- Attachments: deterministische Cache-Dateien im App-Support, verwaltet über `AttachmentStore` / `AttachmentHydrator` (`BrainMesh/Attachments/*`).
- Diese Caches sind reparierbar und nicht die primäre Datenquelle.

### Export / Import

- Exportformat ist `.bmgraph` mit eigener UTI `de.marcfechner.brainmesh.graph` (`BrainMesh/Info.plist`).
- Export enthält Graph, Entities, Attributes, Detail-Schema, Detail-Werte und Links (`BrainMesh/GraphTransfer/GraphExportFileV1.swift`, `BrainMesh/GraphTransfer/GraphTransferDTOs.swift`).
- **Wichtig:** Attachments werden im aktuellen Transferformat **nicht** exportiert/importiert. Bilder in `imageData` von Entities/Attributes können optional enthalten sein, aber `MetaAttachment` nicht.

### Offline-Verhalten

- Lokal benutzbar, solange ein `ModelContainer` erstellt werden kann.
- Release-Build kann komplett lokal weiterlaufen, falls CloudKit nicht verfügbar ist.
- **UNKNOWN:** Es wurde keine explizite Konfliktauflösung oder Merge-Policy für konkurrierende Multi-Device-Edits gefunden.

## UI Map

### Root Entry

- `BrainMesh/BrainMeshApp.swift` ist `@main`.
- `BrainMesh/AppRoot/AppRootView.swift` setzt:
  - Startup
  - Scene-Phase-Reaktion
  - Lock-Fullscreen-Cover
  - Onboarding-Sheet

### Root Tabs (`BrainMesh/ContentView.swift`)

- **Entitäten**
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - NavigationStack mit Suche, Sortierung, Add-Entity, Graph-Picker, Layout-Sheet.

- **Graph**
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - Canvas, Fokus, Inspector, Jump-to-node, Detail-Sheets, Details-Fokus.

- **Stats**
  - `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - Dashboard + per-Graph Kennzahlen.

- **Einstellungen**
  - `BrainMesh/Settings/SettingsView.swift`
  - Hub für Pro, Anzeige, Transfer, Import, Sync/Wartung, Hilfe.

### Wichtige Flows / Sheets

- Graph wechseln / verwalten: `BrainMesh/GraphPicker/GraphPickerSheet.swift`
- Entity-Detail: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Attribute-Detail: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Graph-Import/Export: `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferView.swift`
- Onboarding: `BrainMesh/Onboarding/OnboardingSheetView.swift`
- Graph-Unlock: `BrainMesh/Security/GraphUnlock/GraphUnlockView.swift`
- Pro: `BrainMesh/Pro/ProCenterView.swift`, `BrainMesh/Pro/ProPaywallView.swift`

## Build & Configuration

- Xcode-Projekt: `BrainMesh.xcodeproj/project.pbxproj`
- Targets:
  - `BrainMesh`
  - `BrainMeshTests`
  - `BrainMeshUITests`
- Deployment Target:
  - App: `iOS 26.0`
  - Tests/UI-Tests: ebenfalls `iOS 26.0`
- Device Family: `"1,2"` = iPhone + iPad
- App-Version:
  - `MARKETING_VERSION = 1.06`
  - `CURRENT_PROJECT_VERSION = 1`
- Info/Entitlements:
  - `BrainMesh/Info.plist`
  - `BrainMesh/BrainMesh.entitlements`
- StoreKit:
  - `BrainMesh/BrainMesh Pro.storekit`
  - Produkt-IDs zusätzlich in `Info.plist`
- SPM:
  - Keine `packageProductDependencies` im Projektfile
  - Keine `Package.swift` gefunden
- `.xcconfig`:
  - **UNKNOWN** Keine `.xcconfig`-Dateien gefunden
- Secrets-Handling:
  - Keine separate Secrets-Schicht gefunden
  - Produkt-IDs liegen in `Info.plist`
  - CloudKit-Container liegt in Entitlements

## Conventions

- Multi-Graph-Scoping läuft meist über `graphID`-Felder, nicht über tiefe Parent-Child-Graph-Relationships.
- Suchfelder sind vor-normalisiert und sollen bei neuen Features mitgepflegt werden.
- Schwerere SwiftData-Arbeit soll in Actor-Loadern/Services passieren, nicht im SwiftUI-Renderpfad.
- Keine `@Model`-Objekte über Concurrency-Grenzen transportieren.
- Große Views/Services werden oft in Host + Extensions/Subfiles geschnitten.
- `@AppStorage`-Keys sind zentralisiert in `BrainMesh/Support/BMAppStorageKeys.swift`.
- Cache-Dateien sollen über Store/Hydrator-Schichten laufen, nicht ad hoc aus Views geschrieben werden.
- Queries müssen Legacy-Fälle `graphID == nil` bewusst behandeln, nicht zufällig.

## How to work on this project

### Setup Steps

1. Projekt in Xcode über `BrainMesh.xcodeproj` öffnen.
2. Signing/Entitlements für CloudKit/iCloud prüfen.
3. In Debug beachten: CloudKit läuft gegen Development-Umgebung, Release/TestFlight gegen Production-Haltung der App-Distribution (`BrainMesh/Settings/SettingsView+SyncSection.swift`).
4. App starten und prüfen, ob `SyncRuntime` in Settings sinnvolle Werte liefert.
5. Für Medien-/Cache-Themen auch den Wartungsbereich in Settings prüfen.

### Wo anfangen

- App-Start / Shell: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRoot/*`
- Datenmodell: `BrainMesh/Models/*`, `BrainMesh/Attachments/MetaAttachment.swift`
- Home-Liste: `BrainMesh/Mainscreen/EntitiesHome/*`
- Canvas: `BrainMesh/GraphCanvas/*`
- Stats: `BrainMesh/Stats/*`
- Sync/Wartung: `BrainMesh/Settings/SyncRuntime.swift`, `BrainMesh/Settings/SyncMaintenanceView.swift`

### Typischer Workflow für neue Features

- Datenmodell und `graphID`-Scope klären.
- Falls Query/Compute spürbar schwer wird: neuen Loader/Service mit Snapshot-DTO anlegen.
- UI-Host klein halten, Sheets/Sections/Flows auslagern.
- Suchfelder, Relabeling und Cache-/Hydrator-Folgen bedenken.
- Tests in `BrainMeshTests` ergänzen, vor allem für Loader, Derived State und Roundtrips.

## Quick Wins

- [ ] `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` in Phasen-Dateien schneiden, damit Importlogik review- und testbarer wird.
- [ ] `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift` so umbauen, dass Attachment-Bytes nicht mehr über Vollfetch aller `MetaAttachment` berechnet werden.
- [ ] `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift` um revision-/parameterbasierten Snapshot-Cache ergänzen.
- [ ] `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift` Suchpfade besser separieren und Ergebnis-Caching pro `(graphID, foldedSearch)` prüfen.
- [ ] `BrainMesh/Settings/BrainMeshGuideView.swift` in mehrere Sektionen/Subviews aufteilen.
- [ ] `BrainMesh/GraphCanvas/GraphDetailsFocus.swift` in Compare, PreparedState, RenderPlan, UI-Helfer trennen.
- [ ] Import/Export-Dokumentation im UI klarer machen: `.bmgraph` enthält keine `MetaAttachment`.
- [ ] Beobachtbarkeit um Stats-/Import-Dauer und Cache-Hits erweitern.
- [ ] Einheitliche Revision-/Invalidierungsstrategie für Loader prüfen statt Mischung aus TTL, manueller Invalidierung und “forceReload”.
- [ ] `Open Questions` unten auflösen, bevor größere Datenmodell- oder Sync-Refactors starten.

## Open Questions

- **UNKNOWN:** Kein expliziter `SchemaMigrationPlan` oder `VersionedSchema` gefunden.
- **UNKNOWN:** Keine explizite Merge-/Konfliktstrategie für konkurrierende CloudKit-Edits gefunden.
- **UNKNOWN:** `UIBackgroundModes = remote-notification` ist gesetzt, aber eine klare Push-/Subscription-Verarbeitung wurde beim Scan nicht gefunden.
- **UNKNOWN:** Ob Entity-/Attribute-Lock-Felder produktiv in der UI genutzt werden oder primär Graph-Lock relevant ist, ist beim Scan nicht eindeutig.
