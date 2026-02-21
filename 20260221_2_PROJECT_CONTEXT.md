# BrainMesh — PROJECT_CONTEXT (Start Here)

## TL;DR
BrainMesh ist eine iOS/iPadOS-App (SwiftUI) zum Verwalten eines persönlichen Wissens-„Graphen“: Du legst **Graphen** (Workspaces) an, darin **Entitäten** (Knoten), gibst ihnen **Attribute** (Unterknoten), verknüpfst Knoten über **Links** und hängst **Medien/Dateien** an. Persistenz läuft über **SwiftData** mit **CloudKit-Sync** (Private DB) und lokalen Caches für Bilder/Anhänge. Mindestziel: **iOS 26.0** (siehe `BrainMesh.xcodeproj/project.pbxproj`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`).

---

## Key Concepts / Domänenbegriffe
- **MetaGraph**: Workspace/Container für Daten. Optional per Graph sperrbar (Biometrie/Passwort). (`BrainMesh/Models.swift`)
- **MetaEntity**: „Hauptknoten“ im Graph (Name, Notizen, Icon, Bild). (`BrainMesh/Models.swift`)
- **MetaAttribute**: „Unterknoten“ einer Entität (Owner = Entity) mit eigener Darstellung + Notizen + Bild. (`BrainMesh/Models.swift`)
- **MetaLink**: Kante zwischen zwei Nodes (Entity/Attribute), inkl. optionaler Notiz. Speichert Kind+IDs sowie Source/Target Labels (denormalisiert). (`BrainMesh/Models.swift`)
- **MetaAttachment**: Datei/Video/Gallery-Image, hängt an Entity/Attribute via `(ownerKindRaw, ownerID)` (bewusst ohne Relationship-Makros). `fileData` ist `.externalStorage`. (`BrainMesh/Attachments/MetaAttachment.swift`)
- **Detail-Felder (Schema + Werte)**:
  - **MetaDetailFieldDefinition**: definierbare Felder pro Entity (z.B. Text, Zahl, Datum, Auswahl), inkl. `sortIndex`, `isPinned`. (`BrainMesh/Models.swift`)
  - **MetaDetailFieldValue**: Werte pro Attribute (typed storage: `stringValue/intValue/doubleValue/dateValue/boolValue`). (`BrainMesh/Models.swift`)
- **Graph Scope (`graphID`)**: Fast alle Records sind optional graph-scoped (`graphID: UUID?`) für sanfte Migration alter Daten (legacy = `nil`). Migration/Bootstrap siehe `BrainMesh/GraphBootstrap.swift`.

---

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhängigkeiten)
Textuelle Map (von „oben nach unten“):

1) **UI (SwiftUI)**
- Root Tabs: `BrainMesh/ContentView.swift` (TabView)
- Root Host + App Lifecycle: `BrainMesh/AppRootView.swift` (Startup, ScenePhase, Onboarding/Lock Sheets)
- Feature Screens:
  - Entities Home: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Entity Detail: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (+ Subviews/Extensions)
  - Attribute Detail: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ `GraphCanvasView*`)
  - Stats: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (+ Extensions)
  - Settings: `BrainMesh/Settings/SettingsView.swift` (+ Sections)

2) **State/Stores/Coordinators (ObservableObject / EnvironmentObject)**
- Appearance: `BrainMesh/Settings/Appearance/AppearanceStore.swift` (**UNKNOWN**: genaue Struktur; Datei existiert im Projekt, hier nicht explizit analysiert)
- Display Settings: `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
- Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
- Graph Lock: `BrainMesh/Security/GraphLockCoordinator.swift`
- System Modals: `BrainMesh/Support/SystemModalCoordinator.swift`

3) **Loader/Services (off-main, Actor + Snapshot DTOs)**
Zentrale Konfiguration: `BrainMesh/Support/AppLoadersConfigurator.swift`
- Entities Home Fetch/Search: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` (actor, `EntitiesHomeSnapshot`)
- Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (actor, `GraphCanvasSnapshot`)
- Stats: `BrainMesh/Stats/GraphStatsLoader.swift` (actor, `GraphStatsSnapshot`)
- Attachments Hydration: `BrainMesh/Attachments/AttachmentHydrator.swift` (actor, `ensureFileURL`)
- Media „Alle“ Loader: `BrainMesh/Attachments/MediaAllLoader.swift`
- Node Connections/Picker/Rename Loader/Service: `BrainMesh/**/NodeConnectionsLoader.swift`, `BrainMesh/**/NodePickerLoader.swift`, `BrainMesh/**/NodeRenameService.swift` (**UNKNOWN**: Pfade vorhanden, aber nicht im Detail gelesen)

4) **Persistence / Sync (SwiftData + CloudKit)**
- Model schema + container creation: `BrainMesh/BrainMeshApp.swift`
- Models: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Sync diagnostics/runtime flags: `BrainMesh/Settings/SyncRuntime.swift`

5) **Local caches (Disk + Memory)**
- Image cache: `BrainMesh/ImageStore.swift` + progressive hydration `BrainMesh/ImageHydrator.swift`
- Attachment cache: `BrainMesh/Attachments/AttachmentStore.swift` + thumbnails `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

