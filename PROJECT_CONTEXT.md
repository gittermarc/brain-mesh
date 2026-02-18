# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine SwiftUI-App (iOS/iPadOS **26.0**) für ein persönliches Wissens‑/Beziehungsnetz ("Graph"): Du legst **Entitäten** an, hängst **Attribute** dran, verknüpfst Dinge über **Links**, und sammelst **Anhänge/Medien**. Persistenz läuft über **SwiftData** mit **CloudKit private DB** (automatisch), plus lokale Caches für Bilder/Anhänge.

## Key Concepts / Domänenbegriffe
- **Graph**: Arbeitskontext/Sammlung (`MetaGraph`). Viele Abfragen sind über `graphID` gescoped.
- **Entity**: Knoten im Graph (`MetaEntity`).
- **Attribute**: hängt an einer Entity (`MetaAttribute`, Relationship `owner`).
- **Link**: Kante zwischen zwei Nodes (`MetaLink`). Speichert zusätzlich Label-Snapshots (`sourceLabel`/`targetLabel`) für schnelle Listen.
- **Attachment**: Datei/Bild/Video (`MetaAttachment`). `fileData` ist **external storage**; zusätzlich lokaler Preview-Cache.
- **NodeKind / NodeKey**: vereinheitlicht Entity/Attribute als Node (`BrainMesh/Mainscreen/NodeKey.swift`).
- **SystemModalCoordinator**: Trackt systemseitige Modals (Photos Picker / FaceID), damit Auto‑Lock nicht in den Picker reinfunkt (`BrainMesh/Support/SystemModalCoordinator.swift`).

## Architecture Map (Layer/Module → Verantwortung)

### UI (SwiftUI Views)
- Root & Navigation: `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`
- Home/CRUD: `BrainMesh/Mainscreen/*` (Entities/Attributes/Links + Detailseiten)
- Graph Canvas: `BrainMesh/GraphCanvas/*` (Rendering, Gestures, Physics, Loading)
- Stats: `BrainMesh/Stats/*` (Dashboard + Loader + Service)
- Media/Attachments UI: `BrainMesh/Attachments/*`, `BrainMesh/PhotoGallery/*`
- Settings/Onboarding/Security: `BrainMesh/Settings/*`, `BrainMesh/Onboarding/*`, `BrainMesh/Security/*`

### Data (SwiftData Models)
- Models & Search Helpers: `BrainMesh/Models.swift`
- Attachments Model: `BrainMesh/Attachments/MetaAttachment.swift`

### Storage/Sync + Caches
- SwiftData Container + CloudKit: `BrainMesh/BrainMeshApp.swift`
- Bildcache (JPEG, deterministic): `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
- Attachment Cache (Application Support): `BrainMesh/Attachments/AttachmentStore.swift`
- Thumbnail Pipeline (Memory+Disk, throttled): `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

### Off‑Main Loader Pattern (Hot‑Path Entkoppelung)
- Snapshot‑DTO + `Task.detached` + eigener `ModelContext`, Ergebnis wird UI-seitig "atomar" committed:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/NodePickerLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `BrainMesh/Attachments/MediaAllLoader.swift`

## Folder Map (Ordner → Zweck)
- `BrainMesh/Appearance/`
- `BrainMesh/Assets.xcassets/`
- `BrainMesh/Attachments/`
- `BrainMesh/GraphCanvas/`
- `BrainMesh/GraphPicker/`
- `BrainMesh/Icons/`
- `BrainMesh/Images/`
- `BrainMesh/ImportProgress/`
- `BrainMesh/Mainscreen/`
- `BrainMesh/Observability/`
- `BrainMesh/Onboarding/`
- `BrainMesh/PhotoGallery/`
- `BrainMesh/Security/`
- `BrainMesh/Settings/`
- `BrainMesh/Stats/`
- `BrainMesh/Support/`

Wichtige Root-Files:
- `BrainMesh/AppRootView.swift`
- `BrainMesh/BrainMesh.entitlements`
- `BrainMesh/BrainMeshApp.swift`
- `BrainMesh/ContentView.swift`
- `BrainMesh/FullscreenPhotoView.swift`
- `BrainMesh/GraphBootstrap.swift`
- `BrainMesh/GraphPickerSheet.swift`
- `BrainMesh/GraphSession.swift`
- `BrainMesh/ImageHydrator.swift`
- `BrainMesh/ImageStore.swift`
- `BrainMesh/Info.plist`
- `BrainMesh/Models.swift`
- `BrainMesh/NotesAndPhotoSection.swift`

