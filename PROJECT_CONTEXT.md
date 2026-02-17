# PROJECT_CONTEXT (Start Here) — BrainMesh

## TL;DR
BrainMesh ist eine iOS/iPadOS-App (Deployment Target iOS 26.0, Device Family 1,2), die einen graph-basierten Workspace („Graph“) mit Entitäten, Attributen, Verbindungen (Links) sowie Medien (Bilder/Videos/Dateianhänge) verwaltet. Persistenz läuft über SwiftData mit CloudKit-Sync (konfiguriert in `BrainMeshApp.swift`).

## Key Concepts (Domänenbegriffe)
- **Graph (Workspace)**: Abgrenzung/Sichtbereich der Daten. Technisch über `MetaGraph` + optional `graphID`-Scoping in den Records (`Models.swift`, `GraphBootstrap.swift`).
- **Entität**: Knoten-Typ „Entity“ (`MetaEntity`), kann Attribute besitzen und ein Hauptfoto/Notizen/Icon.
- **Attribut**: Knoten-Typ „Attribute“ (`MetaAttribute`), gehört optional zu einer Entität (`owner`), hat eigenes Foto/Notizen/Icon.
- **Link**: gerichtete Verbindung zwischen zwei Nodes (`MetaLink` mit `sourceKindRaw/sourceID` → `targetKindRaw/targetID`).
- **Attachment**: Datei/Video oder Galerie-Bild (`MetaAttachment`, `AttachmentContentKind`). Attachments hängen an Entity/Attribute via `(ownerKindRaw, ownerID)`.

## Architecture Map (Text)
- **App/Bootstrapping** → `BrainMeshApp.swift` (SwiftData `ModelContainer` + CloudKit config, Dependency wires), `AppRootView.swift` (Startup, Locks, Onboarding, Hydrators).
- **Persistence/Domain** → `Models.swift` + `Attachments/MetaAttachment.swift` (SwiftData `@Model`).
- **Services/Stores** → `ImageStore.swift`, `ImageHydrator.swift`, `Images/ImageImportPipeline.swift`, `Attachments/*Store.swift`, `Attachments/AttachmentHydrator.swift`, `Attachments/MediaAllLoader.swift`, `GraphStatsService.swift`, `GraphPicker/*Service.swift`.
- **Presentation (SwiftUI)**
  - Tabs: `ContentView.swift` → `EntitiesHomeView` / `GraphCanvasScreen` / `GraphStatsView`.
  - Detail Screens: `Mainscreen/EntityDetail/*`, `Mainscreen/AttributeDetail/*`, `Mainscreen/NodeDetailShared/*` (shared sections).
  - Graph: `GraphCanvas/*` (Canvas + UI overlays).
  - Media: `PhotoGallery/*`, `Attachments/*`.
  - Security: `Security/*` (Lock/Unlock + Password).
- **Cross-Cutting** → `Observability/BMObservability.swift` (Logger/Timing), `Support/SystemModalCoordinator.swift`.

## Folder Map
- `Appearance/` — App-weite Appearance/Theme-Modelle, Store und UI (Tint, ColorScheme, Presets).
- `Assets.xcassets/` — Assets (Icons, Colors, etc.).
- `Attachments/` — Anhänge (Files/Videos/GalleryImages): SwiftData-Modell MetaAttachment, Import, Preview, Cache, Thumbnails, Hydration.
- `GraphCanvas/` — Interaktiver Graph-Canvas: Laden/Expand/Layouts/Physics/Rendering/Overlays/Inspector.
- `GraphPicker/` — Graph-Auswahl/Management (wechseln, umbenennen, löschen, Dedupe/Deletion Services).
- `Icons/` — Icon-Auswahl (SF Symbols Katalog, Picker UI, Prewarm).
- `Images/` — Bild-Import-Pipeline (Decode, Resize, JPEG-Kompression für CloudKit).
- `ImportProgress/` — UI-State/Komponenten für Import-Fortschritt.
- `Mainscreen/` — Entitäten/Attribute/Links: Home-Liste, Detail-Screens, Picker, Bulk-Linking, Shared Detail Sections.
- `Observability/` — Micro-Logging + Timing-Helfer (os.Logger, Duration).
- `Onboarding/` — Onboarding Coordinator, Views, Progress-Berechnung.
- `PhotoGallery/` — Galerie UI (Grid/Browser/Viewer), Query/Actions, Thumbnail-Tiles.
- `Security/` — Graph-Sperre/Unlock: Coordinator, Crypto, Unlock/SetPassword UI.
- `Support/` — Kleine app-weite Koordinatoren/Utilities (z.B. SystemModalCoordinator).

