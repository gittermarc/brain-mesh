# BrainMesh — PROJECT_CONTEXT
_Generated: 2026-02-22_

## TL;DR
BrainMesh is an iOS SwiftUI app (deployment target **iOS 26.0**) for building a personal knowledge graph: **Graphs** contain **Entities** and **Attributes**, connected via **Links**, with optional **Attachments** and per-entity **Details fields** (custom schema). The Graph tab renders a physics-based canvas. Persistence uses **SwiftData** with **CloudKit enabled** by default (Release fallback to local-only).

## Key Concepts / Domain Terms
- **Graph (`MetaGraph`)**: workspace/scope. Most records are graph-scoped via `graphID` (optional for legacy migration).
- **Entity (`MetaEntity`)**: primary node type with name, notes, icon, optional image, attributes, details schema.
- **Attribute (`MetaAttribute`)**: secondary node type owned by an entity; can store notes/icon/image and detail values.
- **Link (`MetaLink`)**: denormalized edge record between nodes with optional note (directed notes exist in Graph Canvas rendering).
- **Details schema**: `MetaDetailFieldDefinition` records define custom fields per entity (type/order/pin/unit/options).
- **Details values**: `MetaDetailFieldValue` stores typed values per attribute + field.
- **Attachment (`MetaAttachment`)**: file/video/gallery-image stored as external data; ownership by `(ownerKindRaw, ownerID)`.
- **Hydration**: background processes that build local cache files (images/attachments) so UI doesn’t block on decoding or external data fetch.
- **Graph Lock**: optional biometrics/password protection per graph; enforced when switching active graph.

## Most important files (start reading here)
- App entry + SwiftData setup: `BrainMesh/BrainMeshApp.swift`
- Root orchestration (startup, scene phase): `BrainMesh/AppRootView.swift`
- Root tabs: `BrainMesh/ContentView.swift`
- SwiftData models: `BrainMesh/Models.swift` and `BrainMesh/Attachments/MetaAttachment.swift`
- Loader configuration (off-main): `BrainMesh/Support/AppLoadersConfigurator.swift`
- Sync status surface: `BrainMesh/Settings/SyncRuntime.swift`

## Architecture Map (layers + dependencies)
Text-form dependency sketch (top → bottom):
- **App composition** (`BrainMeshApp`): constructs `ModelContainer`, chooses CloudKit/local-only, then configures background loaders.
- **Root orchestration** (`AppRootView`):
  - Startup tasks: ensure default graph + migrate legacy graphIDs, enforce lock, auto-hydrate images, and show onboarding if needed.
  - ScenePhase policy: debounced background lock to avoid dismissing system pickers during Face ID prompts.
- **UI (SwiftUI)**:
  - Tabs: Entities / Graph / Stats / Settings.
  - Each tab has its own feature folder; screens are often split across `+Section` / `+Helpers` extensions.
- **Stores & Coordinators (EnvironmentObjects)**:
  - Appearance: `Settings/Appearance/AppearanceStore.swift`.
  - Display settings: `Settings/Display/DisplaySettingsStore.swift` (applied in multiple views).
  - Onboarding: `Onboarding/OnboardingCoordinator.swift` + sheets/views.
  - Graph lock: `Security/GraphLockCoordinator.swift` + unlock UI.
  - System modal tracking: `Support/SystemModalCoordinator.swift` (prevents disruptive foreground work during system pickers).
- **Background loaders/services (mostly `actor`s)**:
  - Configured centrally in `Support/AppLoadersConfigurator.swift`.
  - Return **value-only snapshots** (DTOs) to UI; UI navigates by `UUID` and resolves models in the main context.
- **Persistence**: SwiftData `@Model` types + CloudKit integration (framework-managed).

