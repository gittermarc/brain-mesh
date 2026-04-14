# PROJECT_CONTEXT.md
## TL;DR
BrainMesh ist eine iPhone-/iPad-App zur Verwaltung von Wissen als Graph: **Graphen** kapseln getrennte Wissensräume, darin liegen **Entitäten**, **Attribute**, **Links**, **frei definierbare Detailfelder** und **Anhänge/Bilder**. Technisch basiert die App auf **SwiftUI + SwiftData** mit **CloudKit Private Database** als primärem Sync-Backend (`BrainMesh/BrainMeshApp.swift`). Das App-Target läuft auf **iOS/iPadOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj`, `TARGETED_DEVICE_FAMILY = "1,2"`).

---
## Key Concepts / Domänenbegriffe
- **Graph**
  - Eigenständiger Wissensraum / Workspace.
  - Persistiert als `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`).
  - Der aktive Graph wird über `BMAppStorageKeys.activeGraphID` gehalten (`BrainMesh/Support/BMAppStorageKeys.swift`).

- **Entity / Entität**
  - Primäres Objekt im Wissensraum, z. B. Person, Projekt, Thema.
  - Persistiert als `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`).
  - Kann Notizen, Icon, Hauptbild, Attribute und Detailfeld-Definitionen besitzen.

- **Attribute**
  - Untergeordnete Fakten/Elemente einer Entität.
  - Persistiert als `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`).
  - Gehört per Relationship zu genau einer Entität (`owner`).

- **Link**
  - Verbindung zwischen zwei Knoten.
  - Persistiert als `MetaLink` (`BrainMesh/Models/MetaLink.swift`).
  - Nutzt **skalare Endpunkte** (`sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`) statt SwiftData-Relationships.

- **Detail Field Definition / Value**
  - Frei definierbares Schema pro Entität und konkrete Werte pro Attribut.
  - Definition: `MetaDetailFieldDefinition` (`BrainMesh/Models/DetailsModels.swift`)
  - Wert: `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`)

- **Details Template**
  - Wiederverwendbares Satz-Template für Detailfelder.
  - Persistiert als `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`).

- **Attachment / Media**
  - Dateien, Videos oder zusätzliche Galerie-Bilder an Entity/Attribute.
  - Persistiert als `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`).
  - Owner wird ebenfalls **skalar** modelliert (`ownerKindRaw`, `ownerID`).

- **Main Image vs. Gallery Image**
  - Hauptbild einer Entity/Attribute liegt direkt als `imageData`/`imagePath` auf dem Modell (`MetaEntity`, `MetaAttribute`).
  - Zusätzliche Bilder liegen als `MetaAttachment` mit `contentKindRaw == galleryImage` vor.

- **Graph Protection**
  - Schutz eines Graphen per Biometrie und/oder Passwort.
  - UI/Runtime: `BrainMesh/Security/GraphSecuritySheet.swift`, `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`.
  - Hinweis: Lock-Felder existieren auch auf `MetaEntity`/`MetaAttribute`, produktive Nutzung dafür ist im gescannten Code **UNKNOWN**.

- **Graph Transfer**
  - Export/Import eines Graphen als `.bmgraph`.
  - Format und Service unter `BrainMesh/GraphTransfer/...`.

- **Graph Jump**
  - Cross-Screen-Navigation „öffne Graph und selektiere Knoten“.
  - `BrainMesh/GraphJumpCoordinator.swift`.

---
## Architecture Map
### 1) App Shell / Composition Root
- `BrainMesh/BrainMeshApp.swift`
  - erstellt `Schema`, `ModelContainer`, Environment Objects
  - entscheidet zwischen CloudKit-Container und lokalem Fallback
  - konfiguriert Loader/Hydratoren global
- `BrainMesh/AppRootView.swift`
  - Startup-Orchestrierung
  - Graph-Bootstrap
  - Onboarding-Präsentation
  - Lock/Unlock-Flows
  - Foreground/Background-Verhalten
- `BrainMesh/ContentView.swift`
  - Root-TabBar

### 2) Feature Layer
- `BrainMesh/Mainscreen/...` — Entities Home, Entity Detail, Attribute Detail, Add-Flows, Detail-Schema/Werte
- `BrainMesh/GraphCanvas/...` — Graph-Visualisierung, Physics, Lens, Inspector, MiniMap
- `BrainMesh/Stats/...` — Graph-Statistiken, Dashboard, Trends, Struktur, Media-Auswertung
- `BrainMesh/GraphTransfer/...` — Import/Export UI + Service
- `BrainMesh/GraphPicker/...` — Graph auswählen, anlegen, umbenennen, löschen
- `BrainMesh/Settings/...` — Einstellungen, Sync, Wartung, Hilfe, Guide
- `BrainMesh/PhotoGallery/...` — Galerie-Browser und Galerie-Import
- `BrainMesh/Security/...` — Graph Lock/Unlock, Passwort-Setup
- `BrainMesh/Pro/...` — StoreKit 2, Paywall, Feature-Gating

### 3) Data / Persistence Layer
- `BrainMesh/Models/...` — SwiftData-Modelle
- `BrainMesh/Attachments/MetaAttachment.swift` — separates Attachment-Modell
- `BrainMesh/GraphBootstrap.swift` — Laufzeit-Migrationen/Backfills
- `BrainMesh/Settings/SyncRuntime.swift` — CloudKit/iCloud-Status für UI

### 4) Background Loading / Derived Data
- `BrainMesh/Support/AppLoadersConfigurator.swift` — zentraler Configure-Punkt für Loader/Hydratoren
- Loader: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `NodeConnectionsLoader`, `BulkLinkLoader`, `NodePickerLoader`
- Hydratoren/Caches: `ImageHydrator`, `AttachmentHydrator`, `ImageStore`, `AttachmentStore`

### 5) Support / Infra
- `BrainMesh/Support/BMAppStorageKeys.swift` — zentrale Defaults-/AppStorage-Keys
- `BrainMesh/Support/SystemModalCoordinator.swift` — Schutz gegen störendes Locking während System-Picker/Face-ID
- `BrainMesh/Observability/BMObservability.swift` — leichtgewichtiges Logging/Timing

### Abhängigkeitsrichtung
- **Views** hängen an **SwiftData main context**, **Environment Stores** und **Loader-Snapshots**.
- **Loader/Services** hängen an `AnyModelContainer` + eigenem `ModelContext`.
- **Modelle** sind unten in der Hierarchie; keine UI-Abhängigkeiten.
- Eine klassische Repository-Schicht ist **nicht** vorhanden.

---
## Folder Map
- `BrainMesh/` — Root App Shell, globale Stores, Bootstrapping, Root-Tabs
- `BrainMesh/Models/` — SwiftData-Modelle, Such-/Enum-Helfer
- `BrainMesh/Mainscreen/` — Hauptdatenpflege; Unterordner für `EntitiesHome`, `EntityDetail`, `AttributeDetail`, `Details`, `NodeDetailShared`
- `BrainMesh/GraphCanvas/` — Graph-Screen, Rendering, Gesten, Physics, Overlay, Datenloader
- `BrainMesh/Stats/` — Statistik-Service, Loader, Dashboard-Views, Komponenten
- `BrainMesh/Attachments/` — Attachment-Modell, Caches, Import-Pipeline, Preview, Thumbnail-Infra
- `BrainMesh/PhotoGallery/` — Galeriebrowser, Galerieimport, Auswahl-/Viewer-State
- `BrainMesh/GraphTransfer/` — Datei-Format, DTOs, Service, ViewModel, Import/Export-UI
- `BrainMesh/GraphPicker/` — Graph-Liste, Dedupe/Delete/Rename-Helfer
- `BrainMesh/Security/` — Passwort-/Biometrie-Schutz für Graphen
- `BrainMesh/Settings/` — Hub, Wartung, Appearance/Display, Guide, Hilfe, Sync-UI
- `BrainMesh/Pro/` — Pro-Features, StoreKit, Paywall, Pro Center
- `BrainMesh/Icons/` — SF Symbols Katalog und Picker
- `BrainMesh/Support/` — AppStorage-Keys, UTType, AsyncLimiter, Container-Wrapper, Modalkoordination
- `BrainMesh/Observability/` — Logger- und Timing-Helfer
- `BrainMeshTests/` — Unit-/Integrationstests auf In-Memory-SwiftData
- `BrainMeshUITests/` — UI-Tests / Launch-Tests

---
## Data Model Map
### `MetaGraph` — `BrainMesh/Models/MetaGraph.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `name`, `nameFolded`
  - `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Rolle:
  - Scope-/Workspace-Modell
  - aktive Auswahl per `activeGraphID`

### `MetaEntity` — `BrainMesh/Models/MetaEntity.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `name`, `nameFolded`
  - `notes`, `notesFolded`
  - `iconSymbolName`
  - `imageData`, `imagePath`
