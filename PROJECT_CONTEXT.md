# BrainMesh — PROJECT_CONTEXT

## TL;DR
BrainMesh ist eine SwiftUI-App (iPhone/iPad), die Wissens-Graphen verwaltet: *Graph* → enthält *Entitäten* (Nodes), *Attribute* (Nodes) und *Links* (Edges) sowie Medien (*Galerie-Bilder* und *Datei-Anhänge*). Persistenz läuft über **SwiftData** mit **CloudKit Sync** (private DB) via `ModelConfiguration(..., cloudKitDatabase: .automatic)` in `BrainMeshApp.swift`. Mindest‑iOS / Deployment Target ist in diesem ZIP **UNKNOWN** (keine `.xcodeproj`/Build Settings enthalten).

## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph)**: Ein “Workspace” / eine Wissensdatenbank. Umschaltbar über Graph‑Picker. (`Models.swift`, `GraphPickerSheet.swift`)
- **Active Graph**: Aktiver Graph wird als String‑UUID in `@AppStorage("BMActiveGraphID")` gehalten (u.a. `AppRootView.swift`, `GraphCanvasScreen.swift`, `EntitiesHomeView.swift`).
- **Entität (MetaEntity)**: Primäre Node‑Art (z.B. Person, Projekt). Hat Name, Notizen, optional Icon + Hauptbild. (`Models.swift`)
- **Attribut (MetaAttribute)**: Sekundäre Node‑Art, i.d.R. gehört zu einer Entität (`MetaAttribute.owner`). (`Models.swift`)
- **Link (MetaLink)**: Kante zwischen zwei Nodes (Entity/Attribute), plus optionaler Note. (`Models.swift`)
- **Medien (MetaAttachment)**:
  - **Gallery Image**: `contentKind == .galleryImage` (Bilder in “Galerie”). (`Attachments/MetaAttachment.swift`, `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`)
  - **Attachment (File/Video/Doc)**: alles andere, inkl. QuickLook‑Preview/Video‑Playback. (`Attachments/*`, `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`)
- **Hydration**:
  - **Image Hydration**: schreibt `imageData` (CloudKit-synced) als lokale JPEG‑Cache Datei (`imagePath`) in AppSupport. (`ImageHydrator.swift`, `ImageStore.swift`)
  - **Attachment Hydration**: stellt sicher, dass `MetaAttachment.fileData` (External Storage) als lokale Datei vorhanden ist. (`Attachments/AttachmentHydrator.swift`, `Attachments/AttachmentStore.swift`)
- **Graph Lock**: Graph kann per Biometrics und/oder Passwort geschützt werden, Unlock über `GraphLockCoordinator`. (`Security/GraphLockCoordinator.swift`, `Security/GraphSecuritySheet.swift`)

## Architecture Map (Layer/Module → Verantwortung → Abhängigkeiten)
- **UI Layer (SwiftUI Views)**
  - Root/Navigation: `BrainMeshApp.swift` → `AppRootView.swift` → `ContentView.swift`
  - Feature‑Screens:
    - “Entitäten”: `Mainscreen/EntitiesHomeView.swift` → `Mainscreen/EntityDetail/*`
    - “Graph”: `GraphCanvas/GraphCanvasScreen.swift` + `GraphCanvas/GraphCanvasView*.swift`
    - “Stats”: `GraphStatsView.swift` + `GraphStatsService.swift`
    - “Settings”: `SettingsView.swift` (+ `SettingsAboutSection.swift`)
    - “Onboarding”: `Onboarding/*`
  - **Depends on**: SwiftData (`ModelContext`, `@Query`), Services, Storage/Caches.
- **Domain Model (SwiftData @Model)**
  - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink` in `Models.swift`
  - `MetaAttachment` in `Attachments/MetaAttachment.swift`
  - **Used by**: UI, Services, Storage/Hydrators.
- **Services (Domain orchestration)**
  - Graph bootstrap/migration: `GraphBootstrap.swift`
  - Graph deletion: `GraphPicker/GraphDeletionService.swift` + `Attachments/AttachmentCleanup.swift` + `ImageStore.swift`
  - Graph stats: `GraphStatsService.swift`
  - Dedupe: `GraphPicker/GraphDedupeService.swift`
  - Query helpers: `Mainscreen/NodeLinksQueryBuilder.swift`, `Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
- **Storage / Cache**
  - Images: `ImageStore.swift` + `ImageHydrator.swift` + `Images/ImageImportPipeline.swift`
  - Attachments: `Attachments/AttachmentStore.swift`, `Attachments/AttachmentHydrator.swift`, `Attachments/AttachmentThumbnailStore.swift`
  - Observability: `Observability/BMObservability.swift`
