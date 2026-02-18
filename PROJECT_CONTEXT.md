# PROJECT_CONTEXT.md
_Last updated: 2026-02-18_

## TL;DR
BrainMesh is an iOS/iPadOS app (SwiftUI + SwiftData) for building and exploring personal “knowledge graphs”: Graphs contain Entities and Attributes, connected by Links, with Images/Files as Attachments. Minimum deployment target: iOS 26.0 (from Xcode build settings).

## Key Concepts / Domänenbegriffe
- **Graph**: Ein Container/Scope für Daten (Multi-Graph). Aktiv über `@AppStorage("BMActiveGraphID")`. `BrainMesh/GraphSession.swift`, `BrainMesh/ContentView.swift`.
- **Entity (MetaEntity)**: Primäres Objekt im Graph (z.B. “Projekt”, “Person”). Hat optional Icon + Bild + Notizen. `BrainMesh/Models.swift`.
- **Attribute (MetaAttribute)**: Kind-Objekt einer Entity (z.B. “Status”, “Telefonnummer”). `owner: MetaEntity?`. `BrainMesh/Models.swift`.
- **Link (MetaLink)**: Kante zwischen zwei Nodes (Entity/Attribute), speichert Source/Target als (Kind, UUID) + optional Note. `BrainMesh/Models.swift`.
- **Attachment (MetaAttachment)**: Datei/Video/etc. “gehört” zu Entity/Attribute via `ownerKindRaw + ownerID`. Datei-Bytes in SwiftData als `.externalStorage`. Lokale Preview-Datei in App Support Cache. `BrainMesh/Attachments/MetaAttachment.swift`, `BrainMesh/Attachments/AttachmentStore.swift`.
- **Graph Canvas**: Interaktive Visualisierung (Physik + Canvas-Rendering, Lens/Spotlight). `BrainMesh/GraphCanvas/*`.
- **Graph Lock**: Optionaler Schutz pro Graph (Biometrics / Passwort). `BrainMesh/Security/*`.

## Architecture Map
Textuelles Abhängigkeitsmodell (→ = “nutzt”):

- **App/Bootstrap**
  - `BrainMesh/BrainMeshApp.swift` → erstellt `ModelContainer` + konfiguriert Loader/Hydrator + startet Bootstrap.
  - `BrainMesh/AppRootView.swift` → ScenePhase/Lock-Policy + Root-Navigation.
  - `BrainMesh/ContentView.swift` → Tab-Bar (Home / Graph / Stats).

- **Domain Model (SwiftData)**
  - `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
  - UI/Loader greifen **nur** über IDs/DTOs über Actor-Grenzen.

- **Storage & Caches**
  - Images: `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
  - Attachments: `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`, `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

- **Loaders (off-main Snapshots)**
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/NodePickerLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Attachments/MediaAllLoader.swift`