- Relationships:
  - `attributes` (cascade) → `MetaAttribute`
  - `detailFields` (cascade) → `MetaDetailFieldDefinition`
- Besonderheiten:
  - `graphID` ist optional für Legacy-Migration
  - Änderung an `name` aktualisiert Search Labels abhängiger Attribute

### `MetaAttribute` — `BrainMesh/Models/MetaAttribute.swift`
- Wichtige Felder:
  - `id`, `graphID`
  - `name`, `nameFolded`
  - `notes`, `notesFolded`
  - `iconSymbolName`
  - `imageData`, `imagePath`
  - `searchLabelFolded`
- Relationship:
  - `owner: MetaEntity?`
  - `detailValues` (cascade) → `MetaDetailFieldValue`
- Besonderheiten:
  - `displayName = "Entity · Attribute"`
  - `searchLabelFolded` ist ein denormalisierter Suchindex

### `MetaLink` — `BrainMesh/Models/MetaLink.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `note`, `noteFolded`
  - `sourceLabel`, `targetLabel`
  - `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`
- Besonderheiten:
  - keine SwiftData-Beziehungen zu den Knoten
  - Labels werden redundant gespeichert

### `MetaAttachment` — `BrainMesh/Attachments/MetaAttachment.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `ownerKindRaw`, `ownerID`
  - `contentKindRaw`
  - `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - `fileData` mit `@Attribute(.externalStorage)`
  - `localPath`
- Besonderheiten:
  - Owner ist rein skalar modelliert
  - `fileData` ist die autoritative, syncbare Quelle
  - `localPath` zeigt nur auf den lokalen Cache

### `MetaDetailFieldDefinition` — `BrainMesh/Models/DetailsModels.swift`
- Wichtige Felder:
  - `id`, `graphID`, `entityID`
  - `name`, `nameFolded`
  - `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- Relationship:
  - `owner: MetaEntity?`
