# PROJECT_CONTEXT.md

> Generated from repository scan on **2026-02-20** (timezone: Europe/Berlin).  
> Note: No existing `PROJECT_CONTEXT.md` / `ARCHITECTURE_NOTES.md` were found inside the provided ZIP. (**UNKNOWN** whether they exist elsewhere.)

## TL;DR
**BrainMesh** is a SwiftUI iOS/iPadOS app (deployment target **iOS 26.0**) built around **graphs** of **entities** and **attributes** connected by **links**, with rich media/attachments, an interactive **graph canvas**, and per-graph optional **security (Face ID / password)**. Persistence is **SwiftData** with **CloudKit** sync in the private database by default, with a **local-only fallback** in Release builds if CloudKit init fails.

## Key concepts
- **MetaGraph**: a “workspace” / scope for all content (multi-graph). Stored in SwiftData.
- **Entity (MetaEntity)**: primary node type (think “thing/person/topic”).
- **Attribute (MetaAttribute)**: secondary node type owned by an entity.
- **Link (MetaLink)**: edge between nodes (entity ↔ entity, entity ↔ attribute, attribute ↔ attribute).
- **Details schema**: configurable per-entity field definitions (`MetaDetailFieldDefinition`) + per-attribute values (`MetaDetailFieldValue`).
- **Attachments (MetaAttachment)**: files/videos/gallery-images tied to an entity/attribute; bytes stored as `@Attribute(.externalStorage)`.
- **Active graph**: persisted via `@AppStorage("BMActiveGraphID")` (see `BrainMesh/Support/BMAppStorageKeys.swift`).

