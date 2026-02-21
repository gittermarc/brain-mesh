# PROJECT_CONTEXT

_Last updated: 2026-02-21_  
_Project: BrainMesh (iOS app)_

## TL;DR
BrainMesh is a SwiftUI + SwiftData app (iOS deployment target **26.0**) for building knowledge graphs made of **Graphs → Entities → Attributes**, connected by **Links**, with **Attachments** and configurable **Detail Fields**. Persistence is SwiftData with CloudKit enabled (private database) via `ModelConfiguration(..., cloudKitDatabase: .automatic)` in BrainMesh/BrainMeshApp.swift.

## Key Concepts (Domain Glossary)
- **MetaGraph**: A workspace / graph container. Also holds optional per-graph lock settings (biometrics/password).
- **MetaEntity**: A node type (kind: entity). Belongs to a graph (via `graphID`), has name/notes/icon, optional photo.
- **MetaAttribute**: A second node type (kind: attribute) owned by an entity (`owner`) with its own notes/icon/photo.
- **MetaLink**: A link edge between nodes expressed as scalar IDs + labels (no SwiftData relationships).
- **MetaAttachment**: A file/video/gallery-image attached to an entity/attribute (owner expressed as scalar IDs).
- **Detail Fields (Schema + Values)**:
  - **MetaDetailFieldDefinition**: defines custom fields per entity (schema).
  - **MetaDetailFieldValue**: stores typed values per attribute for those fields.

## Architecture Map (Layers + Responsibilities)
**UI (SwiftUI Views)**
- Tab host: BrainMesh/ContentView.swift  
- Root orchestration (onboarding + lock + hydration triggers): BrainMesh/AppRootView.swift
- Main feature screens:  
  - Entities list/search: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift  
  - Graph canvas: BrainMesh/GraphCanvas/GraphCanvasScreen.swift  
  - Stats dashboard: BrainMesh/Stats/GraphStatsView/GraphStatsView.swift  
  - Settings host: BrainMesh/Settings/SettingsView.swift

**Coordinators / Stores (ObservableObject)**
- App-level coordinators injected in BrainMesh/BrainMeshApp.swift:
  - `AppearanceStore` (UI theme)
  - `DisplaySettingsStore` (feature-specific display knobs)
  - `OnboardingCoordinator` (onboarding sheet state)
  - `GraphLockCoordinator` (locking/unlocking flows)
  - `SystemModalCoordinator` (tracks “system picker presented” state to avoid disruptive overlays)
- Graph session state (UserDefaults-backed): BrainMesh/GraphSession.swift

**Loaders / Hydrators (Actors, off-main SwiftData work)**
- The pattern is: configure with `AnyModelContainer` at app start, then expose value-only snapshots.
- Examples:
  - Entities Home snapshot loader: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift
  - Graph canvas data loader: BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift
  - Stats snapshot loader: BrainMesh/Stats/GraphStatsService/GraphStatsLoader.swift
  - Attachment cache hydration: BrainMesh/Attachments/AttachmentHydrator.swift
  - Image cache hydration: BrainMesh/ImageHydrator.swift

**Domain Model (SwiftData @Model)**
- Core models: BrainMesh/Models.swift
- Attachments model: BrainMesh/Attachments/MetaAttachment.swift

**Persistence / Sync**
- SwiftData `ModelContainer` created once in BrainMesh/BrainMeshApp.swift
- CloudKit container identifier (must match entitlements): BrainMesh/Settings/SyncRuntime.swift + BrainMesh/BrainMesh.entitlements

**Local caches (not synced)**
- Images: BrainMesh/ImageStore.swift → Application Support/`BrainMeshImages`
- Attachments: BrainMesh/Attachments/AttachmentStore.swift → Application Support/`BrainMeshAttachments`
- Attachment thumbnails: BrainMesh/Attachments/AttachmentThumbnailStore.swift (in-memory/disk, implementation details in file)

### Dependency Direction (intended)
- Views → (Stores/Coordinators) + (Loaders) + (SwiftData via ModelContext on main)  
- Loaders/Hydrators → SwiftData (background ModelContext) + disk caches  
- Models → no dependency on UI

## Folder Map (App target root: BrainMesh/)
- `Attachments/`  
  Attachment model + import + cache + thumbnails + preview UI.  
  Key files:
  - BrainMesh/Attachments/MetaAttachment.swift
  - BrainMesh/Attachments/AttachmentImportPipeline.swift
  - BrainMesh/Attachments/AttachmentStore.swift
  - BrainMesh/Attachments/AttachmentHydrator.swift
