# PROJECT_CONTEXT

Last updated: 2026-02-26 (Europe/Berlin)

## TL;DR
**BrainMesh** is an iOS app (Deployment Target: **iOS 26.0**) for managing a personal “graph” of knowledge: **Entities** and **Attributes** connected by **Links**, enriched with **Details fields** and **Attachments/Media**. Persistence is **SwiftData** with **CloudKit (private DB)** enabled by default, with a **local-only fallback** in Release builds.

## Key Concepts (Domain Glossary)
- **Graph (MetaGraph)**: A workspace / scope. Most records carry an optional `graphID` for multi-graph support + legacy migration.
- **Entity (MetaEntity)**: A primary node (e.g. “Project X”). Can own Attributes and a Details schema.
- **Attribute (MetaAttribute)**: A secondary node that is often attached to an Entity (e.g. “Status”, “Tag-like”). Can hold Details values.
- **Link (MetaLink)**: Connection between two nodes (Entity/Attribute) with direction and optional note.
- **Details Schema (MetaDetailFieldDefinition)**: Per-Entity schema definition for custom fields (type, pinned, order, options).
- **Details Values (MetaDetailFieldValue)**: Values for Attribute+Field combinations (string/int/double/date/bool).
- **Attachment (MetaAttachment)**: Files/media bound to a node (Entity/Attribute) with CloudKit-compatible storage fields.
- **Active Graph**: Chosen graph stored via `@AppStorage(BMAppStorageKeys.activeGraphID)`.

## Architecture Map (Textual)
- **UI (SwiftUI)**  
  - Root tabs + navigation: `BrainMesh/ContentView.swift`  
  - Feature screens under `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Settings/*`, `BrainMesh/Stats/*`
- **State/Stores (ObservableObject/Coordinators)**  
  - Appearance, display settings, onboarding, lock, system modals: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`
- **Loaders / Hydrators (off-main, ModelContainer-backed)**  
  - Central configuration: `BrainMesh/Support/AppLoadersConfigurator.swift`  
  - Examples: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`
- **Persistence (SwiftData) + Sync (CloudKit)**  
  - Container setup: `BrainMesh/BrainMeshApp.swift`  
  - Runtime sync/account surface: `BrainMesh/Settings/SyncRuntime.swift`, `BrainMesh/Settings/SettingsView+SyncSection.swift`
- **Models (SwiftData @Model)**  
  - `BrainMesh/Models/*` (+ `BrainMesh/Attachments/MetaAttachment.swift`)
- **Support / Utilities**
  - Container abstraction: `BrainMesh/Support/AnyModelContainer.swift`
  - Search helpers: `BrainMesh/Models/BMSearch.swift`
  - Observability/logging: `BrainMesh/Observability/*`

Dependencies direction (intended):
- Views → Stores/Loaders → SwiftData Models
- Loaders/Hydrators → SwiftData Models + Support utilities
- Models → Foundation/SwiftData only (keep “pure”)

## Folder Map
- `BrainMesh/Models/` — SwiftData models + details schema/value models + search helpers
- `BrainMesh/Mainscreen/` — Core CRUD UI (Entities list, detail screens, pickers, bulk link, etc.)
- `BrainMesh/GraphCanvas/` — Graph visualization, loading snapshots, canvas screen(s)
- `BrainMesh/GraphPicker/` — Graph selection UI (switch active graph)
- `BrainMesh/Stats/` — Stats UI + loader(s)
- `BrainMesh/Attachments/` — Attachment models, import pipelines, hydrators, cleanup/migration utilities
- `BrainMesh/PhotoGallery/` — Gallery browsing + actions (node-scoped)
- `BrainMesh/Images/` — Image import/pipeline utilities
- `BrainMesh/Onboarding/` — Onboarding flows + progress computation
- `BrainMesh/Security/` — Graph lock/unlock (biometrics/password) flows
- `BrainMesh/Settings/` — Settings UI, sync/account status, appearance, display settings
- `BrainMesh/Observability/` — Logging helpers / OSLog categories (if any)
- `BrainMesh/Support/` — Cross-cutting helpers (container wrappers, loader config, small utilities)

## Data Model Map (SwiftData)
Model files:
- `BrainMesh/Models/MetaGraph.swift`
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Models/MetaLink.swift`
- `BrainMesh/Models/DetailsModels.swift` (definitions + values)
- `BrainMesh/Attachments/MetaAttachment.swift`

### MetaGraph (Graph/workspace)
File: `BrainMesh/Models/MetaGraph.swift`
- Fields: `id`, `createdAt`, `name`, `nameFolded`
- Lock fields: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`, `isPasswordConfigured`, `isProtected`

