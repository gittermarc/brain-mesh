# PROJECT_CONTEXT — BrainMesh (Start Here)

> Stand: 2026-02-17  
> Zielgruppe: Entwickler:innen, die neu ins Projekt kommen.  
> Stil: technisch/präzise, kein Marketing.

## TL;DR
BrainMesh ist eine iOS-App (Minimum iOS 26.0), die ein persönliches Wissensnetz als Graph verwaltet: **Graphen** enthalten **Entitäten**, **Attribute** und **Links**. Entitäten/Attribute können **Notizen**, ein **Hauptbild** sowie **Medien** (Galeriebilder/Videos/Datei-Anhänge) besitzen. Persistenz läuft über **SwiftData** mit **CloudKit Sync (private DB)** via `ModelConfiguration(..., cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.

## Key Concepts / Domänenbegriffe
- **Graph**: thematische Sammlung (Multi-Graph). Model: `MetaGraph` in `BrainMesh/Models.swift`.
- **Entität**: Knoten-Typ 1 (z.B. „Projekt“, „Person“). Model: `MetaEntity` in `BrainMesh/Models.swift`.
- **Attribut**: Knoten-Typ 2 (gehört zu einer Entität). Model: `MetaAttribute` in `BrainMesh/Models.swift` (Relationship: `owner`).
- **Link**: Verbindung zwischen zwei Knoten (Entity↔Entity, Entity↔Attribute, etc.). Model: `MetaLink` in `BrainMesh/Models.swift`.
- **Main Photo**: „Header“-Bild einer Entität/eines Attributs. Sync via `imageData`, lokaler Cache via `imagePath`. UI/Import in `BrainMesh/NotesAndPhotoSection.swift`.
- **Attachment / Medien**: Dateien, Videos, (und Galeriebilder als `AttachmentContentKind.galleryImage`). Model: `MetaAttachment` in `BrainMesh/Attachments/MetaAttachment.swift`.
- **Hydration**: Ableitung/Cache-Aufbau, um UI-Reads von Disk/SwiftData zu vermeiden:
  - Bilder: `BrainMesh/ImageHydrator.swift` schreibt deterministische JPEGs in den Cache (`ImageStore`).
  - Anhänge: `BrainMesh/Attachments/AttachmentHydrator.swift` stellt lokale Datei-URLs bereit (externalStorage → Cache-Datei).
- **Active Graph**: aktuell gewählter Graph (UserDefaults/AppStorage Key `BMActiveGraphID`), z.B. in `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` und `BrainMesh/AppRootView.swift`.

## Architecture Map (Module/Layers + Verantwortlichkeiten)
**App/Bootstrap**
- `BrainMesh/BrainMeshApp.swift`
  - SwiftData Schema + CloudKit ModelContainer
  - Konfiguration von Hintergrund-Loadern: `AttachmentHydrator` & `MediaAllLoader` via `Task.detached`
- `BrainMesh/AppRootView.swift`
  - Startup-Sequenz: Graph-Bootstrap, Image-Hydration, Onboarding-Trigger, Graph-Lock Enforcement (ScenePhase)
- `BrainMesh/ContentView.swift`
  - Root `TabView`: Entitäten / Graph / Stats

**Data Model (SwiftData)**
- `BrainMesh/Models.swift`: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink` (+ Enums/Keys)
- `BrainMesh/Attachments/MetaAttachment.swift`: `MetaAttachment` (inkl. `@Attribute(.externalStorage)` für `fileData`)

**Storage/Sync Helpers**
- `BrainMesh/ImageStore.swift`: AppSupport Cache für Bilder (load/save/delete, async Varianten + Memory Cache)
- `BrainMesh/ImageHydrator.swift`: schreibt/aktualisiert `imagePath` + Cache-JPEGs aus `imageData`
- `BrainMesh/Attachments/AttachmentStore.swift`: AppSupport Cache für Anhänge (copy/delete/url helpers)
- `BrainMesh/Attachments/AttachmentHydrator.swift`: externalStorage → lokale Datei, dedupe + throttle (AsyncLimiter)
- `BrainMesh/Attachments/MediaAllLoader.swift`: Hintergrund-Fetching/Paging für „Alle Medien“-Screens (verhindert UI-Freezes)
- `BrainMesh/Attachments/AttachmentThumbnailStore.swift`: Thumbnail-Pipeline (Memory + Disk + QuickLook/ImageIO), concurrency-limited