Abhängigkeiten (vereinfachte Richtung):
`SwiftUI Screens` → `Stores/Coordinators` → `Loaders/Services (actor)` → `SwiftData ModelContext/FetchDescriptor` → `@Model` → `Disk caches (ImageStore/AttachmentStore)`

---

## Folder Map (Ordner → Zweck)
Top-Level unter `BrainMesh/`:
- `BrainMesh/Attachments/` — Attachment-Model, Import-Pipeline, Cache/Hydration, Preview/Playback.
- `BrainMesh/GraphCanvas/` — Graph-Rendering (Canvas), Physics, Gestures, DataLoader, MiniMap.
- `BrainMesh/GraphPicker/` — Graph-Auswahl/Verwaltung (Sheet), ActiveGraph Handling.
- `BrainMesh/Mainscreen/` — Haupt-UI: EntitiesHome, EntityDetail, AttributeDetail, Details, Shared Node Components.
- `BrainMesh/Onboarding/` — Onboarding Flow (Sheet + Step Cards + Progress).
- `BrainMesh/Security/` — Graph Lock (Biometrie/Passwort), Unlock/SetPassword Screens.
- `BrainMesh/Settings/` — Einstellungen (Sync/Import/Appearance/Display/Maintenance).
- `BrainMesh/Stats/` — Stats UI + Service + Loader (Counts/Trends/Media/Structure).
- `BrainMesh/Observability/` — Minimale Logger/Timing Helpers.
- `BrainMesh/Support/` — App-weite Utilities (Loader Config, AppStorage Keys, SystemModalCoordinator).

---

## Data Model Map (Entities, Relationships, wichtige Felder)
### MetaGraph (`BrainMesh/Models.swift`)
- `id: UUID`, `createdAt: Date`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity (`BrainMesh/Models.swift`)
- Identity/Scope: `id`, `createdAt`, `graphID: UUID?`
- Content: `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Relations:
  - `attributes: [MetaAttribute]?` (`@Relationship(.cascade, inverse: \MetaAttribute.owner)`) → `attributesList` de-duped
  - `detailFields: [MetaDetailFieldDefinition]?` (`@Relationship(.cascade, inverse: \MetaDetailFieldDefinition.owner)`) → `detailFieldsList` sortiert nach `sortIndex`

### MetaAttribute (`BrainMesh/Models.swift`)
- Identity/Scope: `id`, `graphID: UUID?`
- Content: `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Owner: `owner: MetaEntity?` (kein Relationship-Makro auf dieser Seite, Owner setzt `graphID`)
- Search: `searchLabelFolded` basiert auf `displayName = "Entity · Attribute"`
- Details: `detailValues: [MetaDetailFieldValue]?` (`@Relationship(.cascade, inverse: \MetaDetailFieldValue.attribute)`)

### MetaLink (`BrainMesh/Models.swift`)
- Identity/Scope: `id`, `createdAt`, `graphID: UUID?`
- Edge: `sourceKindRaw`, `sourceID`, `sourceLabel`; `targetKindRaw`, `targetID`, `targetLabel`
- Optional: `note`