### MetaEntity (node)
File: `BrainMesh/Models/MetaEntity.swift`
- Fields: `id`, `createdAt`, `graphID?`, `name`, `nameFolded`, `notes`
- UI/media fields: `iconSymbolName?`, `imageData?`, `imagePath?`, `imageUpdatedAt?`
- Relationships:
  - `attributes` (cascade) inverse `MetaAttribute.owner`
  - `detailFieldDefinitions` (cascade) inverse `MetaDetailFieldDefinition.owner`
- Lock fields: same pattern as MetaGraph

### MetaAttribute (node, typically owned)
File: `BrainMesh/Models/MetaAttribute.swift`
- Fields: `id`, `graphID?`, `name`, `nameFolded`, `notes`
- UI/media fields: `iconSymbolName?`, `imageData?`, `imagePath?`, `imageUpdatedAt?`
- Relationship:
  - `detailFieldValues` (cascade) inverse `MetaDetailFieldValue.attribute`
- Owner relationship:
  - `owner` (nullable) + `ownerID` (UUID, used for scoping)

### MetaLink (edge)
File: `BrainMesh/Models/MetaLink.swift`
- Fields: `id`, `createdAt`, `note?`, `graphID?`
- Endpoints:
  - `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`
  - Computed: `sourceKind`, `targetKind` (NodeKind enum)

### MetaDetailFieldDefinition (details schema)
File: `BrainMesh/Models/DetailsModels.swift`
- Fields: `id`, `graphID?`, `entityID`, `name`, `nameFolded`
- Type: `typeRaw` (DetailFieldType), computed `type`
- Ordering/pin: `sortIndex`, `isPinned`
- Extras: `unit?`, `optionsJSON?`, computed `options: [String]`
- Relationship: `owner: MetaEntity?` (nullify)

### MetaDetailFieldValue (details value)
File: `BrainMesh/Models/DetailsModels.swift`
- Fields: `id`, `graphID?`, `attributeID`, `fieldID`
- Typed storage: `stringValue?`, `intValue?`, `doubleValue?`, `dateValue?`, `boolValue?`
- Relationship: `attribute: MetaAttribute?`

### MetaAttachment (files/media)
File: `BrainMesh/Attachments/MetaAttachment.swift`
- Fields: `id`, `createdAt`, `graphID?`
- Owner: `ownerKindRaw`, `ownerID` (Entity/Attribute), computed `ownerKind`
- Content: `contentKindRaw` (AttachmentContentKind), `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Storage: `fileData?` (inline), `localPath?` (device path cache)

## Sync / Storage
- Primary storage: **SwiftData**.
- Sync: **CloudKit enabled** via `ModelConfiguration(schema:..., cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
- Fallback strategy:
  - **DEBUG**: CloudKit container creation failure triggers **fatalError** (intentional hard-fail).
  - **RELEASE**: If CloudKit init fails, app logs warning and falls back to local-only `ModelConfiguration(schema: schema)`; storage mode is recorded via `SyncRuntime`.
- Account status surface:
  - `SyncRuntime.shared.refreshAccountStatus()` is called on launch using `Task.detached` (see `BrainMesh/BrainMeshApp.swift`).
  - Settings UI reads runtime state in `BrainMesh/Settings/SettingsView+SyncSection.swift`.

Caches / indexes (not exhaustive):
- Graph/Stats loaders build value snapshots (`GraphCanvasSnapshot`, stats snapshots) to avoid SwiftData reads on render path.  
  Examples: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`.

Migrations / legacy handling:
- `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` migrates legacy records to a default graph. (`BrainMesh/GraphBootstrap.swift`)

Offline behavior:
- With CloudKit: SwiftData should work offline and sync later (CloudKit background).  
  **UNKNOWN**: Any explicit conflict resolution strategy / merge policy beyond SwiftData defaults.

## UI Map (Screens, Navigation, Flows)
Root tabs: `BrainMesh/ContentView.swift`
- **Entitäten**: `EntitiesHomeView()` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
- **Graph**: `GraphCanvasScreen()` (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`)
- **Stats**: `GraphStatsView()` (`BrainMesh/Stats/GraphStatsView.swift`)
- **Einstellungen**: `SettingsView()` wrapped in `NavigationStack` (`BrainMesh/Settings/SettingsView.swift`)

Global sheets/covers: `BrainMesh/AppRootView.swift`
- Onboarding sheet: `OnboardingSheetView()` (via `OnboardingCoordinator`)
- Graph unlock fullScreenCover: `GraphUnlockView(request:)` (via `GraphLockCoordinator`)
- ScenePhase-driven: debounced background lock + periodic image hydration