- Besonderheiten:
  - bis zu 3 gepinnte Felder werden laut Kommentar/UI erwartet
  - Optionen als JSON-String

### `MetaDetailFieldValue` — `BrainMesh/Models/DetailsModels.swift`
- Wichtige Felder:
  - `id`, `graphID`, `attributeID`, `fieldID`
  - `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
- Relationship:
  - `attribute: MetaAttribute?`
- Besonderheiten:
  - typisierte Speicherung statt einheitlichem String-Feld

### `MetaDetailsTemplate` — `BrainMesh/Models/MetaDetailsTemplate.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `name`, `nameFolded`
  - `fieldsJSON`
- Rolle:
  - gespeicherte Sets von Detailfeld-Definitionen

### Relationship-Design insgesamt
- Echte SwiftData-Relationships gibt es nur dort, wo sie stabil und lokal sinnvoll sind:
  - `MetaEntity -> MetaAttribute`
  - `MetaEntity -> MetaDetailFieldDefinition`
  - `MetaAttribute -> MetaDetailFieldValue`
- Links und Attachments nutzen stattdessen **skalare IDs**.
- Das ist ein zentrales Architekturmerkmal, kein Zufall.

---
## Sync / Storage
### Persistence-Stack
- SwiftData-Schema wird in `BrainMesh/BrainMeshApp.swift` explizit erstellt.
- Enthaltene Modelle:
  - `MetaGraph`
  - `MetaEntity`
  - `MetaAttribute`
  - `MetaLink`
  - `MetaAttachment`
  - `MetaDetailFieldDefinition`
  - `MetaDetailFieldValue`
  - `MetaDetailsTemplate`

