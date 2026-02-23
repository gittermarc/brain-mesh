# BrainMesh — PROJECT_CONTEXT (Start Here)

## TL;DR
BrainMesh ist eine SwiftUI‑App (iOS/iPadOS) für ein graphbasiertes Wissens-/Notizsystem: **Graph** → **Entitäten** (Nodes) → **Attribute** (Sub‑Nodes) + **Links** (Edges) + **frei definierbare Detail‑Felder** + **Anhänge/Medien**. Persistenz läuft über **SwiftData**; Sync wird über **SwiftData + CloudKit** aktiviert (ModelConfiguration `cloudKitDatabase: .automatic`). Mindest‑Deployment‑Target laut Xcode‑Projekt: **iOS 26.0** (siehe `BrainMesh.xcodeproj/project.pbxproj`).

---

## Key Concepts / Domänenbegriffe
- **Graph**: Ein isolierter „Workspace“ / eine Datenbank (siehe `@Model MetaGraph` in `BrainMesh/Models.swift`). Aktiv via `@AppStorage(BMAppStorageKeys.activeGraphID)`.
- **Entität (Entity Node)**: Oberknoten im Graph (siehe `@Model MetaEntity` in `BrainMesh/Models.swift`).
- **Attribut (Attribute Node)**: Unterknoten, gehört zu einer Entität (`MetaAttribute.owner` / `MetaEntity.attributes`).
- **Link**: Kante zwischen Nodes (aktuell v. a. Entity↔Entity über `MetaLink`, `sourceKindRaw/targetKindRaw` in `BrainMesh/Models.swift`).
- **Detail‑Feld (Schema)**: Pro Entität definierbares Feld‑Schema (`MetaDetailFieldDefinition`, z. B. Text, Datum, Zahl) in `BrainMesh/Models.swift`.
- **Detail‑Wert (Value)**: Konkreter Wert pro Attribut (`MetaDetailFieldValue`) in `BrainMesh/Models.swift`.
- **Pinned Felder**: Max. 3 Felder können „gepinnt“ werden (`MetaDetailFieldDefinition.isPinned`). Sie werden u. a. im Graph‑Selection‑Chip als Peek‑Chips angezeigt (`GraphCanvas/GraphCanvasScreen+DetailsPeek.swift`).
- **Attachments**: Dateien/Videos/Gallery‑Images als `MetaAttachment` (separates Model in `BrainMesh/Attachments/MetaAttachment.swift`, `fileData` als `.externalStorage`).
- **Hydration**: Hintergrund‑Prozesse, die lokale Cache‑Dateien (JPEG/Attachments) erstellen, um UI‑Stalls durch Disk‑I/O/Cloud‑Fetches zu vermeiden:
  - `ImageHydrator` (`BrainMesh/ImageHydrator.swift`)
  - `AttachmentHydrator` (`BrainMesh/Attachments/AttachmentHydrator.swift`)
- **GraphCanvas**: Interaktives Canvas mit Physics‑Simulation, Lens/Spotlight und Inspector (Ordner `BrainMesh/GraphCanvas/*`).