## Data Model Map
### SwiftData Modelle
- `MetaGraph` (`Models.swift`)
  - Felder: `id`, `createdAt`, `name`, `nameFolded`
  - Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- `MetaEntity` (`Models.swift`)
  - Scope: `graphID` (optional, Migration/Legacy)
  - Felder: `name`, `nameFolded`, `notes`, `iconSymbolName`
  - Bild: `imageData` (synced), `imagePath` (lokaler Cache-Pfad)
  - Relationship: `attributes: [MetaAttribute]?` (deleteRule `.cascade`, inverse `\MetaAttribute.owner`)
- `MetaAttribute` (`Models.swift`)
  - Scope: `graphID` (optional)
  - Felder: `name`, `nameFolded`, `notes`, `iconSymbolName`
  - Bild: `imageData` (synced), `imagePath` (lokaler Cache-Pfad)
  - Ownership: `owner: MetaEntity?` (kein SwiftData-Relationship-Makro, um Macro-Zyklen zu vermeiden)
  - Suche: `searchLabelFolded` (folded `displayName` = „Entity · Attribute“)
- `MetaLink` (`Models.swift`)
  - Scope: `graphID` (optional)
  - Felder: `createdAt`, `note`
  - Kanten: `sourceKindRaw`, `sourceID`, `sourceLabel` und `targetKindRaw`, `targetID`, `targetLabel`
- `MetaAttachment` (`Attachments/MetaAttachment.swift`)
  - Scope: `graphID` (optional)
  - Owner: `ownerKindRaw` + `ownerID` (kein Relationship-Makro; vermeidet Zyklen)
  - Verwendung: `contentKindRaw` (`AttachmentContentKind`: `.file`, `.video`, `.galleryImage`)
  - Metadaten: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - Bytes: `fileData` mit `@Attribute(.externalStorage)` (SwiftData externes Storage; CloudKit-friendly)
  - Cache: `localPath` (Application Support / BrainMeshAttachments)

## Sync / Storage
### SwiftData + CloudKit
- Container: `BrainMeshApp.swift`
  - Schema: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`
  - Configuration: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - Deployment Target: iOS 26.0 (aus `BrainMesh.xcodeproj/project.pbxproj`)
  - Fallback: In `DEBUG` → `fatalError` bei CloudKit-Container-Fehler; in Release → Fallback auf lokalen `ModelConfiguration(schema:)`.
- Entitlements: `BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud Service: CloudKit
  - APS env: `development`
- Info.plist: `Info.plist`
  - `UIBackgroundModes`: `remote-notification` (typisch für CloudKit push).
  - `NSFaceIDUsageDescription` gesetzt (Graph-Entsperrung).

### Lokale Caches (Application Support)
- **Entity/Attribute Hauptfoto**: `ImageStore.swift` → `BrainMeshImages/`
  - Memory: `NSCache` (countLimit 120)
  - Disk: JPEG-Dateien, i.d.R. deterministisch `"<UUID>.jpg"` (`ImageHydrator.swift`).
- **Attachments**: `Attachments/AttachmentStore.swift` → `BrainMeshAttachments/`
  - Cache-Datei deterministisch `"<UUID>.<ext>"`.
  - Thumbnails auf Disk: `Attachments/AttachmentThumbnailStore.swift` → `thumb_<UUID>.jpg` in demselben Ordner.

### Hydration / Progressive Loading
- `ImageHydrator.swift`: schreibt fehlende JPEGs nach `BrainMeshImages/` (incremental/force rebuild).
- `Attachments/AttachmentHydrator.swift`: erzeugt Cache-Files on-demand pro sichtbarem Attachment, global gedrosselt (`AsyncLimiter maxConcurrent: 2`).
- `Attachments/MediaAllLoader.swift`: lädt Listen/Counts für „Alle“-Medien off-main (detached + eigener `ModelContext`).

