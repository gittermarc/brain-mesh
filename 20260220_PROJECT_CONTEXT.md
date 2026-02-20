# PROJECT_CONTEXT — BrainMesh

## TL;DR
BrainMesh ist eine iOS/iPadOS-App (SwiftUI) für graph-basiertes Wissensmanagement: **Graphen** (Workspaces) enthalten **Entitäten**, deren **Attribute** und **Links** zwischen Nodes; dazu kommen **Medien/Anhänge** und konfigurierbare **Detail-Felder**. Persistenz + Sync laufen über **SwiftData + CloudKit** (private DB, `.automatic`) in `BrainMesh/BrainMeshApp.swift`. Mindest-iOS laut Xcode-Projekt: **iOS 26.0**.

---

## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph)**: Workspace / “Wissensdatenbank”. Umschaltbar via GraphPicker (`BrainMesh/GraphPickerSheet.swift`).
- **Entität (MetaEntity)**: Node-Typ 1; besitzt **Attribute** und optional ein **Main-Bild** (JPEG klein).
- **Attribut (MetaAttribute)**: Node-Typ 2; gehört optional zu einer Entität (`owner`), hat Notizen, optional Icon + Main-Bild.
- **Link (MetaLink)**: Kante zwischen zwei Nodes (Entity/Attribute). Speichert **denormalisierte Labels** (`sourceLabel/targetLabel`) für schnelles Rendering (siehe `BrainMesh/Models.swift`, `BrainMesh/Mainscreen/LinkCleanup.swift`).
- **Attachment (MetaAttachment)**: Datei/Video/Gallery-Image “hängt” an Entity/Attribute; Ownership ist `(ownerKindRaw, ownerID)` ohne SwiftData-Relationships (bewusst, um Macro-Zirkularität zu vermeiden). Bytes werden als `@Attribute(.externalStorage)` gespeichert (`BrainMesh/Attachments/MetaAttachment.swift`).
- **Details-Felder**: Pro Entität definierbares Schema (`MetaDetailFieldDefinition`) + pro Attribut gespeicherte Werte (`MetaDetailFieldValue`). UI-Builder: `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`.
- **Graph Scope (`graphID`)**: Fast alle Records sind optional graph-scoped (`UUID?`). `nil` ist “Legacy/unscope”; es gibt Migration/Bootstrap (`BrainMesh/GraphBootstrap.swift`).

---

## Architecture Map (Layer / Verantwortlichkeiten / Abhängigkeiten)
Text-Diagramm (von oben nach unten):

- **UI (SwiftUI Views)**
  - Root: `BrainMesh/BrainMeshApp.swift` → `AppRootView` → `ContentView`
  - Tabs: Entities (`EntitiesHomeView`), Graph (`GraphCanvasScreen`), Stats (`GraphStatsView`), Settings (`SettingsView`)
  - Detail-/Sheet-Flows: `Mainscreen/*`, `GraphPicker/*`, `PhotoGallery/*`, `Security/*`
  - Abhängigkeiten: `@Environment(\.modelContext)`, `@Query`, `@AppStorage`, `EnvironmentObject` (Appearance/Onboarding/GraphLock/SystemModals)

- **UI-Coordinators (MainActor)**
  - `GraphLockCoordinator` (FaceID/Password Unlock) — `BrainMesh/Security/GraphLockCoordinator.swift`
  - `OnboardingCoordinator` — `BrainMesh/Onboarding/OnboardingCoordinator.swift`
  - `SystemModalCoordinator` (verhindert “Lock while Photos picker open”) — `BrainMesh/Support/SystemModalCoordinator.swift`

- **Loaders / Hydrators (Actors + off-main SwiftData fetch)**
  - Konfiguriert beim App-Start in `BrainMesh/BrainMeshApp.swift` via `AnyModelContainer` + `Task.detached`.
  - Loader-Snapshots für UI:
    - `EntitiesHomeLoader` — `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
    - `GraphCanvasDataLoader` — `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
    - `GraphStatsLoader` — `BrainMesh/Stats/GraphStatsLoader.swift`
    - `NodePickerLoader`, `NodeConnectionsLoader`, `MediaAllLoader` (siehe `BrainMesh/BrainMeshApp.swift`)
  - Hydration/Caches:
    - `ImageHydrator` — `BrainMesh/ImageHydrator.swift`
    - `AttachmentHydrator` — `BrainMesh/Attachments/AttachmentHydrator.swift`