---

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhängigkeiten)
**UI (SwiftUI Views)**
- Tabs + Root: `BrainMesh/ContentView.swift` (TabView)
- Root‑Orchestrierung (Onboarding/Lock/Startup): `BrainMesh/AppRootView.swift`
- Features:
  - Entities Home: `BrainMesh/Mainscreen/EntitiesHome/*`
  - Entity Detail: `BrainMesh/Mainscreen/EntityDetail/*`
  - Attribute Detail: `BrainMesh/Mainscreen/AttributeDetail/*`
  - Graph Canvas: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`
  - Onboarding: `BrainMesh/Onboarding/*`
  - Security (Graph Lock): `BrainMesh/Security/*`

**Domain & Persistence (SwiftData Models)**
- Core Modelle (Graph/Entity/Attribute/Link/Details): `BrainMesh/Models.swift`
- Attachments‑Model: `BrainMesh/Attachments/MetaAttachment.swift`

**Loaders/Services (Async, off‑main)**
- Zentral konfiguriert in `BrainMesh/Support/AppLoadersConfigurator.swift`.
- Pattern: `actor` + `AnyModelContainer` → Hintergrund‑`ModelContext` in `Task.detached` → value‑only DTO Snapshots.
- Beispiele:
  - `GraphCanvasDataLoader` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`)
  - `GraphStatsLoader` (`BrainMesh/Stats/GraphStatsLoader.swift`)
  - `EntitiesHomeLoader` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`)
  - `MediaAllLoader` (`BrainMesh/Attachments/MediaAllLoader.swift`)

**Caching (Memory + Disk)**
- Bilder: `BrainMesh/ImageStore.swift` (NSCache + Application Support `/BrainMeshImages`)
- Attachments: `BrainMesh/Attachments/AttachmentStore.swift` (Application Support `/BrainMeshAttachments`) **(Pfad siehe dort)**

**Observability**
- Minimal‑Logging + Timing: `BrainMesh/Observability/BMObservability.swift` (`BMLog.*`, `BMDuration`).

Abhängigkeiten (grob)
- Views → Models + Loaders/Stores + Support
- Loaders/Hydrators → SwiftData (`ModelContainer`/`ModelContext`) + Disk‑Stores
- Keine externen SPM‑Dependencies im Xcode‑Projekt (siehe `BrainMesh.xcodeproj/project.pbxproj`: `packageProductDependencies = ()`).

---

## Folder Map (Ordner → Zweck)
Top‑Level unter `BrainMesh/`:
- `Attachments/`: Attachment‑Model + Cache/Hydration + UI Rows (`MetaAttachment.swift`, `AttachmentHydrator.swift`, `AttachmentCardRow.swift`, …).
- `GraphCanvas/`: Canvas‑UI, Physics, Rendering, Data‑Loader, Expand‑Logik, Inspector, MiniMap.
- `GraphPicker/`: Graph‑Wechsel/Verwaltung (Rename/Delete/Dedupe) UI‑Helpers.
- `Icons/`: SF‑Symbols Picker (`AllSFSymbolsPickerView.swift`, …).
- `ImportProgress/`: Import‑Flows + Progress UI (Media/Video/File Import) **(Details je nach Datei)**.
- `Mainscreen/`:
  - `EntitiesHome/`: Entitäten‑Übersicht + Loader + Display‑Sheet.
  - `EntityDetail/`: Detail‑Screen einer Entität inkl. Attribute‑Sektionen.
  - `AttributeDetail/`: Detail‑Screen eines Attributs.
  - `Details/`: Details‑Schema + Editor‑Sheets (`DetailsValueEditorSheet.swift`, …).
  - `NodeDetailShared/`: Wiederverwendete Detail‑Bausteine (Media Gallery, Attachments, Connections, Core UI).
- `Observability/`: Logging/Timing.
- `Onboarding/`: Onboarding‑Sheet + Mini‑Explainer + Progress.
- `PhotoGallery/`: Gallery/Browser Views für Bilder.
- `Security/`: Graph‑Lock Coordinator + Unlock UI + Password setup.
- `Settings/`: Settings Root + Appearance + Display + Sync‑Diagnostics + Maintenance.
- `Stats/`: Stats Loader + Service (Counts/Trends/Media/Structure) + Stats UI.
- `Support/`: Querschnitt (Keys, Loader‑Config, AsyncLimiter, SystemModalCoordinator, DetailsCompletion UI/Index).

---

## Data Model Map (Entities, Relationships, wichtige Felder)
### Core
- `MetaGraph` (`BrainMesh/Models.swift`)
  - `id: UUID`, `createdAt`, `name`, `nameFolded`
  - Graph‑Lock: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

- `MetaEntity` (`BrainMesh/Models.swift`)
  - `id`, `createdAt`, `graphID: UUID?` (Scope)
  - `name`, `nameFolded`, `notes`
  - Visuals: `iconSymbolName`, `imageData: Data?`, `imagePath: String?` (lokaler Cache)
  - Relationships:
    - `attributes: [MetaAttribute]?` (inverse: `MetaAttribute.owner`, deleteRule `.cascade`)
    - `detailFields: [MetaDetailFieldDefinition]?` (inverse: `MetaDetailFieldDefinition.owner`, deleteRule `.cascade`)

- `MetaAttribute` (`BrainMesh/Models.swift`)
  - `id`, `graphID: UUID?`, `name`, `nameFolded`, `notes`
  - `owner: MetaEntity?` (kein inverse macro hier; wird über `MetaEntity.attributes` definiert)
  - Visuals: `iconSymbolName`, `imageData`, `imagePath`
  - Details:
    - `detailValues: [MetaDetailFieldValue]?` (inverse: `MetaDetailFieldValue.attribute`, deleteRule `.cascade`)
  - Denormalized search: `searchLabelFolded`

- `MetaLink` (`BrainMesh/Models.swift`)
  - `id`, `createdAt`, `graphID: UUID?`
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`
  - `note: String?`

### Details (Schema + Werte)
- `MetaDetailFieldDefinition` (`BrainMesh/Models.swift`)
  - `id`, `graphID: UUID?`, `entityID: UUID`
  - `name`, `nameFolded`, `typeRaw` (`DetailFieldType`), `sortIndex`
  - `isPinned: Bool` (UI enforced max 3)
  - Optional: `unit`, `optionsJSON` (für `.singleChoice`)
  - Relationship: `owner: MetaEntity?` (deleteRule `.nullify`, originalName „entity“)

- `MetaDetailFieldValue` (`BrainMesh/Models.swift`)
  - `id`, `graphID: UUID?`, `attributeID`, `fieldID`
  - Typed storage: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - Relationship: `attribute: MetaAttribute?` (didSet setzt IDs/graphID)

### Attachments
- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - `id`, `createdAt`, `graphID: UUID?`
  - Owner: `ownerKindRaw`, `ownerID`
  - Usage: `contentKindRaw` (`AttachmentContentKind`: file/video/galleryImage)
  - Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - Data: `fileData: Data?` mit `@Attribute(.externalStorage)`
  - Local cache: `localPath: String?`

**Wichtig:** Viele Modelle nutzen `graphID: UUID?` (optional) für „sanfte Migration“ alter Daten (`GraphBootstrap.migrateLegacyRecordsIfNeeded` in `BrainMesh/GraphBootstrap.swift`).

---

## Sync/Storage
### SwiftData + CloudKit
- Container‑Setup: `BrainMesh/BrainMeshApp.swift`
  - Schema enthält: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`.
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`.
  - Debug: CloudKit‑Init Fehler → `fatalError(...)`.
  - Release: CloudKit‑Init Fehler → Fallback auf lokalen Store (`ModelConfiguration(schema: schema)`), plus `SyncRuntime.shared.setStorageMode(.localOnly)`.

- Sync‑Diagnose UI: `BrainMesh/Settings/SyncRuntime.swift` + `BrainMesh/Settings/SettingsView+SyncSection.swift` **(Section‑Datei existiert, Details dort)**.

- iCloud Container ID (Entitlements müssen matchen):
  - `BrainMesh/BrainMesh.entitlements`: `iCloud.de.marcfechner.BrainMesh`
  - Code‑Konstante: `SyncRuntime.containerIdentifier` (`Settings/SyncRuntime.swift`).

**UNKNOWN:**
- Ob `.automatic` im konkreten Deployment immer „Private DB“ bedeutet oder abhängig vom OS/Capabilities eine andere DB wählt.
- Konfliktauflösung/merge‑Strategie bei gleichzeitigen Änderungen (SwiftData‑intern).

### Lokale Caches
- Main‑Fotos (Entities/Attributes): `ImageStore` (`BrainMesh/ImageStore.swift`)
  - Disk: Application Support `/BrainMeshImages`
  - Memory: NSCache (countLimit 120)
  - Wichtiger Hinweis im Code: `loadUIImage(path:)` nicht im SwiftUI `body` verwenden.

- Attachment Cache: `AttachmentStore` (`BrainMesh/Attachments/AttachmentStore.swift`)
  - Disk: Application Support `/BrainMeshAttachments` **(genauer Pfad siehe Implementierung)**

### Hydrators
- `ImageHydrator` (`BrainMesh/ImageHydrator.swift`):
  - Hintergrund‑Pass (serialisiert über `AsyncLimiter(maxConcurrent: 1)`).
  - Auto‑Run: maximal 1×/24h via `BMAppStorageKeys.imageHydratorLastAutoRun` (siehe `AppRootView.autoHydrateImagesIfDue()`).
- `AttachmentHydrator` (`BrainMesh/Attachments/AttachmentHydrator.swift`):
  - On‑demand (List cells) + dedupe per `attachmentID` (`inFlight`).
  - Throttle global: `AsyncLimiter(maxConcurrent: 2)`.

### Migration
- Graph‑Scope Migration: `BrainMesh/GraphBootstrap.swift` (setzt fehlendes `graphID` für Entities/Attributes/Links).
- Attachment GraphID Migration: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (gerufen aus `MediaAllLoader.migrateLegacyGraphIDIfNeeded(...)`).

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMeshApp` (`BrainMesh/BrainMeshApp.swift`)
  - erstellt `ModelContainer`, startet `SyncRuntime.refreshAccountStatus()`, konfiguriert Loader/Hydrators.
- `AppRootView` (`BrainMesh/AppRootView.swift`)
  - Root: `ContentView()`
  - Onboarding Sheet: `OnboardingSheetView()`
  - Graph Lock Fullscreen: `GraphUnlockView(request:)`
  - ScenePhase‑Handling (Debounce‑Lock bei `.background` um System‑Picker nicht zu zerstören).

### Tabs (`ContentView.swift`)
1) **Entitäten**: `EntitiesHomeView` (NavigationStack)
   - Sheets:
     - Add Entity: `Mainscreen/AddEntityView.swift`
     - Graph Picker: `GraphPickerSheet` (`BrainMesh/GraphPickerSheet.swift`)
     - Display Optionen: `Mainscreen/EntitiesHome/EntitiesHomeDisplaySheet.swift`
   - Navigation:
     - Entity Detail: `EntityDetailRouteView` → `EntityDetailView(entity:)`.

2) **Graph**: `GraphCanvasScreen` (NavigationStack intern)
   - Toolbar minimal (Picker + Inspector).
   - Sheets:
     - Graph Picker: `GraphPickerSheet`
     - Focus Picker: `NodePickerView(kind:.entity, ...)` **(siehe `Mainscreen/*` bzw. `NodePicker*` Dateien)**
     - Inspector: `GraphCanvasScreen+Inspector.swift` (Sheet)
     - Entity Detail (sheet(item:)): `EntityDetailView` wrapped in `NavigationStack`.
     - Attribute Detail (sheet(item:)): `AttributeDetailView` wrapped in `NavigationStack`.
     - Details‑Value‑Edit (sheet(item:)): `DetailsValueEditorSheet(attribute:field:)`.

3) **Stats**: `GraphStatsView` (`Stats/GraphStatsView/GraphStatsView.swift`)
   - Data via `GraphStatsLoader` + `GraphStatsService`.

4) **Einstellungen**: `SettingsView` in `NavigationStack` (`Settings/SettingsView.swift`)
   - Subviews/Sections in `Settings/SettingsView+*.swift`.
   - Display/Appearance Editoren in `Settings/Appearance/*` und `Settings/Display/*`.

---

## Build & Configuration
- Xcode Projekt: `BrainMesh/BrainMesh.xcodeproj`
- Targets:
  - App: `BrainMesh`
  - Tests: `BrainMeshTests` (`BrainMeshTests/BrainMeshTests.swift`)
  - UI Tests: `BrainMeshUITests` (minimal/leer **UNKNOWN**, je nach Dateien)
- Deployment Target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `project.pbxproj`.
- Bundle IDs:
  - App: `de.marcfechner.BrainMesh` (siehe `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`).
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud Container Identifiers + CloudKit service.
  - `aps-environment = development` (**Risiko**: für TestFlight/Release i. d. R. `production` nötig — siehe Open Questions).
- Info.plist: `BrainMesh/Info.plist`
  - `NSFaceIDUsageDescription`
  - `UIBackgroundModes: remote-notification`
- SPM: keine Packages.
- Secrets Handling: keine `.xcconfig` / Secrets‑Files im Repo gefunden (`find *.xcconfig` → leer). **UNKNOWN** ob private CI‑Secrets existieren.

---

## Conventions (Naming, Patterns, Do/Don’t)
- `BM*` Prefix für Querschnitt: `BMAppStorageKeys`, `BMSearch`, `BMLog`, …
- UserDefaults / AppStorage Keys: nur über `Support/BMAppStorageKeys.swift`.
- SwiftData Queries:
  - Heavy fetches nicht im `body` → stattdessen Loader‑Actor + Snapshot (Beispiele: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).
  - Predicates möglichst store‑translatable halten (Kommentare in `Attachments/MediaAllLoader.swift`).
- Concurrency:
  - Keine `@Model` Instanzen über Actor/Task‑Grenzen reichen (Pattern: value DTOs wie `EntitiesHomeRow`).
  - Hintergrund‑I/O über `Task.detached(priority:)` + eigener `ModelContext`.
- GraphCanvas:
  - Render‑Pfad „cheap“ halten: caches (`labelCache`, `imagePathCache`, `iconSymbolCache`) in `GraphCanvasScreen.swift`.

---

## How to work on this project (Setup Steps + wo anfangen)
1) Xcode 26 öffnen: `BrainMesh/BrainMesh.xcodeproj`.
2) Signing checken:
   - Team, Bundle ID, Entitlements (`BrainMesh/BrainMesh.entitlements`).
   - iCloud Capability + Container `iCloud.de.marcfechner.BrainMesh` muss im Apple Developer Portal existieren.
3) iCloud/CloudKit testen:
   - Auf realem Gerät mit iCloud Login.
   - Settings → Sync Section prüfen (StorageMode + AccountStatus) (`Settings/SyncRuntime.swift`).
4) Erststart/Graph Bootstrap:
   - `AppRootView.bootstrapGraphing()` stellt sicher, dass mind. ein Graph existiert (`GraphBootstrap.ensureAtLeastOneGraph`).
5) Neue Features:
   - UI‑Feature? Start im passenden Feature‑Ordner (z. B. `GraphCanvas/`, `Mainscreen/EntityDetail/`).
   - Data‑Model Änderung? `Models.swift`/`MetaAttachment.swift` anpassen + Schema in `BrainMeshApp.init()` aktualisieren.
   - Heavy Load? Neuen Loader als `actor` unter Feature anlegen, in `Support/AppLoadersConfigurator.swift` registrieren.

---

## Quick Wins (max. 10, konkret)
1) `Models.swift` (515 LOC) in mehrere Dateien splitten (`Models/MetaGraph.swift`, `Models/MetaEntity.swift`, …) → weniger Merge‑Konflikte/Compile‑Churn.
2) Entitlements trennen: Debug vs Release (`aps-environment`) → verhindert Push/CloudKit‑Edgecases bei TestFlight.
3) `DetailsSchemaFieldsList.swift` (469 LOC) in: List + Row + Editors splitten → Wartbarkeit.
4) `DetailsValueEditorSheet.swift` (510 LOC) in Subviews pro Field‑Type splitten; Completion‑Logik in eigenes Helper‑File.
5) `GraphCanvasView+Rendering.swift` (532 LOC) weiter modularisieren: „edge pass“, „node pass“, „labels“, „notes“ in separate Funktionen/Files → leichteres Profiling.
6) In allen Loader‑Loops konsequent `Task.checkCancellation()` einbauen (einige tun’s, nicht alle) → weniger wasted work bei schnellem Tippen.
7) „Dead/unused“ Lock‑Felder in `MetaEntity`/`MetaAttribute` klären (siehe Open Questions) → Datenmodell vereinfachen.
8) Minimal‑Tests hinzufügen: `BMSearch.fold`, `AttachmentStore` Path‑Erzeugung, `GraphBootstrap.hasLegacyRecords` (unit tests sind leer).
9) Standardisiere Logger‑Kategorien (z. B. `BMLog.load/expand/physics`) auch in Loader‑Actors nutzen (teilweise `Logger(subsystem:..., category:...)`).
10) Dokumentiere „Hot knobs“ (maxNodes/maxLinks, collisionStrength, lens) zentral (z. B. `GraphCanvas/GraphCanvasTuning.md`) damit UI & Perf‑Tuning nachvollziehbar bleibt.

---

## Open Questions (UNKNOWNs sammeln)
- **CloudKit DB‑Typ**: Ist `.automatic` immer private DB? Welche OS‑Cases führen zu Abweichungen? (**UNKNOWN**)
- **Entitlements**: Soll `aps-environment` für Release/TestFlight `production` sein? (aktuell `development`) (**UNKNOWN**)
- **Lock‑Felder in Entity/Attribute**: Werden `MetaEntity.lock*` und `MetaAttribute.lock*` jemals genutzt? Wenn nein: Modell‑Ballast + Migration‑Risiko. (**UNKNOWN**)
- **Sharing/Collaboration**: Gibt es geplante CloudKit Shares / Gruppen? Keine CKShare‑Codepfade gefunden. (**UNKNOWN**)
- **Attachment Größen/Limit**: Welche max. ByteCounts sind realistisch und wie verhält sich SwiftData externalStorage bei sehr großen Files? (**UNKNOWN**)
