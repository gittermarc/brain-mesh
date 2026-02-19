# PROJECT_CONTEXT

> Start Here — generated from repository scan on 2026-02-19.

## TL;DR
BrainMesh is an iOS/iPadOS knowledge-graph app: you create **Graphs** (workspaces), add **Entities** with **Attributes**, connect nodes via **Links**, attach **Media/Files**, and explore everything on an interactive **GraphCanvas**. Data is stored in **SwiftData** and configured for **CloudKit sync** (see `BrainMesh/BrainMeshApp.swift`). Minimum deployment target is iOS 26.0 (see `BrainMesh.xcodeproj/project.pbxproj`).

## Key concepts (Domain)
- **Graph** (`MetaGraph`): Workspace/scope for all data; can be protected (biometrics/password).
- **Entity** (`MetaEntity`): Primary node type; has name, notes, optional icon and main image.
- **Attribute** (`MetaAttribute`): Secondary node type; optionally owned by an entity; has notes, optional icon and main image.
- **Link** (`MetaLink`): Connection between nodes (entity↔entity, entity↔attribute, attribute↔attribute depending on usage); stores denormalized labels for fast rendering.
- **Attachment** (`MetaAttachment`): Files/videos/gallery images attached to an entity/attribute; `fileData` uses SwiftData external storage.
- **Active Graph**: Currently selected graph id is stored in `@AppStorage("BMActiveGraphID")` (see `BrainMesh/ContentView.swift`, `BrainMesh/AppRootView.swift`, `BrainMesh/GraphSession.swift`).
- **Hydration**: Background population of local caches from SwiftData blobs to disk (images/attachments) via actors (e.g. `BrainMesh/Attachments/AttachmentHydrator.swift`).


## Persistent keys (UserDefaults / AppStorage)
- `BMActiveGraphID` — active graph UUID string (`ContentView.swift`, `GraphCanvasScreen.swift`, `EntitiesHomeView.swift`, `GraphStatsView.swift`, `GraphLockCoordinator.swift`).
- `BMOnboardingHidden` / `BMOnboardingCompleted` — onboarding state (`ContentView.swift`, `GraphCanvasScreen.swift`, `EntitiesHomeView.swift`).
- `BMCompressVideosOnImport` / `BMVideoCompressionQuality` — video import prefs (`BrainMesh/Settings/VideoImportPreferences.swift`).
- (More keys live in settings/appearance models; treat them as app UX prefs, not domain data.)
## Architecture map (text)
**UI (SwiftUI)**
- Root tabs + navigation (`BrainMesh/ContentView.swift`).
- Screen modules: Entities (`BrainMesh/Mainscreen/...`), Graph canvas (`BrainMesh/GraphCanvas/...`), Stats (`BrainMesh/Stats/...`), Settings (`BrainMesh/Settings/...`).

**State / Coordinators (ObservableObject @MainActor)**
- Onboarding sheet control (`BrainMesh/Onboarding/OnboardingCoordinator.swift`).
- Graph lock flow control (`BrainMesh/Security/GraphLockCoordinator.swift`).
- System modal tracking to avoid lock/picker conflicts (`BrainMesh/Support/SystemModalCoordinator.swift`).