## Architecture map
**UI (SwiftUI)**
- Root tabs: `BrainMesh/ContentView.swift`
- Root orchestration: `BrainMesh/AppRootView.swift`
- Main feature screens:
  - Entities home: `BrainMesh/Mainscreen/EntitiesHome/*`
  - Graph canvas: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`

**State / Coordinators (ObservableObject, mostly @MainActor)**
- Appearance: `BrainMesh/Settings/Appearance/*` (`AppearanceStore`, settings persistence)
- Display settings: `BrainMesh/Settings/Display/*` (`DisplaySettingsStore`)
- Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
- Graph lock: `BrainMesh/Security/GraphLockCoordinator.swift`
- System picker/prompt tracking: `BrainMesh/Support/SystemModalCoordinator.swift`
- Active graph session mirror: `BrainMesh/GraphSession.swift` (**see “Open Questions” about redundancy with AppStorage**)

**Data / Storage**
- SwiftData models: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- SwiftData container + CloudKit setup: `BrainMesh/BrainMeshApp.swift`
- Sync status surfaced in Settings: `BrainMesh/Settings/SyncRuntime.swift`

**Background loaders (actors; “value snapshots” to keep UI fast)**
- Entities home: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Node picker: `BrainMesh/Mainscreen/NodePickerLoader.swift`
- Node connections: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
- Graph canvas: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- Stats: `BrainMesh/Stats/GraphStatsLoader.swift`
- Media “All” screen: `BrainMesh/Attachments/MediaAllLoader.swift`

**Caching / Hydration (disk + memory)**
- Images: `BrainMesh/ImageStore.swift` + `BrainMesh/ImageHydrator.swift`
- Attachments: `BrainMesh/Attachments/AttachmentStore.swift` + `BrainMesh/Attachments/AttachmentHydrator.swift`
- Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

**Observability**
- Lightweight os.Logger categories + duration helper: `BrainMesh/Observability/BMObservability.swift`

## Folder map (sources)
> In the ZIP, sources live under `BrainMesh/BrainMesh/…`. Paths below use the Xcode-ish convention `BrainMesh/<Group>/…`.

- `BrainMesh/GraphCanvas/` — graph canvas screen, rendering, physics, loaders, minimap.
- `BrainMesh/Mainscreen/` — main screens beyond canvas (home, details, linking, pickers).
  - `EntitiesHome/` — home list/grid UI + loader (already split into multiple files).
  - `NodeDetailShared/` — shared detail UI for entity/attribute (media, connections, notes, markdown).
  - `Details/` — detail schema builder + value editor sheets.
- `BrainMesh/Attachments/` — attachment model, import pipeline, hydrator, thumbnails, preview UI, video tools.
- `BrainMesh/Onboarding/` — onboarding flow (sheet, step cards, progress).
- `BrainMesh/Settings/` — settings screen + sections; subfolders for Appearance/Display.
- `BrainMesh/Stats/` — stats UI + service layer + loader.
- `BrainMesh/PhotoGallery/` — gallery browser/viewer for media.
- `BrainMesh/Security/` — per-graph lock setup/unlock (Face ID / password).
- `BrainMesh/Support/` — AppStorage keys + system modal coordinator.
- `BrainMesh/Icons/` — SF Symbols picker + icon selection UI.
- `BrainMesh/ImportProgress/` — progress UI for imports.

## Data model map (SwiftData)
### Models
- `MetaGraph` (`BrainMesh/Models.swift`)
  - `id`, `createdAt`, `name` (+ `nameFolded`)
  - security fields: biometrics + password hash/salt/iterations (per graph)

- `MetaEntity` (`BrainMesh/Models.swift`)
  - `id`, `createdAt`, **`graphID` (optional for migration)**, `name` (+ `nameFolded`), `notes`
  - icon: `iconSymbolName`
  - image: `imageData` (synced) + `imagePath` (local cache filename)
  - relationships:
    - `attributes` (cascade, inverse `MetaAttribute.owner`)
    - `detailFields` (cascade, inverse `MetaDetailFieldDefinition.owner`)
  - per-entity security fields (same pattern as `MetaGraph`)

- `MetaAttribute` (`BrainMesh/Models.swift`)
  - `id`, **`graphID`**, `name` (+ `nameFolded`), `notes`, `iconSymbolName`
  - image: `imageData` + `imagePath`
  - `owner: MetaEntity?` (inverse is defined on entity side)
  - relationship:
    - `detailValues` (cascade, inverse `MetaDetailFieldValue.attribute`)
  - per-attribute security fields (same pattern)

- `MetaLink` (`BrainMesh/Models.swift`)
  - `id`, `createdAt`, `note?`, **`graphID`**
  - denormalized labels: `sourceLabel`, `targetLabel`
  - endpoints:
    - `sourceKindRaw`, `sourceID`
    - `targetKindRaw`, `targetID`
  - **No relationships** (ids + labels only)

- `MetaDetailFieldDefinition` (`BrainMesh/Models.swift`)
  - `id`, **`graphID`**, scalar `entityID`, `name` (+ folded), `typeRaw`, `sortIndex`, `isPinned`, `unit?`, `optionsJSON?`
  - relationship:
    - `owner: MetaEntity?` (nullify)

- `MetaDetailFieldValue` (`BrainMesh/Models.swift`)
  - `id`, **`graphID`**, scalar `attributeID`, `fieldID`
  - typed storage: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - `attribute: MetaAttribute?` (inverse is defined on attribute side)

- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - `id`, `createdAt`, **`graphID`**
  - ownership by scalar fields: `ownerKindRaw`, `ownerID` (no relationships)
  - `contentKindRaw` (file/video/galleryImage)
  - metadata: title, filename, UTI, extension, byteCount
  - bytes: `fileData` with `@Attribute(.externalStorage)`
  - `localPath` cache filename

### Relationship/Query strategy (important)
- Multi-graph scoping uses `graphID` everywhere; older records can have `graphID == nil` during migration.
- Some migrations exist to avoid **OR predicates** (store-unfriendly) especially with `externalStorage` blobs:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - `BrainMesh/GraphBootstrap.swift`

## Sync / Storage
- SwiftData schema + container: `BrainMesh/BrainMeshApp.swift`
  - Primary config: `ModelConfiguration(schema: ..., cloudKitDatabase: .automatic)`
  - Release fallback: local-only `ModelConfiguration(schema: schema)` (Debug uses `fatalError`)
- iCloud container id: `iCloud.de.marcfechner.BrainMesh` (matches `BrainMesh/BrainMesh.entitlements`)
- Account status display: `BrainMesh/Settings/SyncRuntime.swift` (`CKContainer.accountStatus()`)

### Local caches
- Images: Application Support `/BrainMeshImages` (`BrainMesh/ImageStore.swift`)
- Attachments: Application Support `/BrainMeshAttachments` (`BrainMesh/Attachments/AttachmentStore.swift`) (**folder name confirmed by code; exact path is platform-managed**)
- Thumbnails: produced/served by `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

## UI map (navigation & major flows)
### Entry points
- `BrainMesh/BrainMeshApp.swift` → `AppRootView()` in `WindowGroup`
- `BrainMesh/AppRootView.swift`
  - Runs startup:
    - ensure at least one graph + migrate legacy graphIDs (`GraphBootstrap`)
    - enforce graph lock
    - occasional image hydration (max once per 24h, see `BMImageHydratorLastAutoRun`)
    - onboarding auto-present
  - Handles tricky scenePhase cases (debounced background lock to avoid Photos “Hidden” picker interruptions)

### Tabs (`BrainMesh/ContentView.swift`)
1) **Entitäten** → `EntitiesHomeView`  
2) **Graph** → `GraphCanvasScreen`  
3) **Stats** → `GraphStatsView`  
4) **Einstellungen** → `SettingsView`

### Common sheets/stacks
- Graph picker: `BrainMesh/GraphPickerSheet.swift` + `BrainMesh/GraphPicker/*`
- Onboarding: `BrainMesh/Onboarding/OnboardingSheetView.swift`
- Graph unlock: `BrainMesh/Security/GraphUnlockView.swift` (fullScreenCover)

## Build & configuration
- Deployment target: **iOS 26.0**
- Device family: **iPhone + iPad (TARGETED_DEVICE_FAMILY=1,2)**
- Info.plist:
  - `UIBackgroundModes`: `remote-notification`
  - `NSFaceIDUsageDescription` present
- Entitlements:
  - CloudKit enabled, iCloud container identifiers present
- SwiftPM: **No `Package.resolved` found** → **UNKNOWN** whether the project uses SPM dependencies indirectly.

## Conventions (Do/Don’t)
**Do**
- Keep SwiftUI `body` free of SwiftData fetches and heavy derived computations.
- Use **loader actors** + **value snapshots** when data can be large (entities lists, stats, canvas, pickers).
- When working off-main: create a new `ModelContext(container)` and set `autosaveEnabled = false` (pattern used in loaders).
- Prefer store-translatable predicates (avoid OR) for performance, especially around `externalStorage` blobs.
- Navigate by **id** and resolve models in the destination view’s main `modelContext`.

**Don’t**
- Don’t pass SwiftData `@Model` instances across actor boundaries.
- Don’t call synchronous disk I/O helpers from `body` (explicitly noted in `BrainMesh/ImageStore.swift`).

## How to work on this project (new dev checklist)
1. Open `BrainMesh/BrainMesh.xcodeproj` in Xcode 26.
2. Confirm signing + iCloud entitlements (CloudKit container: `iCloud.de.marcfechner.BrainMesh`).
3. Run on iOS 26 simulator/device.
4. First launch:
   - app creates a default graph if none exists (`GraphBootstrap.ensureAtLeastOneGraph`)
   - legacy graph scoping migrations may run (entity/attribute/link graphIDs)
5. For performance-sensitive features:
   - check for an existing loader actor or create a new one following patterns in:
     - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
     - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`

## Quick wins (concrete, tool-limit friendly)
1. Split `BrainMesh/Models.swift` into per-model files (low risk, better merges / incremental compiles).
2. Extract `AnyModelContainer` + `AsyncLimiter` into `BrainMesh/Support/` (shared utility, reduces duplicate patterns).
3. Add a small “Loader Template” comment block (copy/paste) in one place (e.g. `BrainMesh/Support/LoaderPatterns.swift`) to standardize detached fetch + snapshot commits.
4. Add `BMLog` timing around the heaviest user actions (graph switch, opening media “All”, opening canvas).
5. Convert remaining `@unchecked Sendable` DTOs to `Sendable` where possible (snapshot structs are value types; remove unchecked where feasible).
6. Audit for `@Query` lists that can grow large and prefer loader snapshots where live-updating isn’t needed.
7. Reduce “stringly typed” `@AppStorage` keys by referencing `BMAppStorageKeys.*` everywhere (some places still inline strings).
8. Add “Cache invalidation hooks” after mutations (e.g., when adding/deleting entities/links) to invalidate loader caches (`EntitiesHomeLoader.invalidateCache` etc.).
9. Create a single `GraphScope` helper for `(graphID == activeGraphID)` predicate fragments to avoid inconsistencies.
10. Put placeholder unit/UI tests on a “realistic” path (currently mostly templates), starting with graph bootstrap + migrations.

## Open questions (needs confirmation / not derivable from the ZIP)
- **UNKNOWN**: Are there specific CloudKit conflict-resolution rules expected beyond SwiftData defaults?
- **UNKNOWN**: Are there privacy manifests / App Store privacy declarations planned (no `.xcprivacy` file found)?
- **UNKNOWN**: Is `GraphSession.shared` intended to remain alongside `@AppStorage(BMActiveGraphID)` or can it be removed?
