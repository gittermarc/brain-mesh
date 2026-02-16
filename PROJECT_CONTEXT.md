# PROJECT_CONTEXT

## TL;DR

BrainMesh is a SwiftUI knowledge-graph app for iOS/iPadOS (deployment target **iOS 26.0**), built on **SwiftData** with **CloudKit-backed sync** via `ModelConfiguration(cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`. The core domain is: **Graphs** contain **Entities** and **Attributes** connected by **Links**, plus **Attachments** and images with a local cache.

## Key Concepts / Domain Terms

- **Graph / Workspace (`MetaGraph`)**: top-level workspace; used to scope records via `graphID` (UUID). The active graph is stored in `@AppStorage("BMActiveGraphID")` (e.g. `BrainMesh/AppRootView.swift`, `BrainMesh/Mainscreen/EntitiesHomeView.swift`).
- **Entity (`MetaEntity`)**: primary node type.
- **Attribute (`MetaAttribute`)**: secondary node type; can be owned by an entity (`MetaAttribute.owner`).
- **Link (`MetaLink`)**: directed edge between two nodes (source/target stored as `(kindRaw, UUID, label)`).
- **Attachment (`MetaAttachment`)**: files/videos/gallery images attached to a node; ownership expressed via `(ownerKindRaw, ownerID)` (no SwiftData relationships).
- **Main image vs Gallery images**:
  - main image is stored on `MetaEntity.imageData` / `MetaAttribute.imageData` (synced) + `imagePath` (local cache).
  - gallery images are stored as `MetaAttachment` with `contentKind == .galleryImage` (`BrainMesh/PhotoGallery/PhotoGalleryImportController.swift`).
- **Graph lock**: optional biometric/password gate per graph (`BrainMesh/Security/*`, fields also present on `MetaGraph`/`MetaEntity`/`MetaAttribute`).
- **Focus / Neighborhood**: Graph view can render a subset around a center entity with *hops* (`BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`).
- **Lens / Spotlight**: Graph rendering can hide non-relevant nodes and restrict physics to selection+neighbors (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + `LensContext` in `GraphCanvasTypes`).
- **NodeKey / NodeRef**: stable identifiers used for graph nodes + linking UI (`BrainMesh/Mainscreen/NodeKey.swift`, `NodeRef.swift`).

## Architecture Map

**UI (SwiftUI)**
- Root: `BrainMesh/ContentView.swift` (TabView) -> `EntitiesHomeView` / `GraphCanvasScreen` / `GraphStatsView`
- Detail flows: `EntityDetailView`, `AttributeDetailView`, sheets for add/link/picker/settings/onboarding.

**Domain / Application Services**
- `BrainMesh/GraphBootstrap.swift`: ensures default graph + migrates legacy `graphID == nil`.
- `BrainMesh/GraphStatsService.swift`: graph counters via `fetchCount`.
- `BrainMesh/GraphPicker/*`: dedupe, rename, delete graph flows.
- `BrainMesh/Security/*`: lock/unlock + password hashing.

**Persistence (SwiftData)**
- Models: `BrainMesh/Models.swift` + `BrainMesh/Attachments/MetaAttachment.swift`
- Queries:
  - `@Query` for simple lists (e.g. graphs), and explicit `FetchDescriptor` in hot screens (e.g. entities search).
  - Reusable link queries: `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`.

**Local Storage / Caches**
- Image cache: `BrainMesh/ImageStore.swift` + deterministic filenames set by `BrainMesh/ImageHydrator.swift`.
- Attachment preview/thumbnail caches: `BrainMesh/Attachments/*` (e.g. `AttachmentStore`, `AttachmentThumbnailStore`).

**Observability**
- `BrainMesh/Observability/BMObservability.swift`: `BMLog` categories + `BMDuration` helper.

## Folder Map

Repository roots:
- `BrainMesh/` — app source + assets
- `BrainMesh.xcodeproj/` — Xcode project (targets, build settings)
- `BrainMeshTests/` — unit tests (Swift `Testing` framework)
- `BrainMeshUITests/` — UI tests

App folder overview (counts include subfolders):