**UI Layer (SwiftUI)**
- Entitäten/Attribute Detail Screens: `BrainMesh/Mainscreen/...` + Shared Sections unter
  `BrainMesh/Mainscreen/NodeDetailShared/*` (Highlights/Connections/Media/Sheets etc.)
- Galerie: `BrainMesh/PhotoGallery/*` (Browser + Viewer)
- Graph Canvas: `BrainMesh/GraphCanvas/*` (Canvas Rendering, Gestures, Physics, Loading)
- Onboarding: `BrainMesh/Onboarding/*`
- Security (Graph Lock): `BrainMesh/Security/*`
- Appearance/Theming: `BrainMesh/Appearance/*`, `BrainMesh/Icons/*`

## Folder Map (Ordner → Zweck)
- `BrainMesh/Mainscreen/`  
  Home- und Detail-Views (Entitäten/Attribute), Picker, Bulk-Operationen.
- `BrainMesh/Mainscreen/NodeDetailShared/`  
  Wiederverwendete Detail-Sections (Core, Highlights, Connections, Media, Sheets).
- `BrainMesh/GraphCanvas/`  
  Graph-Canvas UI: Laden, Rendering (Canvas), Physik-Simulation, Gesten, MiniMap/Inspector.
- `BrainMesh/PhotoGallery/`  
  Galerie-Browser (Grid) + Viewer (Fullscreen), Actions/Sheet-Flows.
- `BrainMesh/Attachments/`  
  Attachment Model + Import/Preview + Cache/Hydration + Thumbnailing + Loader für „Alle“-Screens.
- `BrainMesh/Security/`  
  Graph Lock (Biometrics/Passwort), Unlock Sheet/Flows.
- `BrainMesh/Onboarding/`  
  Onboarding Coordinator + UI (Sheet), Progress Computation.
- `BrainMesh/Appearance/`  
  App- und Graph-Theming (AppearanceStore, Settings, GraphTheme).
- `BrainMesh/Icons/`  
  SF-Symbol-Katalog/Picker (inkl. Prewarm in `AppRootView`).
- `BrainMesh/Observability/`  
  Minimal Logging + Timing (`BMLog`, `BMDuration`) in `BrainMesh/Observability/BMObservability.swift`.

## Data Model Map (Entities, Relationships, wichtige Felder)
- `MetaGraph` (`BrainMesh/Models.swift`)
  - Felder: `id`, `name`, `createdAt`
  - Security: `isProtected`, biometrics/password flags + hash/salt (siehe GraphLock in `BrainMesh/Security/*`)
- `MetaEntity` (`BrainMesh/Models.swift`)
  - Felder: `id`, `name`, `notes`, `createdAt`, `graphID`
  - Bild: `imageData` (sync), `imagePath` (deterministischer Cache-Dateiname)
  - Icon: `iconSymbolName`
  - Beziehungen: `attributes` (zu `MetaAttribute`)
- `MetaAttribute` (`BrainMesh/Models.swift`)
  - Felder: `id`, `name`, `notes`, `createdAt`, `graphID`
  - Owner: `owner` (MetaEntity)
  - Bild: `imageData`, `imagePath`
- `MetaLink` (`BrainMesh/Models.swift`)
  - Felder: `id`, `sourceID`, `targetID`, `sourceKindRaw`, `targetKindRaw`, `graphID`, `note`, `createdAt`
- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - Felder: `id`, `ownerKindRaw`, `ownerID`, `graphID`, `contentKindRaw`
  - Datei-Metadaten: `title`, `contentTypeIdentifier`, `fileExtension`, `byteCount`, `createdAt`
  - Datei-Inhalt: `fileData` (`@Attribute(.externalStorage)`)
  - Lokaler Cache: `localPath` (Dateiname im AttachmentStore)

