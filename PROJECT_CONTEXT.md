# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine iOS-App zum Aufbau, Durchsuchen, Visualisieren und Transferieren mehrerer wissensartiger Graphen aus Entitäten, Attributen, Links, Detailfeldern und Anhängen. Die App ist rein SwiftUI-basiert, nutzt SwiftData als Primärspeicher und aktiviert CloudKit-Sync für die Private Database, fällt in Release-Builds bei Container-Problemen aber auf lokalen Speicher zurück (`BrainMesh/BrainMeshApp.swift`, `BrainMesh/Settings/SyncRuntime.swift`). Laut Projektdatei liegt das Deployment Target bei **iOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj`).

## Key Concepts / Domänenbegriffe
- **Graph**: logischer Datenraum mit eigenem Namen und optionalem Schutz per Biometrics/Passwort (`BrainMesh/Models/MetaGraph.swift`).
- **Entity**: primärer Knoten im Graphen, mit Name, Notizen, Icon/Bild und eigenen Detailfeld-Definitionen (`BrainMesh/Models/MetaEntity.swift`).
- **Attribute**: sekundärer Knoten, der einer Entity gehört und ebenfalls Notizen, Bild und Detailwerte tragen kann (`BrainMesh/Models/MetaAttribute.swift`).
- **Link**: gerichtete Verbindung zwischen zwei Knoten, gespeichert über Typ + UUID der Endpunkte, plus optionale Notiz (`BrainMesh/Models/MetaLink.swift`).
- **Detail Field Definition**: Schema-artige Felddefinition an einer Entity, z. B. Zahl, Datum, Bool, Text (`BrainMesh/Models/DetailsModels.swift`).
- **Detail Field Value**: konkreter Wert eines Detailfelds an einem Attribut (`BrainMesh/Models/DetailsModels.swift`).
- **Details Template**: vorgefertigte Feldsammlung für Entity-Details (`BrainMesh/Models/MetaDetailsTemplate.swift`).
- **Attachment**: Datei, Video oder Galerie-Bild, graph- und owner-scoped, mit optionalem lokalem Cachepfad und extern gespeichertem Blob (`BrainMesh/Attachments/MetaAttachment.swift`).
- **Active Graph**: aktuell ausgewählter Graph, global über `@AppStorage(BMAppStorageKeys.activeGraphID)` gesteuert (`BrainMesh/Support/BMAppStorageKeys.swift`).

## Architecture Map
### Layer / Module Map
1. **App Shell / Composition Root**
   - `BrainMesh/BrainMeshApp.swift`
   - `BrainMesh/AppRootView.swift`
   - Aufgabe: SwiftData-Container erzeugen, EnvironmentObjects injecten, Startup-Migrationen ausführen, globalen Lock/Onboarding/Theme-Zustand halten.

2. **Persistence / Domain Models**
   - `BrainMesh/Models/*.swift`
   - `BrainMesh/Attachments/MetaAttachment.swift`
   - Aufgabe: SwiftData-Modelle, Suchindizes (`*Folded`), Feldtypen, graph-scoped Identität.