### Offline-Verhalten
- SwiftData speichert lokal; CloudKit Sync kommt dazu, wenn iCloud verfügbar ist.
- Konfliktauflösung / Merge-Policy: **UNKNOWN** (SwiftData/CloudKit intern; keine explizite Policy im Code gefunden).

## UI Map (Screens + Navigation + Flows)
### Root Navigation
- `ContentView.swift`: `TabView`
  - Tab 1: `EntitiesHomeView()`
  - Tab 2: `GraphCanvasScreen()`
  - Tab 3: `GraphStatsView()`

### Startup / Global Flows
- `AppRootView.swift`
  - Startup: `runStartupIfNeeded()` → `GraphBootstrap.ensureAtLeastOneGraph`, `GraphBootstrap.migrateLegacyRecordsIfNeeded`
  - Locks: `GraphLockCoordinator` (fullScreenCover `GraphUnlockView` via `graphLock.activeRequest`)
  - Onboarding: `.sheet(isPresented: $onboarding.isPresented) { OnboardingSheetView() }`
  - Background Auto-Lock mit Debounce + System-Modal-Grace (siehe `Support/SystemModalCoordinator.swift`).

### Entities Tab
- `Mainscreen/EntitiesHomeView.swift`
  - `NavigationStack` → `EntityDetailView(entity:)`
  - Sheets: `AddEntityView`, `GraphPickerSheet`, `SettingsView`
  - Suche: debounced `.task(id: taskToken)` → `fetchEntities(...)` (SwiftData fetch + folded search).

### Detail Screens (Entity/Attribute)
- `Mainscreen/EntityDetail/EntityDetailView.swift` + Extensions (z.B. `EntityDetailView+MediaSection.swift`)
- `Mainscreen/AttributeDetail/AttributeDetailView.swift` + Extensions (z.B. `AttributeDetailView+MediaSection.swift`)
- Shared Sections: `Mainscreen/NodeDetailShared/*`
  - Header/Hero: `NodeDetailHeaderCard.swift`, `NodeDetailShared+Core.swift`
  - Highlights: `NodeDetailShared+Highlights.swift`
  - Connections: `NodeDetailShared+Connections.swift`
  - Media: `NodeDetailShared+Media.swift` (Gallery + Attachments + Navigation) + `NodeImagesManageView.swift`

### Graph Tab
- `GraphCanvas/GraphCanvasScreen.swift` (Host/State/Toolbars) + Extensions
- `GraphCanvas/GraphCanvasScreen+Loading.swift`: lädt Nodes/Edges aus SwiftData
- `GraphCanvas/GraphCanvasView.swift` + `GraphCanvasView+Physics.swift` (30 FPS Timer) + `GraphCanvasView+Rendering.swift`

### Stats Tab
- `GraphStatsView.swift`: Stats UI
- `GraphStatsService.swift`: Zählungen/Aggregate via `fetchCount`

### Media UI
- Galerie: `PhotoGallery/*` (Grid, Browser, Viewer)
- Attachments: `Attachments/*` (Import, Preview, Thumbnailing, Video Playback).

## Build & Configuration
### Xcode Projekt
- Projekt: `BrainMesh.xcodeproj`
- Workspace: `BrainMesh.xcworkspace` (vorhanden, enthält i.d.R. das Projekt).
- Deployment Target: iOS 26.0.
- Targeted Device Family: 1,2 ("1"=iPhone, "2"=iPad).

### Capabilities / Entitlements
- iCloud (CloudKit): `BrainMesh.entitlements`
- Push (APS): `aps-environment` gesetzt (development).

### Abhängigkeiten
- Swift Packages: keine `Package.swift` gefunden und keine `XCRemoteSwiftPackageReference` Einträge im `project.pbxproj` → **keine SPM-Abhängigkeiten erkannt**.

### Secrets Handling
- Keine `.xcconfig` Dateien gefunden.
- Kein offensichtliches API-Key-Pattern im Code gefunden.
- Falls Secrets in Xcode Build Settings hinterlegt sind: **UNKNOWN**.