### MetaDetailFieldDefinition (`BrainMesh/Models.swift`)
- Identity/Scope: `id`, `graphID: UUID?`, `entityID: UUID`
- Schema: `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- Owner: `owner: MetaEntity?` (`@Relationship(.nullify, originalName: "entity")`)

### MetaDetailFieldValue (`BrainMesh/Models.swift`)
- Identity/Scope: `id`, `graphID: UUID?`, `attributeID: UUID`, `fieldID: UUID`
- Typed storage: `stringValue/intValue/doubleValue/dateValue/boolValue`
- Owner: `attribute: MetaAttribute?` (setzt `attributeID` + `graphID`)

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- Identity/Scope: `id`, `createdAt`, `graphID: UUID?`
- Owner: `ownerKindRaw`, `ownerID`
- Kind: `contentKindRaw` (`file`, `video`, `galleryImage`)
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Payload: `@Attribute(.externalStorage) fileData: Data?`
- Cache: `localPath: String?` (Application Support / `BrainMeshAttachments`)

---

## Sync/Storage
### SwiftData + CloudKit
- Container + Schema: `BrainMesh/BrainMeshApp.swift`
  - `Schema([...MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment, MetaDetailFieldDefinition, MetaDetailFieldValue...])`
  - `ModelConfiguration(..., cloudKitDatabase: .automatic)`
  - DEBUG: CloudKit init failure → `fatalError(...)` (kein Fallback)
  - RELEASE: CloudKit init failure → Fallback auf `localConfig` + `SyncRuntime.storageMode = .localOnly`
- iCloud Diagnostics: `BrainMesh/Settings/SyncRuntime.swift` (Container-ID `iCloud.de.marcfechner.BrainMesh` muss zu `BrainMesh.entitlements` passen)

### Lokale Caches
- Images:
  - Disk: Application Support / `BrainMeshImages` (`BrainMesh/ImageStore.swift`)
  - Memory: `NSCache` (countLimit 120)
  - Hydration: `BrainMesh/ImageHydrator.swift` (actor, incremental/force rebuild, run-once-per-launch guard)
- Attachments:
  - Disk: Application Support / `BrainMeshAttachments` (`BrainMesh/Attachments/AttachmentStore.swift`)
  - Hydration: `BrainMesh/Attachments/AttachmentHydrator.swift` (actor; fetch `fileData` off-main, write to disk, global throttle)
  - Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (async generation + limiter)

### Migration / Offline
- Graph scoping Migration:
  - Bootstrap: `BrainMesh/GraphBootstrap.swift` setzt Default-Graph + migriert `graphID == nil` Records.
  - Attachments Migration: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (existiert; Details **UNKNOWN** ohne tieferes Lesen)
- Offline: SwiftData persistiert lokal; CloudKit synct bei iCloud-Verfügbarkeit. Detaillierte Sync-Strategie über Conflict Resolution etc. ist **UNKNOWN** (SwiftData übernimmt Standardverhalten).

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMesh/ContentView.swift`: TabView
  - Tab 1: EntitiesHome
  - Tab 2: GraphCanvas
  - Tab 3: Stats
  - Tab 4: Settings (embedded `NavigationStack`)

### App Lifecycle / Global Overlays
- `BrainMesh/AppRootView.swift`:
  - Startup: Graph bootstrap + lock enforcement + image auto-hydration + onboarding auto-show
  - `.onChange(scenePhase)`: debounced Auto-Lock beim Backgrounding (Workaround für Photos Hidden Album / Face ID)
  - Onboarding: `.sheet(isPresented: onboarding.isPresented)` → `BrainMesh/Onboarding/OnboardingSheetView.swift`
  - Graph Unlock: `.fullScreenCover(item: graphLock.activeRequest)` → `BrainMesh/Security/GraphUnlockView.swift`

### Entities Home
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`:
  - `NavigationStack` + `.searchable`
  - Sheets:
    - Add Entity: `BrainMesh/Mainscreen/AddEntityView.swift`
    - Graph Picker: `BrainMesh/GraphPicker/GraphPickerSheet.swift` (**UNKNOWN**: exakter Dateiname/Flow, da nicht geöffnet)
    - Display Options: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeDisplaySheet.swift` (**UNKNOWN**: genaue Datei existiert im Projekt)
  - Data: über `EntitiesHomeLoader.shared.loadSnapshot(...)` (actor, off-main)