- **Security**
  - Unlock & lifecycle lock: `Security/GraphLockCoordinator.swift`, `Security/GraphUnlockView.swift`, `Security/GraphLockCrypto.swift`

## Folder Map (Ordner → Zweck)
- `Mainscreen` (38 Swift files)
- `Attachments` (16 Swift files)
- `GraphCanvas` (16 Swift files)
- `(root)` (15 Swift files)
- `Onboarding` (8 Swift files)
- `PhotoGallery` (8 Swift files)
- `GraphPicker` (6 Swift files)
- `Security` (6 Swift files)
- `Appearance` (5 Swift files)
- `Icons` (4 Swift files)
- `Images` (1 Swift files)
- `Observability` (1 Swift files)

## Data Model Map (Entities, Relationships, wichtige Felder)

### MetaGraph (`Models.swift`)
- Felder:
  - `id: UUID`, `createdAt: Date`
  - `name`, `nameFolded` (folded Search)
  - Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Derived:
  - `isPasswordConfigured`, `isProtected`

### MetaEntity (`Models.swift`)
- Felder:
  - `id: UUID`
  - `graphID: UUID?` (Scope; `nil` als Legacy‑Scope)
  - `name`, `nameFolded`, `notes`
  - `iconSymbolName: String?`
  - `imageData: Data?` (**CloudKit-sync**), `imagePath: String?` (**lokaler Cache**)
  - Relationship: `@Relationship(.cascade) attributes: [MetaAttribute]?` (Inverse nur hier: `\MetaAttribute.owner`)
- Convenience:
  - `attributesList` (de‑dup by `id`)
  - `addAttribute`, `removeAttribute` (setzt Owner + Graph‑Scope)

### MetaAttribute (`Models.swift`)
- Felder:
  - `id`, `graphID: UUID?`
  - `name`, `nameFolded`, `notes`
  - `iconSymbolName: String?`
  - `imageData: Data?` (**CloudKit-sync**), `imagePath: String?` (**lokaler Cache**)
  - `owner: MetaEntity?` (kein inverse hier; Graph‑Scope wird angepasst)
  - `searchLabelFolded` (aus `displayName`)
- Derived:
  - `displayName` (“Entity · Attribute”)

### MetaLink (`Models.swift`)
- Felder:
  - `id`, `createdAt`, `note`
  - `graphID: UUID?`
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`
- Derived:
  - `sourceKind`, `targetKind` (Enum `NodeKind`)

### MetaAttachment (`Attachments/MetaAttachment.swift`)
- Felder:
  - Identität: `id`, `createdAt`
  - Scope: `graphID: UUID?`
  - Owner: `ownerKindRaw`, `ownerID`
  - Datei: `title`, `originalFilename`, `fileExtension`, `contentTypeIdentifier`
  - Inhalte:
    - `contentKindRaw` (`AttachmentContentKind`)
    - `fileData: Data?` mit `@Attribute(.externalStorage)` (**SwiftData external storage; CloudKit asset-style**)
    - `localPath: String?` (device-local cache filename)
- Derived/Helpers:
  - `contentKind`, `ownerKind`, `isGalleryImage`

## Sync/Storage
### SwiftData + CloudKit (Private DB)
- Container Setup: `BrainMeshApp.swift`
  - Schema: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`
  - CloudKit: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - DEBUG: `fatalError(...)` bei Container‑Fehler, RELEASE: fallback local-only (`ModelConfiguration(schema: schema)`)
- Entitlements: `BrainMesh.entitlements`
- `aps-environment`: `development`
- `com.apple.developer.icloud-container-identifiers`: `['iCloud.de.marcfechner.BrainMesh']`
- `com.apple.developer.icloud-services`: `['CloudKit']`
- Info.plist: `Info.plist`
  - `UIBackgroundModes = ["remote-notification"]` (CloudKit/SwiftData background pushes möglich)
  - `NSFaceIDUsageDescription` gesetzt (Graph Unlock)

### Lokale Caches (Device-only)
- **ImageStore**: `ImageStore.swift`
  - Speichert JPEGs in AppSupport unter `BrainMeshImages/`
  - API: `loadUIImageAsync`, `saveJPEGAsync`, `delete`
- **AttachmentStore**: `Attachments/AttachmentStore.swift`
  - Speichert Preview-Dateien in AppSupport unter `BrainMeshAttachments/`
  - Deterministische Dateinamen: `AttachmentStore.makeLocalFilename(...)`