## Data Model Map (Entities / Relationships / wichtige Felder)

### `MetaGraph` (`BrainMesh/Models.swift`)
- `id: UUID`
- `name: String`
- `createdAt: Date`
- `isLocked: Bool`
- `lockPasscodeHash: String?`

### `MetaEntity` (`BrainMesh/Models.swift`)
- `id`, `graphID: UUID?`
- `name`, `nameFolded` (Search)
- `notes`, `createdAt`
- Appearance: `iconSymbolName`, `imageData?`, `imagePath?`
- Relationships: `attributesList: [MetaAttribute]` (inverse `MetaAttribute.owner`)

### `MetaAttribute` (`BrainMesh/Models.swift`)
- `id`, `graphID: UUID?`
- `name`, `nameFolded`, `searchLabelFolded`
- `value`, `notes`, `createdAt`
- Appearance: `iconSymbolName`, `imageData?`, `imagePath?`
- Relationships: `owner: MetaEntity?` (inverse `MetaEntity.attributesList`)

### `MetaLink` (`BrainMesh/Models.swift`)
- `id`, `graphID: UUID?`, `createdAt`, `note?`
- Endpunkte (denormalisiert):
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`

### `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- `id`, `createdAt`, `graphID: UUID?`, `ownerKindRaw`, `ownerID`
- `contentKindRaw` (z.B. galleryImage vs file)
- Metadaten: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Inhalt: `fileData` (**@Attribute(.externalStorage)**)
- Preview Cache: `localPath` (Application Support filename)

## Sync/Storage

### SwiftData + CloudKit
- Container/Schema + CloudKit Config: `BrainMesh/BrainMeshApp.swift`
- iCloud Container (Entitlements): **iCloud.de.marcfechner.BrainMesh** (`BrainMesh/BrainMesh.entitlements`)
- Fallback: In **Release** wird bei CloudKit‑Fehlern auf lokalen Store ohne CloudKit gewechselt (`BrainMesh/BrainMeshApp.swift`)
- **UNKNOWN**: Konfliktauflösung/Merge Policy, CloudKit Schema Evolution Details.

