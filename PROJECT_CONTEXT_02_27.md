# PROJECT_CONTEXT

## TL;DR
BrainMesh ist eine iOS-App (SwiftUI) zur Verwaltung von Wissen als Graph aus **Entitäten**, **Attributen** und **Links**. Persistenz läuft über **SwiftData** mit **CloudKit**-Konfiguration (Fallback auf lokal-only in Release) und einem graph-scoped Datenmodell (via `graphID`). Deployment Target laut Xcode-Projekt: **iOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj`, `IPHONEOS_DEPLOYMENT_TARGET`).

## Key Concepts / Domänenbegriffe
- **Graph / Workspace** (`MetaGraph`, `BrainMesh/Models/MetaGraph.swift`)
  - Container für Daten-Scope + optionaler Zugriffsschutz (Biometrie/Passwort).
- **Entität** (`MetaEntity`, `BrainMesh/Models/MetaEntity.swift`)
  - „Hauptknoten“; besitzt Attribute, Notizen, Icon, Bild.
- **Attribut** (`MetaAttribute`, `BrainMesh/Models/MetaAttribute.swift`)
  - Gehört optional zu einer Entität (`owner`), hat eigene Notizen/Bild und Detail-Werte.
- **Link** (`MetaLink`, `BrainMesh/Models/MetaLink.swift`)
  - Verbindet zwei Knoten über IDs + NodeKind (keine SwiftData-Relationships; arbeitet mit `sourceID/targetID`).
- **Attachment** (`MetaAttachment`, `BrainMesh/Attachments/MetaAttachment.swift`)
  - Dateien/Medien; `fileData` ist als `@Attribute(.externalStorage)` gespeichert.
- **Details-Schema** (`MetaDetailFieldDefinition`, `BrainMesh/Models/DetailsModels.swift`)
  - Konfigurierbare Felder pro Entität (Schema) + Werte pro Attribut.
- **Details-Templates („Meine Sets“)**
  - User-saved Schema-Vorlagen (`MetaDetailsTemplate`, `BrainMesh/Models/MetaDetailsTemplate.swift`).
- **Folded Search Indizes**
  - `BMSearch.fold` normalisiert Strings für Suche (z.B. `nameFolded`, `notesFolded`, `noteFolded`).

## Architecture Map (Layer / Verantwortlichkeiten / Abhängigkeiten)
- **App & Composition Root**
  - `BrainMesh/BrainMeshApp.swift`: erstellt `ModelContainer` + injiziert EnvironmentObjects.
  - `BrainMesh/AppRootView.swift`: App-Lifecycle (ScenePhase), Startup-Migration, Auto-Lock, Auto-Hydration.
- **Domain / Storage (SwiftData Models)**
  - `BrainMesh/Models/*`, `BrainMesh/Attachments/MetaAttachment.swift`
- **Loaders / Services (off-main Fetch, Snapshot-DTOs)**
  - Loader-Actors erzeugen eigene `ModelContext`-Instanzen aus `AnyModelContainer` (`BrainMesh/Support/AnyModelContainer.swift`).
  - Beispiele:
    - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
    - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
    - `BrainMesh/Stats/GraphStatsLoader.swift`
- **UI (SwiftUI)**
  - Root Tabs: `BrainMesh/ContentView.swift`
  - Hauptscreens: `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Stats/*`, `BrainMesh/Settings/*`
- **Coordinators / Routing**
  - Tab-Routing: `BrainMesh/RootTabRouter.swift`
  - Graph-Jumps: `BrainMesh/GraphJumpCoordinator.swift`
  - Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
  - Graph-Security: `BrainMesh/Security/*` (z.B. `GraphLockCoordinator`, Unlock-Sheets)
- **Observability**
  - `BrainMesh/Observability/BMObservability.swift` (os.Logger Kategorien + Timing Helper)
- **Abhängigkeiten**
  - Keine externen SPM Packages im `.pbxproj` gefunden (**UNKNOWN**, falls Abhängigkeiten außerhalb dieses ZIPs existieren).

## Folder Map (Ordner → Zweck)
- `BrainMesh/Attachments/` — Attachment Modelle + Import/Compression + Hydration + Thumbnails. (20 Swift-Dateien)
- `BrainMesh/GraphCanvas/` — Graph-Tab: Screen, DataLoader (SwiftData Fetch off-main), Canvas Rendering + Physics. (23 Swift-Dateien)
- `BrainMesh/GraphPicker/` — UI-Komponenten für Graph-Auswahl/Management (Sheet verwendet GraphPickerSheet.swift). (6 Swift-Dateien)
- `BrainMesh/Icons/` — SF Symbol Picker / Icon selection UI. (6 Swift-Dateien)
- `BrainMesh/Images/` — Bundled image resources/helpers (wenig Code). (1 Swift-Dateien)
- `BrainMesh/ImportProgress/` — UI für Import-Fortschritt (z.B. Bilder/Videos). (2 Swift-Dateien)
- `BrainMesh/Mainscreen/` — Haupt-UI: Entities Home, Entity/Attribute Detail, Link/Picker Flows, Details-Schema UI. (115 Swift-Dateien)
- `BrainMesh/Models/` — SwiftData `@Model` entities + search helpers (z.B. BMSearch.fold). (9 Swift-Dateien)
- `BrainMesh/Observability/` — os.Logger Wrapper + Timing helpers. (1 Swift-Dateien)
- `BrainMesh/Onboarding/` — Onboarding Coordinator + Sheets. (12 Swift-Dateien)
- `BrainMesh/PhotoGallery/` — UI/Logic für Gallery-Ansichten außerhalb des GraphCanvas. (9 Swift-Dateien)
- `BrainMesh/Security/` — Graph-Schutz (Biometrie/Passwort): Coordinator, Unlock-Sheets, Crypto. (13 Swift-Dateien)
- `BrainMesh/Settings/` — Settings-Tab: Hub + Sektionen (Appearance, Import, Sync & Wartung, Help/Info/About). (42 Swift-Dateien)
- `BrainMesh/Stats/` — Stats-Tab: Loader + Services (fetchCount) + Views. (22 Swift-Dateien)
- `BrainMesh/Support/` — Shared infra (AnyModelContainer, Loader-Konfiguration, Indizes/Completion). (10 Swift-Dateien)

Zusätzlich wichtige Root-Dateien:
- `BrainMesh/ContentView.swift` — TabView Root (Entitäten / Graph / Stats / Einstellungen)
- `BrainMesh/GraphBootstrap.swift` — One-time Migration + Backfills (graphID, folded notes)
- `BrainMesh/GraphPickerSheet.swift` — Graph-Switch/Management Sheet Routing
- `BrainMesh/ImageStore.swift` + `BrainMesh/ImageHydrator.swift` — Bildcache/Hydration

## Data Model Map (Entities, Relationships, wichtige Felder)
### `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`)
- Wichtige Felder: `id`, `createdAt`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64/passwordHashB64/passwordIterations`

### `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`)
- Scope/Search: `graphID`, `name/nameFolded`, `notes/notesFolded`
- Media: `imageData` (CloudKit-sync), `imagePath` (lokaler Cache), `iconSymbolName`
- Security: analog zu `MetaGraph`
- Relationships:
  - `attributes: [MetaAttribute]?` (cascade, inverse: `MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (cascade, inverse: `MetaDetailFieldDefinition.owner`)

### `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`)
- Scope/Search: `graphID`, `name/nameFolded`, `notes/notesFolded`, `searchLabelFolded`
- Owner: `owner: MetaEntity?` (Inverse ist auf Entity-Seite definiert)
- Media: `imageData`, `imagePath`, `iconSymbolName`
- Relationships:
  - `detailValues: [MetaDetailFieldValue]?` (cascade, inverse: `MetaDetailFieldValue.attribute`)

### `MetaLink` (`BrainMesh/Models/MetaLink.swift`)
- Scope/Search: `graphID`, `note/noteFolded`
- Endpoints (Scalar): `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
- Keine SwiftData-Relationships (Link-Auflösung erfolgt über IDs / NodeKind).

### `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- Scope: `graphID`, `ownerKindRaw/ownerID`
- Content: `contentKindRaw`, `title`, `originalFilename`, `contentTypeIdentifier`, `byteCount`
- Storage:
  - `@Attribute(.externalStorage) var fileData: Data?` (große Blobs)
  - `localPath: String?` (lokaler Pfad)

### Details (Schema + Werte) (`BrainMesh/Models/DetailsModels.swift`)
- `MetaDetailFieldDefinition`
  - Scope/Search: `graphID`, `entityID`, `name/nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Relationship: `owner: MetaEntity?`
- `MetaDetailFieldValue`
  - Scope: `graphID`, `attributeID`, `fieldID`
  - Value Union: `stringValue/intValue/doubleValue/dateValue/boolValue`
  - Relationship: `attribute: MetaAttribute?`

### `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`)
- Scope/Search: `graphID`, `name/nameFolded`, `fieldsJSON` (JSON Array von FieldDefs)

## Sync/Storage
### SwiftData + CloudKit Konfiguration
- `BrainMesh/BrainMeshApp.swift`
  - `Schema([...])` enthält: MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment, MetaDetailFieldDefinition, MetaDetailFieldValue, MetaDetailsTemplate
  - CloudKit: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - Fehlerpfad:
    - **DEBUG**: `fatalError` bei CloudKit-Container-Fehlern (kein Fallback).
    - **RELEASE**: Fallback auf `ModelConfiguration(schema: schema)` (lokal-only), plus `SyncRuntime.shared.setStorageMode(.localOnly)`.
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - Service: CloudKit
  - `aps-environment = development` (Push für CloudKit / remote-notification)

### Sync-Status in UI
- `BrainMesh/Settings/SyncRuntime.swift`: `CKContainer.accountStatus()` -> Status-Text für Settings.
- `BrainMesh/Settings/SettingsView+SyncSection.swift` und `BrainMesh/Settings/SyncMaintenanceView.swift`: UI/Actions rund um Sync & Wartung (**Details siehe ARCHITECTURE_NOTES**).

### Caches / Local Storage
- `BrainMesh/ImageStore.swift`: Memory (NSCache) + Disk (Application Support/BrainMeshImages); Hinweis im Code: synchrone Loads nicht im SwiftUI `body`.
- `MetaAttachment.fileData` ist externalStorage (SwiftData speichert Blobs außerhalb der Haupt-SQLite).

### Migration / Backfills
- `BrainMesh/GraphBootstrap.swift`
  - `ensureAtLeastOneGraph(using:)` (Graph initialisieren)
  - `migrateLegacyRecordsIfNeeded(defaultGraphID:using:)` (setzt fehlende `graphID`)
  - `backfillFoldedNotesIfNeeded(using:)` (füllt `notesFolded`/`noteFolded`, falls nötig)
- Attachments Sonderfall:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` beschreibt explizit das Risiko, dass Prädikate wie `(gid == nil || a.graphID == gid)` in-memory Filtering auslösen können (fatal bei externalStorage-Blobs).

### Offline-Verhalten
- Lokale Persistenz ist immer vorhanden (SwiftData Store). CloudKit-Sync-Verhalten ist **Apple-Standard**; keine eigene Offline-Queue / Retry-Layer im Code gefunden.

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMesh/BrainMeshApp.swift` → `AppRootView` → `ContentView` (Tabs)
- Tabs (`BrainMesh/ContentView.swift`):
  - **Entitäten**: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (NavigationStack)
  - **Graph**: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - **Stats**: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - **Einstellungen**: `BrainMesh/Settings/SettingsView.swift` (in NavigationStack)
  - Hub/Sections (Auswahl):
    - `BrainMesh/Settings/SettingsView+AppearanceSection.swift`
    - `BrainMesh/Settings/SettingsView+ImportSection.swift`
    - `BrainMesh/Settings/SettingsView+SyncSection.swift`
    - `BrainMesh/Settings/SettingsView+MaintenanceSection.swift`
    - `BrainMesh/Settings/SettingsView+HelpSection.swift`
    - `BrainMesh/Settings/SettingsView+InfoSection.swift`

### Wichtige Flows
- Graph wechseln / verwalten: `BrainMesh/GraphPickerSheet.swift` (+ UI in `BrainMesh/GraphPicker/`)
- Entität/Attribut Details:
  - Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (+ Extensions)
  - Attribute: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` (+ Extensions)
  - Shared Detail UI: `BrainMesh/Mainscreen/NodeDetailShared/*`
- Links:
  - Einzel-Link erstellen: `BrainMesh/Mainscreen/AddLinkView.swift`
  - Bulk-Link: `BrainMesh/Mainscreen/BulkLinkView.swift` + `BrainMesh/Mainscreen/BulkLinkLoader.swift`
- Details-Schema Builder / Values:
  - Values Card: `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - Templates: `BrainMesh/Models/MetaDetailsTemplate.swift` + UI in `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaBuilderView.swift`
- Attachments/Media:
  - Import Pipeline: `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - Manage Views: `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`, `.../NodeAttachmentsManageView*`
- Graph Security:
  - Sheets/Unlock: `BrainMesh/Security/GraphUnlock/*`, `BrainMesh/Security/GraphLock/*`, `BrainMesh/Security/GraphSecuritySheet.swift`


## Hotspots at a glance (nur Orientierung)
- GraphCanvas Simulation: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift` (Timer + O(n²) Repulsion).
- Stats Loader Concurrency: `BrainMesh/Stats/GraphStatsLoader.swift` (`Task.detached` im Loop).
- Startup Migration: `BrainMesh/GraphBootstrap.swift` (fetch+loop+save, MainActor).
- Attachment Queries: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (in-memory filtering + externalStorage Risiko).

## Größte Dateien (Top 5 nach Zeilen)
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 Zeilen**
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **474 Zeilen**
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **442 Zeilen**
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 Zeilen**
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388 Zeilen**

## Build & Configuration
- Xcode Projekt: `BrainMesh.xcodeproj`
  - Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests` (Bundle IDs im `.pbxproj`: de.marcfechner.BrainMesh*)
  - Bundle ID: `de.marcfechner.BrainMesh`
  - Deployment Target: iOS 26.0
  - SDKROOT: `iphoneos`
- `BrainMesh/Info.plist`
  - `UIBackgroundModes`: ['remote-notification']
  - `NSFaceIDUsageDescription`: `BrainMesh nutzt Face ID / Touch ID, um geschützte Graphen zu entsperren.`
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit + Push)
- Dependencies:
  - Keine `XCRemoteSwiftPackageReference` Einträge im `.pbxproj` gefunden (=> keine SPM Packages im Projektfile). **UNKNOWN**, falls Packages über einen Workspace außerhalb dieses ZIPs eingebunden werden.

## Conventions (Naming, Patterns, Do/Don’t)
- **Graph scoping**: Viele Modelle tragen `graphID` (nullable für „soft migration“). Neue Queries sollten graph-scope berücksichtigen.
- **Search Indizes**: Felder wie `nameFolded`, `notesFolded`, `noteFolded` via `BMSearch.fold` in `didSet` synchron halten.
- **SwiftData-Concurrency**:
  - Keine `@Model` Objekte über Concurrency-Grenzen reichen; stattdessen Snapshot-DTOs (z.B. `EntitiesHomeRow`, `GraphCanvasSnapshot`).
  - Background Fetches laufen über Loader-Actors + `ModelContext(AnyModelContainer.container)`.
- **Datei-Splitting**: Viele Views sind per `+` Extensions in Unterdateien gesplittet (z.B. `AttributeDetailView+*.swift`).
- **Do/Don’t**
  - **Don’t**: Synchrone Disk-Loads in SwiftUI `body` (Hinweis in `BrainMesh/ImageStore.swift`).
  - **Do**: `Task.checkCancellation()` in langen Loader-Loops (z.B. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`).

## How to work on this project (Setup Steps + wo anfangen)
1. Xcode öffnen: `BrainMesh.xcodeproj`.
2. Signing/Capabilities prüfen:
   - iCloud/CloudKit Container `iCloud.de.marcfechner.BrainMesh` aktivieren (`BrainMesh/BrainMesh.entitlements`).
   - Push Notifications/Background Modes (remote-notification) passend signieren.
3. Erste Runs:
   - DEBUG: CloudKit-Init kann `fatalError` auslösen (`BrainMesh/BrainMeshApp.swift`).
   - Settings → „Sync & Wartung“ checken: iCloud Account Status (`BrainMesh/Settings/SyncRuntime.swift`).
4. Neue Features:
   - UI-Flow im passenden Tab/Screen starten (meist `Mainscreen/*` oder `GraphCanvas/*`).
   - Wenn Datenlastig: erst Loader/Service schreiben (Snapshot) und erst dann View anbinden.
   - Graph-scope & folded Search Indizes mitdenken.


## Key Files (schneller Einstieg)
- App Entry:
  - `BrainMesh/BrainMeshApp.swift` — ModelContainer + EnvironmentObjects + Loader-Konfiguration
  - `BrainMesh/AppRootView.swift` — ScenePhase Handling + Startup Tasks
  - `BrainMesh/ContentView.swift` — TabView Root
- Storage/Migration:
  - `BrainMesh/GraphBootstrap.swift` — graphID Migration + folded notes Backfill
  - `BrainMesh/Settings/SyncRuntime.swift` — iCloud Account Status
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` — Attachment graphID Migration Strategy
- Graph:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Entities/Details:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
- Attachments/Media:
  - `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
- Settings:
  - `BrainMesh/Settings/SettingsView.swift` + `SettingsView+*Section.swift`
- Logging:
  - `BrainMesh/Observability/BMObservability.swift`

## Typische Workflows (wie fügt man ein Feature hinzu)
### 1) Neues persistentes Feld / neue Entity
Checklist:
- [ ] Model in `BrainMesh/Models/*` (oder `BrainMesh/Attachments/*`) erweitern (`@Model` / stored properties).
- [ ] Falls Suchfeld: `*Folded` Feld + `didSet` mit `BMSearch.fold` (siehe `MetaEntity`, `MetaLink`).
- [ ] Graph-Scope: `graphID` Verhalten definieren (nullable für Migration?).
- [ ] Migration/Backfill prüfen:
  - `BrainMesh/GraphBootstrap.swift` (Legacy graphID, folded notes)
  - ggf. eigene Migration analog zu `AttachmentGraphIDMigration.swift`
- [ ] UI aktualisieren (Query/Loader/Forms) + Tests (**UNKNOWN** Teststrategie).

### 2) Daten-intensiver Screen (Performance)
Checklist:
- [ ] Loader/Service schreiben (actor, Snapshot DTOs, eigener `ModelContext`, `autosaveEnabled = false`).
  - Referenz: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- [ ] In View nur Snapshot/IDs halten; echte `@Model` Objekte im Main-Context auflösen.
- [ ] Cancellation:
  - `Task.checkCancellation()` in Loops
  - Keine `Task.detached` ohne stale-guard (siehe `GraphStatsLoader` als Audit-Kandidat)
- [ ] Logging (Duration) via `BMLog`/`BMDuration`.

### 3) Neue Sheet-/Navigation-Route
Checklist:
- [ ] Route an der passenden Stelle definieren (meist Root-Screen des Tabs).
- [ ] State minimal halten; schwere Subviews in eigene Dateien/Typen.
- [ ] Dismiss + Graph/Tab „Jumps“ ggf. über `RootTabRouter`/`GraphJumpCoordinator`.


## Quick Wins (max. 10, konkret, umsetzbar)
1. **Task.detached Audit & Cancellation/„stale result“ Guards**: z.B. `BrainMesh/Stats/GraphStatsLoader.swift` nutzt `Task.detached` in einem Loop über GraphIDs.
2. **Startup-Migration off-main / batching**: `BrainMesh/GraphBootstrap.swift` fetch+loop+save kann bei großen Datenmengen den Launch blockieren (MainActor).
3. **ExternalStorage Query Hygiene**: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` zeigt das in-memory Filtering Risiko; konsequent einfache AND-Predicates nutzen.
4. **GraphCanvas Physics Tuning**: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift` enthält O(n²) Repulsion (i/j nested loops) + 30Hz Timer.
5. **EntitiesHome Counts Caching**: TTL (8s) in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` ggf. event-driven invalidieren (statt zeitbasiert) für weniger Re-Fetches beim Tippen.
6. **Reduce God-View Surface**: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (474 Zeilen) weiter in State/Actions/Overlays splitten.
7. **Stats Counting**: `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift` ist bereits `fetchCount`-basiert; prüfen, ob weitere Stats Views noch full-fetches machen (**UNKNOWN** ohne weitere Stats-Views auszuwerten).
8. **Observability konsistent nutzen**: `BrainMesh/Observability/BMObservability.swift` überall in Loader-Hotpaths verwenden (Durations + cancellation reason).
9. **Image Hydration Triggering**: `BrainMesh/AppRootView.swift` führt foreground work aus; prüfen, ob Throttle ausreichend ist (siehe `BMAppStorageKeys.imageHydratorLastAutoRun`).
10. **SwiftData Autosave**: Loader-Kontexte setzen `autosaveEnabled = false` (z.B. GraphCanvasDataLoader). Sicherstellen, dass UI-Kontexte nicht unnötig viele Saves triggern (Pattern check).