- **AttachmentThumbnailStore**: `Attachments/AttachmentThumbnailStore.swift`
  - Thumbnail‑Cache (NSCache + disk) unter `BrainMeshAttachmentThumbnails/`
  - Throttling: `AsyncLimiter` (im gleichen File)

### Offline-Verhalten (observed)
- SwiftData arbeitet lokal; CloudKit Sync ist “eventual”.
- Caches (`imagePath`, `localPath`) sind per‑device und können auf einem zweiten Gerät fehlen → Hydrators/Stores stellen die Dateien wieder her.
- Alles darüber hinaus ist **UNKNOWN** (keine Persistenz-/Sync‑Tests im ZIP).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMeshApp.swift` (`@main`) → `AppRootView.swift`
  - Global environment: `AppearanceStore`, `OnboardingCoordinator`, `GraphLockCoordinator`
  - Startup tasks: Graph bootstrap + Image auto-hydration + Onboarding trigger (`AppRootView.swift`)
  - Locking: bei `.inactive/.background` → `graphLock.lockAll()` (`AppRootView.swift`)

### Tabs (`ContentView.swift`)
- Tab 1: **Entitäten** → `Mainscreen/EntitiesHomeView.swift`
  - `NavigationStack` + Suche + Delete
  - Sheets: `AddEntityView`, `GraphPickerSheet`, `SettingsView`
  - NavigationLink: `EntityDetailView(entity:)`
- Tab 2: **Graph** → `GraphCanvas/GraphCanvasScreen.swift`
  - Canvas Rendering: `GraphCanvas/GraphCanvasView.swift` + Splits (`+Rendering`, `+Physics`, …)
  - Toolbars: Graph Picker, Inspector, Fokus/Zoom, etc.
- Tab 3: **Stats** → `GraphStatsView.swift`
  - Berechnung/Fetching via `GraphStatsService.swift`

### Detail Screens
- Entity: `Mainscreen/EntityDetail/EntityDetailView.swift` (+ Subviews in `Mainscreen/EntityDetail/*`)
- Attribute: `Mainscreen/AttributeDetail/*` (analog)
- Shared sections:
  - Hero/Toolbelt + Async image loading: `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
  - Connections: `Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - Highlights: `Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift`
  - Media: `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` (Paging + Preview/Viewer/QuickLook)

### Graph Picker + Security
- Graph switch/manage: `GraphPickerSheet.swift` + `GraphPicker/*`
- Graph security settings: `Security/GraphSecuritySheet.swift`
- Unlock UI: `Security/GraphUnlockView.swift` (fullscreen cover über `GraphLockCoordinator.activeRequest`)

## Build & Configuration (Targets, Entitlements, SPM, Secrets)
- `.xcodeproj` / `.xcworkspace`: **UNKNOWN** (nicht im ZIP enthalten).
- SPM: keine `Package.swift` / `Package.resolved` im ZIP → Third-party Dependencies vermutlich keine (**aber**: ohne Projektdateien bleibt es **UNKNOWN**).
- Entitlements: `BrainMesh.entitlements` (CloudKit + APNs env dev).
- Info.plist: `Info.plist` (Background remote-notification, FaceID usage string).
- Secrets/API Keys: im Snapshot keine erkennbaren Secrets; alles darüber hinaus **UNKNOWN**.

## Conventions (Naming, Patterns, Do/Don’t)
### Patterns, die im Code explizit vorhanden sind
- **Keine Disk I/O / Decode im `body`**:
  - Async Loader View: `NodeAsyncPreviewImageView` (`Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`)
  - `ImageStore.loadUIImageAsync` statt sync read (`ImageStore.swift`)
- **Fetch-limited statt “alles laden”**:
  - Media Preview/Counts: `NodeMediaPreviewLoader.load(...)` (`Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`)
  - Media Paging: `NodeMediaAllView` (`Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`)
- **Item-driven Sheets** gegen “blank sheet races”:
  - `GraphPickerSheet` (`GraphPickerSheet.swift`)
- **Graph Scope**:
  - Predicates häufig `(gid == nil || record.graphID == gid || record.graphID == nil)` für Legacy‑Migration (z.B. `EntitiesHomeView.swift`, `GraphCanvasScreen+Loading.swift`)

### Do
- Disk/Decode/Thumbnail in `.task`/`Task.detached` + Cancellation checks.
- FetchDescriptors mit `fetchLimit` bei potentiell großen Collections.
- Log/Timing im Hot Path über `BMLog`/`BMDuration` (`Observability/BMObservability.swift`).

### Don’t
- Unbounded `@Query` für Attachments/Media (führt zu RAM/CPU-Spikes; wurde bereits gezielt vermieden).
- `ModelContext.fetch` in tight render loops / pro-frame code.

## How to work on this project (Setup Steps)
1. Öffne das Xcode‑Projekt (**UNKNOWN**: Projektdateien fehlen im ZIP) und prüfe:
   - Deployment Target (sollte zu den verwendeten APIs passen).
   - iCloud/CloudKit Capabilities: Container `iCloud.de.marcfechner.BrainMesh` (`BrainMesh.entitlements`).
   - APNs Environment: aktuell `development` (`BrainMesh.entitlements`).
2. Run on device/simulator mit iCloud Account:
   - CloudKit Sync nur sinnvoll mit eingeloggtem iCloud.
3. Debug typische Bereiche:
   - Graph load logs: `BMLog.load` (`GraphCanvas/GraphCanvasScreen+Loading.swift`)
   - Attachment hydration: `Attachments/AttachmentHydrator.swift`
4. Neue Features:
   - UI: neue View unter passendem Ordner (z.B. `Mainscreen/...`, `GraphCanvas/...`), State im Host‑Screen belassen.
   - Data/Services: in kleinen, testbaren Helpers (Pattern: `*Service`, `*Store`, `*Loader`).

## Quick Wins (max 10, konkret)
1. **Deployment Target im Repo fixieren**: `.xcodeproj`/`.xcconfig` mit explizitem iOS Minimum (aktuell **UNKNOWN**).
2. **AppStorage Keys zentral dokumentieren**: (siehe Liste unten) + Defaults/Reset‑Strategie.
3. **ImageHydrator off-main “chunked”**: `ImageHydrator.hydrate(...)` verarbeitet alle Entities/Attributes sequenziell am MainActor (`ImageHydrator.swift`). Chunking + background `ModelContext` (via `ModelContainer`) würde UI contention weiter senken.
4. **Unused Security Flags auf Entity/Attribute prüfen**: Lock‑Felder existieren in `MetaEntity`/`MetaAttribute` (`Models.swift`), werden aber (per grep) nur für `MetaGraph` verwendet (`Security/*`). Entweder entfernen oder tatsächlich implementieren.
5. **Graph Scope Predicate helper**: die `graphID == gid || graphID == nil` Logik ist mehrfach dupliziert (z.B. `EntitiesHomeView.swift`, `GraphCanvasScreen+Loading.swift`, `NodeMediaPreviewLoader.swift`). Ein Helper reduziert Fehler.
6. **Media paging constants vereinheitlichen**: Page sizes/limits (`NodeDetailShared+Media.swift`) als zentrale Konstanten, damit UI + perf reproduzierbar sind.
7. **GraphCanvas maxNodes/maxLinks in Settings**: Defaults `maxNodes=140`, `maxLinks=800` (`GraphCanvas/GraphCanvasScreen.swift`) sind hardcoded — Settings + Persistenz (AppStorage) wären nützlich.
8. **Observability ausbauen**: zusätzliche `BMLog.physics` samples (z.B. repulsion loop duration) in `GraphCanvasView+Physics.swift`.
9. **Settings: “Repair caches”** UI klarer: `ImageHydrator.forceRebuild(...)` existiert (`ImageHydrator.swift`), Exposure/UX prüfen.
10. **Automatisierte Repro-Checkliste**: Minimal dataset generator (z.B. 1k nodes/edges) für Performance Regression Tests (**UNKNOWN**, keine Tests/Tools im ZIP).

## AppStorage / UserDefaults Keys (snapshot)
- `BMActiveGraphID` — used in 11 file(s): `AppRootView.swift`, `GraphCanvas/GraphCanvasScreen.swift`, `GraphPickerSheet.swift`, `GraphSession.swift`, `GraphStatsView.swift` (+6 more)
- `BMEntityAttributeSortMode` — used in 1 file(s): `Mainscreen/EntityDetail/EntityAttributesSectionView.swift`
- `BMImageHydratorLastAutoRun` — used in 1 file(s): `AppRootView.swift`
- `BMOnboardingAutoShown` — used in 1 file(s): `AppRootView.swift`
- `BMOnboardingCompleted` — used in 4 file(s): `AppRootView.swift`, `GraphCanvas/GraphCanvasScreen.swift`, `Mainscreen/EntitiesHomeView.swift`, `Onboarding/OnboardingSheetView.swift`
- `BMOnboardingHidden` — used in 4 file(s): `AppRootView.swift`, `GraphCanvas/GraphCanvasScreen.swift`, `Mainscreen/EntitiesHomeView.swift`, `Onboarding/OnboardingSheetView.swift`
- `BMRecentSymbolNames` — used in 1 file(s): `Icons/IconPickerView.swift`