## Conventions (Patterns, Do/Don't)
### Naming & Data Patterns
- Suche: immer über `BMSearch.fold(...)` und die persistierten Felder `nameFolded` / `searchLabelFolded` (`Models.swift`).
- Graph Scope: `graphID` ist optional (Legacy/Migration). Queries i.d.R. `e.graphID == gid || e.graphID == nil` (siehe z.B. `Mainscreen/EntitiesHomeView.swift`).
- Beziehungen: nur eine Seite als `@Relationship(inverse:)` definieren, andere Seite als normales Feld (siehe `MetaEntity.attributes` vs. `MetaAttribute.owner`).

### UI/Performance Do/Don't
- ❌ keine synchrone Disk-I/O im `body` (`ImageStore.loadUIImage(path:)` ist explizit als „nicht im body“ dokumentiert).
- ✅ Bilder/Thumbnails async laden + drosseln (`ImageStore.loadUIImageAsync`, `AttachmentThumbnailStore` + `AsyncLimiter`).
- ✅ bei potentiell großen Listen: debounce + fetch in `.task(id:)` (z.B. `EntitiesHomeView`).
- ✅ für „global screens“ die SwiftData Fetches in background `ModelContext` auslagern, wenn Navigation/Scroll jankt (Pattern siehe `Attachments/MediaAllLoader.swift`).

### Logging
- `Observability/BMObservability.swift`: nutze `BMLog.*` + `BMDuration()` in Hot Paths (Graph load/expand/physics).

## How to work on this project
### Setup (neuer Dev)
1. Öffne `BrainMesh.xcworkspace` (oder `BrainMesh.xcodeproj`, falls workspace leer).
2. Team/Signing setzen (Xcode → Signing & Capabilities).
3. iCloud Capability aktiv lassen, wenn CloudKit Sync getestet werden soll (Container: `iCloud.de.marcfechner.BrainMesh`).
4. Build & Run auf iPhone/iPad (Deployment Target iOS 26.0).

### Wo anfangen (Code)
- Einstieg: `BrainMeshApp.swift` → `AppRootView.swift` → `ContentView.swift`.
- Neue UI-Features: typischerweise in `Mainscreen/` (Entities/Details) oder `GraphCanvas/` (Graph).
- Media/Files: `PhotoGallery/` (Bilder/Videos UI), `Attachments/` (Files/Thumbnails/Import).
- Performance: starte bei den in `ARCHITECTURE_NOTES.md` markierten Hotspots (Graph load/render, Stats view).

## Quick Wins (max 10, konkret)
1. **Graph-Laden off-main**: `GraphCanvas/GraphCanvasScreen+Loading.swift` lädt SwiftData derzeit unter `@MainActor` → Loader-Pattern wie `Attachments/MediaAllLoader.swift` übernehmen.
2. **Stats UI entknoten**: `GraphStatsView.swift` (1152 Zeilen) in Subviews/Sections splitten (compile-time + Wartbarkeit).
3. **Media Section split**: `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` (726 Zeilen) in `+Gallery`, `+Attachments`, `+Navigation` zerlegen.
4. **Lock/Picker Robustness**: SystemModal-Tracking konsistent in allen Pickern nutzen (`Support/SystemModalCoordinator.swift`) – sicherstellen, dass jede Picker-Präsentation begin/end aufruft. (Sonst wieder Face-ID/Hidden-Album Loops.)
5. **Predicate Hygiene**: OR/Optional-Tricks vermeiden (vgl. Kommentare in `GraphStatsService.swift`, `Attachments/MediaAllLoader.swift`).
6. **Prewarm / Cache Limits audit**: NSCache Limits (`ImageStore`, `AttachmentThumbnailStore`) auf reale Datenmengen abstimmen (Memory Pressure).
7. **Attachment Hydration Telemetrie**: minimal logging um Cache-Miss-Raten zu sehen (`AttachmentHydrator`, `AttachmentThumbnailStore`).
8. **GraphCanvas Physics Sleep**: prüfen, ob `physicsIsSleeping` zuverlässig greift (Timer/CPU). Falls nicht, aggressiveres Sleep/Resume.
9. **Delete Workflows**: beim Löschen von Entities/Attributes konsequent Links + Attachments cleanup (Pattern in `EntitiesHomeView.deleteEntities`).
10. **Test-Szenarien als Checkliste**: Multi-Device (cache leer), Hidden Album FaceID, große Graphen (N>1k) als reproduzierbare Steps dokumentieren.