3. **Background Loaders / Services**
   - `BrainMesh/Support/AppLoadersConfigurator.swift`
   - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`
   - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
   - `BrainMesh/Stats/GraphStatsLoader.swift`
   - `BrainMesh/GraphTransfer/GraphTransferService/*`
   - `BrainMesh/Attachments/*Hydrator*`, `BrainMesh/ImageHydrator.swift`
   - Aufgabe: Off-main Fetches, Snapshot-Building, Cache-Hydration, Import/Export, große Mutationen.

4. **UI Screens / Feature Hosts**
   - `BrainMesh/ContentView.swift`
   - `BrainMesh/Mainscreen/*`
   - `BrainMesh/GraphCanvas/*`
   - `BrainMesh/Stats/*`
   - `BrainMesh/Settings/*`
   - Aufgabe: Screen-Level State, Navigation, Sheet-Orchestrierung, Darstellung von DTOs/Snapshots.

5. **Cross-Cutting Stores / Coordinators**
   - `BrainMesh/Settings/Appearance/AppearanceStore.swift`
   - `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
   - `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`
   - `BrainMesh/GraphJumpCoordinator.swift`
   - `BrainMesh/RootTabRouter.swift`
   - `BrainMesh/Settings/SyncRuntime.swift`
   - Aufgabe: globaler UI-/Session-/Lock-/Sync-Zustand.

### Abhängigkeitsrichtung
- SwiftUI Screens hängen an Stores/Coordinators und an Loadern/Services.
- Loader/Services hängen an `AnyModelContainer` / `ModelContext`, nicht an SwiftUI Views.
- Persistenzmodelle hängen nicht an UI.
- Datei-/Bild-Caches hängen an stabilen IDs/Pfaden aus SwiftData, nicht umgekehrt.

## Folder Map
- `BrainMesh/Attachments`: Attachment-Model, Import, Store, Thumbnailing, Cleanup, Hydration.
- `BrainMesh/GraphCanvas`: Graph-Visualisierung, Datenloader, Physics-/Canvas-Rendering.
- `BrainMesh/GraphPicker`: Graph-Auswahl, Rename/Delete/Dedupe, aktive Graph-Verwaltung.
- `BrainMesh/GraphTransfer`: `.bmgraph` Export/Import, Preview, UI-Flow, Limits.
- `BrainMesh/Icons`: SF-Symbol-Picker und Icon-Hilfen.
- `BrainMesh/Images`: Bildimport-Pipeline.
- `BrainMesh/ImportProgress`: Fortschritts-UI für Imports.
- `BrainMesh/Mainscreen`: Entity-/Attribute-Detail, Home-Liste, Node-Create, Bulk-Link, gemeinsame Node-Detail-Komponenten.
- `BrainMesh/Models`: SwiftData-Domainmodelle, Detailfeld-Modelle, Suchhelfer.
- `BrainMesh/Observability`: leichtgewichtiges Logging/Timing (`BMLog`, `BMDuration`).
- `BrainMesh/Onboarding`: Onboarding-UI und Koordinator.
- `BrainMesh/PhotoGallery`: Galerie-Browser/Viewer/Sections.
- `BrainMesh/Pro`: StoreKit/Entitlements, Paywall, Limits.
- `BrainMesh/Security`: Graph-Lock, Unlock-Screens, Kryptohilfen.
- `BrainMesh/Settings`: Settings-Hub, Display/Appearance, Import, Sync/Wartung, Hilfeseiten.
- `BrainMesh/Stats`: Dashboard, Service, Snapshots, Breakdown-Komponenten.
- `BrainMesh/Support`: AppStorage-Keys, Loader-Konfiguration, Hilfsbausteine.

## Data Model Map
### MetaGraph
Pfad: `BrainMesh/Models/MetaGraph.swift`
- Wichtige Felder:
  - `id: UUID`
  - `createdAt: Date`
  - `name`, `nameFolded`
  - `lockBiometricsEnabled`, `lockPasswordEnabled`
  - `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Rolle:
  - Benutzer-sichtbarer Container für alle graph-scoped Daten.
  - Träger des Lock-/Unlock-Zustands.

### MetaEntity
Pfad: `BrainMesh/Models/MetaEntity.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `name`, `nameFolded`
  - `notes`, `notesFolded`
  - `iconSymbolName`
  - `imageData`, `imagePath`
- Beziehungen:
  - `attributes` (Cascade, inverse `MetaAttribute.owner`)
  - `detailFields` (Cascade, inverse `MetaDetailFieldDefinition.owner`)
- Hinweise:
  - `graphID` ist zentral für Scoping und Migration.
  - Enthält zusätzlich Lock-Felder analog zu `MetaGraph`; aktuelle produktive Nutzung dafür ist **UNKNOWN**.

### MetaAttribute
Pfad: `BrainMesh/Models/MetaAttribute.swift`
- Wichtige Felder:
  - `id`, `graphID`
  - `name`, `nameFolded`
  - `notes`, `notesFolded`
  - `searchLabelFolded`
  - `iconSymbolName`, `imageData`, `imagePath`
- Beziehungen:
  - `owner: MetaEntity?`
  - `detailValues` (Cascade, inverse `MetaDetailFieldValue.attribute`)
- Hinweise:
  - Suchpfad für Home-Suche läuft über `searchLabelFolded`.

### MetaLink
Pfad: `BrainMesh/Models/MetaLink.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `note`, `noteFolded`
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`
- Modellierung:
  - Keine SwiftData-Relationship auf Entity/Attribute.
  - Endpunkte werden über Typ + UUID + denormalisierte Labels gespeichert.

### MetaAttachment
Pfad: `BrainMesh/Attachments/MetaAttachment.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `ownerKindRaw`, `ownerID`
  - `contentKindRaw`
  - `title`, `originalFilename`, `contentType`, `fileExtension`, `byteCount`
  - `fileData` mit `@Attribute(.externalStorage)`
  - `localPath`
- Modellierung:
  - Owner ebenfalls nur über Typ + UUID.
  - Graph-Scoping ist für performante Predicates kritisch.

### Detail Field Definition / Value
Pfad: `BrainMesh/Models/DetailsModels.swift`
- `MetaDetailFieldDefinition`
  - `graphID`, `entityID`, `name`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Relationship: `owner`
- `MetaDetailFieldValue`
  - `graphID`, `attributeID`, `fieldID`
  - Wertspalten: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - Relationship: `attribute`
- Bedeutung:
  - Entity definiert Schema, Attribute halten konkrete Werte.

### MetaDetailsTemplate
Pfad: `BrainMesh/Models/MetaDetailsTemplate.swift`
- Felder: `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `fieldsJSON`
- Nutzung: vorgefertigte Feldsets; genaue produktive Flows dafür sind nur teilweise sichtbar.

## Sync / Storage
### Primärspeicher
- SwiftData `ModelContainer` mit Schema aus:
  - `MetaGraph`
  - `MetaEntity`
  - `MetaAttribute`
  - `MetaLink`
  - `MetaAttachment`
  - `MetaDetailFieldDefinition`
  - `MetaDetailFieldValue`
  - `MetaDetailsTemplate`
- Quelle: `BrainMesh/BrainMeshApp.swift`.

### CloudKit
- Konfiguration: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - `iCloud.de.marcfechner.BrainMesh`
  - `aps-environment = development`
- Runtime-Sichtbarkeit des Modus: `BrainMesh/Settings/SyncRuntime.swift`.

### Release-Fallback
- DEBUG: Crash bei Container-Init-Fehler.
- Release: Fallback auf lokalen SwiftData-Store ohne CloudKit (`BrainMesh/BrainMeshApp.swift`).
- Folge:
  - App bleibt benutzbar.
  - Sync ist dann explizit aus.

### Startup-Migration / Backfill
- `BrainMesh/GraphBootstrap.swift`
  - stellt sicher, dass mindestens ein Graph existiert
  - migriert Legacy-Datensätze ohne `graphID`
  - backfillt `notesFolded` / `noteFolded`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - migriert Legacy-Attachments mit `graphID == nil`
  - vermeidet OR-Predicates, die sonst in-memory Filtering auf Blob-lastigen Daten triggern könnten

### Lokale Caches
- Bilder:
  - `BrainMesh/ImageStore.swift`
  - `BrainMesh/ImageHydrator.swift`
- Attachments:
  - `BrainMesh/Attachments/AttachmentStore.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Muster:
  - stabile Dateinamen aus IDs
  - lokale Cache-Dateien in Application Support
  - deduplizierte In-Flight-Loads

### Offline-Verhalten
- Belegbar:
  - Lokaler SwiftData-Store existiert unabhängig von CloudKit.
  - Release-Fallback auf local-only ist implementiert.
  - Datei-/Bild-Caches sind lokal.
- Daraus ableitbar:
  - Lesen/Schreiben ist lokal möglich, Sync ist opportunistisch.
- Konfliktlösung jenseits von SwiftData/CloudKit-Standardverhalten ist **UNKNOWN**.

### Migration / Versionierung
- Expliziter `SchemaMigrationPlan` wurde im gescannten Projekt **nicht gefunden**.
- Vorhanden sind ad-hoc Migrations-/Backfill-Pfade im App-Code.

## UI Map
### Root Tabs
Pfad: `BrainMesh/ContentView.swift`
- `EntitiesHomeView` → Tab „Entitäten“
- `GraphCanvasScreen` → Tab „Graph“
- `GraphStatsView` → Tab „Stats“
- `NavigationStack { SettingsView(...) }` → Tab „Einstellungen“

### App-Start / globale Overlays
Pfad: `BrainMesh/AppRootView.swift`
- Startup-Task mit:
  - Graph-Bootstrap
  - Onboarding-Auto-Show
  - Graph-Lock-Enforcement
  - Image-Hydration-Autorun
- Reagiert auf `scenePhase`.
- Präsentiert:
  - Onboarding-Sheet
  - Graph-Unlock `fullScreenCover`

### Entities / Main Screen
Pfad: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`
- `NavigationStack`
- `searchable(...)`
- Sheets:
  - `AddEntityView`
  - `GraphPickerSheet`
  - `EntitiesHomeDisplaySheet`
- Daten kommen nicht direkt aus `@Query`, sondern aus `EntitiesHomeLoader`-Snapshots.

### Graph Canvas
Pfad: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
- `NavigationStack`
- Toolbar absichtlich klein gehalten
- Sheets:
  - `GraphPickerSheet`
  - `NodePickerView` für Fokus
  - Inspector-Sheet
  - `EntityDetailView`
  - `AttributeDetailView`
  - `DetailsValueEditorSheet`
- Unterstützt Cross-Screen Jump über `GraphJumpCoordinator`.

### Stats
Pfad: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- `NavigationStack`
- Dashboard mit KPI-, Trend-, Media-, Struktur- und Per-Graph-Bereich
- Per-Graph Counts werden lazy nach Disclosure-Öffnung geladen

### Settings
Pfad: `BrainMesh/Settings/SettingsView.swift`
- Hub/Grid-Navigation zu:
  - Pro
  - Display
  - Graph Transfer
  - Import Settings
  - Sync & Wartung
  - Hilfe & Support

## Build & Configuration
### Targets
Quelle: `BrainMesh.xcodeproj/project.pbxproj`
- App Target: `BrainMesh`
- Test Target: `BrainMeshTests`
- UI Test Target: `BrainMeshUITests`

### Deployment / Swift
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- `SWIFT_VERSION = 5.0`
- Quelle: `BrainMesh.xcodeproj/project.pbxproj`

### Info.plist / Entitlements
- `BrainMesh/Info.plist`
  - `UIBackgroundModes = remote-notification`
  - Face ID Usage Description vorhanden
  - Exported Type Declaration für `.bmgraph`
  - Pro-Subscription-IDs in Info.plist-Keys `BM_PRO_SUBSCRIPTION_ID_01/02`
- `BrainMesh/BrainMesh.entitlements`
  - iCloud / CloudKit Capability
  - APS Environment (development)

### StoreKit / Monetization
- Lokale StoreKit-Konfiguration vorhanden: `BrainMesh/BrainMesh Pro.storekit`
- Laufzeit-Store: `BrainMesh/Pro/ProEntitlementStore.swift`
- Freigrenze: `ProLimits.freeGraphLimit = 3` in `BrainMesh/Pro/ProLimits.swift`

### Paketmanagement / Config-Dateien
- `Package.swift`: nicht gefunden
- `.xcconfig`: nicht gefunden
- Dediziertes Secrets-Handling außerhalb von Info.plist / Entitlements / StoreKit-Datei: **UNKNOWN**

## Conventions
- Heavy Screens werden oft in Partials/Extensions gesplittet, z. B. `GraphCanvasScreen+*.swift`, `GraphCanvasView+*.swift`, `GraphStatsView+*.swift`.
- Große Listen/Canvas/Stats meiden Fetches im unmittelbaren Renderpfad und arbeiten stattdessen mit DTO-/Snapshot-Layern.
- Suchfelder werden vorindiziert gespeichert (`nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`).
- Globaler Graph-Kontext läuft konsistent über `BMAppStorageKeys.activeGraphID`.
- Loader erzeugen eigene `ModelContext`s und setzen häufig `autosaveEnabled = false`.
- Value-only DTOs/Snapshots werden bewusst genutzt, um `@Model`-Objekte nicht quer über Concurrency-Grenzen zu schleifen.
- Kommentare dokumentieren oft den Grund für technische Entscheidungen; diese Kommentare sind architekturtragend.

### Do
- Neue graph-scoped Daten konsequent mit `graphID` modellieren.
- Für große Screens lieber Loader/Snapshot statt direkter `@Query`-Komposition verwenden.
- Beim Suchen gefaltete Indexfelder pflegen.
- Bei Off-main Arbeit neue `ModelContext`s verwenden.
- Für Cache-Dateien stabile IDs/Pfade verwenden.

### Don’t
- Keine OR-Predicates auf bloblastigen Attachment-Queries einführen, wenn einfache store-translatable AND-Predicates möglich sind.
- Keine schweren Sorts/Fetches direkt in `body` oder in oft invalidierten Computed Properties verlagern.
- `@Model`-Objekte nicht unkontrolliert über Actor-Grenzen transportieren.
- Neue Screen-Hosts nicht wieder in monolithische Dateien zurückkippen.

## How to work on this project
### Setup Steps
1. Projekt in Xcode öffnen.
2. Signing / iCloud / CloudKit prüfen.
3. StoreKit-Testdatei bei Bedarf aktivieren: `BrainMesh/BrainMesh Pro.storekit`.
4. App starten und prüfen, ob `SyncRuntime` iCloud-Status liefern kann.
5. Testtargets ausführen:
   - `BrainMeshTests/GraphTransferRoundtripTests.swift`
   - `BrainMeshUITests/*`

### Wo anfangen als neuer Dev
- App-Lebenszyklus zuerst lesen:
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/AppRootView.swift`
- Dann das Datenmodell:
  - `BrainMesh/Models/*.swift`
  - `BrainMesh/Attachments/MetaAttachment.swift`
- Danach Loader-/Service-Ebene:
  - `BrainMesh/Support/AppLoadersConfigurator.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
  - `BrainMesh/Stats/GraphStatsService/*`
  - `BrainMesh/GraphTransfer/GraphTransferService/*`

### Typischer Workflow für ein neues Feature
1. Prüfen, ob das Feature graph-scoped sein muss.
2. Falls ja: `graphID` von Anfang an mitdenken.
3. Domainmodell ergänzen.
4. Such-/Sortierindizes mitpflegen, falls das Feature suchbar sein soll.
5. Für größere Screen-Daten einen Loader/Service statt Inline-Fetch bauen.
6. Lokalen Cache nur ergänzen, wenn Blob-/Bild-/Dateizugriff ein echter Hotspot ist.
7. Settings/Appearance nur über die Stores mutieren, nicht über verstreute `UserDefaults`-Strings.
8. Testen, ob CloudKit-Fallback, lokaler Cache und aktive Graph-Selektion stabil bleiben.

## Quick Wins
1. `GraphSession.swift` wirkt im gescannten Code unreferenziert und ist Kandidat für Löschung oder Konsolidierung mit `@AppStorage`-basierter Session-Logik (`BrainMesh/GraphSession.swift`).
2. `Onboarding/Untitled.swift` ist laut Kommentar nur noch ein Platzhalter und sollte entfernt werden, sobald Xcode-Navigation sauber ist (`BrainMesh/Onboarding/Untitled.swift`).
3. `GraphStatsService` summiert Attachment-Bytes über Vollfetches; ein leichter Aggregations-/Cachepfad würde Stats spürbar billiger machen (`BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`).
4. Link-Note-Suche in `EntitiesHomeLoader` löst Endpunkte per Einzel-Fetch auf; Batch-Resolution würde Last senken (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`).
5. Security-Felder auf `MetaEntity`/`MetaAttribute` auf tatsächliche Nutzung prüfen; aktuell wirkt das redundant zu `MetaGraph` (`BrainMesh/Models/MetaEntity.swift`, `BrainMesh/Models/MetaAttribute.swift`).
6. Remote-Notification-Capability gegen tatsächlich implementierten Push-Pfad prüfen (`BrainMesh/Info.plist`).
7. `GraphTransferViewModel.swift` ist ein großer UI-State-Host; Split in Import/Export/Replace/Alerts würde Wartbarkeit verbessern (`BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift`).
8. Große Node-Detail-Dateien weiter nach Screen-Host vs. Media/Connections/Editoren trennen (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`, `BrainMesh/Mainscreen/NodeDetailShared/*`).
9. Stats/Canvas/EntitiesHome benutzen bereits Loader; dieses Muster sollte für weitere medienlastige Detailbereiche konsequent weitergezogen werden.
10. Explizite Architekturdoku für Konflikt-/Migrationsstrategie fehlt derzeit im Code und sollte ergänzt werden, falls Multi-Device-Sync kritisch ist.
