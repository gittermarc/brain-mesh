# PROJECT_CONTEXT.md

_Generated: 2026-03-01 • Project: BrainMesh • Deployment target: iOS 26.0_

## TL;DR
BrainMesh is a SwiftUI iOS app (iOS 26.0 target) for building a personal knowledge graph. Data is stored in SwiftData and synced via CloudKit (Private DB) when available; in Release builds it can fall back to local-only storage if CloudKit initialization fails (see `BrainMesh/BrainMeshApp.swift`).

## Key Concepts (Domain Terms)
- **Graph (Workspace)**: A scoped dataset. Many records carry an optional `graphID` to separate workspaces (`BrainMesh/Models/MetaGraph.swift`, `graphID` fields across models).
- **Entity**: A top-level node concept (e.g. “Project”, “Person”) (`BrainMesh/Models/MetaEntity.swift`).
- **Attribute**: A node that belongs to an entity (e.g. “Marc”, “München”) (`BrainMesh/Models/MetaAttribute.swift`).
- **Link**: Directed connection between two nodes (entity/attribute), optional note (`BrainMesh/Models/MetaLink.swift`).
- **Details fields**: Custom field schema per entity (`MetaDetailFieldDefinition`) and typed values per attribute (`MetaDetailFieldValue`) (`BrainMesh/Models/DetailsModels.swift`).
- **Attachments**: Files/videos/gallery images attached to an entity/attribute (`BrainMesh/Attachments/MetaAttachment.swift`).
- **Graph Canvas**: Interactive graph visualization with physics simulation and incremental expand (`BrainMesh/GraphCanvas/...`).

## Architecture Map (Layers / Modules)
- **UI (SwiftUI Views)**
  - Root tabs: `BrainMesh/ContentView.swift` (Entities, Graph, Stats, Settings)
  - Main CRUD flows: `BrainMesh/Mainscreen/...`
  - Graph canvas UI: `BrainMesh/GraphCanvas/GraphCanvasScreen/...` + `BrainMesh/GraphCanvas/GraphCanvasView/...`
  - Settings: `BrainMesh/Settings/...`
  - Onboarding: `BrainMesh/Onboarding/...`
  - Pro / Paywall: `BrainMesh/Pro/...`

- **App Coordinators / Stores (ObservableObject @MainActor)**
  - App bootstrap & DI: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`
  - Appearance: `BrainMesh/Settings/Appearance/AppearanceStore.swift`
  - Display settings: `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
  - Tabs: `BrainMesh/RootTabRouter.swift`
  - Cross-screen jump: `BrainMesh/GraphJumpCoordinator.swift`
  - Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
  - Security: `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`
  - “System picker is open” guard: `BrainMesh/Support/SystemModalCoordinator.swift`

- **Data Access / Background Loaders (Actors + background ModelContext)**
  - Central configuration: `BrainMesh/Support/AppLoadersConfigurator.swift` (fire-and-forget Task that configures all loaders with a `ModelContainer`).
  - Graph canvas snapshot loader: `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift` (+Global/+Neighborhood/+Caches).
  - Entities list loader: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift` (+Fetch/+Counts/+Cache).
  - Stats loader: `BrainMesh/Stats/GraphStatsLoader.swift`.
  - Pickers / connections / bulk link:
    - `BrainMesh/Mainscreen/NodePickerLoader.swift`
    - `BrainMesh/Mainscreen/NodeConnectionsLoader.swift`
    - `BrainMesh/Mainscreen/BulkLinkLoader.swift`

- **Storage / Caches**
  - Image cache: `BrainMesh/ImageHydrator.swift` + `BrainMesh/ImageStore.swift` (deterministic JPEG cache in Application Support).
  - Attachment cache: `BrainMesh/Attachments/AttachmentHydrator.swift` + `BrainMesh/Attachments/AttachmentStore.swift` (cached bytes in Application Support).
  - Throttling primitives: `BrainMesh/Support/AsyncLimiter.swift`.

## Folder Map (Directory → Purpose)
- `BrainMesh/Models/` → SwiftData @Model types + enums (graph/entity/attribute/link/details/templates).
- `BrainMesh/Mainscreen/` → Main CRUD UI: Entities list, detail screens, pickers, link flows.
- `BrainMesh/GraphCanvas/` → Graph visualization, physics, overlays, snapshot loaders.
- `BrainMesh/Attachments/` → Attachment model, import pipeline, hydration, thumbnails, migration helpers.
- `BrainMesh/PhotoGallery/` → Gallery browsing/viewing/import UX (PhotosUI).
- `BrainMesh/GraphTransfer/` → Export/import format + services + UI.
- `BrainMesh/Stats/` → Graph statistics UI + off-main loader.
- `BrainMesh/Settings/` → Settings UI, sync runtime surfaces, display prefs.
- `BrainMesh/Security/` → Graph lock (biometrics/password) flows and crypto.
- `BrainMesh/Pro/` → StoreKit2 products, entitlement store, paywall, Pro center.
- `BrainMesh/Onboarding/` → Onboarding sheets and helper flows.
- `BrainMesh/Support/` → Shared utilities (AnyModelContainer, AsyncLimiter, etc.).
- `BrainMesh/Observability/` → Logging categories + micro timing (`BMLog`, `BMDuration`).

## Data Model Map (SwiftData)
Schema is created in `BrainMesh/BrainMeshApp.swift`:
- `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`)
  - `id`, `createdAt`, `name`, `nameFolded`
  - Optional lock settings (biometrics/password hash+salt)
- `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`)
  - `graphID` (optional), `name`, `nameFolded`, `notes`, `notesFolded`
  - `iconSymbolName`, `imageData` (synced), `imagePath` (local cache)
  - Relationships: `attributes` (cascade), `detailFields` (cascade)
- `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`)
  - `graphID` (optional), `name`, `nameFolded`, `notes`, `notesFolded`
  - `owner: MetaEntity?` (no macro inverse on this side), `searchLabelFolded`
  - Relationships: `detailValues` (cascade)
- `MetaLink` (`BrainMesh/Models/MetaLink.swift`)
  - `graphID` (optional), `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
  - `note` + `noteFolded`
- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - `graphID` (optional), `ownerKindRaw + ownerID` (no relationship macros), `contentKindRaw`
  - metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - `fileData` is `@Attribute(.externalStorage)` + `localPath` for cache
- `MetaDetailFieldDefinition` (`BrainMesh/Models/DetailsModels.swift`)
  - `graphID` (optional), `entityID`, `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Relationship: `owner: MetaEntity?` (nullify) with `originalName: "entity"`
- `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`)
  - `graphID` (optional), `attributeID`, `fieldID`, typed storage (`string/int/double/date/bool`)
  - Reference: `attribute: MetaAttribute?` (inverse defined on `MetaAttribute.detailValues`)
- `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`)
  - User-saved details schema templates (`fieldsJSON`) scoped by optional `graphID`

### Graph Scoping Pattern
- Most models carry `graphID: UUID?` and treat `nil` as legacy/unscoped data.
- Many queries include `(record.graphID == activeGraphID || record.graphID == nil)` to stay migration-friendly (example: `BrainMesh/Onboarding/OnboardingSheetView.swift`).

## Sync / Storage
- SwiftData container is created in `BrainMesh/BrainMeshApp.swift` with `ModelConfiguration(schema: cloudKitDatabase: .automatic)`.
- In DEBUG: CloudKit init failure triggers `fatalError` (no fallback). In Release: fallback to local-only container and `SyncRuntime.shared.setStorageMode(.localOnly)`.
- iCloud account status is surfaced via `BrainMesh/Settings/SyncRuntime.swift` (CKContainer.accountStatus).
- Local caches:
  - Images: deterministic `UUID.jpg` cache files (`BrainMesh/ImageHydrator.swift`, `BrainMesh/ImageStore.swift`).
  - Attachments: cached bytes in Application Support; on-demand hydration uses background `ModelContext` to fetch `fileData` and write cache (`BrainMesh/Attachments/AttachmentHydrator.swift`).
- Migrations:
  - No explicit SwiftData `MigrationPlan` found (automatic migration assumed).
  - App bootstrap performs legacy data fixes (`BrainMesh/AppRootView.swift`: `GraphBootstrap.migrateLegacyRecordsIfNeeded`, `backfillFoldedNotesIfNeeded`).

## UI Map (Screens, Navigation, Main Flows)
### Root Tabs (`BrainMesh/ContentView.swift`)
- **Entitäten** → `EntitiesHomeView()`
- **Graph** → `GraphCanvasScreen()`
- **Stats** → `GraphStatsView()`
- **Einstellungen** → `NavigationStack { SettingsView(showDoneButton: false) }`

### Entities / Details
- Entities home list + search + sort: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView*.swift`
- Entity details: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Attribute details: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView*.swift`
- Link creation: `BrainMesh/Mainscreen/AddLinkView.swift`
- Node picker view: `BrainMesh/Mainscreen/NodePickerView.swift`

### Graph Canvas
- Composition shell + state: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
- Body + overlays + expand/jump/load scheduling: `BrainMesh/GraphCanvas/GraphCanvasScreen/*.swift`
- Physics simulation (30 FPS timer): `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Snapshot loader (off-main): `BrainMesh/GraphCanvas/GraphCanvasDataLoader/...`

### Graph Picker / Transfer / Pro / Security
- Graph switching: `BrainMesh/GraphPicker/GraphPickerListView.swift` (+rename/delete flows).
- Import/export: `BrainMesh/GraphTransfer/...` (file type `.bmgraph`).
- Pro/paywall: `BrainMesh/Pro/ProPaywallView.swift`, `BrainMesh/Pro/ProCenterView.swift`, `BrainMesh/Pro/ProEntitlementStore.swift`.
- Graph lock/unlock: `BrainMesh/Security/...` (FaceID + password).

## Build & Configuration
- Xcode project: `BrainMesh.xcodeproj`
- Deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `BrainMesh.xcodeproj/project.pbxproj`.
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud service: CloudKit
  - `aps-environment`: `development` (check Release signing entitlements) **UNKNOWN**
- Info.plist: `BrainMesh/Info.plist`
  - Background mode: `remote-notification` (likely for CloudKit push sync).
  - FaceID usage string.
  - Pro product IDs override keys: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02` (defaults: "01"/"02").
  - Exported UTType: `de.marcfechner.brainmesh.graph` + extension `.bmgraph`.
- Dependencies:
  - No Swift Package Manager dependencies found in `BrainMesh.xcodeproj/project.pbxproj`.
  - Tests use the Swift `Testing` framework (`BrainMeshTests/GraphTransferRoundtripTests.swift`).

## Conventions (Patterns, Do/Don't)
### Do
- Keep SwiftData fetches off the render path; prefer actor loaders configured via `AppLoadersConfigurator`.
- For off-main work: create a short-lived `ModelContext` from `AnyModelContainer`, set `autosaveEnabled = false`, and check cancellation (`Task.checkCancellation()`).
- Store folded search indices in-model (`nameFolded`, `notesFolded`, `noteFolded`) using `BMSearch.fold(...)` in `didSet`.
- Use throttling for expensive/IO work (`AsyncLimiter`) and dedupe in-flight tasks (example: `AttachmentHydrator.inFlight`).

### Don't
- Avoid `Task.detached` from SwiftUI views unless you explicitly control lifecycle/cancellation.
- Avoid doing multi-step SwiftData fetch+transform on `@MainActor` for flows that can be triggered frequently (graph loads, expand, searches).

## How to work on this project (new dev checklist)
1. Open `BrainMesh.xcodeproj` in Xcode (needs iOS 26 SDK).
2. Ensure signing supports iCloud + CloudKit container `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`).
3. Run on a real device for CloudKit testing; Simulator behavior can differ for iCloud.
4. First-run sanity:
   - App creates/ensures at least one graph (`BrainMesh/AppRootView.swift` → `GraphBootstrap.ensureAtLeastOneGraph`).
   - Confirm Sync status in Settings (uses `SyncRuntime`).
5. Run tests: `BrainMeshTests/GraphTransferRoundtripTests.swift` (in-memory SwiftData).

## Quick Wins (max 10, concrete)
1. **Move GraphCanvas “Expand” fetches off-main** (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Expand.swift`) by delegating to `GraphCanvasDataLoader` (actor + background ModelContext).
2. Add a **stale-result guard + cancellation** to Expand, similar to the existing load token pattern in GraphCanvasScreen (`currentLoadToken`, `loadTask`).
3. Standardize a **Task lifetime pattern** in UI: store tasks in `@State` and cancel on new triggers (already done in some places; expand it).
4. Split `GraphTransferViewModel.swift` into smaller files (UI state vs import vs export vs error handling) to reduce merge conflicts and ease testing.
5. Extract `NodeImagesManageView.swift` subviews (row, thumbnail loading, actions) to reduce re-render complexity and compile time.
6. Audit `.task(id:)` in gallery/thumbnail lists to ensure they **cancel** quickly and don’t write UI state after disappearance.
7. Add lightweight `BMLog` instrumentation around the most expensive loaders (Stats, EntitiesHome) to correlate stalls with actions.
8. Ensure Pro product IDs are **real App Store Connect IDs** (current defaults are short strings "01"/"02").
9. Introduce a single helper for “graph scoped predicate” to avoid repeating `(graphID == gid || graphID == nil)` everywhere.
10. Confirm Release entitlements: `aps-environment` should match distribution signing (currently set to `development` in file).