| Path (BrainMesh/BrainMesh) | Files | Swift files |
| --- | --- | --- |
| Appearance | 5 | 5 |
| AppRootView.swift | 1 | 1 |
| Assets.xcassets | 40 | 0 |
| Attachments | 15 | 15 |
| BrainMesh.entitlements | 1 | 0 |
| BrainMeshApp.swift | 1 | 1 |
| ContentView.swift | 1 | 1 |
| FullscreenPhotoView.swift | 1 | 1 |
| GraphBootstrap.swift | 1 | 1 |
| GraphCanvas | 17 | 16 |
| GraphPicker | 6 | 6 |
| GraphPickerSheet.swift | 1 | 1 |
| GraphSession.swift | 1 | 1 |
| GraphStatsService.swift | 1 | 1 |
| GraphStatsView.swift | 1 | 1 |
| Icons | 5 | 4 |
| ImageHydrator.swift | 1 | 1 |
| Images | 1 | 1 |
| ImageStore.swift | 1 | 1 |
| Info.plist | 1 | 0 |
| Mainscreen | 22 | 22 |
| Models.swift | 1 | 1 |
| NotesAndPhotoSection.swift | 1 | 1 |
| Observability | 1 | 1 |
| Onboarding | 8 | 8 |
| PhotoGallery | 8 | 8 |
| Security | 6 | 6 |
| SettingsAboutSection.swift | 1 | 1 |
| SettingsView.swift | 1 | 1 |

## Data Model Map

| Model | Defined in | Purpose | Key fields (partial) | Relationships |
| --- | --- | --- | --- | --- |
| MetaGraph | BrainMesh/Models.swift | Workspace / Graph container (name + security settings). | id: UUID<br>createdAt: Date<br>name, nameFolded<br>lockBiometricsEnabled<br>lockPasswordEnabled<br>… | (none in SwiftData; graphs referenced by graphID in other models) |
| MetaEntity | BrainMesh/Models.swift | Entity node in graph. | id: UUID<br>graphID: UUID? (scope; nil = legacy)<br>name, nameFolded<br>notes<br>iconSymbolName<br>… | attributes: [MetaAttribute]? @Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner) |
| MetaAttribute | BrainMesh/Models.swift | Attribute node, optionally owned by an entity. | id: UUID<br>graphID: UUID?<br>name, nameFolded<br>notes<br>iconSymbolName<br>… | owner is a plain property; inverse defined on MetaEntity.attributes only |
| MetaLink | BrainMesh/Models.swift | Directed link between two nodes (entity/attribute). | id: UUID<br>createdAt: Date<br>note: String?<br>graphID: UUID?<br>sourceKindRaw/sourceID/sourceLabel<br>… | No SwiftData relationships; references by IDs + kind. |
| MetaAttachment | BrainMesh/Attachments/MetaAttachment.swift | Files/videos/gallery-images attached to entities/attributes. | id: UUID<br>createdAt: Date<br>graphID: UUID?<br>ownerKindRaw/ownerID<br>contentKindRaw (file|video|galleryImage)<br>… | No SwiftData relationships; owner expressed as kind+ID. |

### Relationships & Ownership Rules

- `MetaEntity.attributes` is the only explicit SwiftData relationship macro in the core graph model (`BrainMesh/Models.swift`).
  - Delete rule: **cascade** (deleting an entity deletes its attributes).
  - The inverse is declared only once (on the entity side) to avoid SwiftData macro circularity.
- `MetaLink` is ID-based (no relationships).
- `MetaAttachment` is ID-based (no relationships); deletions must be handled explicitly (see `BrainMesh/Attachments/AttachmentCleanup.swift`).

## Sync / Storage

### SwiftData container
- Container is created in `BrainMesh/BrainMeshApp.swift`:
  - `Schema([MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment])`
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - In **DEBUG**: failure is a `fatalError` (no silent fallback).
  - In **RELEASE**: falls back to local-only `ModelConfiguration(schema: schema)`.

### iCloud / CloudKit capabilities
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud container: **iCloud.de.marcfechner.BrainMesh**
  - iCloud service: CloudKit
  - `aps-environment = development` (push entitlement present; CloudKit sync uses push under the hood).