## Folder Map (source root `BrainMesh/`)
### High-level
- `Assets.xcassets/` — 0 Swift files
- `Attachments/` — 20 Swift files
- `GraphCanvas/` — 19 Swift files
- `GraphPicker/` — 6 Swift files
- `Icons/` — 6 Swift files
- `Images/` — 1 Swift files
- `ImportProgress/` — 2 Swift files
- `Mainscreen/` — 84 Swift files
- `Observability/` — 1 Swift files
- `Onboarding/` — 9 Swift files
- `PhotoGallery/` — 9 Swift files
- `Security/` — 11 Swift files
- `Settings/` — 36 Swift files
- `Stats/` — 19 Swift files
- `Support/` — 10 Swift files
- `AppRootView.swift`
- `BrainMesh.entitlements`
- `BrainMeshApp.swift`
- `ContentView.swift`
- `FullscreenPhotoView.swift`
- `GraphBootstrap.swift`
- `GraphPickerSheet.swift`
- `GraphSession.swift`
- `ImageHydrator.swift`
- `ImageStore.swift`
- `Info.plist`
- `Models.swift`
- `NotesAndPhotoSection.swift`

### What lives where (pragmatic)
- `BrainMesh/Mainscreen/` — the “Entities” tab + shared detail views
  - `EntitiesHome/` (home list/grid + loader + toolbar/sheets)
  - `EntityDetail/` and `AttributeDetail/` (detail screens; section composition controlled by display settings)
  - `Details/` (details schema builder + value editor sheets/cards)
  - `NodeDetailShared/` (shared UI blocks: hero header, attachments/media sections, connections lists)
  - Pickers and add flows: `AddEntityView.swift`, `AddAttributeView.swift`, `AddLinkView.swift`, `NodePicker*.swift`, `BulkLinkView.swift`
- `BrainMesh/GraphCanvas/` — the “Graph” tab
  - `GraphCanvasScreen.swift` (+ `GraphCanvasScreen+*.swift` extensions for overlays/inspector/loading/layout/expand/peek)
  - `GraphCanvasView.swift` (+ `…+Physics.swift`, `…+Rendering.swift`, `…+Gestures.swift`, `…+Camera.swift`)
  - `GraphCanvasDataLoader.swift` (SwiftData → snapshot DTO, off-main)
  - `MiniMapView.swift` (graph minimap overlay)
- `BrainMesh/Stats/` — the “Stats” tab
  - `GraphStatsLoader.swift` (off-main) + `GraphStatsService/` (query/count logic)
  - `GraphStatsView/` + `StatsComponents/` (dashboard UI)
- `BrainMesh/Settings/` — settings UI + runtime surfaces
  - `Appearance/` (theme/tint/graph colors) and `Display/` (per-screen layout/section toggles)
  - `SyncRuntime.swift` (storage mode + iCloud account availability text)
  - `SettingsView.swift` + section extensions (`SettingsView+*.swift`)
- `BrainMesh/Attachments/` — attachment model + import + caching + UI sections
  - `MetaAttachment.swift` model, `AttachmentStore.swift` cache IO, `AttachmentHydrator.swift` progressive cache hydration
  - Import: `AttachmentImportPipeline.swift`, `VideoPicker.swift`, `VideoCompression.swift`
  - UI: `AttachmentsSection.swift` (+ presentation/import/preview extensions), `AttachmentRow.swift`
  - `MediaAllLoader.swift` for “All media” listing off-main
- `BrainMesh/PhotoGallery/` — gallery UI & actions
- `BrainMesh/Security/` — graph lock + crypto + unlock views
- `BrainMesh/Support/` — shared infra
  - `BMAppStorageKeys.swift` (UserDefaults keys), `AsyncLimiter.swift` (throttling), `AnyModelContainer.swift` (type erasure)
  - `DetailsCompletion/` (in-memory suggestions index for details fields)
- `BrainMesh/Observability/` — lightweight logging (`BMLog`) + timers (`BMDuration`)

