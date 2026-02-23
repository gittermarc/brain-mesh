# PROJECT_CONTEXT

Last updated: 2026-02-23

## TL;DR
BrainMesh is a SwiftUI iOS/iPadOS app (deployment target: **iOS 26.0**) for building personal knowledge graphs. Users manage multiple **Graphs** (workspaces) containing **Entities**, **Attributes**, and **Links**, enriched by configurable **Detail Fields** and **Attachments**. Persistence is **SwiftData** with **CloudKit (private DB) sync** when available; Release builds can fall back to local-only storage on CloudKit init failure (BrainMesh/BrainMeshApp.swift).

## Key concepts / domain terms
- **Graph**: workspace container (name + optional lock settings). Active graph is stored in `@AppStorage(BMAppStorageKeys.activeGraphID)`.
- **Entity**: primary node type (name, notes, optional icon/photo), scoped by `graphID`.
- **Attribute**: secondary node type owned by an Entity (name, notes, optional icon/photo), scoped by `graphID`.
- **Link**: edge between nodes. Stored as scalar endpoints + denormalized endpoint labels.
- **Detail Field**: schema defined on an Entity (type, order, pinning, unit/options).
- **Detail Value**: typed value for a Detail Field, stored per Attribute.
- **Attachment**: file/video/gallery image attached to a node (owner expressed as kind + UUID; bytes stored as external storage).
- **Graph lock**: optional biometric/passcode and/or password gating (full-screen cover).

## Architecture map (layers + dependencies)