### Local caches
- Images (main images):
  - Disk cache folder: Application Support / `BrainMeshImages` (`BrainMesh/ImageStore.swift`).
  - Cache path is a deterministic `{UUID}.jpg` stored in `MetaEntity.imagePath` / `MetaAttribute.imagePath`.
  - Hydration: `BrainMesh/ImageHydrator.swift` (incremental scan where `imageData != nil`, sets `imagePath` + writes file if missing).
  - Startup trigger: `BrainMesh/AppRootView.swift` (throttled to at most once per 24h; run-once-per-launch guard).

- Attachments:
  - `MetaAttachment.fileData` uses `@Attribute(.externalStorage)` (`BrainMesh/Attachments/MetaAttachment.swift`) to reduce record size pressure.
  - Local preview/cache paths live in `MetaAttachment.localPath` and are cleaned via `BrainMesh/Attachments/AttachmentCleanup.swift` / settings maintenance.

### Offline behavior (what the code guarantees)
- **Guaranteed**: SwiftData provides a local store; UI reads/writes via `ModelContext`.
- **UNKNOWN**: explicit offline UX (conflict messaging, retry/backoff) — no dedicated sync UI is present in the codebase.

## UI Map

### Root navigation
- `BrainMesh/BrainMeshApp.swift` -> `AppRootView` (startup orchestration) -> `ContentView` (TabView)

### Tabs (`BrainMesh/ContentView.swift`)
1) **Entitäten**: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
   - Search + list (custom `FetchDescriptor`-based fetching)
   - Sheets:
     - Add Entity: `BrainMesh/Mainscreen/AddEntityView.swift`
     - Graph picker: `BrainMesh/GraphPickerSheet.swift`
     - Settings: `BrainMesh/SettingsView.swift`

2) **Graph**: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
   - Canvas rendering + physics: `BrainMesh/GraphCanvas/GraphCanvasView.swift` and partials
   - Inspector, overlays, loading, layout seeding are split across `GraphCanvasScreen+*.swift`
   - Sheets:
     - Entity/Attribute details: `EntityDetailView` / `AttributeDetailView`
     - Graph picker: `GraphPickerSheet`

3) **Stats**: `BrainMesh/GraphStatsView.swift`
   - Uses `BrainMesh/GraphStatsService.swift` (count-based; avoids loading full objects).

### Cross-cutting sheets / flows
- Onboarding: `BrainMesh/Onboarding/OnboardingSheetView.swift`
  - Presented from `AppRootView` (auto show rules based on `@AppStorage` + `OnboardingProgress.compute`).
- Graph lock / unlock:
  - Coordinator: `BrainMesh/Security/GraphLockCoordinator.swift`
  - Unlock UI: `BrainMesh/Security/GraphUnlockView.swift` via `fullScreenCover` in `AppRootView`.
- Photos / gallery images: `BrainMesh/PhotoGallery/*`
- File/video attachments: `BrainMesh/Attachments/*`

## Build & Configuration

- Xcode project: `BrainMesh.xcodeproj/project.pbxproj`
- Targets (bundle IDs from pbxproj):
  - App: `de.marcfechner.BrainMesh`
  - Unit tests: `de.marcfechner.BrainMeshTests`
  - UI tests: `de.marcfechner.BrainMeshUITests`
- Deployment target: **iOS 26.0** (`IPHONEOS_DEPLOYMENT_TARGET` in pbxproj)
- Team: `HPJKAPZ8A3` (`DEVELOPMENT_TEAM` in pbxproj)
- Info.plist: `BrainMesh/Info.plist`
  - `UIBackgroundModes`: `remote-notification`
  - `NSFaceIDUsageDescription`: present
- SPM dependencies: **none** detected in `project.pbxproj` (`XCSwiftPackageProductDependency` not present).
- Secrets handling: **UNKNOWN** (no `.xcconfig` found; no obvious secret placeholders in repo).

## Conventions

- File splitting:
  - Large SwiftUI screens are split by feature area using `+` partial files, e.g. `GraphCanvasScreen+Loading.swift`, `GraphCanvasScreen+Inspector.swift`.
- SwiftData macros:
  - Keep inverse relationships defined on only one side to avoid macro cycles (`MetaEntity.attributes` vs `MetaAttribute.owner` in `BrainMesh/Models.swift`).
