# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine iOS-App (SwiftUI + SwiftData) für wissensbasierte Graphen: Du verwaltest **Graphen** (Workspaces), darin **Entitäten**, deren **Attribute**, und **Links** zwischen Nodes. Persistenz + Sync laufen über **SwiftData mit CloudKit (Private DB)**; lokale Disk-Caches materialisieren Bilder/Anhänge für schnelles Rendering.

- Plattform: iOS
- Mindest-iOS: **26.0** (aus `BrainMesh.xcodeproj/project.pbxproj` via `IPHONEOS_DEPLOYMENT_TARGET`)
- Bundle ID: `de.marcfechner.BrainMesh` (aus `BrainMesh.xcodeproj/project.pbxproj` via `PRODUCT_BUNDLE_IDENTIFIER`)

---

## Key Concepts / Domänenbegriffe

- **Graph (MetaGraph)**: Workspace / Wissensdatenbank. Optional geschützt (Biometrie/Passwort). (`BrainMesh/Models.swift`)
- **Entität (MetaEntity)**: „Ding“ im Graph, mit Name, Notes, optional Icon/Bild. Hat **Attribute** und **Detail-Feld-Definitionen**. (`BrainMesh/Models.swift`)
- **Attribut (MetaAttribute)**: Eigenschaft einer Entität; kann Notes, Icon/Bild, und **Detail-Feld-Werte** haben. (`BrainMesh/Models.swift`)
- **Link (MetaLink)**: Beziehung zwischen zwei Nodes (Entity/Attribute). Speichert IDs + *denormalisierte Labels* (`sourceLabel/targetLabel`) für schnelle Anzeige. (`BrainMesh/Models.swift`, `BrainMesh/Mainscreen/LinkCleanup.swift`)
- **Detail-Feld-Definition (MetaDetailFieldDefinition)**: „Schema“ frei konfigurierbarer Felder pro Entität (Typ, Sortierung, Pinning, Unit, Options). (`BrainMesh/Models.swift`)
- **Detail-Feld-Wert (MetaDetailFieldValue)**: konkrete Werte je Attribut/Feld, typed storage (String/Int/Double/Date/Bool). (`BrainMesh/Models.swift`)
- **Attachment (MetaAttachment)**: Dateien/Videos/Gallery-Images pro Owner (Entity/Attribute) – Owner wird via `(ownerKindRaw, ownerID)` referenziert (keine Relationship-Makros), `fileData` als `@Attribute(.externalStorage)`. (`BrainMesh/Attachments/MetaAttachment.swift`)
- **Graph Scoping (`graphID`)**: Fast alle Records tragen optional `graphID` (sanfte Migration: alte Records können `nil` sein). Migration/Bootstrapping: `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.

---

## Architecture Map

**UI (SwiftUI Views)**
- Root Tabs: `BrainMesh/ContentView.swift` → Tabs: Entities / Graph / Stats / Settings.
- Navigation pro Tab via `NavigationStack` + Sheets (z.B. Graph Picker, Inspector, Detail-Sheets).

**State / Coordinators (EnvironmentObject)**
- `AppearanceStore` (Theme/Look) → injected in `BrainMesh/BrainMeshApp.swift`.
- `DisplaySettingsStore` (Darstellung/Display options) → injected in `BrainMesh/BrainMeshApp.swift`.
- `OnboardingCoordinator` (Sheet Präsentation) → injected in `BrainMesh/BrainMeshApp.swift`.
- `GraphLockCoordinator` (Graph-Schutz / Unlock Flow) → injected in `BrainMesh/BrainMeshApp.swift`, UI in `BrainMesh/Security/*`.
- `SystemModalCoordinator` (verhindert Locks während system picker) → injected in `BrainMesh/BrainMeshApp.swift`, verwendet in `BrainMesh/AppRootView.swift`.

**Storage / Sync (SwiftData + CloudKit)**
- SwiftData Schema + Container in `BrainMesh/BrainMeshApp.swift`.
- CloudKit Config: `ModelConfiguration(schema:, cloudKitDatabase: .automatic)`; Release-Fallback auf local-only (Debug: `fatalError`). (`BrainMesh/BrainMeshApp.swift`)
- Sync-Diagnose/Status: `BrainMesh/Settings/SyncRuntime.swift` + UI in Settings.

**Off-main Loaders / Hydrators (Actors, value snapshots)**
- Regeln: *Keine SwiftData `@Model`-Objekte über Actor-Grenzen* → DTO/Snapshot-Structs.
- Entities Home Snapshot: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.
- Graph Canvas Snapshot (inkl. BFS-Neighborhood): `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`.
- Graph Stats Snapshot: `BrainMesh/Stats/GraphStatsLoader.swift` + `BrainMesh/Stats/GraphStatsService/*`.
- Attachments Hydration + Throttling (externalStorage → Disk Cache): `BrainMesh/Attachments/AttachmentHydrator.swift` (+ `AsyncLimiter` in `BrainMesh/Attachments/AttachmentThumbnailStore.swift`).
- Images Hydration: `BrainMesh/ImageHydrator.swift` (Disk cache via `BrainMesh/ImageStore.swift`).
- Media-All Loader (paged list, ohne `fileData` zu laden): `BrainMesh/Attachments/MediaAllLoader.swift`.

**Utilities / Cross-cutting**
- Search folding helper: `BMSearch.fold` (`BrainMesh/Models.swift`).
- Central AppStorage keys: `BrainMesh/Support/BMAppStorageKeys.swift`.
- Micro-logging/timing: `BrainMesh/Observability/BMObservability.swift`.

---

## Folder Map (Ordner → Zweck)

> Pfade relativ zu `BrainMesh/` (Target Sources liegen in `BrainMesh/BrainMesh/*`).

- `BrainMesh/` (Root): App Entry + Core Files (z.B. `BrainMeshApp.swift`, `ContentView.swift`, `Models.swift`, `GraphBootstrap.swift`).
- `BrainMesh/Attachments/`: Attachments (Model `MetaAttachment`, Import, Video-Compression, Preview, Thumbnailing, Hydrator, „Alle Medien“-Loader).
- `BrainMesh/GraphCanvas/`: Graph-Canvas UI (Physics/Rendering/Gestures) + `GraphCanvasDataLoader`.
- `BrainMesh/GraphPicker/` + `BrainMesh/GraphPickerSheet.swift`: Graph-Auswahl/Verwaltung (Rename/Delete/Dedupe/Security entry).
- `BrainMesh/ImportProgress/`: UI/State für Import-Fortschritt (**UNKNOWN**: genaue Rolle; nicht im Detail geprüft).
- `BrainMesh/Mainscreen/`: Haupt-UI außerhalb Canvas (EntitiesHome, EntityDetail, AttributeDetail, NodeDetailShared, Details-Schema, Bulk-Linking, etc.).
- `BrainMesh/Onboarding/`: Onboarding Sheets + Mini-Explainer.
- `BrainMesh/PhotoGallery/`: Gallery UI (Browsing/Viewer/Section).
- `BrainMesh/Security/`: Graph Locks (Biometrics/Password) + UI Flows.
- `BrainMesh/Settings/`: Settings Root + Subfolders:
  - `Settings/Appearance/`: AppearanceStore + Appearance UI.
  - `Settings/Display/`: DisplaySettingsStore + Display-Optionen (Listen/Row-Density etc.).
- `BrainMesh/Stats/`: Stats UI + Service + Loader.
- `BrainMesh/Support/`: Infrastruktur (AppStorage Keys, SystemModalCoordinator).

---

## Data Model Map (SwiftData)

> SwiftData-Models (Schema in `BrainMesh/BrainMeshApp.swift`, Implementierung in `BrainMesh/Models.swift` + `BrainMesh/Attachments/MetaAttachment.swift`).

### MetaGraph (`BrainMesh/Models.swift`)
- `id: UUID`
- `createdAt: Date`
- `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity (`BrainMesh/Models.swift`)
- `id: UUID`, `createdAt: Date`
- `graphID: UUID?` (scoping)
- `name`, `nameFolded`, `notes`
- Icon/Bild: `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes: [MetaAttribute]?` (cascade, inverse `\MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (cascade, inverse `\MetaDetailFieldDefinition.owner`)

### MetaAttribute (`BrainMesh/Models.swift`)
- `id: UUID`, `graphID: UUID?`
- `name`, `nameFolded`, `notes`
- Icon/Bild: `iconSymbolName`, `imageData`, `imagePath`
- Owner: `owner: MetaEntity?` (inverse kommt von Entity)
- `searchLabelFolded` (z.B. „Entity · Attribut“)
- Relationship:
  - `detailValues: [MetaDetailFieldValue]?` (cascade, inverse `\MetaDetailFieldValue.attribute`)

### MetaLink (`BrainMesh/Models.swift`)
- `id`, `createdAt`, `graphID: UUID?`
- Denormalisierte Labels: `sourceLabel`, `targetLabel`
- Endpoints:
  - `sourceKindRaw`, `sourceID`
  - `targetKindRaw`, `targetID`
- Optional: `note`

### MetaDetailFieldDefinition (`BrainMesh/Models.swift`)
- `id`, `graphID: UUID?`, `entityID: UUID`
- `name`, `nameFolded`
- `typeRaw` (`DetailFieldType`), `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- Relationship:
  - `owner: MetaEntity?` (`@Relationship(deleteRule: .nullify, originalName: "entity")`)

### MetaDetailFieldValue (`BrainMesh/Models.swift`)
- `id`, `graphID: UUID?`, `attributeID`, `fieldID`
- Typed storage: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
- Owner: `attribute: MetaAttribute?`

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- `id`, `createdAt`, `graphID: UUID?`
- Owner reference: `ownerKindRaw`, `ownerID`
- Type: `contentKindRaw` (`file` / `video` / `galleryImage`)
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Data: `fileData: Data?` via `@Attribute(.externalStorage)`
- Local cache pointer: `localPath: String?`

---

## Sync / Storage

### SwiftData + CloudKit
- Container setup: `BrainMesh/BrainMeshApp.swift`
  - Schema list: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`.
  - CloudKit: `ModelConfiguration(..., cloudKitDatabase: .automatic)`.
  - Release fallback: Wenn CloudKit init fehlschlägt → lokal-only Container.

**iCloud Entitlements**
- `BrainMesh/BrainMesh.entitlements`:
  - `com.apple.developer.icloud-container-identifiers`: `iCloud.de.marcfechner.BrainMesh`
  - `com.apple.developer.icloud-services`: `CloudKit`

**Runtime Sync Diagnostics**
- `BrainMesh/Settings/SyncRuntime.swift`:
  - `storageMode` (`cloudKit` vs `localOnly`) wird beim Container-Setup gesetzt.
  - iCloud account status via `CKContainer.accountStatus()`.

### Lokale Caches (Application Support)
- Images: `BrainMesh/ImageStore.swift` → Folder `BrainMeshImages`.
- Attachments: `BrainMesh/Attachments/AttachmentStore.swift` → Folder `BrainMeshAttachments`.
- Thumbnails (**UNKNOWN**: exakter Foldername/Ort) → siehe `BrainMesh/Attachments/AttachmentThumbnailStore.swift`.

### Offline-Verhalten
- **UNKNOWN**: Explizite Offline-Strategie/Conflict-Resolution ist nicht im Code implementiert; es wird primär auf SwiftData/CloudKit-Standardverhalten gesetzt.

---

## UI Map (Hauptscreens + Navigation)

### Root Tabs (`BrainMesh/ContentView.swift`)
- **Entitäten**: `EntitiesHomeView` (NavigationStack intern)
- **Graph**: `GraphCanvasScreen` (NavigationStack intern)
- **Stats**: `GraphStatsView`
- **Einstellungen**: `SettingsView` in eigenem `NavigationStack`

### Entities Home (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
- List/Grid Rendering via:
  - `EntitiesHomeList.swift`, `EntitiesHomeGrid.swift` (UI)
  - Daten: `EntitiesHomeLoader.shared.loadSnapshot(...)` (off-main; value DTOs)
- Wichtige Sheets:
  - `EntitiesHomeDisplaySheet` (`.sheet(isPresented:)`)
  - `GraphPickerSheet` (`.sheet(isPresented:)`)
  - `AddEntityView` (`.sheet(isPresented:)`)
- Detail Navigation:
  - `NavigationLink → EntityDetailRouteView(entityID:)` (resolves model via `@Query`).

### Entity/Attribute Detail
- Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` + Split files (z.B. `EntityDetailView+AttributesSection.swift`).
- Attribute: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`.
- Shared detail components: `BrainMesh/Mainscreen/NodeDetailShared/*`.

### Graph Canvas (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift`)
- Data load off-main: `GraphCanvasDataLoader.shared.loadSnapshot(...)`.
- Rendering/Physics/Gestures split:
  - `GraphCanvasView.swift` + `GraphCanvasView+Physics.swift`, `+Gestures.swift`, `+Camera.swift`, `+Rendering.swift`.
- Inspector UI: `GraphCanvasScreen+Inspector.swift` (Sheet).
- Graph Picker: `GraphPickerSheet` (Sheet).
- Detail sheets: `EntityDetailView` / `AttributeDetailView` als `sheet(item:)`.

### Stats (`BrainMesh/Stats/*`)
- UI: `GraphStatsView` + Components in `StatsComponents/`.
- Data load off-main: `GraphStatsLoader.shared.loadSnapshot(...)`.
- Heavy queries: `GraphStatsService/*`.

### Settings (`BrainMesh/Settings/SettingsView.swift`)
- Sync diagnostics + Cache maintenance + Import prefs + Appearance/Display.
- Onboarding Intro Sheet: `DetailsOnboardingSheetView`.

### Security (Graph Locks)
- Coordinator: `BrainMesh/Security/GraphLockCoordinator.swift`.
- UI: `GraphSecuritySheet.swift`, `GraphUnlockView.swift`, `GraphSetPasswordView.swift`.
- FaceID usage declared: `BrainMesh/Info.plist` (`NSFaceIDUsageDescription`).

---

## Build & Configuration

- Xcode Project: `BrainMesh/BrainMesh.xcodeproj`
- Targets:
  - App: `BrainMesh` (iOS 26.0)
  - Tests: `BrainMeshTests` (Swift Testing, `BrainMeshTests/BrainMeshTests.swift`)
  - UI Tests: `BrainMeshUITests/*`
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit container)
- Info.plist: `BrainMesh/Info.plist`
  - `NSFaceIDUsageDescription`
  - `UIBackgroundModes: [remote-notification]` (für CloudKit push / background sync)
- Concurrency Build Settings (aus `project.pbxproj`):
  - `SWIFT_APPROACHABLE_CONCURRENCY = YES`
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

**Secrets-Handling**
- **UNKNOWN**: Keine `.xcconfig` / Secrets-Dateien im ZIP gefunden; wenn extern vorhanden, hier ergänzen.

---

## Conventions (Naming, Patterns, Do/Don’t)

### Datenzugriff & Concurrency
- ✅ Do: Für „große Listen / heavy fetch“ → Actor-Loader bauen, *value-only* Snapshots zurückgeben.
  - Beispiele: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `MediaAllLoader`.
- ❌ Don’t: SwiftData `@Model`-Instanzen über Actor-/Task-Grenzen reichen.
  - Pattern in Code: Kommentare in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.
- ✅ Do: In Loaders `Task.checkCancellation()` / `Task.isCancelled` nutzen (z.B. `EntitiesHomeLoader`, `GraphCanvasDataLoader`).
- ✅ Do: Disk I/O off-main (z.B. `ImageStore.saveJPEGAsync`, `AttachmentHydrator.ensureFileURL`).

### Search/Sorting
- `BMSearch.fold` für case-/diacritic-insensitive Suche.
- `nameFolded`/`searchLabelFolded` in didSet aktuell halten (`BrainMesh/Models.swift`).

### AppStorage
- Keys zentral in `BrainMesh/Support/BMAppStorageKeys.swift`.

---

## How to work on this project (Setup + Einstieg)

### Setup Steps
1) Xcode öffnen: `BrainMesh/BrainMesh.xcodeproj`
2) Signing anpassen (Team auswählen) für Target `BrainMesh`.
3) Capability iCloud/CloudKit muss zur Entitlements-Datei passen:
   - iCloud Container: `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`, `BrainMesh/Settings/SyncRuntime.swift`).
4) Run auf einem Gerät/Simulator mit iOS 26.0.

### Wo anfangen (für neue Devs)
- Entry + Container + EnvObjects: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`
- Datenmodell: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Loader/Hot paths:
  - Entities Home: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` + `GraphCanvasView+Rendering.swift`
  - Stats: `BrainMesh/Stats/GraphStatsLoader.swift` + `GraphStatsService/*`

### Feature hinzufügen (typischer Flow)
- Neues SwiftData Model?
  - `@Model` anlegen → **Schema in `BrainMesh/BrainMeshApp.swift` ergänzen**.
  - Migration/Defaults beachten (z.B. `createdAt = .distantPast`, `graphID` optional).
- Neue Screen/Flow?
  - Tab? → `BrainMesh/ContentView.swift`
  - Sheet/Route? → in jeweiligem Screen (z.B. `EntitiesHomeView`, `GraphCanvasScreen`).
- Heavy data?
  - Loader als `actor` + DTO bauen; UI navigiert über IDs und resolved im Main `ModelContext`.

---

## Quick Wins (max. 10, konkret)

1) **Pinned Values Lookup graph-scope**: `EntityAttributesAllListModel.fetchPinnedValuesLookup(...)` filtert aktuell nur nach `fieldID` (kein `graphID`). Prüfen, ob `graphID` als zusätzlicher AND-Filter möglich ist. Datei: `BrainMesh/Mainscreen/EntityDetail/EntityAttributesAllListModel.swift`.
2) **EntitiesHome counts TTL tunen**: `countsCacheTTLSeconds = 8` ist konservativ. Für große Graphen könnte 15–30s die Typing-Experience verbessern. Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.
3) **GraphCanvas maxNodes/maxLinks UI gating**: Klarere Defaults + Warnhinweis im Inspector, dass hohe Werte FPS drücken. Dateien: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`, `GraphCanvasScreen+Inspector.swift`.
4) **Thumbnail folder visibility**: In Settings Cache Maintenance zusätzlich Thumbnail-Cache-Größe anzeigen/clear. Dateien: `BrainMesh/Settings/SettingsView.swift`, `BrainMesh/Attachments/AttachmentThumbnailStore.swift`.
5) **Remove wholemodule in Release?** Falls Buildzeiten wichtiger als Runtime, prüfen ob `SWIFT_COMPILATION_MODE = wholemodule` in Release nötig ist. Datei: `BrainMesh.xcodeproj/project.pbxproj`.
6) **Link label consistency**: Sicherstellen, dass Rename flows `NodeRenameService` immer aufrufen (bei allen Rename UI Pfaden). Datei: `BrainMesh/Mainscreen/LinkCleanup.swift` + Rename UI Dateien (**UNKNOWN**: nicht alle Rename Call-Sites geprüft).
7) **Attachment graphID Migration Hook Coverage**: `AttachmentGraphIDMigration` wird in MediaAllLoader verwendet. Prüfen, ob auch Detail-Views die Migration früh genug triggern. Dateien: `BrainMesh/Attachments/MediaAllLoader.swift`, `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
8) **Logging knobs**: BMLog Kategorien nutzen/vereinheitlichen für Loader Durations (Start/Stop). Datei: `BrainMesh/Observability/BMObservability.swift`.
9) **Test scaffold**: Ein minimaler Snapshot-Test für `BMSearch.fold` + Sortmode (Entity/Attribute) anlegen. Datei: `BrainMeshTests/BrainMeshTests.swift`.
10) **Docs in-app**: Help/Support Section in Settings verlinkt? (**UNKNOWN**: helpSection Inhalt nicht geprüft). Datei: `BrainMesh/Settings/SettingsView.swift`.

---

## Open Questions (UNKNOWNs)

- **ImportProgress**: Welche konkreten Flows/States werden dort gepflegt? (`BrainMesh/ImportProgress/*`)
- **Thumbnail Cache**: Wo genau liegt der Thumbnail-Cache (Foldername/Policy) und wie wird er invalidiert? (`BrainMesh/Attachments/AttachmentThumbnailStore.swift`)
- **Offline/Conflict**: Gibt es erwartete Conflict-Resolution Regeln über SwiftData/CloudKit hinaus? (kein expliziter Code gefunden)
- **Help/Support UX**: Welche URLs/Support-Kanäle sollen Settings anbieten? (`BrainMesh/Settings/SettingsView.swift`)
- **Secrets**: Gibt es externe Konfig (xcconfig/Secrets) außerhalb des ZIP? (im ZIP nicht gefunden)