## Data Model Map (SwiftData)
### Schema & model list
- Schema is defined explicitly in `BrainMesh/BrainMeshApp.swift` and includes:
  - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`.

### Graph scoping
- Many records have `graphID: UUID?` for multi-graph support.
- Legacy migration: missing `graphID` records are moved into a default graph on startup (`BrainMesh/GraphBootstrap.swift`).

### Detail fields & types
- Field types are defined in `DetailFieldType` (`BrainMesh/Models.swift`):
  - `singleLineText`, `multiLineText`, `numberInt`, `numberDouble`, `date`, `toggle`, `singleChoice`.
- `MetaDetailFieldDefinition` stores:
  - `typeRaw` (Int), `sortIndex`, `isPinned` (UI enforces “up to 3 pinned”).
  - `unit` (numbers) and `optionsJSON` (singleChoice).
- `MetaDetailFieldValue` stores typed values in dedicated columns for future sort/filter correctness.

### Relationship summary (as implemented)
- `MetaEntity.attributes` **cascade** → `MetaAttribute.owner` (inverse is on entity side). (`BrainMesh/Models.swift`)
- `MetaEntity.detailFields` **cascade** → `MetaDetailFieldDefinition.owner`.
- `MetaAttribute.detailValues` **cascade** → `MetaDetailFieldValue.attribute`.
- `MetaLink` and `MetaAttachment` intentionally avoid SwiftData relationship macros and use scalar ids for endpoints/owners.

## Sync / Storage
### SwiftData + CloudKit configuration
- Container setup: `BrainMesh/BrainMeshApp.swift`
  - `ModelConfiguration(schema:…, cloudKitDatabase: .automatic)` (CloudKit enabled).
  - Debug: CloudKit init failure triggers `fatalError` (no silent fallback).
  - Release: CloudKit init failure falls back to local-only configuration (and updates `SyncRuntime`).
- Runtime surface: `Settings/SyncRuntime.swift` (storage mode + iCloud account status).

### iCloud + notifications
- Entitlements: `BrainMesh/BrainMesh.entitlements` includes:
  - iCloud container id: `iCloud.de.marcfechner.BrainMesh`
  - CloudKit service enabled
- Info.plist: `BrainMesh/Info.plist` includes `UIBackgroundModes = remote-notification`.
  - Whether this is purely for CloudKit/SwiftData background sync, or for custom notifications, is **UNKNOWN** (no explicit notification handlers found).

### Local file caches
- Images:
  - `imageData` is the synced payload; `imagePath` points to a local cache file (`<uuid>.jpg`).
  - `ImageStore.swift` handles file IO; `ImageHydrator.swift` builds/repairs cache files in the background.
- Attachments:
  - `MetaAttachment.fileData` uses `@Attribute(.externalStorage)`; cache files live in Application Support (`AttachmentStore.swift`).
  - `AttachmentHydrator` ensures cache existence on demand (throttled + deduped).

### De-normalization invariants (important)
- `MetaLink.sourceLabel/targetLabel` must stay in sync with entity/attribute names.
  - `LinkCleanup.swift` contains `NodeRenameService` (actor) that relabels links after renames.
- Folded search fields (`nameFolded`, `searchLabelFolded`) are maintained in `didSet` hooks on name/owner changes (`Models.swift`).

## UI Map (main screens + navigation)
### Root tabs (`BrainMesh/ContentView.swift`)
- **Entitäten**: `Mainscreen/EntitiesHome/EntitiesHomeView.swift` (NavigationStack).
- **Graph**: `GraphCanvas/GraphCanvasScreen.swift` (NavigationStack).
- **Stats**: `Stats/GraphStatsView/GraphStatsView.swift` (no explicit NavigationStack here; internal navigation depends on view implementation).
- **Einstellungen**: `Settings/SettingsView.swift` inside a `NavigationStack`.

### Entities tab
- `EntitiesHomeView` uses a loader (`EntitiesHomeLoader`) to fetch a snapshot of rows (entities + optional counts + optional notes preview).
  - Reload trigger: `.task(id: taskToken)` with debounce; token includes graph id, search term, and flags that influence what to fetch.
  - Layout & density are resolved by merging Appearance + Display settings (`EntitiesHomeView.swift`).
- Navigation targets:
  - Entity detail: `EntityDetailView(entity:)`
  - Attribute detail: `AttributeDetailView(attribute:)`
  - Some destinations fetch models by id at render time (see Hot Path notes in ARCHITECTURE_NOTES).

### Graph tab
- `GraphCanvasScreen` owns graph state + caches and delegates:
  - Heavy SwiftData fetching to `GraphCanvasDataLoader` (snapshot DTO).
  - Rendering + physics to `GraphCanvasView` (Canvas drawing + simulation timer).
- “Inspector” pattern: top bar intentionally minimal; additional controls are reachable via an inspector overlay (`GraphCanvasScreen+Inspector.swift`).

### Settings tab
- `SettingsView` is a host with section extensions; it surfaces:
  - Appearance & graph theme (`Settings/Appearance/…`).
  - Display settings per screen (`Settings/Display/…`).
  - Sync status and maintenance actions (including manual rebuild triggers such as image cache).

## Core background loaders/services (inventory)
- Configured in `Support/AppLoadersConfigurator.swift`:
  - `Attachments/AttachmentHydrator.swift` — cache file URL hydration for attachments (throttled).
  - `ImageHydrator.swift` — JPEG cache hydration for entity/attribute images (serialized).
  - `Attachments/MediaAllLoader.swift` — loads media list off-main.
  - `GraphCanvas/GraphCanvasDataLoader.swift` — loads nodes/edges + render caches (global or neighborhood BFS).
  - `Stats/GraphStatsLoader.swift` — counts + dashboard snapshots via `GraphStatsService`.
  - `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — home list snapshot + short-lived count caches while typing.
  - `Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` — loads connections lists off-main.
  - `Mainscreen/NodePickerLoader.swift` — picker rows for entity/attribute selection (search + limit).
  - `Mainscreen/LinkCleanup.swift` → `NodeRenameService` — relabel denormalized link labels after renames (dedupes in-flight).

