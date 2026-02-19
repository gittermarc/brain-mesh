# BrainMesh – Project Context (Start Here)
_Generated: 2026-02-19_

## TL;DR
BrainMesh is an iOS (iPhone + iPad) SwiftUI app that lets users build and explore multiple “graphs” (workspaces) made of **Entities**, their **Attributes**, and **Links** between nodes. Persistence uses **SwiftData** with **CloudKit sync** enabled via a `ModelContainer` configured with `cloudKitDatabase: .automatic` (see `BrainMesh/BrainMesh/BrainMeshApp.swift`). Main UI is a 4-tab root: **Entities**, **Graph (canvas)**, **Stats**, **Settings** (`BrainMesh/BrainMesh/ContentView.swift`). Minimum iOS deployment target is currently set to **26.0** in `BrainMesh/BrainMesh.xcodeproj/project.pbxproj` (verify if intended).

---

## Key Concepts / Domain Terms
- **Graph / Workspace**: user-visible container for data; identified by `MetaGraph.id` (UUID). (`BrainMesh/BrainMesh/Models.swift`)
- **Active Graph**: selected graph id persisted in `@AppStorage("BMActiveGraphID")`. (`BrainMesh/BrainMesh/AppRootView.swift`, `BrainMesh/BrainMesh/GraphSession.swift`)
- **Entity**: primary node type; has name, notes, optional icon + photo. (`MetaEntity` in `BrainMesh/BrainMesh/Models.swift`)
- **Attribute**: secondary node type; belongs to an entity (`owner`) and has its own notes/icon/photo. (`MetaAttribute` in `BrainMesh/BrainMesh/Models.swift`)
- **Link**: edge between any two nodes (entity/attribute), stored as IDs + denormalized labels. (`MetaLink` in `BrainMesh/BrainMesh/Models.swift`)
- **Attachment**: file/video/gallery image attached to an entity/attribute; bytes stored as SwiftData external storage (`@Attribute(.externalStorage)`). (`MetaAttachment` in `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`)
- **Folded Search**: “case/diacritic insensitive” search string via `BMSearch.fold(_:)`, stored in `nameFolded` / `searchLabelFolded` to keep predicates simple. (`BrainMesh/BrainMesh/Models.swift`)
- **Hydration**: background creation of local cache files from synced `Data` blobs (images/attachments) to avoid UI thread stalls. (`BrainMesh/BrainMesh/ImageHydrator.swift`, `BrainMesh/BrainMesh/Attachments/AttachmentHydrator.swift`)
- **Graph Canvas**: interactive visualization with physics simulation + SwiftUI `Canvas` rendering. (`BrainMesh/BrainMesh/GraphCanvas/*`)
- **Lens / Spotlight**: filtering/highlighting on the canvas; limits what is shown and what the physics sim runs on. (`BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + partials)

---

## Architecture Map (Layers, Responsibilities, Dependencies)
Text-form dependency direction: **UI → Loaders/Services → SwiftData Models → Storage/Sync**
- **App / Composition**
  - `BrainMesh/BrainMesh/BrainMeshApp.swift`
    - Builds `Schema([MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment])`
    - Creates `ModelContainer` with CloudKit enabled
    - Injects env objects: `AppearanceStore`, `OnboardingCoordinator`, `GraphLockCoordinator`, `SystemModalCoordinator`
    - Configures background loaders via `Task.detached` + `AnyModelContainer` (container wrapper)
- **Startup / Session**
  - `BrainMesh/BrainMesh/AppRootView.swift`
    - Startup orchestration: graph bootstrap + migrations, lock enforcement, scheduled image hydration, onboarding auto-present
  - `BrainMesh/BrainMesh/GraphSession.swift`
    - `GraphSession.shared` mirrors `BMActiveGraphID` from `UserDefaults` into a published `activeGraphID`
- **Domain Model (SwiftData)**
  - Core: `BrainMesh/BrainMesh/Models.swift` (`MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`)
  - Attachments: `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`
- **Storage & Sync**
  - SwiftData + CloudKit: configured in `BrainMesh/BrainMesh/BrainMeshApp.swift`
  - Local caches:
    - Images: `BrainMesh/BrainMesh/ImageStore.swift` (Application Support / `BrainMeshImages`)
    - Attachments: `BrainMesh/BrainMesh/Attachments/AttachmentStore.swift` (Application Support / `BrainMeshAttachments`)
    - Thumbnails: `BrainMesh/BrainMesh/Attachments/AttachmentThumbnailStore.swift`
  - Hydration/repair:
    - Images: `BrainMesh/BrainMesh/ImageHydrator.swift`
    - Attachments: `BrainMesh/BrainMesh/Attachments/AttachmentHydrator.swift`
    - Graph scoping migration: `BrainMesh/BrainMesh/GraphBootstrap.swift`, `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
    - Duplicate graph repair: `BrainMesh/BrainMesh/GraphPicker/GraphDedupeService.swift`
- **Loaders / Services (performance-oriented, mostly actors)**
  - Home: `BrainMesh/BrainMesh/Mainscreen/EntitiesHomeLoader.swift` (actor; value DTO snapshot)
  - Canvas: `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (actor; neighborhood loading)
  - Stats: `BrainMesh/BrainMesh/Stats/GraphStatsLoader.swift` + `Stats/GraphStatsService/*` (counts via `fetchCount`)
  - Pickers: `BrainMesh/BrainMesh/Mainscreen/NodePickerLoader.swift`, `NodeConnectionsLoader` (`Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`)
  - Rename side effects: `BrainMesh/BrainMesh/Mainscreen/LinkCleanup.swift` (`actor NodeRenameService`)
- **UI (SwiftUI)**
  - Root tabs: `BrainMesh/BrainMesh/ContentView.swift`
  - Entities tab: `BrainMesh/BrainMesh/Mainscreen/EntitiesHomeView.swift` → `EntityDetailView` (`Mainscreen/EntityDetail/EntityDetailView.swift`)
  - Canvas tab: `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + `GraphCanvasView*`
  - Stats tab: `BrainMesh/BrainMesh/Stats/GraphStatsView/*`
  - Settings tab: `BrainMesh/BrainMesh/Settings/SettingsView.swift` (+ sections)
  - Cross-cutting UI: Attachments (`BrainMesh/BrainMesh/Attachments/*`), PhotoGallery (`BrainMesh/BrainMesh/PhotoGallery/*`), Icons (`BrainMesh/BrainMesh/Icons/*`), Onboarding (`BrainMesh/BrainMesh/Onboarding/*`), Security (`BrainMesh/BrainMesh/Security/*`)
- **Cross-cutting**
  - Observability: `BrainMesh/BrainMesh/Observability/BMObservability.swift` (Logger categories + tiny timer)
  - Appearance: `BrainMesh/BrainMesh/Appearance/*` (theme + user settings)

---

## Folder Map (Folder → Purpose)
Top-level app sources live in `BrainMesh/BrainMesh/`.
- `BrainMesh/BrainMesh/Appearance/`
  - Appearance settings models + store + preview UI (tint, color scheme, canvas theme)
- `BrainMesh/BrainMesh/Attachments/`
  - Attachment model + import/hydration + thumbnails + preview sheets + video import/compression
- `BrainMesh/BrainMesh/GraphCanvas/`
  - Graph visualization: data loading, lens/filtering, Canvas rendering, gestures, physics, minimap
- `BrainMesh/BrainMesh/GraphPicker/`
  - Graph selection + rename/delete flows (used by multiple tabs via `GraphPickerSheet`)
- `BrainMesh/BrainMesh/Icons/`
  - SF Symbols picker + local JSON catalog/search index
- `BrainMesh/BrainMesh/Images/`
  - Shared image import pipeline (safe decode, downscale)
- `BrainMesh/BrainMesh/ImportProgress/`
  - UI model + card for showing import progress
- `BrainMesh/BrainMesh/Mainscreen/`
  - Entities home + detail screens (Entity/Attribute), link creation, shared “node detail” building blocks
- `BrainMesh/BrainMesh/Observability/`
  - Logging helpers (`BMLog`) + timing (`BMDuration`)
- `BrainMesh/BrainMesh/Onboarding/`
  - Onboarding coordinator + sheet UI + progress tracker
- `BrainMesh/BrainMesh/PhotoGallery/`
  - Viewing/importing photos and “gallery images” (separate from main node image)
- `BrainMesh/BrainMesh/Security/`
  - Graph lock (biometrics/password), crypto helpers, lock/unlock views
- `BrainMesh/BrainMesh/Settings/`
  - Settings screen split into sections (appearance, maintenance, import preferences, about/help)
- `BrainMesh/BrainMesh/Stats/`
  - Graph stats UI + services + loader snapshots
- `BrainMesh/BrainMesh/Support/`
  - System modal coordinator (used to avoid disruptive work while system pickers are up)

---

## Data Model Map (Entities, Relationships, Key Fields)
### `MetaGraph` (Workspace)
File: `BrainMesh/BrainMesh/Models.swift`
- Fields:
  - `id: UUID` (user-visible graph identifier; duplicates possible in store → see dedupe service)
  - `createdAt: Date`
  - `name`, `nameFolded`
  - Optional security flags + password material:
    - `lockBiometricsEnabled`, `lockPasswordEnabled`
    - `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Computeds:
  - `isPasswordConfigured`, `isProtected`

### `MetaEntity` (Node: Entity)
File: `BrainMesh/BrainMesh/Models.swift`
- Fields:
  - `id: UUID`
  - `graphID: UUID?` (scope; optional for migration)
  - `name`, `nameFolded`
  - `notes: String`
  - `iconSymbolName: String?`
  - `imageData: Data?` (synced JPEG bytes; intended to be small)
  - `imagePath: String?` (local cache filename in Application Support; may sync as a string)
  - Lock flags/password fields (same pattern as `MetaGraph`)
- Relationships:
  - `@Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner) var attributes: [MetaAttribute]?`
  - Helper `attributesList` de-dupes by `id` (defensive repair)
- Invariants enforced in code:
  - `addAttribute(_:)` sets `attr.owner = self` and aligns `attr.graphID` with the entity when missing

### `MetaAttribute` (Node: Attribute)
File: `BrainMesh/BrainMesh/Models.swift`
- Fields:
  - `id: UUID`
  - `graphID: UUID?`
  - `name`, `nameFolded`
  - `notes: String`
  - `iconSymbolName: String?`
  - `imageData: Data?`
  - `imagePath: String?`
  - `owner: MetaEntity?` (relationship; inverse defined on `MetaEntity.attributes`)
  - `searchLabelFolded: String` (folded `displayName`)
  - Lock flags/password fields
- Computeds:
  - `displayName`: `"\(owner.name) · \(name)"` if owner exists

### `MetaLink` (Edge)
File: `BrainMesh/BrainMesh/Models.swift`
- Fields:
  - `id: UUID`, `createdAt: Date`
  - `graphID: UUID?`
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`
  - `note: String?`
- Tradeoff:
  - Uses IDs + denormalized labels instead of relationship macros (faster list/canvas rendering, avoids macro cycles)
  - Requires explicit relabel on rename (see `actor NodeRenameService` in `BrainMesh/BrainMesh/Mainscreen/LinkCleanup.swift`)

### `MetaAttachment` (File/Video/Gallery Image)
File: `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`
- Fields:
  - `id`, `createdAt`, `graphID`
  - Owner expressed as: `ownerKindRaw` + `ownerID` (IDs; no relationships)
  - `contentKindRaw` (`file`, `video`, `galleryImage`)
  - Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - `@Attribute(.externalStorage) var fileData: Data?` (synced bytes, stored externally)
  - `localPath: String?` (local cache filename under Application Support)

---

## Sync / Storage (SwiftData / CloudKit / Caches / Migration / Offline)
### SwiftData + CloudKit
- Container creation: `BrainMesh/BrainMesh/BrainMeshApp.swift`
  - `Schema([MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment])`
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - In **DEBUG**: if CloudKit container creation fails → `fatalError(...)`
  - In **Release**: CloudKit failure falls back to local-only `ModelConfiguration(schema: schema)`
- iCloud container + CloudKit entitlement:
  - `BrainMesh/BrainMesh/BrainMesh.entitlements` includes `iCloud.de.marcfechner.BrainMesh` and CloudKit service
- Background sync triggers:
  - `BrainMesh/BrainMesh/Info.plist` enables `UIBackgroundModes = ["remote-notification"]`
- Offline behavior:
  - **UNKNOWN** (no explicit offline policy; relies on SwiftData + CloudKit default behavior)

### Local caches (performance + UX)
- Images (entity/attribute “main photo”):
  - Persisted bytes: `MetaEntity.imageData`, `MetaAttribute.imageData` (`BrainMesh/BrainMesh/Models.swift`)
  - Local cache filenames: `imagePath` (relative name)
  - Disk store: `BrainMesh/BrainMesh/ImageStore.swift` → Application Support / `BrainMeshImages`
  - Progressive hydration: `BrainMesh/BrainMesh/ImageHydrator.swift`
    - Runs off-main using a background `ModelContext` and throttles passes (`AsyncLimiter(maxConcurrent: 1)`)
    - Auto-run throttled: once per 24h via `BMImageHydratorLastAutoRun` (`AppRootView.swift`)
- Attachments:
  - Synced bytes: `MetaAttachment.fileData` as `.externalStorage` (`MetaAttachment.swift`)
  - Disk store: `BrainMesh/BrainMesh/Attachments/AttachmentStore.swift` → Application Support / `BrainMeshAttachments`
  - Progressive hydration: `BrainMesh/BrainMesh/Attachments/AttachmentHydrator.swift`
  - Thumbnails: `BrainMesh/BrainMesh/Attachments/AttachmentThumbnailStore.swift`
    - Uses QuickLookThumbnailing/AVFoundation; throttled via `AsyncLimiter(maxConcurrent: 3)`

### Migration / Data Repair
- Graph scoping migration for core models:
  - `BrainMesh/BrainMesh/GraphBootstrap.swift`
    - Ensures at least one graph exists (`ensureAtLeastOneGraph`)
    - Migrates legacy records with `graphID == nil` to default graph (`migrateLegacyRecordsIfNeeded`)
- Attachment graphID migration (performance critical):
  - `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - Rationale (from file comments): predicates like `(gid == nil OR a.graphID == gid)` can force **in-memory filtering**, which is “catastrophic” when `externalStorage` blobs exist
- Duplicate graph ID repair:
  - `BrainMesh/BrainMesh/GraphPicker/GraphDedupeService.swift` removes duplicate `MetaGraph` records with same `id`

---

## UI Map (Main Screens, Navigation, Sheets / Flows)
### Root
- Entry point: `@main` in `BrainMesh/BrainMesh/BrainMeshApp.swift`
- Root view: `BrainMesh/BrainMesh/AppRootView.swift` → `ContentView()`

### Tabs (`BrainMesh/BrainMesh/ContentView.swift`)
1. **Entitäten** tab
   - `EntitiesHomeView()` (`BrainMesh/BrainMesh/Mainscreen/EntitiesHomeView.swift`)
   - Navigation: `NavigationStack` + `NavigationLink` to `EntityDetailRouteView(entityID:)` (same file)
   - Sheets:
     - Add entity: `AddEntityView()` (`Mainscreen/AddEntityView.swift`)
     - Graph switch/manage: `GraphPickerSheet()` (`BrainMesh/BrainMesh/GraphPickerSheet.swift`)
2. **Graph** tab
   - `GraphCanvasScreen()` (`BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + partials)
   - Navigation: `NavigationStack` in `GraphCanvasScreen`
   - Flows:
     - Graph picker sheet (`showGraphPicker`)
     - Focus picker / inspectors / overlays (see `GraphCanvasScreen+Inspector.swift`, `GraphCanvasScreen+Overlays.swift`)
     - Detail routing on node tap (helper `openDetails(for:)` in `GraphCanvasScreen` partials)
3. **Stats** tab
   - `GraphStatsView()` (`BrainMesh/BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` + partials)
   - Navigation: `NavigationStack` hosting “dashboard style” sections
4. **Einstellungen** tab
   - `NavigationStack` hosts `SettingsView(showDoneButton: false)` (`BrainMesh/BrainMesh/Settings/SettingsView.swift` + partials)

### Cross-cutting sheets / modals (selected)
- Onboarding:
  - Presentation coordination via `OnboardingCoordinator` (`BrainMesh/BrainMesh/Onboarding/OnboardingCoordinator.swift`)
  - Main sheet: `OnboardingSheetView` (`BrainMesh/BrainMesh/Onboarding/OnboardingSheetView.swift`)
- Node detail attachments/media:
  - Shared detail building blocks in `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/*`
  - Attachment preview: `AttachmentPreviewSheet.swift`, `QuickLookPreview.swift` (`BrainMesh/BrainMesh/Attachments/`)
- Graph security:
  - `GraphSecuritySheet.swift`, `GraphUnlockView.swift` (`BrainMesh/BrainMesh/Security/`)

---

## Build & Configuration (Targets, Entitlements, SPM, Secrets)
- Xcode project:
  - `BrainMesh/BrainMesh.xcodeproj/project.pbxproj`
- Targets:
  - `BrainMesh` (app)
  - `BrainMeshTests`
  - `BrainMeshUITests`
- Bundle identifier:
  - `de.marcfechner.BrainMesh` (from `project.pbxproj`)
- Team:
  - `HPJKAPZ8A3` (from `project.pbxproj`)
- Deployment target:
  - `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (from `project.pbxproj`)
- Devices:
  - `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad) (from `project.pbxproj`)
- Entitlements:
  - `BrainMesh/BrainMesh/BrainMesh.entitlements`
    - CloudKit enabled + iCloud container: `iCloud.de.marcfechner.BrainMesh`
    - `aps-environment = development`
- Info.plist:
  - `BrainMesh/BrainMesh/Info.plist` (background remote notifications; FaceID usage string)
- Dependencies (SPM):
  - No Swift Package references found in `project.pbxproj` (**SPM appears unused**).
- Secrets handling:
  - No `.xcconfig` files found in repo (**UNKNOWN** how API keys would be handled if introduced later).

---

## Conventions (Naming, Patterns, Do/Don’t)
### SwiftData + predicates
- Prefer store-translatable predicates; avoid `OR` on `graphID` when `externalStorage` blobs exist.
  - Rationale documented in `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- Use folded search fields:
  - Keep `nameFolded` / `searchLabelFolded` updated in `didSet` to avoid expensive transforms during query time (`Models.swift`)
- Multi-graph scoping:
  - New records should get `graphID` set (or derived from owner) to avoid legacy patterns (`Models.swift`, `GraphBootstrap.swift`)

### Concurrency / background loading
- Do NOT pass `@Model` instances across concurrency boundaries.
  - Pattern: loaders return value-only DTOs (`EntitiesHomeRow`, `GraphCanvasSnapshot`, `NodePickerRowDTO`) and UI resolves models by id in main context.
  - Example: `BrainMesh/BrainMesh/Mainscreen/EntitiesHomeLoader.swift` comment explicitly calls this out.
- Use actors + `Task.detached(priority: .utility)` for background `ModelContext` fetches.
  - Common pattern in: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `NodePickerLoader`, `NodeRenameService`
- Disk I/O must be off-main:
  - `ImageStore` warns: `loadUIImage(path:)` is synchronous; avoid calling from SwiftUI `body` (`BrainMesh/BrainMesh/ImageStore.swift`).

### SwiftUI file organization
- Large screens are split using `+` files (extensions) to keep compile times stable:
  - Example: `GraphCanvasScreen+*.swift`, `GraphCanvasView+*.swift`, `NodeDetailShared+*.swift`, `GraphStatsView+*.swift`, `StatsComponents+*.swift`
- Prefer item-driven sheets (avoids “blank sheet” races):
  - Example: `GraphPickerSheet.swift` uses item-driven `securityGraph` / `renameGraph` / `deleteGraph`.

---

## How to work on this project (setup + where to start)
### Setup checklist
- [ ] Open `BrainMesh/BrainMesh.xcodeproj`
- [ ] Verify Signing & Capabilities:
  - [ ] iCloud + CloudKit enabled (entitlements present in `BrainMesh/BrainMesh/BrainMesh.entitlements`)
  - [ ] Background Modes: Remote notifications (in `Info.plist`)
- [ ] Run on a device with iCloud logged in to validate sync behavior (**CloudKit is used by default**)
- [ ] First launch should create a default graph via `GraphBootstrap.ensureAtLeastOneGraph(using:)` (`GraphBootstrap.swift`)
- [ ] If the app shows “graph locked”, follow `Security/GraphUnlockView.swift` and `GraphLockCoordinator.swift`

### “Where do I start?” for new devs
- Understand persistence + scoping first:
  - `BrainMesh/BrainMesh/BrainMeshApp.swift` (ModelContainer + CloudKit)
  - `BrainMesh/BrainMesh/Models.swift` (models and scoping fields)
  - `BrainMesh/BrainMesh/GraphBootstrap.swift` (migration/bootstrapping)
  - `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (why strict predicates matter)
- Then UI entry points:
  - `BrainMesh/BrainMesh/ContentView.swift` (tabs)
  - `BrainMesh/BrainMesh/AppRootView.swift` (startup orchestration)
- Then performance-sensitive screens:
  - `BrainMesh/BrainMesh/GraphCanvas/*` (canvas)
  - `BrainMesh/BrainMesh/Mainscreen/EntitiesHomeView.swift` + `EntitiesHomeLoader.swift`

### Typical workflow: adding a feature (pattern)
- UI-only feature:
  - Add view(s) under the closest folder (`Mainscreen/`, `Settings/`, `GraphCanvas/`, …)
  - Wire via existing navigation (TabView / NavigationStack / sheet)
- Feature that needs data:
  - Add/extend a SwiftData model (usually in `Models.swift` or `Attachments/MetaAttachment.swift`)
  - Add the model to `Schema([...])` in `BrainMeshApp.swift`
  - Add migration/bootstrapping logic if new fields need backfill (**otherwise UNKNOWN how migration should be handled**)
- Feature that needs heavy fetching or I/O:
  - Create an `actor` loader returning value-only DTO(s)
  - Configure it at app start with the container (see `BrainMeshApp.swift` pattern using `AnyModelContainer`)
  - Keep SwiftUI views thin; avoid fetches in `body`

---

## Quick Wins (max 10, concrete)
1. **Verify / fix deployment target**: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `BrainMesh/BrainMesh.xcodeproj/project.pbxproj` looks suspiciously high; confirm intended minimum iOS.
2. **Consider `.externalStorage` for node images**: `MetaEntity.imageData` / `MetaAttribute.imageData` are plain `Data?` (`Models.swift`). If images grow, this can pressure CloudKit record size; evaluate moving to external storage (requires migration design → **UNKNOWN**).
3. **Centralize background `ModelContext` creation**: many loaders repeat `ModelContext(container.container); autosaveEnabled=false` (e.g. `EntitiesHomeLoader.swift`, `GraphCanvasDataLoader.swift`, `GraphStatsLoader.swift`, `LinkCleanup.swift`). A single helper reduces drift and mistakes.
4. **Add explicit cancellation for long canvas loads**: ensure `GraphCanvasScreen` cancels in-flight snapshot loads when switching graphs/params (some cancellation exists; verify in `GraphCanvasScreen+Loading.swift` → **UNKNOWN** if all paths cancel).
5. **Audit “sync image load in body”**: enforce `ImageStore.loadUIImageAsync` usage (file comment warns about sync loads in `ImageStore.swift`).
6. **GraphID completion sweep**: ensure all records are fully migrated to non-nil `graphID`, so predicates can be strict AND-only (see `GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`).
7. **Add perf signposts around hot paths**: use `BMLog` + `BMDuration` to time snapshot loads and render steps (`Observability/BMObservability.swift`).
8. **Consolidate AppStorage keys into one file**: keys are spread (`BMActiveGraphID`, onboarding flags, hydrator timestamps). A single constants enum reduces typos.
9. **Stabilize huge SwiftUI files further**: the biggest files (GraphCanvas rendering, EntitiesHome, NodeDetail shared core) are already split in places; continuing to extract subviews can improve compile times and readability.
10. **Add a “CloudKit status” debug panel**: even basic surface (iCloud available? container creation succeeded?) would reduce support time (**implementation currently UNKNOWN**).