- `GraphCanvas/`  
  Interactive canvas, physics, rendering, loaders, inspector/sheets.  
  Key files:
  - BrainMesh/GraphCanvas/GraphCanvasScreen.swift
  - BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift
  - BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift
- `GraphPicker/`  
  Graph selection UI and related helpers (also used as sheet from multiple tabs).
- `Images/`  
  Image import pipeline / helpers for resizing/compression (see BrainMesh/Images/ImageImportPipeline.swift).
- `ImportProgress/`  
  Import progress state + UI (used by attachments import).
- `Mainscreen/`  
  Entity/Attribute detail screens, shared “node detail” components, entities home, details schema UI.  
  Subfolders of interest:
  - `EntitiesHome/` (search/list/grid, loader, display sheet)
  - `EntityDetail/` (entity details + attributes list models)
  - `AttributeDetail/` (attribute details)
  - `NodeDetailShared/` (shared subviews/sheets used by entity + attribute)
  - `Details/` (custom details schema & value editing)
- `Observability/`  
  Lightweight logging + timing helpers: BrainMesh/Observability/BMObservability.swift
- `Onboarding/`  
  Onboarding sheet + progress computation: BrainMesh/Onboarding/OnboardingSheetView.swift
- `PhotoGallery/`  
  Gallery UI for additional images (distinct from “main photo”).
- `Security/`  
  Graph lock crypto + unlock UI (see files under BrainMesh/Security/).
- `Settings/`  
  Settings host + sections (appearance, display, sync, import preferences). Display settings are in BrainMesh/Settings/Display/.
- `Stats/`  
  Stats loaders + UI sections.

## Data Model Map (SwiftData)
### MetaGraph (BrainMesh/Models.swift)
Key fields:
- `id: UUID`
- `createdAt: Date`
- `name`, `nameFolded` (folded used for search)
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

Relationships:
- No SwiftData relationships to other models. Graph scoping is via scalar `graphID` fields on other models.

### MetaEntity (BrainMesh/Models.swift)
Key fields:
- `id`, `createdAt`
- `graphID: UUID?` (graph scope; optional for legacy migration)
- `name`, `nameFolded`, `notes`
- `iconSymbolName: String?`
- Image: `imageData: Data?` (synced), `imagePath: String?` (local cache filename)

Relationships:
- `attributes: [MetaAttribute]?` (cascade), inverse defined on `MetaAttribute.owner`
- `detailFields: [MetaDetailFieldDefinition]?` (cascade), inverse defined on `MetaDetailFieldDefinition.owner`

Convenience:
- `attributesList` + `detailFieldsList` de-dupe and sort (see BrainMesh/Models.swift)

### MetaAttribute (BrainMesh/Models.swift)
Key fields:
- `id`
- `graphID: UUID?`
- `name`, `nameFolded`, `notes`
- `iconSymbolName`, image fields (`imageData`, `imagePath`)
- `owner: MetaEntity?` (no inverse macro here to avoid circular issues)
- `searchLabelFolded` (folded “Entity · Attribute” label for searching)

Relationships:
- `detailValues: [MetaDetailFieldValue]?` (cascade), inverse defined on `MetaDetailFieldValue.attribute`