## Sync/Storage (SwiftData + CloudKit + Caches)
### SwiftData/CloudKit
- Container: `BrainMesh/BrainMeshApp.swift` nutzt `ModelConfiguration(..., cloudKitDatabase: .automatic)`.
- Entitlements: `BrainMesh/BrainMesh.entitlements` enthält iCloud + CloudKit Container `iCloud.com.marcfechner.BrainMesh`.
- `Info.plist`: Background Mode `remote-notification` aktiv (CloudKit Push möglich), siehe `BrainMesh/Info.plist`.

**UNKNOWN**
- Ob ein eigenes CloudKit Schema/Zone-Setup existiert (im Code kein `import CloudKit` sichtbar; Sync läuft implizit über SwiftData).
- Ob es Multi-User Sharing/Collab gibt (kein Sharing-Code gefunden).

### Bilder
- Sync-Quelle: `imageData` (JPEG bytes) in `MetaEntity`/`MetaAttribute`.
- Lokaler Cache: `imagePath` + Datei im AppSupport (`ImageStore`).
- Import/Kompression: `BrainMesh/Images/ImageImportPipeline.swift` (CloudKit-schonende JPEGs).
- Auto-Hydration: `BrainMesh/AppRootView.swift` ruft `ImageHydrator.hydrateIncremental` max. alle 24h auf.

### Attachments (Dateien/Videos/Galeriebilder)
- Sync-Quelle: `MetaAttachment.fileData` (externalStorage) + Metadaten.
- Lokaler Cache: `AttachmentStore` schreibt Dateien unter AppSupport (siehe `BrainMesh/Attachments/AttachmentStore.swift`).
- Hydration: `AttachmentHydrator.ensureFileURL(...)` holt `fileData` (SwiftData) und schreibt Cache-Datei, throttled.
- Thumbnails: `AttachmentThumbnailStore.thumbnail(...)` (Memory+Disk Cache, concurrency-limited).

### Migration / Offline
- Graph scoping: `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` in `BrainMesh/GraphBootstrap.swift`.
- Attachment graphID Migration: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (wichtig, um OR-Predicates zu vermeiden).
- Offline: SwiftData Store ist lokal; CloudKit Sync ist opportunistisch. Konfliktstrategie ist **UNKNOWN** (SwiftData Standard).