### CloudKit
- `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`
- Runtime-Status-Helfer: `BrainMesh/Settings/SyncRuntime.swift`
- Container-ID: `iCloud.de.marcfechner.BrainMesh`
- Entitlements: `BrainMesh/BrainMesh.entitlements`
- Gescannter Modus: **Private DB**, keine Hinweise auf `CKShare`/Shared Database.

### Fallback-Verhalten
- **DEBUG**: CloudKit-Container-Fehler führen zu `fatalError`.
- **Nicht-DEBUG**: Fallback auf lokalen `ModelConfiguration(schema: schema)` und `SyncRuntime.storageMode = .localOnly`.
- Das ist ein bewusst sichtbares Betriebsmodell, kein stilles „best effort“.

### Laufzeit-Migrationen / Backfills
- `BrainMesh/GraphBootstrap.swift`
  - `ensureAtLeastOneGraph(...)`
  - `migrateLegacyRecordsIfNeeded(...)` für `graphID == nil`
  - `backfillFoldedNotesIfNeeded(...)` für `notesFolded` / `noteFolded`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - migriert alte Attachments owner-bezogen von `graphID == nil` auf konkreten Graph

### Caches
- Hauptbilder:
  - syncbar als `imageData` auf `MetaEntity`/`MetaAttribute`
  - lokal gecacht über `imagePath` + `BrainMesh/ImageStore.swift`
  - Wiederaufbau per `BrainMesh/ImageHydrator.swift`
- Attachments:
  - syncbar als `fileData`
  - lokal gecacht per `localPath` + `BrainMesh/Attachments/AttachmentStore.swift`
  - Wiederaufbau/Materialisierung per `BrainMesh/Attachments/AttachmentHydrator.swift`

### Offline-Verhalten
- Lokale SwiftData-Daten sind grundsätzlich nutzbar.
- Bild-/Attachment-Caches können lokal fehlen und bei Bedarf neu materialisiert werden.
- Ob es eine explizite Konfliktauflösung jenseits des Standardverhaltens von SwiftData/CloudKit gibt, ist **UNKNOWN**.

### Migrations-/Schema-Strategie
- Sichtbar ist eine **laufzeitbasierte Reparatur-/Backfill-Strategie**.
- Eine separate, versionierte Migrationsdokumentation wurde im Scan **nicht** gefunden.

---
## UI Map
### Root Navigation
- `BrainMesh/ContentView.swift`
  - `TabView(selection: $tabRouter.selection)`
  - Tabs:
    - `EntitiesHomeView()`
    - `GraphCanvasScreen()`
    - `GraphStatsView()`
    - `NavigationStack { SettingsView(...) }`

### Tab 1 — Entities
- Root: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- Navigation:
  - `NavigationStack`
  - Suche, Sortierung, Display-Optionen, Add Entity
  - Navigation zu Entity Detail
- Wichtige Flows:
  - `AddEntityView`
  - `GraphPickerSheet`
  - Entity Detail / Attribute Detail

### Entity Detail
- Host: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Enthält:
  - Hero/Header
  - Attribute-Sektionen
  - Links-Vorschau und „Alle“-Verbindungen
  - Gallery / Attachments
  - Notizen, Rename, Customize, Delete, Add Attribute, Add Link, Bulk Link
- Viele Teilbereiche liegen in Split-Dateien unter `BrainMesh/Mainscreen/EntityDetail/...` und `BrainMesh/Mainscreen/NodeDetailShared/...`

### Attribute Detail
- Host: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Enthält:
  - Hero/Header
  - Detailwerte/Detailschema
  - Gallery / Attachments
  - Links
  - Rename / Delete / Customize

### Tab 2 — Graph
- Root: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
- Body/Navigation: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
- Enthält:
  - Canvas mit Physics-Simulation
  - Inspector
  - MiniMap
  - Selection Action Chip
  - Focus/Neighborhood-Modus
  - Graph Jump Handling
  - Sheets für GraphPicker, NodePicker, Detailansichten, DetailsValueEditor