### Migration / Legacy Daten
- Graph Scoping:
  - Entities/Attributes/Links: `BrainMesh/GraphBootstrap.swift` migriert `graphID == nil` → Default‑Graph.
  - Attachments: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` migriert owner‑scoped legacy attachments (wichtig für store‑translatable Predicates).

### Caches
- Bildcache: JPEGs in App Support (deterministic `UUID.jpg`) + `imagePath` im Model (`BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`).
- Attachment Cache: lokale Preview-Kopien in App Support (`BrainMesh/Attachments/AttachmentStore.swift`).
- Thumbnails: Dedupe + throttling (`AsyncLimiter(maxConcurrent: 3)`) (`BrainMesh/Attachments/AttachmentThumbnailStore.swift`).

### Offline-Verhalten
- SwiftData arbeitet lokal; CloudKit sync't opportunistisch.
- **UNKNOWN**: explizite Offline‑UX (Banner/Retry), Konflikt‑UI.

## UI Map (Hauptscreens + Navigation)

### Entry Points
- App Entry: `BrainMesh/BrainMeshApp.swift`
- Root Lifecycle: `BrainMesh/AppRootView.swift`
- Tabs: `BrainMesh/ContentView.swift`

### Tabs
- **Home**: `BrainMesh/Mainscreen/EntitiesHomeView.swift` (Search + Liste)
  - Daten: `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` (off-main Snapshot)
- **Graph**: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - Loading: `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift` → `GraphCanvasDataLoader`
  - Physics/Rendering: `GraphCanvasView+Physics.swift`, `GraphCanvasView+Rendering.swift`
- **Stats**: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - Daten: `BrainMesh/Stats/GraphStatsLoader.swift` (off-main Snapshot)

### Wichtige Sheets/Flows
- Graph Picker / Manage / Lock: `BrainMesh/GraphPickerSheet.swift`, `BrainMesh/GraphPicker/*`
- Detail-Sheets (Media/Links/Bulk): `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift`
- Media Import (PhotosPicker): `BrainMesh/PhotoGallery/*` + `SystemModalCoordinator`.
- Settings: `BrainMesh/Settings/SettingsView.swift`
- Onboarding: `BrainMesh/Onboarding/OnboardingSheetView.swift`

## Build & Configuration
- Xcode Project: `BrainMesh/BrainMesh.xcodeproj`
- Targets:
  - App: **de.marcfechner.BrainMesh**
  - Tests: `de.marcfechner.BrainMeshTests`, `de.marcfechner.BrainMeshUITests`
- Deployment Target: **iOS/iPadOS 26.0**
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit + APS)
- Info.plist: `BrainMesh/Info.plist` (FaceID, background remote-notification)
- SPM: **NONE detected** (keine Swift Package References im pbxproj)
- Secrets: **NONE detected** (keine offensichtliche Secrets/.xcconfig im Zip)

## Conventions (Naming, Patterns, Do/Don’t)

### Do
- Keine SwiftData Models über Actor/Thread Grenzen reichen → DTO/Snapshots verwenden.
- Fetch/Sort nicht im Renderpfad (`body`, Row) → Loader/Service + `.task`.
- Predicates store‑translatable halten (kein OR über `nil`), sonst droht in‑memory filtering (siehe Attachments Migration).
- Cancellation/Dedupe bei schnellen UI-Interaktionen (Search tippen, Graph wechseln).

### Don’t
- `modelContext.fetch` in `body`.
- UI-Sheets aus List-Row heraus präsentieren (Row-Rehosting kann modals sofort dismissen) → Parent-owned presentation (wird in `PhotoGallerySection` explizit kommentiert).

## How to work on this project

### Setup Steps
- `BrainMesh.xcodeproj` öffnen.
- Signing/Capabilities: CloudKit Container + Push Entitlements müssen zum Team passen.
- Für Graph Lock: FaceID/TouchID läuft über LocalAuthentication (siehe `BrainMesh/Security/*`).

### Wo anfangen (für neue Devs)
- Datenmodell: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Root/Lifecycle: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`
- Hot Path Screens: Home/Graph/Stats

### Neues Feature hinzufügen (Workflow)
1) Model ändern/neu (`@Model`) → `Models.swift` oder neue Datei
2) Schema in `BrainMeshApp.swift` aktualisieren
3) Migration/Scoping prüfen (`GraphBootstrap`, `AttachmentGraphIDMigration`)
4) UI/Navigation bauen (Tabs/Stacks/Sheets)
5) Wenn Daten schwer sind: Loader Pattern nutzen (actor + detached + snapshot)
6) Logging: `BrainMesh/Observability/*`

## Quick Wins (max 10)
1) `NodeDetailShared+SheetsSupport.swift` splitten → Compile-Time & Wartbarkeit.
2) Home Listing Counts ohne N+1 (Batch counts im Loader) → Scroll bleibt smooth.
3) Audit `GraphCanvasDataLoader` Predicates mit `Array.contains` (store translation) → Guardrails.
4) Einheitliches Debounce für Search Inputs (EntitiesHome/Picker).
5) Stats Snapshot caching (zeitbasiert) wenn DB sehr groß.
6) Attachment Cache Policy (TTL/LRU) ergänzen oder bewusst "nur manuell" dokumentieren.
7) Zentraler LoaderRegistry statt viele `Task.detached { configure }` im App init.
8) Migration Errors sichtbar machen (Logging statt `try?` silent).
9) Paging in Link/Attachment "Alle" Screens, falls Daten extrem groß.
10) Mini Perf Dashboard in Settings (Loader timings, thumbnail hit rate).

## Open Questions (UNKNOWNs)
- SwiftData/CloudKit Konfliktauflösung, Merge Policy, deterministische Reihenfolge.
- CloudKit Asset Limits + Verhalten bei sehr großen `fileData`.
- Graph Lock: genaue Speicherung/Hashing/Keychain Nutzung (**welche Datei?**).
- remote-notification: wird aktiv genutzt oder nur CloudKit Hintergrundsync?
- Test Coverage: wie viel Logik ist über Tests abgedeckt?