**Loaders & Services (actors + background ModelContext)**
- Off-main snapshot loaders returning value DTOs (e.g. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`, `BrainMesh/Mainscreen/NodePickerLoader.swift`).
- Domain services (e.g. stats: `BrainMesh/Stats/GraphStatsService/*`, graph dedupe/delete: `BrainMesh/GraphPicker/*`).

**Storage & Sync (SwiftData + CloudKit)**
- `ModelContainer` created in `BrainMesh/BrainMeshApp.swift` with schema `[MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment]` and `ModelConfiguration(..., cloudKitDatabase: .automatic)`.
- iCloud/CloudKit entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit + container id).

**Caches (disk + memory)**
- Image cache: `BrainMesh/ImageStore.swift` (NSCache + Application Support/BrainMeshImages).
- Attachment cache: `BrainMesh/Attachments/AttachmentStore.swift` (Application Support/BrainMeshAttachments).


## Runtime wiring (who configures what)
- SwiftData `ModelContainer` is created once in `BrainMesh/BrainMeshApp.swift` and passed into the environment via `.modelContainer(container)`.
- Several background loaders/hydrators are configured at startup with an `AnyModelContainer` wrapper (so they can create their own background `ModelContext`):
  - `GraphCanvasDataLoader.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`)
  - `EntitiesHomeLoader.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`)
  - `GraphStatsLoader.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`)
  - `AttachmentHydrator.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`)
  - `MediaAllLoader.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`)
  - `NodePickerLoader.shared.configure(container:)` and `NodeConnectionsLoader.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`)
  - `NodeRenameService.shared.configure(container:)` (`BrainMesh/BrainMeshApp.swift`, implementation is in `BrainMesh/Mainscreen/LinkCleanup.swift`)
- Global UI state objects are created in `BrainMesh/ContentView.swift` (`AppearanceStore`, `GraphLockCoordinator`, `OnboardingCoordinator`, `SystemModalCoordinator`) and injected with `.environmentObject`.
## Folder map (what lives where)
Top-level code folder: `BrainMesh/`
- `BrainMesh/Assets.xcassets/` — 0 Swift files.
- `BrainMesh/Attachments/` — 20 Swift files.
- `BrainMesh/GraphCanvas/` — 17 Swift files.
- `BrainMesh/GraphPicker/` — 6 Swift files.
- `BrainMesh/Icons/` — 6 Swift files.
- `BrainMesh/Images/` — 1 Swift files.
- `BrainMesh/ImportProgress/` — 2 Swift files.
- `BrainMesh/Mainscreen/` — 56 Swift files.
- `BrainMesh/Observability/` — 1 Swift files.
- `BrainMesh/Onboarding/` — 8 Swift files.
- `BrainMesh/PhotoGallery/` — 9 Swift files.
- `BrainMesh/Security/` — 6 Swift files.
- `BrainMesh/Settings/` — 14 Swift files.
- `BrainMesh/Stats/` — 19 Swift files.
- `BrainMesh/Support/` — 1 Swift files.

### Folder details (curated)
- `BrainMesh/Mainscreen/` — Entities list/search, entity/attribute detail screens, link management, shared detail components.
- `BrainMesh/GraphCanvas/` — Graph visualization (rendering, gestures, physics), canvas data loading.
- `BrainMesh/Stats/` — Stats dashboard and supporting components/loaders/services.
- `BrainMesh/Attachments/` — Attachment models, caching, hydration, import flows, "Alle Medien" loader.
- `BrainMesh/GraphPicker/` — Graph selection UI, rename/delete flows, dedupe cleanup.
- `BrainMesh/Security/` — Graph protection (FaceID/TouchID + password hashing/verification), unlock UI.
- `BrainMesh/Settings/` — Settings UI + appearance models; video import preferences.
- `BrainMesh/PhotoGallery/` — Gallery views/sections and photo-specific actions.
- `BrainMesh/Icons/` — SF Symbols picker UIs (curated + full list).
- `BrainMesh/Observability/` — lightweight logging/timing helpers (`BMLog`, `BMDuration`).

## Data model map (SwiftData)
Schema configured in `BrainMesh/BrainMeshApp.swift`.

### `MetaGraph` (`BrainMesh/Models.swift`)
- Fields: `id`, `createdAt`, `name`, `nameFolded`.
- Security fields: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations` + computed `isProtected`/`isPasswordConfigured`.

### `MetaEntity` (`BrainMesh/Models.swift`)
- Fields: `id`, `createdAt`, `graphID?`, `name`, `nameFolded`, `notes`.
- Media fields: `iconSymbolName?`, `imageData?`, `imagePath?`.
- Relationship: `@Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner) var attributes: [MetaAttribute]?`.
- Convenience: `attributesList` (de-dupes by id), `addAttribute(_:)`, `removeAttribute(_:)`.

### `MetaAttribute` (`BrainMesh/Models.swift`)
- Fields: `id`, `graphID?`, `name`, `nameFolded`, `notes`.
- Media fields: `iconSymbolName?`, `imageData?`, `imagePath?`.
- Relationship: `var owner: MetaEntity?` (inverse defined only on entity side to avoid macro cycles).
- Search: `searchLabelFolded` updated by `recomputeSearchLabelFolded()`; display name uses `"Entity · Attribute"` when owned.

### `MetaLink` (`BrainMesh/Models.swift`)
- Fields: `id`, `createdAt`, `note?`, `graphID?`.
- Endpoints: `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID` (kind is `NodeKind`).
- Denormalization: `sourceLabel`, `targetLabel` stored for fast UI rendering; must be updated on rename (see `BrainMesh/Mainscreen/LinkCleanup.swift`).

### `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- Fields: `id`, `createdAt`, `graphID?`, `ownerKindRaw`, `ownerID`, `contentKindRaw` (`file`/`video`/`galleryImage`).
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`.
- Data: `@Attribute(.externalStorage) var fileData: Data?` (CloudKit-asset-like).
- Cache pointer: `localPath?` (filename under Application Support/BrainMeshAttachments).

## Sync / Storage
- SwiftData container configuration: `cloudKitDatabase: .automatic` (`BrainMesh/BrainMeshApp.swift`).
- iCloud entitlements: CloudKit enabled and container `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`).
- External blobs: attachments use `externalStorage` (`BrainMesh/Attachments/MetaAttachment.swift`).
- Local caching:
  - Images: `BrainMesh/ImageStore.swift` (memory + disk).
  - Attachments: `BrainMesh/Attachments/AttachmentStore.swift` (disk).
- Background hydration (off-main):
  - `AttachmentHydrator` (`BrainMesh/Attachments/AttachmentHydrator.swift`).
  - `ImageHydrator` (`BrainMesh/ImageHydrator.swift`).

### Migration / legacy handling
- Graph scoping is optional (`graphID: UUID?`) on most models to support legacy records.
- Graph bootstrap + legacy migration: `BrainMesh/GraphBootstrap.swift`.
- Attachment graphID migration to avoid OR predicates on externalStorage: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.

## UI map (screens + navigation)
Root tabs (`BrainMesh/ContentView.swift`):
- **Entitäten**: `EntitiesHomeView()` (`BrainMesh/Mainscreen/EntitiesHomeView.swift`) — list/grid, search, graph picker, add entity sheet.
- **Graph**: `GraphCanvasScreen()` (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift`) — interactive canvas, focus/inspector, graph picker.
- **Stats**: `GraphStatsView()` (`BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`) — dashboard + per-graph breakdown sheets.
- **Einstellungen**: `SettingsView(showDoneButton: false)` inside `NavigationStack` (`BrainMesh/Settings/SettingsView.swift`).

Key flows:
- Graph selection: sheet pickers (e.g. `GraphPickerSheet` from `EntitiesHomeView` and `GraphCanvasScreen`).
- Entity detail navigation: `NavigationLink` → `EntityDetailRouteView(entityID:)` (nested in `BrainMesh/Mainscreen/EntitiesHomeView.swift`).
- Attribute detail navigation: similar route views under `BrainMesh/Mainscreen/AttributeDetail/` (**UNKNOWN** exact route entry points until inspected).
- Detail screen composition (Entity/Attribute): shared building blocks in `BrainMesh/Mainscreen/NodeDetailShared/*` (hero, notes/markdown, connections, media gallery, manage sheets).
- Media management: image picker/manage (`BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`), attachment manage sheet split across `NodeAttachmentsManageView+*.swift`.
- Graph lock/unlock: fullScreenCover from `AppRootView` (`BrainMesh/AppRootView.swift`) presenting `GraphUnlockView` (`BrainMesh/Security/GraphUnlockView.swift`).

## Build & configuration
- Xcode project: `BrainMesh.xcodeproj`. No Swift Package references found in `BrainMesh.xcodeproj/project.pbxproj` (no `XCRemoteSwiftPackageReference`).
- Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests` (see `BrainMesh.xcodeproj/project.pbxproj`).
- Deployment target: iOS 26.0; Device families: iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- Bundle id: `de.marcfechner.BrainMesh`.
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit; aps-environment=development).
- Info.plist: `BrainMesh/Info.plist` (UIBackgroundModes: remote-notification; NSFaceIDUsageDescription set).
- Crypto: uses `CommonCrypto` for PBKDF2 password hashing (`BrainMesh/Security/GraphLockCrypto.swift`).
- Secrets handling: **UNKNOWN** (no `.xcconfig` or obvious secrets file found).

## Conventions (Do / Don't)
### Data + queries
- DO scope fetches by `graphID` using AND-only predicates when possible (avoid `(gid == nil || ...)` patterns). See `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` for rationale.
- DO store folded search strings (`nameFolded`, `searchLabelFolded`) and keep them updated on mutations (`BrainMesh/Models.swift`, `BMSearch.fold`).
- DON'T pass SwiftData `@Model` instances across concurrency boundaries. Use IDs + DTO snapshots (pattern used in `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).

### UI performance
- DON'T call synchronous disk I/O from SwiftUI `body` (explicitly documented in `BrainMesh/ImageStore.swift`).
- DO use `Task.detached` + background `ModelContext` for heavy fetch/hydration (see `BrainMesh/BrainMeshApp.swift` container injection).

### Security
- Graph protection status is stored on graph/entity/attribute models (see `isProtected` / password fields in `BrainMesh/Models.swift`).
- Passwords are stored as salt+hash+iterations (PBKDF2-SHA256) — never plain text (`BrainMesh/Security/GraphLockCrypto.swift`).

## How to work on this project (new dev checklist)
### Setup
1. Open `BrainMesh.xcodeproj` in Xcode.
2. Select the `BrainMesh` scheme and run on an iOS 26 simulator/device.
3. For CloudKit sync on device: ensure the target has iCloud/CloudKit capability enabled and is signed with a team that can access the container in `BrainMesh/BrainMesh.entitlements`.
4. If you see CloudKit container errors at startup, check the container id and signing entitlements (startup logs come from `BrainMesh/BrainMeshApp.swift`).

### Where to start when adding a feature
- New UI flow: start at the tab entry (`BrainMesh/ContentView.swift`) and follow the screen module folder (e.g. `BrainMesh/Mainscreen/...`).
- New data field: update the relevant `@Model` in `BrainMesh/Models.swift` or `BrainMesh/Attachments/MetaAttachment.swift`, then ensure it’s included in the schema in `BrainMesh/BrainMeshApp.swift` (already includes all current models).
- New heavy query: implement it in an actor loader returning a value snapshot; inject container in `BrainMesh/BrainMeshApp.swift` (pattern: `*.shared.configure(container:)`).


## Smoke test checklist (after any change)
- App launch: no crash, ModelContainer initializes, tabs render (`BrainMesh/BrainMeshApp.swift`, `ContentView.swift`).
- Graph switching: pick a graph in at least two places (Entities + GraphCanvas) and verify lists/canvas update.
- Search: type quickly in Entities search → no hitching, results update (loader debounce).
- Media: open an entity, add a photo, open gallery, open attachment manage, then return (ensure no lock/picker glitch).
- Lock: enable graph lock, switch graphs, verify unlock flow + fallback behavior.
## Quick wins (<= 10, concrete)
1. **Split `MarkdownTextView.swift`** into 3–5 focused files (UIKit wrapper, toolbar/undo-redo, link insertion UI, preview formatter). Path: `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift`.
2. **Extract `NodeRenameService` out of `LinkCleanup.swift`** for single-responsibility and faster incremental builds. Path: `BrainMesh/Mainscreen/LinkCleanup.swift`.
3. **Add a small os_signpost wrapper** around expensive loaders (GraphCanvas/Stats/EntitiesHome) using `BMLog` + `BMDuration`. Paths: `BrainMesh/Observability/BMObservability.swift`, loaders mentioned above.
4. **Reduce GraphCanvas physics work for large graphs** by defaulting to spotlight physics (`physicsRelevant`) when node count is high. Paths: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`, `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`.
5. **Make graphID migrations more centralized** (one place that ensures no `graphID == nil` persists after bootstrap for active graph). Paths: `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
6. **Standardize predicate helpers** for graph-scoped fetches to prevent accidental OR predicates (e.g. `FetchDescriptorFactory`). Touchpoints: `GraphCanvasDataLoader`, `GraphStatsService`, `MediaAllLoader`, `LinkCleanup`.
7. **Move 'UI-only' enums/models out of large files** to reduce compile ripple (e.g. move small helpers out of `EntitiesHomeView.swift`).
8. **Add a debug-only “Reset local caches” button** that clears `BrainMeshImages` + `BrainMeshAttachments` and reports freed space (stores already exist). Paths: `ImageStore.swift`, `AttachmentStore.swift`, `SettingsView.swift`.
9. **Add explicit Task cancellation** for long-running loads when switching graph quickly (store task handles in state; pattern exists in `GraphStatsView`).
10. **Document the graph lock UX constraints** (system modal avoidance) directly next to picker flows to prevent regressions. Paths: `AppRootView.swift`, `SystemModalCoordinator.swift`.

## Open Questions (UNKNOWNs)
1. **UNKNOWN:** Confirm the exact navigation entry points for Attribute detail routing (file(s) define AttributeDetailRouteView or equivalent).
2. **UNKNOWN:** How secrets (if any) are handled. No `.xcconfig` or obvious secret keys found in this scan.