## Build & Configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj` (targets: BrainMesh + tests).
- Bundle identifier: `de.marcfechner.BrainMesh` (`project.pbxproj`).
- Deployment target: **iOS 26.0** (`project.pbxproj`: `IPHONEOS_DEPLOYMENT_TARGET`).
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit + push env).
- No SPM dependencies detected (no `Package.resolved`, no package refs in `project.pbxproj`).
- Frameworks used (non-exhaustive, from imports): SwiftData, CloudKit, LocalAuthentication, PhotosUI, QuickLook, AVFoundation/AVKit, Combine, os.Logger.

## Conventions (Do / Don’t)
### Persistence + concurrency
- ✅ Use snapshot DTOs and IDs across concurrency boundaries (pattern used by `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).
- ✅ Create background `ModelContext` inside detached tasks when doing heavy fetch/aggregation work.
- ❌ Don’t keep a `ModelContext` as shared global state across threads/actors.

### View performance
- ✅ Cache derived render state when physics ticks would otherwise cause repeated recomputation (see `GraphCanvasScreen`’s `drawEdgesCache`/`lensCache`/`physicsRelevantCache`).
- ❌ Avoid `FetchDescriptor` / `modelContext.fetch` inside frequently re-rendered view `body` sections (some destinations currently do this).

### Search
- Normalize strings via `BMSearch.fold` (case/diacritic insensitive). Store folded variants in model fields (`nameFolded`, `searchLabelFolded`).

### Settings persistence
- Centralize `@AppStorage` keys in `Support/BMAppStorageKeys.swift` (prevents drift between screens).

## How to work on this project (new dev checklist)
1. Open `BrainMesh/BrainMesh.xcodeproj` in Xcode.
2. Verify Signing & Capabilities (especially iCloud):
   - Ensure your Team is set.
   - iCloud container id matches `BrainMesh/BrainMesh.entitlements` and `Settings/SyncRuntime.swift`.
3. Run on a real device for CloudKit validation; simulator can be misleading for iCloud/account status.
4. When changing SwiftData models:
   - Update the schema list in `BrainMeshApp.swift` (the app does not rely on implicit schema discovery).
   - Run through the app’s main flows on at least two devices to validate sync + migrations.
5. When adding a new heavy query/aggregation:
   - Put it into a loader actor returning a DTO; configure it in `AppLoadersConfigurator`.
   - Ensure the UI triggers it with `.task(id:)` and cancellation checks.

## Quick Wins (max 10, concrete)
1. **Avoid fetch-in-body for navigation destinations**: `NodeDestinationView` fetches entities/attributes inside `body` (`Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`). Move fetch into `.task` + `@State` cache or use `@Query` predicates.
2. **Clarify CloudKit database mode**: code comment says “private DB” but config uses `.automatic` (`BrainMeshApp.swift`). Either switch to explicit `.private` or adjust wording + UI strings (`Settings/SyncRuntime.swift`).
3. **Reduce per-frame allocations in Graph rendering**: `GraphCanvasView+Rendering.swift` allocates new dictionaries each frame in `buildFrameCache`. Consider reusing buffers between frames for large graphs (careful with SwiftUI value semantics).
4. **Make details completion loading non-blocking on large datasets**: `DetailsCompletionIndex.buildCache` fetches on `MainActor` (`Support/DetailsCompletion/DetailsCompletionIndex.swift`). Consider feeding it a background `ModelContext`.
5. **Centralize graph-scoped predicates**: multiple files repeat `graphID == gid` (loader/service/query builders). Small helper builders reduce subtle bugs.
6. **Audit the 25MB attachment limit end-to-end**: limit is defined in detail views (e.g. `EntityDetailView.swift`), but imports happen in `Attachments/…`. Ensure consistent user feedback + enforcement.
7. **Add slow-frame logging in Graph physics**: only log when tick time crosses a threshold (already measured by `BMDuration` in `GraphCanvasView+Physics.swift`).
8. **Consolidate “maintenance” actions**: settings have import/sync/maintenance sections; unify image rebuild + attachment cleanup entry points.
9. **Unit-test fold/search helpers**: `BMSearch.fold` and the denormalization hooks are critical for search UX.
10. **Document what triggers cache invalidation**: several loaders have in-memory caches; a short “who invalidates what” table prevents stale UI surprises.

## Key user workflows (where the code lives)
### 1) Create an entity
- UI entry: `Mainscreen/EntitiesHome/EntitiesHomeView.swift` → sheet `Mainscreen/AddEntityView.swift`.
- Persistence: `MetaEntity` (`Models.swift`), inserted in the main `modelContext`.
- Post-create refresh: `EntitiesHomeView` invalidates loader cache on sheet dismiss (`EntitiesHomeLoader.invalidateCache`).

### 2) Create an attribute for an entity
- UI entry: `EntityDetailView` → sheet `Mainscreen/AddAttributeView.swift`.
- Relationship: `MetaEntity.addAttribute(_:)` sets the `owner` and aligns `graphID` (`Models.swift`).

### 3) Create links between nodes
- UI entry points: `Mainscreen/AddLinkView.swift`, `Mainscreen/BulkLinkView.swift`, plus shared `NodeAddLinkSheet.swift` / `NodeBulkLinkSheet.swift`.
- Data: `MetaLink` is denormalized; always set `sourceLabel/targetLabel` for fast rendering (`Models.swift`).
- Rename maintenance: `NodeRenameService` in `Mainscreen/LinkCleanup.swift` updates existing link labels after renames.

### 4) Define custom detail fields (schema) for an entity
- UI: `Mainscreen/Details/DetailsSchema/...` (builder list/actions/templates).
- Data: `MetaDetailFieldDefinition` records under `MetaEntity.detailFields` (cascade delete).
- Pinning: up to 3 fields can be pinned (UI-enforced; definition stores `isPinned`).

### 5) Edit detail values on an attribute
- UI: `Mainscreen/Details/DetailsValueEditorSheet.swift` (field-type-aware editor).
- Data: `MetaDetailFieldValue` under `MetaAttribute.detailValues` (cascade delete).
- Suggestions: `Support/DetailsCompletion/DetailsCompletionIndex.swift` builds an in-memory index per (graphID, fieldID).

### 6) Add/manage images and attachments
- Images (entity/attribute): managed in shared views under `Mainscreen/NodeDetailShared/`.
- Image caching: `ImageHydrator.swift` writes deterministic JPEGs and updates `imagePath`.
- Attachments: UI sections in `Attachments/AttachmentsSection.swift` and shared manage views in `Mainscreen/NodeDetailShared/`.
- Attachment caching: `Attachments/AttachmentHydrator.swift` ensures a local file URL exists for QuickLook/preview.

### 7) Switch active graph
- Storage: `@AppStorage(BMAppStorageKeys.activeGraphID)` is the single source of truth (used in multiple screens).
- Observer: `GraphSession.swift` listens to UserDefaults changes and publishes `activeGraphID` (main actor).
- Enforcement: `AppRootView` calls `GraphLockCoordinator.enforceActiveGraphLockIfNeeded` on changes.

### 8) Lock/unlock graphs
- Security state lives on `MetaGraph` and `MetaEntity/MetaAttribute` (lock flags + password hash/salt).
- Flow entry: `Settings` shows security UI and `GraphUnlockView` is presented as a fullScreenCover (`AppRootView.swift`).
- Crypto: `Security/GraphLockCrypto.swift` uses `CommonCrypto` (PBKDF-style hashing; exact details in that file).

## State persistence (UserDefaults / AppStorage)
- `BMAppStorageKeys` centralizes keys (`Support/BMAppStorageKeys.swift`).
- Frequently used keys:
  - Active graph: `BMAppStorageKeys.activeGraphID` (used by EntitiesHome + GraphCanvas + AppRootView).
  - Onboarding flags: `BMAppStorageKeys.onboardingHidden`, `…onboardingCompleted`, `…onboardingAutoShown` (`AppRootView.swift`).
  - Image hydrator throttle timestamp: `BMAppStorageKeys.imageHydratorLastAutoRun` (`AppRootView.swift`).

## Hot paths to keep in mind (quick orientation)
- **Graph physics**: O(n²) repulsion loop per tick (`GraphCanvas/GraphCanvasView+Physics.swift`) at 30 FPS (Timer).
- **Graph rendering**: per-frame loops over edges + nodes + dictionary cache build (`GraphCanvas/GraphCanvasView+Rendering.swift`).
- **Search / typing**: `EntitiesHomeView` debounced `.task(id:)` calling `EntitiesHomeLoader` which may compute counts and do multiple fetches (`Mainscreen/EntitiesHome/…`).
- **Large-field completion index**: building suggestions fetches all string values for a field (`Support/DetailsCompletion/DetailsCompletionIndex.swift`).

## Biggest Swift files (orientation)
| # | Lines | File |
|---:|---:|---|
| 1 | 630 | `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` |
| 2 | 532 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` |
| 3 | 515 | `BrainMesh/Models.swift` |
| 4 | 510 | `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift` |
| 5 | 504 | `BrainMesh/Onboarding/OnboardingSheetView.swift` |
| 6 | 491 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` |
| 7 | 469 | `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` |
| 8 | 411 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` |
| 9 | 410 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` |
| 10 | 401 | `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` |

## Open Questions (UNKNOWN)
- **CloudKit database selection**: `.automatic` is used (`BrainMeshApp.swift`), but SyncRuntime text claims “Private DB” (`Settings/SyncRuntime.swift`). Intended behavior is **UNKNOWN**.
- **Remote notification usage**: background mode is enabled (`Info.plist`) but no custom handlers/subscriptions are found. Is it only for framework sync? **UNKNOWN**.
- **Schema migration policy**: beyond `GraphBootstrap`’s `graphID` migration, there is no explicit migration orchestration. Expected behavior for breaking model changes is **UNKNOWN**.