# BrainMesh — PROJECT_CONTEXT

Last generated: 2026-02-16 (Europe/Berlin)

## TL;DR
BrainMesh ist eine SwiftUI-App (iOS/iPadOS, Deployment Target 26.0), mit der Nutzer pro **Graph** Entitäten und Attribute anlegen, sie per **Links** verbinden und im **Graph-Canvas** visuell erkunden können. Persistenz & Sync laufen über **SwiftData** mit CloudKit-Backing (`ModelConfiguration(..., cloudKitDatabase: .automatic)` in BrainMesh/BrainMeshApp.swift).

## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph)**: Workspace/Container; mehrere Graphen möglich; optional geschützt (Lock).
- **Entität (MetaEntity)**: Hauptknoten; kann Notizen, Icon, Hauptbild haben.
- **Attribut (MetaAttribute)**: Kind-Knoten einer Entität (`owner`); eigenes Icon, Notizen, Hauptbild.
- **Link (MetaLink)**: Verbindung zwischen Nodes (in der Praxis vor allem Entität↔Entität); speichert nur IDs/Kinds + optional Note.
- **Attachment (MetaAttachment)**: Datei/Video/Galerie-Bild; wird einem Owner über `(ownerKindRaw, ownerID)` zugeordnet.
- **Hauptbild**: `imageData` am Entity/Attribute; zusätzlich lokaler JPEG-Cache via `imagePath` (BrainMesh/ImageStore.swift).
- **Galerie**: Images als Attachments mit `contentKind = galleryImage` (BrainMesh/Attachments/MetaAttachment.swift).
- **Graph Scope**: `graphID: UUID?` an mehreren Models; `nil` wird als legacy/unscoped behandelt und in Predicates oft mit-inkludiert.
- **NodeKey / GraphNode / GraphEdge**: In-memory Keys und Render-Daten für Canvas (BrainMesh/Models.swift, BrainMesh/GraphCanvas/*).
- **Lens / Pinned / Selection**: Canvas-Filter + Pinning + selektierter Node.
- **Graph Lock**: Unlock-Flows über `GraphLockCoordinator.activeRequest` + `GraphUnlockView` (BrainMesh/Security/*).

## Architecture Map (Layer/Module → Responsibility → Dependencies)
- **App/Composition** (BrainMesh/BrainMeshApp.swift, BrainMesh/AppRootView.swift)
-   - Baut `ModelContainer` + injiziert EnvironmentObjects (Appearance/Onboarding/GraphLock).
-   - Startet Bootstrapping (Default Graph, Legacy Migration, Image Hydration, Security enforcement).
- **UI Layer (SwiftUI)** (BrainMesh/ContentView.swift, BrainMesh/Mainscreen/*, BrainMesh/GraphCanvas/*, BrainMesh/PhotoGallery/*, BrainMesh/Attachments/*)
-   - Navigation: TabView → NavigationStack/Sheets/FullScreenCovers.
-   - Data access über `@Query` + `ModelContext` (kein Repository-Layer).
- **Domain/Model** (BrainMesh/Models.swift, BrainMesh/Attachments/MetaAttachment.swift)
-   - SwiftData @Model Typen + derived fields für Suche (`nameFolded`, `searchLabelFolded`).
- **Services / Utilities**
-   - Graph bootstrap + legacy scope migration (BrainMesh/GraphBootstrap.swift).
-   - Image cache + hydration (BrainMesh/ImageStore.swift, BrainMesh/ImageHydrator.swift).
-   - Attachment cache + thumbnails (BrainMesh/Attachments/AttachmentStore.swift, BrainMesh/Attachments/AttachmentThumbnailStore.swift).
-   - GraphPicker housekeeping: rename/delete/dedupe (BrainMesh/GraphPicker/*).
- **Cross-cutting**
-   - Security (`BrainMesh/Security/*`) – Graph/Unlock flows.
-   - Observability (`BrainMesh/Observability/BMObservability.swift`) – `BMLog` + `BMDuration`.

## Folder Map (Ordner → Zweck → Key Files)
- `BrainMesh/` — App root + composition
-   - BrainMesh/BrainMeshApp.swift (ModelContainer + env objects)
-   - BrainMesh/AppRootView.swift (startup tasks + lock overlay)
-   - BrainMesh/ContentView.swift (TabView)
-   - BrainMesh/SettingsView.swift + BrainMesh/SettingsAboutSection.swift
- `BrainMesh/Mainscreen/` — Entities/Attributes UI
-   - EntitiesHomeView.swift (list + search + graph picker + settings sheet)
-   - EntityDetail/*, AttributeDetail/* (detail screens; sheet wiring in `...+Sheets.swift`)
-   - NodeDetailShared/* (shared hero/highlights/connections/media blocks)
-   - BulkLinkView.swift + NodeBulkLinkSheet.swift (bulk linking)
- `BrainMesh/GraphCanvas/` — Canvas UI + data/physics/rendering
-   - GraphCanvasScreen.swift (screen state + controls)
-   - GraphCanvasScreen+Loading.swift (SwiftData load + caches)
-   - GraphCanvasView.swift + GraphCanvasView+Rendering.swift (per-frame drawing)
-   - GraphCanvasView+Physics.swift (simulation loop)
-   - GraphLens.swift + GraphTheme.swift (lens/theming)
- `BrainMesh/Attachments/` — Attachment model + pipelines
-   - MetaAttachment.swift (SwiftData model)
-   - AttachmentStore.swift (local cache), AttachmentThumbnailStore.swift (thumbs)
-   - AttachmentsSection* (import/manage UI), AttachmentPreviewSheet.swift
- `BrainMesh/PhotoGallery/` — Detail-only image gallery
-   - PhotoGallerySection.swift (embedded section), PhotoGalleryBrowserView.swift (grid), PhotoGalleryViewerView.swift (viewer)
-   - PhotoGalleryQuery.swift (shared Query builders)
- `BrainMesh/Security/` — Graph locks
-   - GraphLockCoordinator.swift + GraphUnlockView.swift + GraphSecuritySheet.swift
-   - GraphLockCrypto.swift (hashing/salt)
- `BrainMesh/Appearance/` — UI appearance presets
-   - AppearanceStore.swift, AppearanceModels.swift, DisplaySettingsView.swift
- `BrainMesh/GraphPicker/` — Graph management UI
-   - GraphPickerListView.swift, GraphPickerRow.swift, GraphPickerRenameSheet.swift
-   - GraphDeletionService.swift, GraphDedupeService.swift
- `BrainMesh/Onboarding/` — Onboarding flow
-   - OnboardingCoordinator.swift, OnboardingSheetView.swift, Steps/*

## Data Model Map (Entities, Relationships, wichtige Felder)
### MetaGraph (BrainMesh/Models.swift)
- `id: UUID`, `createdAt: Date`
- `name`, `nameFolded` (für Suche; Aktualisierung via didSet)
- Lock config: `lockBiometricsEnabled`, `lockPasswordEnabled`
- Password material: `passwordSaltB64`, `passwordHashB64`, `passwordIterations` (Hash/Salt liegen im Model, nicht Keychain).

### MetaEntity (BrainMesh/Models.swift)
- Scope: `graphID: UUID?` (aktiv pro Graph; `nil` = legacy/unscoped).
- Display: `name`, `nameFolded`, `iconSymbolName`.
- Notes: `notes`.
- Hauptbild: `imageData: Data?` + `imagePath: String?` (lokaler Cache-Filename).
- Relationship: `attributes: [MetaAttribute]?` (cascade deleteRule) mit inverse `\MetaAttribute.owner`.

### MetaAttribute (BrainMesh/Models.swift)
- Scope: `graphID: UUID?`.
- Display: `name`, `nameFolded`.
- Search helper: `searchLabelFolded` ("Entity · Attribute" folded).
- Notes/Icon/Hauptbild: `notes`, `iconSymbolName`, `imageData`, `imagePath`.
- Owner: `owner: MetaEntity?` (keine Relationship-Macro; Kommentar: Macro-Zirkularität vermeiden).

### MetaLink (BrainMesh/Models.swift)
- Scope/Meta: `graphID: UUID?`, `createdAt`, optional `note`.
- Endpoints: `sourceKindRaw`, `sourceID`, `sourceLabel`, `targetKindRaw`, `targetID`, `targetLabel`.
- Storage: IDs statt Relationships (wichtig für Performance/Entkopplung, aber Cleanup muss manuell sein).

### MetaAttachment (BrainMesh/Attachments/MetaAttachment.swift)
- Owner routing: `ownerKindRaw` (NodeKind) + `ownerID` (UUID).
- Scope: `graphID` (nicht optional im Model; default via init), Filter in Queries nutzt `(gid == nil || a.graphID == gid)`.
- Content: `contentKindRaw` (file/video/galleryImage), `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`.
- Bytes: `fileData` mit `@Attribute(.externalStorage)`.
- Local cache: `localPath` (Application Support/BrainMeshAttachments).

## Sync/Storage (SwiftData/CloudKit/Caches/Migration/Offline)
- **ModelContainer**: `BrainMesh/BrainMeshApp.swift` → Schema {MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment}.
- **CloudKit**: per `cloudKitDatabase: .automatic` aktiviert (RELEASE fallback auf local-only config bei Container-Init-Failure).
- **Entitlements**: `BrainMesh/BrainMesh.entitlements` → iCloud container + CloudKit + push (`aps-environment`).
- **Offline**: lokale SwiftData-Store ist primary; Sync ist „eventual“ via CloudKit. Merge/Conflict-Strategie ist nicht explizit konfiguriert → **UNKNOWN** (SwiftData defaults).
- **Image storage**:
-   - Persistiert: `imageData` am Model (SwiftData).
-   - Cache: deterministisches JPEG in `Application Support/BrainMeshImages` (BrainMesh/ImageStore.swift).
-   - Hydration: `ImageHydrator.hydrateIncremental(...)` (max 1x pro Launch, gesteuert in AppRootView via `BMImageHydratorLastAutoRun`).
- **Attachment storage**:
-   - Persistiert: `fileData` externalStorage (SwiftData).
-   - Local cache: `AttachmentStore` schreibt Dateien deterministisch (id + extension).
-   - Thumbnails: `AttachmentThumbnailStore` (actor) → memory + disk cache + QuickLook/AV fallback.

## UI Map (Screens, Navigation, wichtige Sheets/Flows)
- **Root composition**: `AppRootView` (BrainMesh/AppRootView.swift)
-   - `.task`: `GraphBootstrap.ensureAtLeastOneGraph`, optional `migrateLegacyRecordsIfNeeded`, `ImageHydrator.hydrateIncremental` (periodisch).
-   - `.fullScreenCover`: GraphUnlock overlay wenn `GraphLockCoordinator.activeRequest` gesetzt ist.
- **Tabs**: `ContentView` (BrainMesh/ContentView.swift)
-   - Entitäten: `EntitiesHomeView`
-   - Graph: `GraphCanvasScreen`
-   - Stats: `GraphStatsView`
- **EntitiesHomeView** (BrainMesh/Mainscreen/EntitiesHomeView.swift)
-   - Search: debounced reload (`taskToken`) → `fetchEntities(...)` (2 Queries + in-memory merge).
-   - Add: Sheet `AddEntityView` (BrainMesh/Mainscreen/AddEntityView.swift).
-   - Graph switch: Sheet `GraphPickerSheet` (BrainMesh/GraphPickerSheet.swift).
-   - Settings: Sheet `SettingsView` (BrainMesh/SettingsView.swift).
-   - Delete: swipe-to-delete + manual link/attachment cleanup (siehe deleteEntities/deleteLinks).
- **EntityDetailView** (BrainMesh/Mainscreen/EntityDetail/*)
-   - Sections: Notes, Connections, Media, Attributes.
-   - Sheets: media management, add link, add attribute, attachments preview (wiring in `EntityDetailView+Sheets.swift`).
- **AttributeDetailView** (BrainMesh/Mainscreen/AttributeDetail/*)
-   - Analoge Struktur; shared UI über NodeDetailShared.
- **Media**
-   - `NodeMediaCard` zeigt Galerie-Thumbs + attachments preview; „Alle“ navigiert zu `NodeMediaAllView` (BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift).
-   - Gallery: `PhotoGalleryBrowserView`/`PhotoGalleryViewerView` via `fullScreenCover` (BrainMesh/PhotoGallery/*).
-   - Attachment preview: `AttachmentPreviewSheet` + optional `VideoPlaybackSheet` (BrainMesh/Attachments/*).
- **GraphCanvasScreen** (BrainMesh/GraphCanvas/GraphCanvasScreen.swift)
-   - Data load: global oder neighborhood (focus entity + hops) via `GraphCanvasScreen+Loading.swift`.
-   - Physics + rendering: `GraphCanvasView` + extensions (Physics/Rendering).
-   - Graph picker: `showGraphPicker` → `GraphPickerSheet`.
- **SettingsView** (BrainMesh/SettingsView.swift)
-   - Wartung: Bildcache rebuild (`ImageHydrator.forceRebuild`), Attachment cache clear (`AttachmentStore.clearCache`).
-   - About: `SettingsAboutSection` mit Link zur Anleitung/FAQ.

## Build & Configuration (Targets, Entitlements, SPM, Secrets)
- **Targets (Xcode)**: BrainMesh + BrainMeshTests + BrainMeshUITests (aus `BrainMesh.xcodeproj`).
- **Deployment Target**: 26.0 (pbxproj).
- **Entitlements**:
-   - `com.apple.developer.icloud-container-identifiers`: `iCloud.de.marcfechner.BrainMesh`
-   - `com.apple.developer.icloud-services`: `CloudKit`
-   - `aps-environment`: `development`
- **Info.plist**:
-   - `UIBackgroundModes`: `remote-notification`
-   - `NSFaceIDUsageDescription`
- **SPM**: keine Remote Packages gefunden (pbxproj `packageProductDependencies` leer).
- **Secrets handling**: keine `.xcconfig`/Secrets-Dateien im Repo gefunden → **UNKNOWN** (evtl. nur per Signing/Entitlements).

## Conventions (Do/Don’t, Patterns)
- **No fetch in render path**: GraphCanvas lädt Labels/Bilder/Icons in Caches im Load-Step (`labelCache`, `imagePathCache`, `iconSymbolCache`) und nutzt diese im Renderpfad (GraphCanvasScreen+Loading).
- **Avoid sync disk in body**: `ImageStore.loadUIImage(path:)` ist synchron (Kommentar in BrainMesh/ImageStore.swift). Nicht in `body`/computed props verwenden; stattdessen `loadUIImageAsync`/prefetch.
- **UI splits**: `+Loading`, `+Rendering`, `+Physics`, `+Sheets` für große Screens (bereits genutzt).
- **Owner references**: Links/Attachments referenzieren Owner über IDs (kein SwiftData relationship) → Cleanup immer explizit implementieren.
- **Search fields**: `nameFolded`, `searchLabelFolded` persistent halten; bei Name-Änderung wird `MetaEntity` Setter genutzt um Attribute neu zu labeln.

## How to work on this project (Setup steps + Einstieg für neue Devs)
- Setup
-   1) Xcode öffnen → `BrainMesh.xcodeproj`.
-   2) Signing einstellen (Team, Bundle ID).
-   3) Capabilities prüfen: iCloud (CloudKit) + Push. Ohne korrektes Signing kann CloudKit init failen.
-   4) Run auf Device oder Simulator. Für echte CloudKit-Sync: iCloud Login + Container verfügbar.
- Einstiegspunkte
-   - Datenmodell verstehen: BrainMesh/Models.swift + BrainMesh/Attachments/MetaAttachment.swift.
-   - Navigation verstehen: BrainMesh/ContentView.swift + EntitiesHomeView + GraphCanvasScreen.
-   - Performance-Hotspots: GraphCanvasView+Rendering, NodeMediaAllView, Detail-Header Image loading.
- Debug/Tools
-   - Instruments: Time Profiler (Graph), Core Animation (FPS), File Activity (Disk I/O), Memory (PhotoGallery/Attachments).
-   - Settings → Wartung: Bildcache rebuild/Attachment cache clear, um Cache-Probleme einzugrenzen.

## How to add a feature (typischer Workflow)
- 1) UI: Neuen Screen in passendem Feature-Folder anlegen (z.B. BrainMesh/Mainscreen oder BrainMesh/GraphCanvas).
- 2) Routing: Tab erweitern (BrainMesh/ContentView.swift) oder NavigationLink/Sheet in bestehendem Screen (oft `...+Sheets.swift`).
- 3) Data: Falls neues persistentes Model nötig:
-    - `@Model` in neuer Datei anlegen (oder Models.swift erweitern).
-    - `schema` in BrainMesh/BrainMeshApp.swift ergänzen.
-    - Migration-Risiko dokumentieren (ARCHITECTURE_NOTES).
- 4) Storage: Wenn Files/Images betroffen → `ImageStore`/`AttachmentStore` nutzen (keine ad-hoc FileManager calls im View).
- 5) Performance: Kein SwiftData-Fetch und kein Disk I/O in `body`/Canvas-Draw; heavy computed values cachen.
- 6) Observability: bei neuen Hot Paths Logging via `BMLog` ergänzen.

## Quick Wins (max 10, konkret)
- 1) Sync-Disk-I/O aus Detail-Hero entfernen: `NodeDetailHeaderCard` und `NodeHeroCard` laden Bilder synchron (`ImageStore.loadUIImage`) → async load + state caching.
- 2) `NodeMediaAllView`: Attachment-Liste lazy machen (`LazyVStack`/`List`) und optional paging, um große Datenmengen stabil zu halten.
- 3) Deletion/Cleanup off-main: Attachment file deletes und massive link deletes asynchron kapseln.
- 4) GraphCanvas: Sync image loads im Renderpfad eliminieren; nur cached `UIImage` rendern.
- 5) Graph scope predicate helper zentralisieren (reduziert Drift).
- 6) `SettingsView` Wartung: lange Operationen (Rebuild) auf Background auslagern + progress/disable sauber.
- 7) Stats screen: Aggregationen/Sorts in computed caches oder background tasks; main-thread blocking vermeiden.
- 8) Query Builder ausbauen: für Connections/Links analog zu PhotoGalleryQueryBuilder (reduziert Predicate-Duplikate).
- 9) Dokumentiere CloudKit/SwiftData Failure Modes (Container init fail, Sync delays) im README/Notes.
- 10) Minimale Smoke Tests (Model creation, basic navigation) hinzufügen.