### UI (SwiftUI)
- Root tabs: BrainMesh/ContentView.swift
- Screens and components:
  - Entities + node details: `BrainMesh/Mainscreen/*`
  - Graph canvas: `BrainMesh/GraphCanvas/*`
  - Stats dashboard: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`
  - Onboarding: `BrainMesh/Onboarding/*`
  - Graph lock/unlock: `BrainMesh/Security/*`

### State / stores (ObservableObject + AppStorage)
- Appearance: BrainMesh/Settings/Appearance/AppearanceStore.swift (persisted JSON in UserDefaults)
- Display settings: BrainMesh/Settings/Display/DisplaySettingsStore.swift (preset + per-screen overrides; migrations included)
- Coordinators:
  - `OnboardingCoordinator` (`BrainMesh/Onboarding/OnboardingCoordinator.swift`)
  - `GraphLockCoordinator` (BrainMesh/Security/GraphLockCoordinator.swift)
  - `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`)
- AppStorage keys are centralized in BrainMesh/Support/BMAppStorageKeys.swift

### Background data work (actors)
Heavy SwiftData fetches are moved off the UI thread via actor loaders/hydrators configured in BrainMesh/Support/AppLoadersConfigurator.swift.

### Storage (SwiftData + disk caches)
- SwiftData models: `BrainMesh/Models/*` + BrainMesh/Attachments/MetaAttachment.swift
- CloudKit-enabled `ModelContainer`: BrainMesh/BrainMeshApp.swift
- Local caches:
  - BrainMesh/ImageStore.swift
  - BrainMesh/Attachments/AttachmentStore.swift

### Dependency direction (intended)
`SwiftUI Views` → `Stores/Coordinators` and (when heavy) → `Loader actor (DTO)` → `SwiftData Models` → `Disk cache stores`

Implementation convention evidenced in multiple DTO comments: **do not pass SwiftData `@Model` instances across actor boundaries** (e.g. BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift, BrainMesh/Mainscreen/NodePickerLoader.swift, BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift).

## Service catalog (where “work” happens)
This is the practical index for navigation/debugging.

| Service / component | Type | Responsibility | File |
|---|---|---|---|
| `EntitiesHomeLoader` | actor | Off-main entity list + search + optional counts caches | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` |
| `GraphCanvasDataLoader` | actor | Off-main graph snapshot loading (global or neighborhood BFS) | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` |
| `GraphStatsLoader` | actor | Off-main stats snapshots (dashboard + per-graph) | `BrainMesh/Stats/GraphStatsLoader.swift` |
| `GraphStatsService` | service | Stats computations using `ModelContext` | `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift` |
| `NodePickerLoader` | actor | Off-main node picker rows (entities/attributes) | `BrainMesh/Mainscreen/NodePickerLoader.swift` |
| `NodeConnectionsLoader` | actor | Off-main incoming/outgoing link DTOs | `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` |
| `NodeMediaPreviewLoader` | actor | Media preview/count snapshot for detail screens | `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift` |
| `MediaAllLoader` | actor | Off-main media list (attachments) snapshot | `BrainMesh/Attachments/MediaAllLoader.swift` |
| `ImageHydrator` | actor | Background: ensure deterministic JPEG cache for `imageData` | `BrainMesh/ImageHydrator.swift` |
| `AttachmentHydrator` | actor | On-demand: materialize `fileData` to local cache URL | `BrainMesh/Attachments/AttachmentHydrator.swift` |
| `NodeRenameService` | actor | Update denormalized link labels after rename | `BrainMesh/Mainscreen/LinkCleanup.swift` |
| `GraphLockCoordinator` | MainActor O.O. | Enforce graph unlock, maintain unlocked set | `BrainMesh/Security/GraphLockCoordinator.swift` |
| `SyncRuntime` | MainActor O.O. | CloudKit vs local-only + iCloud account status | `BrainMesh/Settings/SyncRuntime.swift` |
| `ImageStore` / `AttachmentStore` | nonisolated | Local cache management + IO helpers | `BrainMesh/ImageStore.swift`, `BrainMesh/Attachments/AttachmentStore.swift` |

Notes:
- Loader services are configured once via `AppLoadersConfigurator.configureAllLoaders(with:)` (BrainMesh/Support/AppLoadersConfigurator.swift).
- DTO snapshots sometimes use `@unchecked Sendable`; treat them as “value-only, no SwiftData models” contracts.

## Folder map (folder → purpose)
- `BrainMesh/Models/`: SwiftData models + search helpers (`BMSearch`).
- `BrainMesh/Attachments/`: attachments model, cache store, hydrator, and media import flows.
- `BrainMesh/GraphCanvas/`: graph canvas UI (rendering/physics/gestures), minimap, inspector, and snapshot loader.
- `BrainMesh/Mainscreen/`: main navigation for entities/attributes, detail screens, pickers, link creation flows.
- `BrainMesh/Stats/`: stats service + loader + dashboard views.
- `BrainMesh/Settings/`: settings UI + sync diagnostics (`SyncRuntime`).
- `BrainMesh/Security/`: graph lock coordinator + unlock UI + password setup.
- `BrainMesh/Onboarding/`: onboarding sheet and explainer UI.
- `BrainMesh/Icons/`: SF Symbols picker and icon picker wrappers.
- `BrainMesh/PhotoGallery/`: lightweight gallery viewer/browser.
- `BrainMesh/Observability/`: logging categories + duration measurement helpers.
- `BrainMesh/Support/`: utilities (AppStorage keys, async limiter, AnyModelContainer, system modal coordination, details completion UI).

## Data model map (SwiftData)
SwiftData `Schema([...])` is defined in BrainMesh/BrainMeshApp.swift.

### `MetaGraph` (BrainMesh/Models/MetaGraph.swift)
- `id`, `createdAt`, `name`, `nameFolded`
- Security fields: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### `MetaEntity` (BrainMesh/Models/MetaEntity.swift)
- `id`, `createdAt`, `graphID` (optional), `name`, `nameFolded`, `notes`
- Media: `iconSymbolName`, `imageData` (synced), `imagePath` (local cache filename)
- Relationships:
  - `attributes` → `[MetaAttribute]` (cascade; inverse on `MetaAttribute.owner`)
  - `detailFields` → `[MetaDetailFieldDefinition]` (cascade; inverse on `MetaDetailFieldDefinition.owner`)

### `MetaAttribute` (BrainMesh/Models/MetaAttribute.swift)
- `id`, `graphID` (optional), `name`, `nameFolded`, `searchLabelFolded`, `notes`
- Media: `iconSymbolName`, `imageData` (synced), `imagePath` (local cache filename)
- Owner: `owner: MetaEntity?` (inverse defined on entity side only)
- Relationship: `detailValues` → `[MetaDetailFieldValue]` (cascade)

### Details schema + values (BrainMesh/Models/DetailsModels.swift)
- Definition (`MetaDetailFieldDefinition`): belongs to an Entity; supports pinned fields (UI enforces max 3).
- Value (`MetaDetailFieldValue`): belongs to an Attribute; stores typed columns for future sort/filter potential.

### `MetaLink` (BrainMesh/Models/MetaLink.swift)
- Scalar endpoints: kind+UUID on both sides
- Denormalized labels: `sourceLabel`, `targetLabel`
- Maintenance after rename: `NodeRenameService` in BrainMesh/Mainscreen/LinkCleanup.swift

### `MetaAttachment` (BrainMesh/Attachments/MetaAttachment.swift)
- Owner expressed as: `ownerKindRaw` + `ownerID`
- Bytes: `fileData` in external storage
- Local cache pointer: `localPath`

### Graph scoping + legacy
- Many models include `graphID: UUID?` and startup migration backfills `graphID` for legacy records in BrainMesh/GraphBootstrap.swift.

## Sync / storage

### SwiftData + CloudKit
- Container initialization: `ModelConfiguration(schema: ..., cloudKitDatabase: .automatic)` in BrainMesh/BrainMeshApp.swift.
- Debug: CloudKit container creation failure → `fatalError` (no fallback).
- Release: CloudKit init failure → fallback to local-only ModelConfiguration + `SyncRuntime.storageMode = .localOnly` (BrainMesh/BrainMeshApp.swift, BrainMesh/Settings/SyncRuntime.swift).

### iCloud configuration
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - CloudKit enabled
  - Container identifier: `iCloud.de.marcfechner.BrainMesh`
- `Info.plist` highlights:
  - `UIBackgroundModes = remote-notification`
  - `NSFaceIDUsageDescription`

### Local caches + hydration
- `ImageStore` (BrainMesh/ImageStore.swift): NSCache memory cache + Application Support / `BrainMeshImages`.
- `AttachmentStore` (BrainMesh/Attachments/AttachmentStore.swift): Application Support / `BrainMeshAttachments`.
- `ImageHydrator` (BrainMesh/ImageHydrator.swift): background pass ensuring deterministic JPEG cache for records with `imageData`.
- `AttachmentHydrator` (BrainMesh/Attachments/AttachmentHydrator.swift): on-demand materialization of attachment bytes to disk with throttling + per-ID de-duplication.

Offline behavior: **UNKNOWN** (no explicit offline policy documented).

## UI map (screens, navigation, sheets)

### Root
- `BrainMeshApp` → `AppRootView` (BrainMesh/BrainMeshApp.swift, BrainMesh/AppRootView.swift)
- Tabs in BrainMesh/ContentView.swift:
  1) **Entitäten**: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift
  2) **Graph**: BrainMesh/GraphCanvas/GraphCanvasScreen.swift
  3) **Stats**: BrainMesh/Stats/GraphStatsView/GraphStatsView.swift
  4) **Einstellungen**: BrainMesh/Settings/SettingsView.swift

### Global sheets / full-screen covers
- Onboarding sheet: presented from BrainMesh/AppRootView.swift
- Graph unlock full-screen cover: presented from BrainMesh/AppRootView.swift

### Core flows (where to look)
- Switch/manage graphs: BrainMesh/GraphPickerSheet.swift
- Create Entity: BrainMesh/Mainscreen/AddEntityView.swift
- Create Attribute: BrainMesh/Mainscreen/AddAttributeView.swift
- Create Link: BrainMesh/Mainscreen/AddLinkView.swift and BrainMesh/Mainscreen/BulkLinkView.swift
- Configure Details schema: BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaBuilderView.swift
- Edit Details values: BrainMesh/Mainscreen/Details/DetailsValueEditorSheet/DetailsValueEditorSheet.swift
- Details rendering: BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift
- Pickers: `NodePickerView` (BrainMesh/Mainscreen/NodePickerView.swift) + BrainMesh/Mainscreen/NodePickerLoader.swift

### Per-tab data flow (operational view)
- **Entities tab**: `EntitiesHomeView` triggers `EntitiesHomeLoader.loadSnapshot(...)` and renders DTO rows; navigation resolves models from main `ModelContext` by id.
- **Graph tab**: `GraphCanvasScreen.loadGraph(...)` calls `GraphCanvasDataLoader.loadSnapshot(...)`, commits nodes/edges/caches in one go, then `GraphCanvasView` runs physics + Canvas rendering.
- **Stats tab**: `GraphStatsView` requests a dashboard snapshot (`GraphStatsLoader.loadDashboardSnapshot`) and optionally per-graph counts (`loadPerGraphCounts`).
- **Detail screens**: mix of `@Query` for links and actor loaders for heavy lists/previews (`NodeConnectionsLoader`, `NodeMediaPreviewLoader`).

## Build & configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj`
- Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests`
- Bundle identifiers: `de.marcfechner.BrainMesh` (+ tests variants)
- Deployment target: iOS 26.0
- Swift Package dependencies: none found in `project.pbxproj`.
- Secrets handling: **UNKNOWN** (no `.xcconfig` found).

## Conventions (Do / Don’t)

### Do
- Keep SwiftData fetches off the render path; use actor loaders returning DTO snapshots.
- Prefer `.task(id:)` + cancellation for debounced reload flows.
- Use `BMSearch.fold` for folded search indexes and store folded fields on models.
- Use `BMAppStorageKeys.*` for AppStorage keys (BrainMesh/Support/BMAppStorageKeys.swift).
- Keep file I/O off-main; prefer async IO helpers.
- When a View has many sheets, prefer item-driven `.sheet(item:)`.

### Don’t
- Don’t pass SwiftData models across actor boundaries.
- Don’t do synchronous disk IO in `body`.
- Don’t introduce infinite/uncancellable background work.

## How to work on this project

### Setup (new dev)
1. Open `BrainMesh/BrainMesh.xcodeproj` in Xcode.
2. Set a valid Signing Team for the `BrainMesh` target.
3. Ensure iCloud capability is enabled and the container matches entitlements (`iCloud.de.marcfechner.BrainMesh`).
4. Run on an iOS 26 simulator/device.

### Smoke test checklist
- [ ] Entities tab: create entity, search it, delete it
- [ ] Entity detail: add attribute, set notes, edit details values
- [ ] Links: create link, confirm duplicates are blocked
- [ ] Graph tab: load, pan/zoom, select a node, open detail sheet, return
- [ ] Settings: Sync section shows account status; maintenance actions run
- [ ] Background/foreground: app locks as expected (graph lock)

### Adding features (practical checklist)
- **New SwiftData model/field** → update model file(s) + Schema in BrainMesh/BrainMeshApp.swift + consider migration defaults.
- **New heavy list/screen** → actor loader + DTO + wire in BrainMesh/Support/AppLoadersConfigurator.swift.
- **New setting** → prefer `DisplaySettingsStore` for per-screen display, `AppearanceStore` for global theme; add AppStorage keys only when needed.
- **New completion/suggestions behavior** → see Details completion index in BrainMesh/Support/DetailsCompletion/DetailsCompletionIndex.swift.

### Debug “where do I look?”
- Graph load timings: `BMLog.load` in `GraphCanvasScreen+Loading.swift`
- Physics tick timings: `BMLog.physics` in `GraphCanvasView+Physics.swift`
- Sync diagnostics: `SyncRuntime` surfaced in Settings

## Quick wins (max 10; concrete)
1. Scope pinned detail value fetches by `graphID` to avoid cross-graph scans (EntityAttributesAllListModel lookup helper).
2. Extract repeated “active graph name” helper into one place and reuse it across tabs.
3. Persist GraphCanvas `keyByIdentifier` across frames (rebuild only when node set changes).
4. Replace TTL counts cache with mutation-driven invalidation in `EntitiesHomeLoader`.
5. Add explicit graph scoping to attachment-related fetches wherever possible (owner kind + graphID).
6. Document or remove unused node-level lock fields (only graph lock enforced today).
7. Audit `FetchDescriptor` usage for fetch limits on potentially large lists (symbols picker, media lists).
8. Make cache maintenance actions cancellable and show progress states that can dismiss.
9. Split the largest shared UI file (`NodeDetailShared+Core.swift`) into focused views to reduce compile churn.
10. Add a short schema guard comment near the Schema array in `BrainMeshApp.swift` to prevent drift.