### MetaLink (BrainMesh/Models.swift)
Key fields:
- `id`, `createdAt`, `note`
- `graphID: UUID?`
- Source/target (scalar typed):
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`

Notes:
- Links are intentionally relationship-free to avoid SwiftData macro complexity and to keep fetches controllable.

### Details Schema
**MetaDetailFieldDefinition** (BrainMesh/Models.swift)
- Scalars for stability/querying: `entityID`, `graphID`
- `name`, `nameFolded`
- `typeRaw` (maps to `DetailFieldType`)
- `sortIndex`, `isPinned`
- `unit`, `optionsJSON` (for single choice)
- Relationship: `owner: MetaEntity?` uses `originalName: "entity"` (see file for rationale)

**MetaDetailFieldValue** (BrainMesh/Models.swift)
- Scalars: `attributeID`, `fieldID`, `graphID`
- Typed values: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
- Relationship: `attribute: MetaAttribute?`

### Attachments
**MetaAttachment** (BrainMesh/Attachments/MetaAttachment.swift)
- Scalars: `ownerKindRaw`, `ownerID`, `graphID`
- Content kind: `contentKindRaw` (`file`, `video`, `galleryImage`)
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Data: `fileData: Data?` uses `@Attribute(.externalStorage)` (important for CloudKit record pressure)
- Local cache: `localPath: String?` (Application Support filename)

## Sync / Storage
### SwiftData + CloudKit
- Container setup is in BrainMesh/BrainMeshApp.swift:
  - Schema includes: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`
  - CloudKit enabled via `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
- Debug vs Release behavior:
  - DEBUG: `fatalError(...)` if CloudKit container creation fails (no fallback).
  - Release: falls back to local-only storage and sets `SyncRuntime.storageMode = .localOnly`.

### iCloud runtime status surface
- `SyncRuntime` exposes:
  - storage mode (cloudKit vs local-only)
  - iCloud account status via `CKContainer(accountStatus)`
- Files:
  - BrainMesh/Settings/SyncRuntime.swift
  - BrainMesh/Settings/SettingsView+SyncSection.swift

### Local-only caches (Application Support)
- Images: BrainMesh/ImageStore.swift (folder `BrainMeshImages`)
- Attachments: BrainMesh/Attachments/AttachmentStore.swift (folder `BrainMeshAttachments`)
- Hydration:
  - `ImageHydrator` writes deterministic JPEG filenames (`<UUID>.jpg`) and updates `imagePath` fields off-main: BrainMesh/ImageHydrator.swift
  - `AttachmentHydrator` writes cached files for previewing (per visible items) with throttling: BrainMesh/Attachments/AttachmentHydrator.swift

### Migration / Legacy handling
- `GraphBootstrap` ensures at least one graph exists and migrates legacy records missing `graphID`: BrainMesh/GraphBootstrap.swift

### Offline behavior (observed in code)
- SwiftData provides local persistence; CloudKit sync is eventual.
- If CloudKit fails at startup in Release builds, the app runs local-only (no sync), surfaced in Settings via `SyncRuntime`.

## UI Map (Screens + Navigation)
### Root tabs (BrainMesh/ContentView.swift)
- **Entitäten** → BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift
- **Graph** → BrainMesh/GraphCanvas/GraphCanvasScreen.swift
- **Stats** → BrainMesh/Stats/GraphStatsView/GraphStatsView.swift
- **Einstellungen** → SettingsView inside a NavigationStack (see BrainMesh/ContentView.swift)

### Entities Home (list/search)
- Navigation host: `NavigationStack` inside EntitiesHomeView.
- Search: `.searchable(text:)` triggers a debounced `.task(id: taskToken)` and loads via `EntitiesHomeLoader`.
- Sheets:
  - Graph picker: BrainMesh/GraphPickerSheet.swift
  - View options: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeDisplaySheet.swift
  - Add entity: BrainMesh/Mainscreen/EntitiesHome/AddEntityView.swift

### Entity / Attribute detail
- Entity detail host: BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift (plus extensions in same folder)
- Attribute detail host: BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift (plus extensions)
- Shared components & sheets:
  - Node detail shared: BrainMesh/Mainscreen/NodeDetailShared/ (multiple `NodeDetailShared+*.swift`)
  - Attachments manage sheet: BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift (+ split files `NodeAttachmentsManageView+*.swift`)

### Graph canvas
- Navigation host: `NavigationStack` inside BrainMesh/GraphCanvas/GraphCanvasScreen.swift
- Sheets:
  - Graph picker (shared): BrainMesh/GraphPickerSheet.swift
  - Focus node picker: BrainMesh/GraphPicker/NodePickerView.swift
  - Inspector: `GraphCanvasScreen` extensions (files under BrainMesh/GraphCanvas/)
  - Detail sheets for selected entity/attribute: presents `EntityDetailView` / `AttributeDetailView` inside their own NavigationStack

### Onboarding / Locking
- Auto-onboarding orchestrated in BrainMesh/AppRootView.swift based on `OnboardingProgress.compute(...)`.
- Onboarding UI: BrainMesh/Onboarding/OnboardingSheetView.swift
- Graph lock fullScreenCover:
  - Coordinator: BrainMesh/Security/GraphLockCoordinator.swift
  - Unlock UI: BrainMesh/Security/GraphUnlockView.swift
- AppRootView debounces background lock while system pickers are up: BrainMesh/AppRootView.swift (`scheduleDebouncedBackgroundLock()`)

## Build & Configuration
### Xcode project / targets
- Project: `BrainMesh.xcodeproj`
- Targets:
  - `BrainMesh` (app)
  - `BrainMeshTests` (Swift Testing): `BrainMeshTests/BrainMeshTests.swift`
  - `BrainMeshUITests` (XCTest): `BrainMeshUITests/*`

### Deployment + Bundle IDs
- iOS deployment target: **26.0**
- Bundle identifiers:
  - App: `de.marcfechner.BrainMesh`
  - Tests: `de.marcfechner.BrainMeshTests`
  - UI tests: `de.marcfechner.BrainMeshUITests`

### Entitlements / Capabilities
- iCloud CloudKit enabled: BrainMesh/BrainMesh.entitlements (`iCloud.de.marcfechner.BrainMesh`)
- Background remote notifications enabled: BrainMesh/Info.plist (`UIBackgroundModes = ["remote-notification"]`)

### Info.plist
- Face ID usage description is present: BrainMesh/Info.plist

### Dependencies
- Apple frameworks only (SwiftUI, SwiftData, CloudKit, os.log, UIKit, UniformTypeIdentifiers, AVFoundation).
- No Swift Package Manager dependencies found in this repository snapshot.

### Secrets handling
- No `.xcconfig` secrets pattern found in this snapshot. Marked as **UNKNOWN** if handled outside the repo.

## Conventions (Patterns, Do/Don’t)
### Persistence + concurrency
- Do: Use value-only snapshot DTOs for loaders (avoid passing SwiftData `@Model` across actors). Example: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift (`EntitiesHomeRow`).
- Do: Create background `ModelContext` from `ModelContainer` in detached tasks for heavy fetches (seen in multiple loaders).
- Do: Add cancellation checks in long loops (`Task.checkCancellation()`).
- Don’t: Fetch from SwiftData inside SwiftUI `body` or per-frame loops.

### Search
- Use `BMSearch.fold(_:)` and stored folded fields (`nameFolded`, `searchLabelFolded`) for case/diacritic-insensitive contains queries.

### Settings keys
- Prefer `BMAppStorageKeys` constants: BrainMesh/Support/BMAppStorageKeys.swift

### File splitting
- Split large views via extensions into multiple files. Avoid `private` when extensions need access (Swift access control is file-scoped).

## How to work on this project
### Setup checklist (new machine)
1. Open `BrainMesh.xcodeproj` in Xcode.
2. Select your Development Team for the `BrainMesh` target and ensure signing works.
3. Enable iCloud capability with CloudKit and ensure the container matches BrainMesh/BrainMesh.entitlements.
4. Run on device/simulator.
   - Debug builds crash if CloudKit container init fails (see BrainMesh/BrainMeshApp.swift).

### Adding a feature (typical workflow)
- Model change:
  1. Update SwiftData model in BrainMesh/Models.swift (or BrainMesh/Attachments/MetaAttachment.swift).
  2. Update schema list in BrainMesh/BrainMeshApp.swift.
  3. Consider migration/legacy handling (see BrainMesh/GraphBootstrap.swift).
- UI + performance:
  1. Identify the relevant host view (ContentView tab or detail screen).
  2. Keep heavy work out of the render path; add a loader actor returning snapshots if needed.
  3. Add timing/logging via BrainMesh/Observability/BMObservability.swift if you touch hot paths.

## Quick Wins (max 10, concrete)
1. Tighten pinned-value fetches in BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift to avoid pulling values for unrelated attributes during typing.
2. Split BrainMesh/Models.swift into per-model files to reduce compile churn.
3. Add a small developer-only Settings section to run “force rebuild image cache” and “clear attachment cache” (APIs already exist: BrainMesh/ImageHydrator.swift, BrainMesh/Attachments/AttachmentStore.swift).
4. Centralize remaining raw `@AppStorage("...")` keys to BrainMesh/Support/BMAppStorageKeys.swift.
5. Add explicit load timing logs for EntitiesHome snapshot loads (mirroring GraphCanvas’ `BMLog.load` pattern).
6. Consolidate repeated “active graph resolution” logic into a helper (appears in EntitiesHomeView, GraphCanvasScreen, GraphStatsView, OnboardingSheetView).
7. Consider adding an optional local-only fallback in DEBUG builds to improve contributor experience (currently `fatalError` in BrainMesh/BrainMeshApp.swift).
8. Audit `contains`-based SwiftData predicates on large datasets; use `fetchLimit` + staged loading where possible.
9. Add a repo-level `README.md` pointing to this file and listing required capabilities (iCloud/CloudKit).
10. Add a “Known Issues” section to Settings for system-picker + lock edge cases (the debounce logic exists in BrainMesh/AppRootView.swift; documenting it will save time).