- **Storage / Cache Layer**
  - SwiftData Models: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
  - Disk-Caches:
    - `ImageStore` → `Application Support/BrainMeshImages` (`BrainMesh/ImageStore.swift`)
    - `AttachmentStore` → `Application Support/BrainMeshAttachments` (`BrainMesh/Attachments/AttachmentStore.swift`)
    - Thumbnails: `AttachmentThumbnailStore` (inkl. `AsyncLimiter`) (`BrainMesh/Attachments/AttachmentThumbnailStore.swift`)

- **Persistenz & Sync**
  - `ModelContainer` + `ModelConfiguration(cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`
  - Sync-Status: `SyncRuntime` (`BrainMesh/Settings/SyncRuntime.swift`)

---

## Folder Map (Ordner → Zweck)
- `BrainMesh/Attachments` — Anhänge/Dateien/Videos: Modelle, Import-Pipeline, Cache/Hydration, Thumbnailing, Manage-Screens
- `BrainMesh/GraphCanvas` — Graph-Canvas Tab: Loader (BFS), Rendering/Physics/Gestures/Camera, MiniMap, Screen-Overlays
- `BrainMesh/GraphPicker` — Graph-Auswahl & -Verwaltung (Sheet), Security, Delete/Dedupe Services, List-SubViews
- `BrainMesh/Icons` — SF Symbols Picker + Icon UI
- `BrainMesh/Images` — Bild-Import (JPG/Resize), ggf. Hilfen für Photos
- `BrainMesh/ImportProgress` — Import-Progress UI/Models (für Attachments/Media)
- `BrainMesh/Mainscreen` — Entities/Attributes/Links: Home, Details, Sheets, Bulk-Operations, NodeDetailShared
- `BrainMesh/Observability` — os.Logger Wrapper + kleine Observability Utilities
- `BrainMesh/Onboarding` — Onboarding Koordinator, Progress, Sheet UI
- `BrainMesh/PhotoGallery` — Gallery Grid/Sheets, Photo Actions (Set main photo, delete), Media Loader
- `BrainMesh/Security` — Graph Lock/Unlock: FaceID/TouchID/Password, crypto helpers, coordinator
- `BrainMesh/Settings` — Settings Tab, Appearance, Sync status, Maintenance
- `BrainMesh/Stats` — Stats Tab, Loader + Service + UI components
- `BrainMesh/Support` — kleine Helpers/Coordinators (SystemModalCoordinator etc.)
- `BrainMesh/Assets.xcassets` — App assets

---

## Data Model Map (Entities / Relationships / Felder)
> Quelle: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`

### MetaGraph
- `id: UUID`, `createdAt: Date`, `name`, `nameFolded`
- **Security (optional):** `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Derived: `isProtected`, `isPasswordConfigured`