## UI Map (Hauptscreens + Navigation + wichtige Flows)
### Root Navigation
- `TabView` in `BrainMesh/ContentView.swift`:
  1. **Entitäten** → `BrainMesh/Mainscreen/EntitiesHomeView.swift` (NavigationStack intern)
  2. **Graph** → `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  3. **Stats** → `BrainMesh/GraphStatsView.swift` (öffnet Settings via Sheet)

### Wichtige Flows
- Entität öffnen → Detail Screen (siehe `BrainMesh/Mainscreen/EntityDetail/*` und shared Sections in `NodeDetailShared/*`)
- Attribute öffnen → Detail Screen (`BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`)
- Medien:
  - „Medien“-Card zeigt Preview-Grid + Buttons („Bilder verwalten“, „Anhänge verwalten“) in `NodeDetailShared+Media.swift`.
  - „Alle Medien“ Screen: `NodeMediaAllView` (`NodeDetailShared+Media.swift`) mit Paging via `FetchDescriptor` + `MediaAllLoader`.
  - Attachment Manager: `NodeAttachmentsManageView` (`NodeDetailShared+SheetsSupport.swift`)
- Galerie Viewer:
  - Browser/Grid: `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
  - Viewer: `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`
- Graph Picker / Multi Graph:
  - Sheet: `BrainMesh/GraphPickerSheet.swift` + `BrainMesh/GraphPicker/*`
- Graph Lock:
  - Coordinator: `BrainMesh/Security/GraphLockCoordinator.swift`
  - Unlock UI: `BrainMesh/Security/GraphUnlockView.swift` (FullScreenCover in `AppRootView`)

## Build & Configuration
- Xcode Projekt: `BrainMesh.xcodeproj` (Deployment Target **26.0**).
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit, iCloud, KVS).
- Info.plist: `BrainMesh/Info.plist` (Background remote-notification).
- SPM Dependencies: **keine** Remote Swift Packages im `project.pbxproj` gefunden.
- Secrets-Handling: **UNKNOWN** (keine .xcconfig / Key-Dateien im Repo gefunden; keine API Keys in Swift Files gefunden).

## Conventions (Naming, Patterns, Do/Don't)
- Große Views werden in **Extensions / +Files** gesplittet (z.B. `GraphCanvasView+Physics.swift`, `NodeDetailShared+Media.swift`).
- Expensive I/O nicht im `body`:
  - Bilder: `ImageStore.loadUIImageAsync` + lokale `@State` Caches (z.B. `NotesAndPhotoSection.swift`).
  - Attachments: `MediaAllLoader` & `AttachmentHydrator` (Actors, Task.detached).
- SwiftData Query-Regel (aus Code-Kommentaren):
  - Vermeide `OR`/komplexe `#Predicate` über optionale Strings (siehe `GraphStatsService.swift`, `AttachmentGraphIDMigration.swift`).
- Bei Media Grids: Thumbnails immer **downscaled** (ImageIO) + concurrency-limited (`AttachmentThumbnailStore.swift`).

## How to work on this project (Setup + Einstieg)
Checklist:
1. `BrainMesh.xcodeproj` öffnen, iOS 26 Simulator/Device wählen.
2. Für CloudKit Sync: iCloud Login am Device/Simulator (sonst kann DEBUG-Init fatalen). Siehe `BrainMesh/BrainMeshApp.swift` (DEBUG kein Fallback).
3. First run:
   - `AppRootView` bootstrapped mindestens einen Graph (`GraphBootstrap.ensureAtLeastOneGraph`).
   - Falls Legacy Daten: Migration `graphID == nil` → Default Graph.
4. Feature-Startpunkte:
   - Neue Modelle: `BrainMesh/Models.swift` (+ Schema-Update in `BrainMesh/BrainMeshApp.swift`).
   - Neue Screens/Flows: `BrainMesh/ContentView.swift` (Tabs) oder `BrainMesh/Mainscreen/*` (NavigationStack).
   - Neue Media/Attachment Workflows: über `AttachmentStore`/`AttachmentHydrator`/`MediaAllLoader`.

## Quick Wins (max. 10, konkret)
1. **Graph Load off MainActor**: `GraphCanvasScreen+Loading.swift` fetcht synchron auf MainActor → Hintergrund-Context wie `MediaAllLoader` einführen.
2. **Stats off MainActor**: `GraphStatsService` ist `@MainActor` und macht viele `fetchCount` → Background-Context, UI nur Result committen.
3. **Active-Graph-State vereinheitlichen**: `GraphSession.swift` (Combine) vs. überall `@AppStorage("BMActiveGraphID")` → entscheiden, eins löschen.
4. **Hydration-Trigger observability**: `ImageHydrator`/`AttachmentHydrator` kurze Logs/Timestamps in `BMObservability` integrieren (Repro einfacher).
5. **Attachment-Bytes Summierung**: `GraphStatsService.totalAttachmentBytes()` lädt alle `MetaAttachment` Objekte → in Background, oder persistenten Counter pro Graph einführen.
6. **NodeDetailShared+Media splitten**: `NodeDetailShared+Media.swift` (726 LOC) in kleinere Views/Files (AllView, ThumbGrid, Tile) für Compile-Time.
7. **Predicate-Härtung**: überall `OR` vermeiden (wie bereits bei Attachments) und Graph scoping konsequent sicherstellen.
8. **UI-Test/Smoke-Test Skeleton**: Test Targets existieren im `.xcodeproj`, aber keine Tests im Repo → minimalen Smoke Test hinzufügen (**UNKNOWN**, ob absichtlich entfernt).