Notable flows:
- **Active Graph switching**: `GraphPicker/*` and `@AppStorage(BMAppStorageKeys.activeGraphID)`
- **Node Detail**:
  - Entity detail: `BrainMesh/Mainscreen/EntityDetail/*`
  - Attribute detail: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Shared detail components: `BrainMesh/Mainscreen/NodeDetailShared/*`
- **Attachments**:
  - Import + manage: `BrainMesh/Attachments/AttachmentImportPipeline.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`, `BrainMesh/PhotoGallery/*`
- **Security**:
  - Lock/unlock UI: `BrainMesh/Security/GraphUnlockView.swift`, coordinators in `BrainMesh/BrainMeshApp.swift`

## Build & Configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj`
- Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests` (see `BrainMesh.xcodeproj/project.pbxproj`)
- Deployment target: **26.0** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0` in pbxproj)
- Info.plist: `BrainMesh/BrainMesh/Info.plist`
- Swift Package Manager:
  - No `Package.resolved` found in the ZIP and no `XCRemoteSwiftPackageReference` in pbxproj → likely **no SPM deps**. (**UNKNOWN** if local packages exist outside this ZIP.)

Secrets/keys:
- **UNKNOWN**: Any API keys / secrets handling (no `.xcconfig` in ZIP). Check Xcode Build Settings / `.gitignore`.

Entitlements:
- **UNKNOWN**: `*.entitlements` file not present in ZIP; likely configured in Xcode project settings.

## Conventions (Observed)
- Naming:
  - `Meta*` prefix for SwiftData persisted models.
  - “Loader”/“Hydrator” suffix for off-main data work (often `actor`).
- Patterns:
  - Prefer value-only “snapshot” DTOs for UI (`GraphCanvasSnapshot`).
  - Central loader configuration at app start (`AppLoadersConfigurator.configureAllLoaders`).
- Do / Don’t:
  - ✅ Do: keep heavy SwiftData fetches out of SwiftUI `body`; prefer loaders + snapshots.
  - ✅ Do: use `Task` cancellation & `.utility` priority for background data work.
  - ❌ Don’t: perform `modelContext.fetch(...)` inside render path or inside `.task` without bounding/cancellation if it can scale with data size.

## How to work on this project (Setup + workflow)
Checklist:
- [ ] Open `BrainMesh/BrainMesh.xcodeproj`
- [ ] Select iOS 26 simulator/device
- [ ] Run target `BrainMesh`
- [ ] Validate SwiftData container creation:
  - DEBUG: CloudKit must be correctly configured or the app will crash at startup.
  - Release: app should fall back to local-only.
- [ ] Use Settings → Sync to verify `SyncRuntime` sees account status.

Where to start for new features:
- UI entry: `BrainMesh/ContentView.swift` → choose target tab/screen
- Models: `BrainMesh/Models/*` (keep persistence changes small & migratable)
- Data access: prefer adding/using a loader under `BrainMesh/*/*Loader.swift`
- Cross-cutting services: `BrainMesh/Support/*`, `BrainMesh/Observability/*`

## Quick Wins (max 10, concrete)
1. Move remaining `modelContext.fetch(...)` calls out of SwiftUI view lifecycle into loaders (see Hot Paths: `BulkLinkView`, `NodeImagesManageView`, `NodeDetailShared+Connections`, onboarding sheets).
2. Add cancellation to view-triggered tasks that fetch data (store `Task` in `@State`, cancel on disappear).
3. Normalize “graph scope” predicates: ensure every fetch that can be scoped uses `graphID` to avoid cross-graph work.
4. Standardize snapshot DTOs for heavy screens (Stats, GraphCanvas, Node details) and commit UI state in one go.
5. Add lightweight performance logging around large loads (start/end durations) using `os.Logger`.
6. Audit any “unbounded” arrays in memory (e.g., loading all attachments into RAM) and add limits/paging.
7. Make “lock fields” reusable via a shared protocol/extension to reduce duplication and mistakes across MetaGraph/Entity/Attribute.
8. Consolidate link queries into a single builder (already started: `NodeLinksQueryBuilder` usage in AttributeDetail).
9. Ensure background hydration respects scenePhase + “system picker is open” (pattern exists in `AppRootView`—reuse for other foreground tasks).
10. Add a small “Data size” debug panel (counts per model) to spot accidental cross-graph fetches quickly.

## Open Questions (UNKNOWN)
- CloudKit container identifier & entitlements configuration (no `.entitlements` in ZIP).
- Conflict resolution / merge strategy beyond SwiftData defaults.
- Any background refresh / push-trigger strategy for CloudKit beyond SwiftData defaults.
- External dependencies (SPM/local) outside this ZIP.
- Migration strategy for schema changes beyond `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)`.