### MetaEntity
- `id`, `createdAt`, `graphID: UUID?` (Workspace-Scope)
- `name`, `nameFolded`, `notes`, `iconSymbolName?`
- **Main-Image (CloudKit-sync + Cache):** `imageData: Data?`, `imagePath: String?`
- **Security fields vorhanden** (analog MetaGraph) — **UNKNOWN** ob in UI wirklich genutzt (siehe Open Questions).
- Relationships:
  - `attributes: [MetaAttribute]?` (Cascade, inverse bei `MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (Cascade, inverse bei `MetaDetailFieldDefinition.owner`)

### MetaAttribute
- `id`, `createdAt`, `graphID: UUID?`
- `name`, `nameFolded`, `notes`, `iconSymbolName?`
- **Main-Image (CloudKit-sync + Cache):** `imageData: Data?`, `imagePath: String?`
- `owner: MetaEntity?` (kein Relationship-Macro hier; set `graphID` beim Setzen)
- `searchLabelFolded` für Suche (Entity · Attribute)
- Relationship:
  - `detailValues: [MetaDetailFieldValue]?` (Cascade, inverse bei `MetaDetailFieldValue.attribute`)

### MetaLink
- `id`, `createdAt`, `graphID: UUID?`, `note?`
- `sourceKindRaw`, `sourceID`, `sourceLabel`
- `targetKindRaw`, `targetID`, `targetLabel`
- Denormalisierte Labels werden beim Rename per `NodeRenameService` nachgezogen (`BrainMesh/Mainscreen/LinkCleanup.swift`).

### MetaAttachment
- `id`, `createdAt`, `graphID: UUID?`
- Ownership: `ownerKindRaw` + `ownerID` (Entity/Attribute)
- `contentKindRaw` (file/video/galleryImage)
- Metadaten: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Bytes: `fileData: Data?` mit `@Attribute(.externalStorage)` (CloudKit-friendly)
- Cache: `localPath: String?`

### MetaDetailFieldDefinition
- `id`, `graphID`, `entityID`, `name`, `nameFolded`
- `typeRaw`, `sortIndex`, `isPinned`, `unit?`, `optionsJSON?`
- Relationship: `owner: MetaEntity?` (nullify; inverse von `MetaEntity.detailFields`)

### MetaDetailFieldValue
- `id`, `graphID`, `attributeID`, `fieldID`
- Typed storage: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
- `attribute: MetaAttribute?` (setzt `attributeID`, `graphID`)

---

## Sync / Storage
### SwiftData + CloudKit
- `ModelContainer` wird in `BrainMesh/BrainMeshApp.swift` gebaut mit:
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
- Fallback-Verhalten:
  - **DEBUG:** `fatalError` wenn CloudKit-Konfiguration scheitert (kein Fallback).
  - **RELEASE:** Fallback auf lokalen Store ohne CloudKit (`ModelConfiguration(schema: schema)`).
- `SyncRuntime`:
  - Setzt Storage-Mode (`cloudKit` vs `localOnly`) und liest iCloud Account Status (`CKContainer.default().accountStatus()`), angezeigt in Settings (`BrainMesh/Settings/SyncRuntime.swift`).

### Bilder
- Import/Kompression: `ImageImportPipeline.prepareJPEG(...)` nutzt `maxPixelSize` und `maxBytes` (default 280 KB) (`BrainMesh/Images/ImageImportPipeline.swift`).
- Speicherung:
  - `MetaEntity.imageData` / `MetaAttribute.imageData` (JPEG) syncen über CloudKit.
  - Lokaler Cache-Pfad in `imagePath` + Disk-Cache in `ImageStore` (`BrainMesh/ImageStore.swift`).
- Hintergrund-Hydration:
  - `AppRootView` triggert “rare” Auto-Hydration maximal alle 24h + einmal pro Launch (`BrainMesh/AppRootView.swift` → `autoHydrateImagesIfDue()`).
  - Hydration läuft off-main: `ImageHydrator` erstellt eigene `ModelContext` in `Task.detached` (`BrainMesh/ImageHydrator.swift`).

### Attachments (Datei/Video/Gallery Images)
- Import:
  - `AttachmentImportPipeline.importFile(...)` und `importVideoFromPhotos(...)` (`BrainMesh/Attachments/AttachmentImportPipeline.swift`).
  - Größenlimit in UI meist: **25 MB** (`maxBytes` in Entity/Attribute Detail Views, z.B. `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`).
  - Video-Kompression optional (Setting) via `VideoImportPreferences` / `VideoImportProcessor` (`BrainMesh/Settings/VideoImportPreferences.swift`, `BrainMesh/Attachments/VideoImportProcessor.swift`).
- Speicherung:
  - `MetaAttachment.fileData` als `.externalStorage` (CloudKit Asset-ähnlich).
  - Lokaler Disk-Cache: `AttachmentStore` (`BrainMesh/Attachments/AttachmentStore.swift`).
- Hydration:
  - `AttachmentHydrator` schreibt `fileData` auf Disk + setzt `localPath` in SwiftData (off-main, concurrency-limited) (`BrainMesh/Attachments/AttachmentHydrator.swift`).

### Migration / Legacy
- Graph-Bootstrap & Migration:
  - `GraphBootstrap.ensureAtLeastOneGraph(...)` + `migrateLegacyRecordsIfNeeded(...)` (`BrainMesh/GraphBootstrap.swift`)
  - Migrationsziel: vorhandene `MetaEntity`/`MetaAttribute`/`MetaLink` mit `graphID == nil` in einen Default-Graph schieben.
- Duplicate Graph IDs cleanup:
  - `GraphDedupeService.removeDuplicateGraphs(using:)` beim Öffnen des GraphPickers (`BrainMesh/GraphPickerSheet.swift`, `BrainMesh/GraphPicker/GraphDedupeService.swift`).

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMesh/BrainMeshApp.swift` → `AppRootView` (App-Lifecycle + Auto-Hydration + Auto-Lock + Onboarding)
- `BrainMesh/ContentView.swift` Tabs:
  - **Entitäten** → `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - **Graph** → `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - **Stats** → `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - **Einstellungen** → `BrainMesh/Settings/SettingsView.swift` (in `NavigationStack`)

### GraphPicker (Sheet)
- Öffnet aus EntitiesHome / GraphCanvas (je nach UI): `GraphPickerSheet` (`BrainMesh/GraphPickerSheet.swift`)
- Enthält Graph-Liste + Add/Rename/Delete + Security Sheet (`BrainMesh/GraphPicker/*`)

### Entity / Attribute Details
- Entity:
  - `BrainMesh/Mainscreen/EntityDetail/*`
  - Shared: Teile aus `BrainMesh/Mainscreen/NodeDetailShared/*` (Markdown, Media/Attachments, Connections)
- Attribute:
  - `BrainMesh/Mainscreen/AttributeDetail/*`
  - Shared: `NodeDetailShared/*`

### Links
- Add Link: `BrainMesh/Mainscreen/AddLinkView.swift`
- Bulk Links: `BrainMesh/Mainscreen/BulkLinkView.swift`
- Connections “Alle”: `NodeConnectionsLoader` + `NodeDetailShared+Connections.swift`

### Graph Canvas
- `GraphCanvasScreen` + `GraphCanvasView`:
  - Rendering: `GraphCanvasView+Rendering.swift`
  - Gestures: `GraphCanvasView+Gestures.swift`
  - Physics: `GraphCanvasView+Physics.swift`
  - Camera: `GraphCanvasView+Camera.swift`

### Security (Lock/Unlock)
- Lock-Requests werden als FullscreenCover präsentiert:
  - `AppRootView` → `.fullScreenCover(item: $graphLock.activeRequest)` (`BrainMesh/AppRootView.swift`)
  - UI: `GraphUnlockView` (`BrainMesh/Security/GraphUnlockView.swift`)
- Debounced background lock (Picker-safe): `AppRootView.scheduleDebouncedBackgroundLock()` (`BrainMesh/AppRootView.swift`)
- SystemModal Tracking: `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`)

### Onboarding
- `OnboardingSheetView` als Sheet, gesteuert durch `OnboardingCoordinator` (`BrainMesh/Onboarding/*`, `BrainMesh/AppRootView.swift`)

---

## Build & Configuration
- Xcode Projekt: `BrainMesh/BrainMesh.xcodeproj`
- Deployment target: **iOS 26.0** (aus `project.pbxproj`)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - CloudKit enabled
  - APS env: `development`
- Info.plist: `BrainMesh/Info.plist`
  - `UIBackgroundModes`: `remote-notification` (typisch für CloudKit Push)
  - `NSFaceIDUsageDescription`: gesetzt
- Third-party Dependencies: **keine gefunden** (keine SPM `XCRemoteSwiftPackageReference` im pbxproj).
- Secrets-Handling: **keine `.xcconfig` / Secrets-Dateien gefunden** → **UNKNOWN** ob es externe Secrets gibt (z.B. in lokalen Xcode Settings).

---

## Conventions (Naming, Patterns, Do/Don’t)
### Patterns, die im Code bereits konsistent genutzt werden
- **Graph-Scope als `graphID: UUID?`**: `nil` steht für Legacy; neue Records sollten möglichst früh `graphID` erhalten (siehe `GraphBootstrap`, `MetaAttribute.owner` didSet).
- **Value-Snapshots aus Loaders**: UI bekommt DTOs, nicht live SwiftData-Objekte (z.B. `EntitiesHomeLoader`, `GraphStatsLoader`, `GraphCanvasDataLoader`).
- **Off-main Fetch + Disk I/O**: “Heavy work” wird in `Task.detached(priority: .utility)` mit eigenem `ModelContext` ausgeführt (siehe Loader/Hydrator Files).
- **Deduping gegen alte Duplikate**: Listen-Accessors wie `attributesList`, `detailFieldsList`, `detailValuesList` de-dupen per `Set<UUID>` (`BrainMesh/Models.swift`).

### Do
- Für UI-Listen mit potentiell vielen Items:
  - Loader/Actor + Snapshot bauen, UI nur “anzeigen”.
  - Cancellation/Token-Pattern wie in `EntitiesHomeView` (Task token + debounce) übernehmen.
- Für Media:
  - Immer über `ImageImportPipeline` / `AttachmentImportPipeline` gehen; keine “raw Data” in UI lesen.
  - Cache-Pfade (`imagePath` / `localPath`) nutzen statt wiederholt `Data` zu decoden.

### Don’t
- Keine `ModelContext.fetch(...)` im Renderpfad (body/computed properties, die pro Frame laufen).
- Keine unbounded parallel I/O: nutze `AsyncLimiter` oder ähnliche Begrenzungen (siehe `AttachmentThumbnailStore.swift`).

---

## How to work on this project (Setup Steps)
1. Öffne `BrainMesh.xcodeproj` (Root: `BrainMesh/`).
2. Stelle Team + Bundle ID + iCloud/CloudKit Entitlements korrekt ein (sonst CloudKit Container Fehler).
3. Run auf einem Gerät/Simulator mit iCloud:
   - Für realen CloudKit Sync braucht es iCloud Login + korrekte Container-Config.
4. Erste App-Starts:
   - `AppRootView.bootstrapGraphing()` legt ggf. einen Default-Graph an und migriert Legacy-Records (`BrainMesh/AppRootView.swift`).
5. Debugging:
   - Logs kommen über `os.Logger` (`BrainMesh/Observability/*`) und Print-Statements beim Container-Setup.

---

## Quick Wins (max. 10, konkret & umsetzbar)
1. **DetailsSchemaBuilderView** splitten (UI vs Actions vs Templates) → schnelleres Navigieren/Ändern ohne 700+ Zeilen File (siehe `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`).
2. `MarkdownTextView.swift` in kleinere Komponenten zerlegen (UITextView subclass, toolbar, link prompt, markdown utilities) → weniger Compile- und Merge-Pain.
3. `GraphCanvasView+Rendering.swift`: Render-Helper in separate `EdgeRenderer`/`NodeRenderer` auslagern und “per frame allocations” minimieren (siehe Hot Path Notes).
4. `Models.swift`: in `Models/MetaGraph.swift`, `Models/MetaEntity.swift`, … splitten; Schema-Liste in `BrainMeshApp` bleibt zentral.
5. `MetaEntity` / `MetaAttribute` Security-Fields validieren: wenn ungenutzt, entfernen oder klar in UI integrieren (**UNKNOWN** Nutzung).
6. “Folded search strings” konsequent als Cache nutzen: überall `BMSearch.fold(...)` nur einmal pro Input berechnen und weiterreichen (z.B. EntitiesHome: schon gut).
7. Einheitliches “GraphID normalization” Helper (legacy `nil` vs active graph): kleine Utility-API statt ad-hoc `graphID ?? activeGraphID`.
8. Attachment/Media “cleanup” zentralisieren: `AttachmentCleanup` und `LinkCleanup` sind schon da; “delete flows” überall konsequent nutzen.
9. Add lightweight metrics toggles für Hydrator Runs (count, duration) in Settings (Hooks sind über `SyncRuntime`/`BMObservability` nahe dran).
10. Konsistente Snapshot-Signatures (IDs statt ganze Model-Objekte) in Views, um `@Query`-Invalidation zu reduzieren (GraphPicker macht das schon mit `graphsSignature`).

---

## Open Questions (UNKNOWN)
- **Security fields in `MetaEntity`/`MetaAttribute`:** sind die in UI/Flows aktiv genutzt oder Altbestand? (`BrainMesh/Models.swift`, `BrainMesh/Security/*`)
- **CloudKit conflict policy / merge behavior:** SwiftData-Default oder gibt es bewusstes Handling? (keine expliziten Merge-Policies gefunden)
- **Secrets/Config:** keine `.xcconfig` im Repo; gibt es externe Keys/Endpoints, die nur lokal gesetzt werden?
- **CloudKit Push usage:** `remote-notification` ist gesetzt; gibt es tatsächliche CK subscriptions oder verlässt man sich komplett auf SwiftData? (keine CKSubscription Nutzung gefunden)


## Where to start (für neue Devs)
Wenn du dich schnell orientieren willst, lies in dieser Reihenfolge:
1. `BrainMesh/BrainMeshApp.swift` — ModelContainer/Schema + Startup-Konfiguration der Loader/Hydratoren.
2. `BrainMesh/AppRootView.swift` — App-Lifecycle (foreground/background), Auto-Lock, Auto-Hydration, Onboarding.
3. `BrainMesh/ContentView.swift` — Tabs.
4. Data Model: `BrainMesh/Models.swift` + `BrainMesh/Attachments/MetaAttachment.swift`.
5. Ein “Feature vertical slice”:
   - Entities Home: `BrainMesh/Mainscreen/EntitiesHomeView.swift` + `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
   - Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + `BrainMesh/GraphCanvas/GraphCanvasView.swift`
   - Stats: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` + `BrainMesh/Stats/GraphStatsLoader.swift`

---

## Typical Workflows (wie fügt man ein Feature hinzu)
### 1) Neues Feld / neues Model
Checkliste:
- [ ] Neues `@Model` anlegen (idealerweise in eigener Datei; aktuell sind viele Models in `BrainMesh/Models.swift`).
- [ ] Schema erweitern: `let schema = Schema([...])` in `BrainMesh/BrainMeshApp.swift`.
- [ ] Graph-Scope definieren (`graphID: UUID?`) und setze ihn beim Erstellen möglichst früh.
- [ ] Delete-/Cleanup-Regeln klären:
  - Relationship-Macro + `deleteRule` *oder* manuelles Cleanup wie bei `MetaAttachment` (`AttachmentCleanup`).
- [ ] UI-Flow hinzufügen (View + Sheet) und ggf. Loader/Actor falls das Feature potenziell viele Records lädt.

### 2) “Heavy list” / “heavy compute” UI
- [ ] Actor-Loader mit `configure(container:)` + `loadSnapshot(...)` (Pattern siehe `EntitiesHomeLoader`, `GraphStatsLoader`).
- [ ] In der View: `Task` lifecycle klar (Token + Cancel + Debounce, siehe `EntitiesHomeView.taskToken`).
- [ ] Snapshot in einem `@State`-Commit setzen (keine vielen kleinen States).

### 3) Media / Attachments
- [ ] Bilder: immer über `ImageImportPipeline` (Resize + Byte-Limit) (`BrainMesh/Images/ImageImportPipeline.swift`).
- [ ] Dateien/Videos: immer über `AttachmentImportPipeline` + optional Video-Compression (`BrainMesh/Attachments/AttachmentImportPipeline.swift`).
- [ ] Cache: `ImageStore` / `AttachmentStore` nutzen, nicht “on the fly” decoden.

---

## Tests
- Targets vorhanden: `BrainMeshTests` und `BrainMeshUITests` (Ordner im Repo).
- **UNKNOWN**: ob bereits relevante Tests implementiert sind (nicht im Detail geprüft).