- **UI (SwiftUI)**
  - Mainscreen: `BrainMesh/Mainscreen/*`
  - Graph Canvas: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`, Appearance: `BrainMesh/Appearance/*`

## Folder Map (Ordner → Zweck)
- `BrainMesh/` (Root):
  - `BrainMeshApp.swift` (App + ModelContainer + Configure)
  - `AppRootView.swift` (Root + Lock/ScenePhase)
  - `ContentView.swift` (Tabs)
  - `Models.swift` (SwiftData Modelle: Graph/Entity/Attribute/Link + Helpers)
  - `ImageStore.swift`, `ImageHydrator.swift` (Bildcache)
  - `GraphBootstrap.swift` (Default-Graph + Legacy-Migration)
  - `GraphPickerSheet.swift` (Graph-Auswahl/Manage)
- `BrainMesh/Mainscreen/`: Home/Detail Screens + Picker/Link Flows.
  - `EntityDetail/`, `AttributeDetail/`, `NodeDetailShared/` (geteilte Detail-Bausteine)
- `BrainMesh/GraphCanvas/`: Canvas Screen, View, Loader, Rendering/Physics, Inspector, Expand etc.
- `BrainMesh/Stats/`: Stats View (Sections), Loader + Service + UI Components.
- `BrainMesh/Attachments/`: Attachment Model, Cache/Thumbnail Pipeline, Loader, Cleanup/Migration.
- `BrainMesh/PhotoGallery/`: Detail-Galerie (Attachments als Bilder/Videos), Viewer/Browser.
- `BrainMesh/Security/`: Graph Lock Coordinator + Crypto + Sheets.
- `BrainMesh/Onboarding/`: Onboarding Coordinator + UI.
- `BrainMesh/Settings/`: Settings + About + Display Settings.
- `BrainMesh/Appearance/`: UI-Presets/DisplaySettings.
- `BrainMesh/Observability/`: Mini-Logging/Timing (`BMLog`, `BMDuration`).
- `BrainMesh/Support/`: Support Utilities (z.B. `SystemModalCoordinator`).

## Data Model Map (Entities, Relationships, wichtige Felder)
### MetaGraph (`BrainMesh/Models.swift`)
- `id: UUID`
- `createdAt: Date`
- `name: String`, `nameFolded: String` (Search)
- Protection:
  - `isProtected: Bool`
  - `lockBiometricsEnabled: Bool`
  - `lockPasswordEnabled: Bool`
  - `passwordSaltB64`, `passwordHashB64`, `passwordIterations` (siehe `BrainMesh/Security/GraphLockCrypto.swift`)

### MetaEntity (`BrainMesh/Models.swift`)
- Graph scoping: `graphID: UUID?` (Legacy: kann `nil` sein; Migration siehe `BrainMesh/GraphBootstrap.swift`)
- Display/Search: `name`, `nameFolded`
- Media: `imageData: Data?`, `imagePath: String?` (lokal gecached JPEG)
- UI: `iconSymbolName: String?`
- Notes: `note: String`
- Relationship: `attributesList: [MetaAttribute]` (`.cascade` delete)

### MetaAttribute (`BrainMesh/Models.swift`)
- Graph scoping: `graphID: UUID?`
- Display/Search: `name`, `nameFolded`, `searchLabel`, `searchLabelFolded`
- Media/UI/Notes: analog zu Entity
- Relationship: `owner: MetaEntity?`

### MetaLink (`BrainMesh/Models.swift`)
- `graphID: UUID?`
- `createdAt: Date`
- `note: String?`
- Source/Target als value-pairs:
  - `sourceKindRaw: Int`, `sourceID: UUID`
  - `targetKindRaw: Int`, `targetID: UUID`
  - `sourceLabel`, `targetLabel` (denormalized labels for UI)

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- `graphID: UUID?` (Legacy: kann `nil` sein → Migration: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`)
- Owner reference: `ownerKindRaw: Int`, `ownerID: UUID` (Entity/Attribute)
- File metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Blob: `fileData: Data?` marked `.externalStorage`
- Local cache: `localPath: String?` (Application Support cache filename)

## Sync/Storage
### SwiftData + CloudKit
- Persistent Store: SwiftData `ModelContainer` mit CloudKit `.automatic`. `BrainMesh/BrainMeshApp.swift`.
- CloudKit Container: `iCloud.de.marcfechner.BrainMesh` (Entitlement: `BrainMesh/BrainMesh.entitlements`).
- Offline-Verhalten:
  - SwiftData persistiert lokal; CloudKit Sync läuft opportunistisch im Hintergrund (kein custom Sync-Code im Repo sichtbar).
  - Conflict/Merge Policy: **UNKNOWN** (keine explizite Merge-Policy im Code gefunden; SwiftData defaults).

### Local Caches / Hydration
- Images:
  - Cache folder + size metrics: `BrainMesh/ImageStore.swift`
  - Progressive hydration (off-main) setzt `imagePath` + schreibt JPEG: `BrainMesh/ImageHydrator.swift`
- Attachments:
  - Cache folder: `BrainMesh/Attachments/AttachmentStore.swift` (Application Support/BrainMeshAttachments)
  - On-demand file materialization for preview: `AttachmentStore.ensurePreviewURL(for:)`
  - Background hydrator (throttled, deduped): `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Thumbnail pipeline (memory + disk + throttled generation): `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

### Migration / Legacy
- GraphID Legacy:
  - Startup migration: `BrainMesh/GraphBootstrap.swift` (`migrateLegacyRecordsIfNeeded`)
- Attachment Graph scoping:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (vermeidet OR-Predicates mit `graphID == nil`)

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMesh/AppRootView.swift`
  - Root gating: Graph Lock Sheet via `GraphLockCoordinator.activeRequest`
  - ScenePhase handling + debounce bei System-Modals (`SystemModalCoordinator`) um PhotoPicker/Hidden-Album nicht zu resetten.

### Tabs
- `BrainMesh/ContentView.swift`
  - Tab 1: **Entities (Home)** → `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Tab 2: **Graph** → `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - Tab 3: **Stats** → `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`

### Home / Detail
- Home list + search + Add Entity + Settings + Graph picker:
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Navigation: `EntityDetailRouteView` (resolves by ID via `@Query`).
- Entity/Attribute Details:
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Shared sections/sheets:
    - Connections: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
    - Media sections: `.../NodeDetailShared+Media*.swift`
    - “Anhänge verwalten” sheet: `.../NodeDetailShared+Sheets.Attachments.swift`
    - Links sheet etc: `.../NodeDetailShared+Sheets.Links.swift`

### Graph Canvas
- Screen host + sheets:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ extension files in same folder)
  - Graph picker sheet: `BrainMesh/GraphPickerSheet.swift`
  - Inspector sheet: `GraphCanvasScreen` (see `GraphCanvasScreen+Inspector.swift` etc)
- Loading off-main:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- Rendering/Physics:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`

### Stats
- Host: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- Off-main snapshot:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - Services: `BrainMesh/Stats/GraphStatsService/*`
- Settings entry:
  - `BrainMesh/Settings/SettingsView.swift`

## Build & Configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj`
- Targets (from `project.pbxproj`):
  - App: `BrainMesh` (bundle id: `de.marcfechner.BrainMesh`)
  - Unit tests: `BrainMeshTests`
  - UI tests: `BrainMeshUITests`
- Deployment target: iOS 26.0 (`IPHONEOS_DEPLOYMENT_TARGET` in `project.pbxproj`)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - CloudKit container + aps-environment=development
- Info.plist: `BrainMesh/Info.plist`
  - Background modes: `remote-notification`
  - `NSFaceIDUsageDescription`

SPM:
- **No `Package.resolved` found** in the repo snapshot → likely no Swift Package dependencies. **UNKNOWN** if local packages exist outside the zip.

## Conventions (Naming, Patterns, Do/Don’t)
### Patterns that are “the house style”
- **Off-main loading via actor + detached `ModelContext`** returning DTO snapshots:
  - Examples: `GraphCanvasDataLoader`, `GraphStatsLoader`, `EntitiesHomeLoader`, `NodePickerLoader`, `NodeConnectionsLoader`.
- **No SwiftData `@Model` across concurrency boundaries** (use DTOs + `id`).
- **Graph scoping**: prefer predicates like `x.graphID == gid` (no `(== gid || == nil)`), because OR can trigger in-memory filtering.
  - See rationale in `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.

### Do
- Use `BMSearch.fold(...)` and `nameFolded`/`searchLabelFolded` for case/diacritic-insensitive search (`BrainMesh/Models.swift`).
- Cancel long-running tasks when inputs change (pattern: keep `@State var loadTask` and cancel on `onDisappear` / `onChange`).
  - Example: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`, `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`.

### Don’t
- Don’t do `modelContext.fetch(...)` in SwiftUI render paths (`body`, `computed var` used by body).
- Don’t use unbounded concurrent thumbnail generation (use `AttachmentThumbnailStore` throttle).
- Don’t keep `graphID == nil` fallback logic in hot queries after bootstrap/migrations.

## How to work on this project (Setup + wo anfangen)
### Setup Checklist
- [ ] Open `BrainMesh/BrainMesh.xcodeproj`
- [ ] Select target `BrainMesh`, choose a device/simulator with iOS ≥ 26.0
- [ ] For CloudKit sync tests: run on a real device logged into iCloud and with proper signing:
  - Capabilities must include iCloud/CloudKit using container `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`).
  - **UNKNOWN**: which Apple Developer Team ID is required (not extracted here).
- [ ] For Graph Lock / Face ID: real device recommended (simulator behavior differs).
- [ ] First launch: verify bootstrap created a default graph (`BrainMesh/GraphBootstrap.swift`).

### “Wo anfangen” for new devs
- Read `BrainMesh/BrainMeshApp.swift` first (container + bootstrap + configure).
- Then `BrainMesh/AppRootView.swift` (scene phase + lock) and `BrainMesh/ContentView.swift` (tabs).
- For data model: `BrainMesh/Models.swift` + `BrainMesh/Attachments/MetaAttachment.swift`.
- For hot paths: `BrainMesh/GraphCanvas/*`, `BrainMesh/Mainscreen/NodeDetailShared/*`, `BrainMesh/Attachments/*`.

### Adding a feature (typical workflow)
- [ ] Decide scope: per-graph or global. If per-graph, make sure new records carry `graphID`.
- [ ] If you add a SwiftData model:
  - Add `@Model` type and include it in schema in `BrainMesh/BrainMeshApp.swift`.
  - Add folded/search fields if needed (follow pattern in `Models.swift`).
- [ ] If UI needs “big” data: add an actor loader returning DTOs (follow `EntitiesHomeLoader`).
- [ ] Hook loader/hydrator config in `BrainMesh/BrainMeshApp.swift` (configure with `AnyModelContainer`).
- [ ] Add logging in hot path via `BMLog` + `BMDuration` (`BrainMesh/Observability/BMObservability.swift`).

## Quick Wins (max. 10, konkret)
1. Split `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift` into smaller files (Loading / Import / Row UI). (Compile-time + readability)
2. Add a “hard” graphID normalization task that runs once per launch in background for remaining `graphID == nil` records (entities/attrs/links), then delete legacy OR predicates everywhere. (`BrainMesh/GraphBootstrap.swift`)
3. Add cancellation to any `.task Ellipsis` that can overlap (use stored `Task` like in Stats/Canvas) in the remaining heavy sheets (e.g. attachments manage sheet).
4. Centralize `AnyModelContainer` into a single file (currently defined inside `BrainMesh/Attachments/AttachmentHydrator.swift`) to avoid “where is this type?” friction.
5. Add a tiny “FetchDescriptor helpers” module for graph-scoped predicates (reduces copy/paste and OR mistakes).
6. Move heavy sorting (e.g. large sets in pickers) into loaders; keep UI-level sorting only for small arrays.
7. Add a debug-only “SwiftData fetch timing” wrapper (log slow fetches > X ms) to identify accidental main-thread queries.
8. Add unit tests for `GraphLockCrypto` password hashing/verification (`BrainMesh/Security/GraphLockCrypto.swift`).
9. Add a maintenance action to purge orphaned cache files (image + attachment thumbnails) not referenced in DB.
10. Add a small “Data Integrity” check page in Settings (counts mismatches, missing local cache file ratios).