### Entity Detail
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`:
  - ScrollView mit Sections (reorder/hide/collapse über `DisplaySettingsStore`)
  - Attribute Preview + Details + Notes + Media + Connections
  - Attachments/Media:
    - Add/Manage via Sheets (Chooser/Manager) + `AttachmentImportPipeline` / `VideoPicker` etc. (`BrainMesh/Attachments/*`)
  - Links:
    - Queries gebaut über `NodeLinksQueryBuilder` (`BrainMesh/Mainscreen/NodeDetailShared/NodeLinksQueryBuilder.swift` **UNKNOWN**: Datei nicht geöffnet)

### Attribute Detail
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`:
  - Analog zu Entity Detail, aber auf Attribut-Ebene (Details Values + Media + Connections)

### Graph Canvas
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ Extensions):
  - Loads `GraphCanvasSnapshot` via `GraphCanvasDataLoader` (actor, off-main)
  - Rendering: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (Canvas drawing, per-frame caches)
  - Gestures/Physics: `GraphCanvasView+Gestures.swift`, `GraphCanvasView+Physics.swift`

### Stats
- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (+ Extensions)
  - Loads `GraphStatsSnapshot` via `GraphStatsLoader` (actor, off-main)
  - Computation: `BrainMesh/Stats/GraphStatsService/*.swift`

### Settings
- `BrainMesh/Settings/SettingsView.swift` + section files
  - Sync diagnostics: `SyncRuntime` + iCloud account status
  - Maintenance: rebuild image cache, clear attachment cache etc. (`SettingsView+MaintenanceSection.swift`)
  - Import: Video compression preferences (`BrainMesh/Attachments/VideoCompression.swift`)
  - Appearance/Display: `BrainMesh/Settings/Appearance/*`, `BrainMesh/Settings/Display/*`

---

## Build & Configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj`
- Bundle IDs:
  - App: `de.marcfechner.BrainMesh` (`BrainMesh.xcodeproj/project.pbxproj`)
  - Tests: `de.marcfechner.BrainMeshTests`, `de.marcfechner.BrainMeshUITests`
- Deployment Target: iOS **26.0** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`)
- Device families: iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud Services: CloudKit
  - APNs env: development
- Info.plist: `BrainMesh/Info.plist`
  - `NSFaceIDUsageDescription`
  - `UIBackgroundModes: remote-notification` (kein passender Code im Repo gefunden → **UNKNOWN** ob genutzt)
- SPM/Dependencies:
  - Keine `Package.resolved` im Repo gefunden → vermutlich keine SPM-Dependencies (**UNKNOWN**: kann lokal existieren, aber nicht im ZIP).
- Secrets:
  - Keine `.xcconfig` im Repo gefunden → Secrets-Handling ist **UNKNOWN**.

---

## Conventions (Naming, Patterns, Do/Don’t)
### Datenzugriff / Concurrency
- **Do**: `@Model`-Instanzen nicht über Actor/Task-Grenzen reichen. Stattdessen IDs + value-only Snapshots.
  - Beispiel: `EntitiesHomeRow`, `EntitiesHomeSnapshot` in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.
- **Do**: Off-main Loader als `actor`, Konfiguration über `AppLoadersConfigurator.configureAllLoaders(with:)`.
- **Don’t**: Disk I/O in SwiftUI `body` (explizit kommentiert in `BrainMesh/ImageStore.swift`).

### Suche
- Normalisierung: `BMSearch.fold(_:)` (diacritic/case insensitive) (`BrainMesh/Models.swift`).
- Denormalisierte Felder:
  - `MetaEntity.nameFolded`, `MetaAttribute.nameFolded`, `MetaAttribute.searchLabelFolded`.

### AppStorage Keys
- Zentral: `BrainMesh/Support/BMAppStorageKeys.swift` (nicht überall genutzt → bei neuen Keys bevorzugen).

### Graph Scope
- `graphID: UUID?` ist optional. Code soll mit `nil` (Legacy) klar kommen.
- Migration/Bootstrap auf App-Start: `BrainMesh/GraphBootstrap.swift`.

---

## How to work on this project (Setup + Einstieg)
### Setup (neuer Dev)
1. Repo öffnen: `BrainMesh.xcodeproj`.
2. Signing/Team setzen + Entitlements prüfen (`BrainMesh.entitlements`).
3. Für CloudKit Sync: sicherstellen, dass iCloud Container `iCloud.de.marcfechner.BrainMesh` im Apple Developer Portal aktiv ist.
4. Build/Run (Simulator oder Device). Mindest-iOS: 26.0.

### Wo anfangen?
- App-Start/Storage: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`
- Data Model: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- „Home“ UX + Search Performance: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` + Loader
- Graph Rendering: `BrainMesh/GraphCanvas/*`

### Typischer Feature-Workflow
- UI: Screen/Subview unter passendem Feature-Ordner.
- Data: Falls Fetch/Compute spürbar ist → eigener `actor` Loader + Snapshot DTO.
- Settings: Toggle/Option → `DisplaySettingsStore` / `AppearanceStore` statt neue `@AppStorage` Strings.
- Migration: Wenn Model-Feld neu → Defaulting + ggf. Bootstrap/Migration in `GraphBootstrap` oder spezifischem Migration-Helper.

---

## Quick Wins (max. 10, konkret)
1. `AnyModelContainer` aus `BrainMesh/Attachments/AttachmentHydrator.swift` nach `BrainMesh/Support/AnyModelContainer.swift` ziehen (aktueller Ort ist überraschend, wird aber app-weit genutzt).
2. `AsyncLimiter` aus `BrainMesh/Attachments/AttachmentThumbnailStore.swift` nach `BrainMesh/Support/AsyncLimiter.swift` ziehen (wird auch in `BrainMesh/ImageHydrator.swift` genutzt).
3. `BMAppStorageKeys.*` konsequent verwenden (einige Files nutzen noch String-Literale wie `"BMActiveGraphID"`).
4. `EntitiesHomeLoader.computeAttributeCounts/computeLinkCounts`: Profiling + ggf. bessere Strategie (z.B. inkrementelle/denormalisierte Counts), weil aktueller Ansatz „fetch all attrs/links“ skaliert schlecht bei großen Graphen.
5. `GraphCanvasDataLoader`: überprüfen, ob `#Predicate` mit `Array.contains(UUID)` in iOS 26 wirklich zuverlässig ist (es gibt im Code widersprüchliche Kommentare; siehe `EntitiesHomeLoader.fetchEntities` vs `GraphCanvasDataLoader.loadNeighborhood`).
6. `UIBackgroundModes: remote-notification` entfernen oder implementieren (aktuell kein passender Code gefunden → reduziert Attack Surface/Review-Fragen).
7. `Onboarding/Untitled.swift` prüfen und ggf. löschen/umbenennen (toter/vergessener File-Kandidat).
8. Zentraler „Performance Budget“ Abschnitt in `BMObservability` ergänzen: Loader-Durations loggen (z.B. EntitiesHome/Canvas/Stats) → schnellere Regression-Erkennung.
9. Konsistente Pfad-Konventionen für Caches dokumentieren + in Settings anzeigen (Images/Attachments cache sizes existieren bereits in `SettingsView`).
10. Tests für Migration: `GraphBootstrap.migrateLegacyRecordsIfNeeded` (Smoke-Test mit in-memory container) → reduziert Datenverlust-Risiko.

---

## Open Questions (UNKNOWN)
- **CloudKit Sync Semantik**: Konfliktauflösung, Background Sync Triggers, Error Handling über SwiftData hinaus: **UNKNOWN**.
- **remote-notification**: Wird der Background Mode bewusst genutzt? **UNKNOWN**.
- **Sharing/Collaboration (CKShare)**: Kein Code gefunden → Feature vermutlich nicht vorhanden; Confirm: **UNKNOWN**.
- **AppearanceStore**: genaue Persistenz/Versionierung: **UNKNOWN**.
- **GraphPicker/Display Sheets**: genaue Flow-Details ohne Öffnen aller Files: **UNKNOWN**.