- Graph scoping:
  - Most fetches include a `graphID` filter; legacy (`graphID == nil`) is often included for gentle migration (e.g. `EntitiesHomeView.fetchEntities`).
- Search:
  - Case/diacritic-insensitive search uses `BMSearch.fold` and stored folded fields (`nameFolded`, `searchLabelFolded`) to avoid expensive runtime transforms.
- Avoid fetch in render path:
  - GraphCanvas caches derived state to reduce per-frame computations (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift`).
- Sheets:
  - Prefer item-driven sheets (`.sheet(item:)`) for stability (commented in `BrainMesh/GraphPickerSheet.swift`).

## How to work on this project

### Setup (new dev)
1. Open `BrainMesh.xcodeproj`.
2. Verify Signing & Capabilities:
   - iCloud (CloudKit) container: `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`).
   - Background mode: remote notifications (`BrainMesh/Info.plist`).
3. Run on a device/simulator signed into iCloud if you want to exercise CloudKit-backed SwiftData sync.
4. If you see SwiftData/CloudKit container creation failures:
   - DEBUG builds will `fatalError` by design (`BrainMesh/BrainMeshApp.swift`).
   - Consider temporarily switching to local-only configuration for debugging (**do not ship that unintentionally**).

### Where to start when adding a feature
- UI feature on entity/attribute detail:
  - `BrainMesh/Mainscreen/EntityDetailView.swift` / `AttributeDetailView.swift`
  - Reuse query helpers where possible (`NodeLinksQueryBuilder`, `PhotoGalleryQuery`).
- New persisted data:
  - Extend the SwiftData schema (`BrainMesh/Models.swift` or a new `@Model` file)
  - Update `Schema([...])` in `BrainMesh/BrainMeshApp.swift`
  - Consider migration implications (see `ARCHITECTURE_NOTES.md`).
- Graph view behavior:
  - State + wiring: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - Loading / graph building: `GraphCanvasScreen+Loading.swift`
  - Rendering / physics: `GraphCanvasView+Rendering.swift`, `GraphCanvasView+Physics.swift`

## Quick Wins (max 10)

1. Add legacy migration for `MetaAttachment.graphID == nil` (currently `GraphBootstrap.migrateLegacyRecordsIfNeeded` covers entities/attributes/links only).  
   - Files: `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Attachments/MetaAttachment.swift`.
2. Centralize the “graph scope predicate” logic (currently repeated in many `FetchDescriptor`/`#Predicate` blocks).  
   - Files: `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`, `BrainMesh/Attachments/*`.
3. Delete or rename `BrainMesh/Onboarding/Untitled.swift` if unused (reduce noise; avoid accidental compilation issues).
4. Ensure all delete flows also clean up attachments and cached files (attachments are not cascade-related).  
   - Files: `BrainMesh/Attachments/AttachmentCleanup.swift`, delete actions in `EntityDetailView` / `AttributeDetailView` (**verify**).
5. Audit `Task { ... }` reloads in `GraphCanvasScreen` for overlap; consider a single cancellable loader task handle.  
   - Files: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`.
6. Add unit tests for the fold/search helpers and query builders (`BMSearch.fold`, `NodeLinksQueryBuilder`).  
   - Files: `BrainMeshTests/BrainMeshTests.swift`.
7. Add a debug-only “reset local caches” action for images + attachments to reproduce cache edge cases.  
   - Files: `BrainMesh/SettingsView.swift`, `BrainMesh/ImageStore.swift`, `BrainMesh/Attachments/*`.
8. Consider making `MetaEntity.imageData` / `MetaAttribute.imageData` use `@Attribute(.externalStorage)` if images grow beyond “small JPEGs”.  
   - Files: `BrainMesh/Models.swift`. (**Schema change; see risks**)
9. Add cheap counters/logs for load sizes (nodes/edges) and physics tick max time to spot regressions (some already exist via `BMLog` + `BMDuration`).  
   - Files: `BrainMesh/GraphCanvas/*`, `BrainMesh/Observability/BMObservability.swift`.
10. Document the expected iCloud/CloudKit behavior for QA (when data should appear on device B, how long it can take, what to do if it doesn’t).  
    - Docs only; implementation not required.