### Tab 3 — Stats
- Root: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- Enthält:
  - Dashboard Header
  - KPI Grid
  - Trends
  - Media Breakdown
  - Structure Breakdown
  - Legacy-Daten-Card
  - lazy „Pro Graph“-Bereich

### Tab 4 — Settings
- Root: `BrainMesh/Settings/SettingsView.swift`
- Hub für:
  - Pro
  - Appearance / Display
  - Graph Transfer
  - Import Settings
  - Sync & Wartung
  - Hilfe / Guide / Rechtliches

### Cross-Cutting UI Flows
- Onboarding: `BrainMesh/Onboarding/OnboardingSheetView.swift`
- Graph Picker: `BrainMesh/GraphPickerSheet.swift`
- Graph Unlock: `BrainMesh/Security/GraphUnlock/GraphUnlockView.swift`
- Pro Paywall: `BrainMesh/Pro/ProPaywallView.swift`
- Graph Transfer: `BrainMesh/GraphTransfer/GraphTransferView/...`

---
## Build & Configuration
### Targets
- App Target: `BrainMesh`
- Unit Tests: `BrainMeshTests`
- UI Tests: `BrainMeshUITests`
- Quelle: `BrainMesh.xcodeproj/project.pbxproj`

### Plattform / Deployment
- `SDKROOT = iphoneos`
- `TARGETED_DEVICE_FAMILY = "1,2"`
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`

### Bundle / Versioning
- App Bundle ID: `de.marcfechner.BrainMesh`
- Tests Bundle IDs:
  - `de.marcfechner.BrainMeshTests`
  - `de.marcfechner.BrainMeshUITests`
- Versionen:
  - `MARKETING_VERSION = 1.06`
  - `CURRENT_PROJECT_VERSION = 1`

### Info.plist / Entitlements
- `BrainMesh/Info.plist`
  - StoreKit-Produkt-IDs
  - `UIBackgroundModes = [remote-notification]`
  - exportierter UTType für `.bmgraph`
- `BrainMesh/BrainMesh.entitlements`
  - CloudKit aktiviert
  - iCloud-Container gesetzt
  - `aps-environment = development`

### StoreKit / Pro
- Produkt-IDs aus `Info.plist`, gelesen in `BrainMesh/Pro/ProEntitlementStore.swift`
- Lokale StoreKit-Konfigurationsdatei:
  - `BrainMesh/BrainMesh Pro.storekit`

### SPM / xcconfig / Secrets
- `packageProductDependencies` sind im Projekt leer.
- Keine separaten `.xcconfig`-Dateien im gescannten Projekt gefunden.
- Explizites Secrets-Handling jenseits `Info.plist`/Signing ist **UNKNOWN**.

### Filesystem Groups
- Das Projekt nutzt filesystem-synced groups (`PBXFileSystemSynchronized...` / `fileSystemSynchronizedGroups` in `project.pbxproj`).

---
## Conventions
### Technische Patterns
- **Graph-Scope ernst nehmen**
  - Neue persistierte Datensätze brauchen korrektes `graphID`.
- **Folded Search Indices pflegen**
  - `nameFolded`, `notesFolded`, `noteFolded`, `searchLabelFolded` sind Teil des Datenmodells, nicht bloßer UI-Komfort.
- **Keine SwiftData-Fetches im Renderpfad**
  - Beispiel Gegenmaßnahme: Render-Caches für Graph Canvas in `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Caches.swift`.
- **Schwere Fetches off-main**
  - Actor-/Loader-Muster ist Standard für größere Listen/Stats/Canvas.
- **Skalare IDs statt Relationships dort, wo Stabilität wichtiger ist**
  - besonders bei Links und Attachments.
- **Kleine Split-Dateien statt God Files**
  - sichtbar in `GraphCanvasScreen`, `GraphCanvasView`, `GraphStatsView`, `NodeDetailShared`.
- **Konzentrierte AppStorage-Keys**
  - neue Keys gehören in `BrainMesh/Support/BMAppStorageKeys.swift`.
- **Settings-State nicht wild verteilen**
  - Appearance/Display via `AppearanceStore` und `DisplaySettingsStore`.

### Do
- teure Queries in Loader/Services kapseln
- `ModelContext` pro Background-Task sauber lokal erzeugen
- späte Ergebnisse mit Token/Cancellation absichern
- deterministische Cache-Dateinamen verwenden
- Tests mit `BrainMeshTests/TestSupport/BrainMeshTestContainer.swift` und `BrainMeshFixtureBuilder.swift` anlegen

### Don’t
- keine großen `@Query`-Sammlungen direkt in sehr häufig neu rendernden Views nachziehen
- keine ad-hoc UserDefaults-Strings verteilen
- `imagePath`/`localPath` nicht als syncbare Wahrheit behandeln
- keine OR-lastigen SwiftData-Prädikate auf extern gespeicherten Blobs aufbauen, wenn vermeidbar

---
## How to work on this project
### Setup Steps
1. Projekt in Xcode öffnen: `BrainMesh.xcodeproj`
2. Signing/iCloud-Setup prüfen
   - Bundle ID
   - iCloud/CloudKit Capability
   - Container `iCloud.de.marcfechner.BrainMesh`
3. App auf Gerät oder Simulator starten
4. Im ersten Lauf prüfen:
   - wird ein Default-Graph erzeugt?
   - öffnet `EntitiesHomeView`?
   - zeigt `Settings -> Sync & Wartung` plausiblen Status?
5. Für StoreKit-/Pro-Tests optional `BrainMesh Pro.storekit` verwenden

### Wo neue Entwickler anfangen sollten
1. `BrainMesh/BrainMeshApp.swift`
2. `BrainMesh/AppRootView.swift`
3. `BrainMesh/ContentView.swift`
4. danach den betroffenen Feature-Ordner öffnen

### Wenn du ein neues Persistenz-Feature baust
- Modell unter `BrainMesh/Models/` oder passendem Feature-Ordner anlegen
- Modell in `Schema([...])` in `BrainMesh/BrainMeshApp.swift` ergänzen
- `graphID`-Scope prüfen
- Suchfelder/Folded-Indices mitdenken
- Import/Export-Auswirkung prüfen, falls graphrelevant
- Tests im In-Memory-Container ergänzen

### Wenn du einen Performance-kritischen Screen anfasst
- zuerst prüfen, ob bereits ein Loader/Snapshot-Muster existiert
- keine schweren Fetches im `body`
- große Derived-State-Berechnungen cachen oder vorrechnen
- Task-Lebensdauer/Cancellation explizit behandeln

---
## Quick Wins
1. `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift` von `@MainActor` lösen und in ein Background-Loader-Muster überführen.
2. `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift` für Attachment-Bytes nicht per Vollfetch aller `MetaAttachment` rechnen lassen.
3. `BrainMesh/GraphCanvas/GraphCanvasScreen/...` weiter in Load-/Jump-/MiniMap-/Selection-Orchestrierung schneiden.
4. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` funktional aufsplitten; aktuell zu viele Aufgaben in einer Datei.
5. `BrainMesh/Attachments/AttachmentImportPipeline.swift` in File-/Video-/Gallery-Pfade trennen, damit Fehlerpfade beherrschbarer werden.
6. `BrainMesh/Onboarding/Untitled.swift` löschen oder bewusst dokumentieren; laut Dateikommentar ist sie bereits obsolet.
7. `BrainMesh/GraphSession.swift` gegen die reale Nutzung via `@AppStorage(BMAppStorageKeys.activeGraphID)` prüfen; Doppelzustand riecht nach Wartungsfalle.
8. Startup-Timing für `GraphBootstrap` und `ImageHydrator` messen/loggen, um Launch-Latenz auf realen Stores sichtbar zu machen.
9. `UIBackgroundModes = remote-notification` gegen realen Codebestand prüfen; Nutzungszweck ist im Scan **UNKNOWN**.
10. Graph-Lock-Felder auf `MetaEntity`/`MetaAttribute` auf aktive Nutzung prüfen; derzeit sichtbar produktiv orchestriert ist nur Graph-Level-Schutz.