## Typical Workflows (Dev Mental Model)

### Add a new persisted field / model
- Edit or add a SwiftData `@Model` in:
  - `BrainMesh/Models/*` or `BrainMesh/Attachments/MetaAttachment.swift`
- Keep these rules:
  - Prefer optional fields for “soft migrations” unless you are ready to ship a migration.
  - If the field is used for sorting/searching, add a folded/normalized variant (pattern: `nameFolded`).
- Update schema registration in `BrainMesh/BrainMeshApp.swift` (schema array inside `Schema([ ... ])`).
- Verify:
  - cold start on device/simulator
  - graph switching
  - Settings → Sync account status still loads

### Add a new main screen / tab
- Root tabs live in `BrainMesh/ContentView.swift`.
- If the screen has heavy data work, create:
  - `FeatureX/FeatureXLoader.swift` as an `actor`
  - a small `FeatureXSnapshot` value DTO
  - configure loader in `BrainMesh/Support/AppLoadersConfigurator.swift`
- Avoid `modelContext.fetch(...)` in `body` / computed properties.

### Add a new sheet / modal flow
- Prefer central coordinators if the flow is cross-screen:
  - Onboarding: `BrainMesh/Onboarding/*` + `OnboardingCoordinator`
  - Locking: `BrainMesh/Security/*` + `GraphLockCoordinator`
  - System pickers: respect `SystemModalCoordinator` to avoid scenePhase surprises (see `BrainMesh/AppRootView.swift`).

### Add a new attachment type / import path
- Pipeline entry points:
  - `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - `BrainMesh/Images/ImageImportPipeline.swift`
- Storage is `MetaAttachment`:
  - Prefer `localPath` for large media and keep `fileData` bounded.
- Hydration/caching:
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/ImageHydrator.swift`

## Troubleshooting (Common)
- **App crashes on launch in DEBUG**:
  - Likely SwiftData CloudKit container init failed.
  - See `BrainMesh/BrainMeshApp.swift` — DEBUG uses `fatalError` (no fallback).
  - Check signing/iCloud capability/CloudKit container in Xcode.
- **UI feels “sticky” when opening a screen**:
  - Look for `modelContext.fetch(...)` usage in view `.task` or `body`.
  - Prefer moving into a loader actor and committing a snapshot.
- **Graph unlock overlays dismiss a system picker**:
  - Pattern fix exists in `BrainMesh/AppRootView.swift` (debounced background lock + `SystemModalCoordinator` guard).


## Loader / Hydrator Inventory (performance-relevant)
Configured via `BrainMesh/Support/AppLoadersConfigurator.swift`:
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — Builds `GraphCanvasSnapshot` off-main (SwiftData fetch + relationship traversal).
- `BrainMesh/Stats/GraphStatsLoader.swift` — Computes stats snapshots off-main (avoid recompute in render path).
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — Prepares entity list data/counts for the home tab.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` — Loads link-related data for detail screens (when used).
- `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift` — Fetch-limited media preview/counts for node details.
- `BrainMesh/Mainscreen/NodePickerLoader.swift` — Data source for pickers (entity/attribute selection).
- `BrainMesh/Attachments/MediaAllLoader.swift` — Loads attachment/media inventory (be careful with unbounded loads).
- `BrainMesh/Attachments/AttachmentHydrator.swift` — Resolves local files, thumbnails, caching for attachments.
- `BrainMesh/ImageHydrator.swift` — Periodic incremental image hydration (throttled in `BrainMesh/AppRootView.swift`).

## Main Screens Inventory (where to look)
- Home list: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- Entity detail: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (+ shared components in `BrainMesh/Mainscreen/NodeDetailShared/*`)
- Attribute detail: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Graph canvas: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
- Stats: `BrainMesh/Stats/GraphStatsView.swift`
- Settings: `BrainMesh/Settings/SettingsView.swift`
- Onboarding: `BrainMesh/Onboarding/OnboardingSheetView.swift`
- Lock/unlock: `BrainMesh/Security/GraphUnlockView.swift`

## Node Kinds / Identity
- Node types are represented by `NodeKind` (`BrainMesh/Models/NodeKind.swift`).
- Many cross-cutting stores/loaders use a `(kind, id)` key to avoid generic type constraints in snapshots.
- Links store endpoint kinds as raw ints (`sourceKindRaw`/`targetKindRaw`) for persistence stability.

## Search / Normalization
- Name folding helper is used to keep search/sort stable (pattern: `nameFolded`).
  - See `BrainMesh/Models/BMSearch.swift` and `didSet` hooks in `MetaEntity`/`MetaAttribute`/`MetaGraph`.
