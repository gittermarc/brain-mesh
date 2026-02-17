# BrainMesh — PROJECT_CONTEXT

> Stand: 2026-02-17

## TL;DR
BrainMesh ist eine SwiftUI-App für iOS/iPadOS (Deployment Target: iOS **26.0**) zum Verwalten mehrerer **Wissens-Graphen** ("Graphs"). Pro Graph gibt es **Entitäten** (MetaEntity) mit **Attributen** (MetaAttribute), Beziehungen als **Links** (MetaLink) sowie **Medien/Anhänge** (MetaAttachment + Entity/Attribute Header-Bild). Persistenz läuft über **SwiftData** mit **CloudKit Sync** (private DB, `.automatic`), plus lokale Disk-Caches für Bilder/Dateien.

* iOS Target/Deployment: `BrainMesh.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`)
* SwiftData Container + CloudKit config: `BrainMesh/BrainMeshApp.swift`

---

## Key Concepts / Domänenbegriffe

- **Graph (MetaGraph)**
  - Container/Scope für alle Inhalte (Entitäten, Attribute, Links, Attachments).
  - Optional **geschützt** (FaceID/Passwort). Siehe `BrainMesh/Models.swift` (Felder) und `BrainMesh/Security/*` (Flow).

- **Entität (MetaEntity)**
  - "Ding" im Graphen, z.B. Person, Projekt, Begriff.
  - Kann: Header-Bild, Notizen, Icon, Attribute-Liste. Siehe `BrainMesh/Models.swift`.

- **Attribut (MetaAttribute)**
  - Key/Value-artiger Eintrag, der immer zu genau einer Entität gehört (`owner`).
  - Hat ebenfalls Notizen, optional Header-Bild, Icon. Siehe `BrainMesh/Models.swift`.

- **Link (MetaLink)**
  - Beziehung zwischen zwei Nodes (Entity oder Attribute), gespeichert als IDs + Labels.
  - Link-Notiz ist optional. Siehe `BrainMesh/Models.swift`.

- **Attachment / Medien (MetaAttachment)**
  - Einheitliches Modell für Gallery-Images, Files, Videos.
  - Wichtig: keine SwiftData-Relationship zu Owner; stattdessen `ownerKindRaw` + `ownerID` + optional `graphID`.
  - Datei-Bytes liegen in `fileData` als `@Attribute(.externalStorage)`. Siehe `BrainMesh/Attachments/MetaAttachment.swift`.

- **Header-Bild vs Gallery-Image**
  - Header-Bild: `MetaEntity.imageData` / `MetaAttribute.imageData` (SwiftData, synced) + `imagePath` (lokaler Cachepfad, derived).
    - Siehe `BrainMesh/Models.swift` und Cache: `BrainMesh/ImageStore.swift`, Hydration: `BrainMesh/ImageHydrator.swift`.
  - Gallery-Images: als `MetaAttachment` mit `contentKind == .galleryImage`. Siehe `BrainMesh/Attachments/MetaAttachment.swift`.

- **Off-main Loader Pattern**
  - Actor + `Task.detached` + eigener `ModelContext` → liefert nur DTO/Snapshot (keine `@Model`-Objekte).
  - Beispiele: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/Attachments/MediaAllLoader.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`, `BrainMesh/Mainscreen/NodePickerLoader.swift`.

---

## Architecture Map

**(Text-Dependency Map, "oben" = UI, "unten" = Storage)**

- **App Composition / DI**
  - `BrainMesh/BrainMeshApp.swift`
    - erstellt `ModelContainer` (CloudKit `.automatic`, Release-Fallback local-only)
    - konfiguriert Off-main Loader (`*.configure(container: AnyModelContainer)`) per `Task.detached`
    - setzt EnvironmentObjects: `AppearanceStore`, `OnboardingCoordinator`, `GraphLockCoordinator`, `SystemModalCoordinator`

- **Root UI / Navigation**
  - `BrainMesh/AppRootView.swift` (ScenePhase, Auto-Lock Debounce, Onboarding Sheet, GraphUnlock FullScreenCover)
  - `BrainMesh/ContentView.swift` (TabView: Entities / Graph / Stats)

- **Feature UI (SwiftUI)**
  - Entities/Attribute Detail: `BrainMesh/Mainscreen/*` (+ `NodeDetailShared/*`)
  - Graph Canvas: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Graph Picker + Security: `BrainMesh/GraphPicker/*`, `BrainMesh/GraphPickerSheet.swift`, `BrainMesh/Security/*`
  - Media/Gallery/Attachments: `BrainMesh/PhotoGallery/*`, `BrainMesh/Attachments/*`
  - Settings/Appearance: `BrainMesh/Settings/*`, `BrainMesh/Appearance/*`
  - Onboarding: `BrainMesh/Onboarding/*`

- **Domain / Model**
  - Core Models: `BrainMesh/Models.swift` (MetaGraph, MetaEntity, MetaAttribute, MetaLink + Search folding)
  - Attachments Model: `BrainMesh/Attachments/MetaAttachment.swift`

- **Storage / Sync**
  - SwiftData + CloudKit: `BrainMesh/BrainMeshApp.swift` (ModelConfiguration(cloudKitDatabase: .automatic))
  - Disk Caches
    - Header-Bilder: `BrainMesh/ImageStore.swift`
    - Attachment-Files: `BrainMesh/Attachments/AttachmentStore.swift`
    - Attachment-Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

- **Cross-cutting**
  - Locking: `BrainMesh/Security/GraphLockCoordinator.swift`, `BrainMesh/Security/GraphUnlockView.swift`
  - System modal suppression (Photos/FaceID etc.): `BrainMesh/Support/SystemModalCoordinator.swift` + Nutzung in `AppRootView.swift` und diversen Pickern (z.B. `BrainMesh/NotesAndPhotoSection.swift`).
  - Observability: `BrainMesh/Observability/BMObservability.swift` (BMLog + BMDuration)

---

## Folder Map (Ordner → Zweck)

> Pfade relativ zum App-Target-Root `BrainMesh/`.

- `BrainMesh/Appearance/`
  - Display-/Theme-Modelle + Store (z.B. `AppearanceModels.swift`, `AppearanceStore.swift`).

- `BrainMesh/Attachments/`
  - MetaAttachment Modell + Import/Preview + Cache/Hydration/Thumbnails.
  - Kritische Dateien: `MetaAttachment.swift`, `AttachmentStore.swift`, `AttachmentHydrator.swift`, `MediaAllLoader.swift`, `AttachmentGraphIDMigration.swift`.

- `BrainMesh/GraphCanvas/`
  - Interaktiver Graph (Rendering + Physics + Inspector + Data Loading).
  - Kritische Dateien: `GraphCanvasScreen.swift`, `GraphCanvasDataLoader.swift`, `GraphCanvasView+Physics.swift`, `GraphCanvasView+Rendering.swift`.

- `BrainMesh/GraphPicker/`
  - UI-Bausteine für Graph-Auswahl/Management (List, Rename/Delete Flows).
  - Sheet-Host: `BrainMesh/GraphPickerSheet.swift`.

- `BrainMesh/Icons/`
  - SF Symbols Katalog + Icon Picker (`IconCatalog.swift`, `IconPickerView.swift`).

- `BrainMesh/ImportProgress/`
  - Wiederverwendbare Fortschrittsanzeige für Imports (`ImportProgressState.swift`, `ImportProgressCard.swift`).

- `BrainMesh/Mainscreen/`
  - Home + Detail Screens, Link-Flows, NodePicker etc.
  - Unterordner:
    - `EntityDetail/` und `AttributeDetail/`: Screen-spezifische Extensions.
    - `NodeDetailShared/`: geteilte Cards/Sheets/Media/Connections.

- `BrainMesh/Observability/`
  - Micro Logging + Timing (`BMObservability.swift`).

- `BrainMesh/Onboarding/`
  - Onboarding UI + Coordinator (`OnboardingCoordinator.swift`, `OnboardingSheetView.swift`).

- `BrainMesh/PhotoGallery/`
  - Galerie UI (Grid, Browser, Viewer) + Import/Selection.

- `BrainMesh/Security/`
  - Graph Lock/Unlock + Crypto (`GraphLockCoordinator.swift`, `GraphUnlockView.swift`, `GraphLockCrypto.swift`).

- `BrainMesh/Settings/`
  - Settings UI und Hilfsviews (`SettingsView.swift`, etc.).

- `BrainMesh/Support/`
  - Systemmodal-Tracking (`SystemModalCoordinator.swift`).

- Root-Dateien im Target:
  - `BrainMesh/BrainMeshApp.swift` (App entry, SwiftData container, loader DI)
  - `BrainMesh/AppRootView.swift` (ScenePhase/Lock/Onboarding Gate)
  - `BrainMesh/ContentView.swift` (TabView)
  - `BrainMesh/Models.swift` (Model Map)
  - `BrainMesh/GraphSession.swift` (Active graph session)
  - `BrainMesh/GraphBootstrap.swift` (Legacy graphID bootstrap/migration)
  - `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`

---

## Data Model Map (Entities, Relationships, wichtige Felder)

### MetaGraph (`BrainMesh/Models.swift`)
- `id: UUID` (`@Attribute(.unique)`) — Primär-ID
- `name: String`
- `createdAt: Date`
- Security:
  - `isProtected: Bool`
  - `lockPasswordEnabled: Bool`, `lockBiometricsEnabled: Bool`
  - `passwordSaltB64`, `passwordHashB64`, `passwordIterations` (Passwort-KDF)

### MetaEntity (`BrainMesh/Models.swift`)
- `id: UUID` (`@Attribute(.unique)`)
- `graphID: UUID?` — Scope (Legacy kann `nil` sein; siehe `GraphBootstrap.swift`)
- `name`, `nameFolded` (Such-normalisiert; Updates in `didSet`)
- `notes: String`
- Header-Bild:
  - `imageData: Data?` (`@Attribute(.externalStorage)`, synced)
  - `imagePath: String?` (lokaler Cachepfad)
- `iconSymbolName: String?`
- Relationship:
  - `attributesList: [MetaAttribute]` (inverse: `MetaAttribute.owner`)

### MetaAttribute (`BrainMesh/Models.swift`)
- `id: UUID` (`@Attribute(.unique)`)
- `graphID: UUID?`
- `owner: MetaEntity?` (Relationship)
- `name`, `value`, `notes`
- Search:
  - `nameFolded`, `searchLabelFolded` (kombiniert aus Entity/Attribute; Updates in `didSet`)
- Header-Bild:
  - `imageData: Data?` (`@Attribute(.externalStorage)`)
  - `imagePath: String?`
- `iconSymbolName: String?`
- Computed:
  - `displayName` / `searchLabel` (UI)

### MetaLink (`BrainMesh/Models.swift`)
- `id: UUID` (`@Attribute(.unique)`)
- `graphID: UUID?`
- Source:
  - `sourceKindRaw: Int` (NodeKind)
  - `sourceID: UUID`
  - `sourceLabel: String`
- Target:
  - `targetKindRaw: Int`
  - `targetID: UUID`
  - `targetLabel: String`
- `note: String?`
- `createdAt: Date`

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- `id: UUID` (`@Attribute(.unique)`)
- `graphID: UUID?`
- Owner (keine Relationship):
  - `ownerKindRaw: Int` (NodeKind)
  - `ownerID: UUID`
- Content:
  - `contentKindRaw: Int` (AttachmentContentKind: file/video/galleryImage)
  - `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`
  - `byteCount: Int`
  - `fileData: Data?` (`@Attribute(.externalStorage)`) — kann sehr groß sein
- Cache:
  - `localPath: String?` (Dateiname in Application Support)

---

## Sync / Storage

### SwiftData + CloudKit
- Container/Schema:
  - `BrainMesh/BrainMeshApp.swift` erstellt `Schema([MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment])`.
  - CloudKit: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`.
- Fallback:
  - In **DEBUG**: `fatalError` wenn Container nicht erstellt werden kann.
  - In **Release**: fallback auf `ModelConfiguration(schema: schema)` (local-only). Siehe `BrainMesh/BrainMeshApp.swift`.

### Entitlements / Permissions
- iCloud/CloudKit Entitlements: `BrainMesh/BrainMesh.entitlements` (iCloud containers + CloudKit).
- Background Mode: `UIBackgroundModes` enthält `remote-notification` (`BrainMesh/Info.plist`).
- Photos/FaceID Usage:
  - `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSFaceIDUsageDescription` (`BrainMesh/Info.plist`).

### Disk Caches
- Header-Bilder Cache
  - Pfadlogik: `BrainMesh/ImageStore.swift` (`Application Support/BrainMeshImages/<uuid>.jpg`).
  - Hydration: `BrainMesh/ImageHydrator.swift` (scannt Modelle, schreibt fehlende Cache-Dateien aus `imageData`).
- Attachment Cache
  - Dateiablage: `BrainMesh/Attachments/AttachmentStore.swift` (`Application Support/BrainMeshAttachments/<attachmentID>.<ext>`).
  - Progressive Hydration (throttled): `BrainMesh/Attachments/AttachmentHydrator.swift` (`AsyncLimiter(maxConcurrent: 2)`; dedupe per attachmentID).
  - Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (+ Disk Cache + limiter).

### Migration / Legacy Handling
- GraphID Bootstrap (Entities/Attributes/Links): `BrainMesh/GraphBootstrap.swift`.
- Attachment graphID Migration (vermeidet OR-Predicate / in-memory filtering): `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` und Nutzung in `BrainMesh/Attachments/MediaAllLoader.swift`.

### Offline-Verhalten
- Lokale SwiftData DB ist immer verfügbar.
- CloudKit Sync läuft asynchron; Conflict Resolution/Merge Policy ist **UNKNOWN** (SwiftData intern, nicht explizit konfiguriert in `BrainMesh/BrainMeshApp.swift`).

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)

### Root
- `BrainMesh/AppRootView.swift`
  - Hostet `ContentView`.
  - Reagiert auf `scenePhase`:
    - `.active`: `handleBecameActive()` (z.B. Auto-Hydration) + Lock enforcement.
    - `.background`: debounced Auto-Lock (`scheduleDebouncedBackgroundLock()`), explizit um FaceID/Photos Hidden Album Flaps abzufangen.
  - Sheets:
    - Onboarding: `OnboardingSheetView` (`BrainMesh/Onboarding/OnboardingSheetView.swift`)
    - Unlock: `GraphUnlockView` als `fullScreenCover(item:)` (`BrainMesh/Security/GraphUnlockView.swift`)

### Tabs
- `BrainMesh/ContentView.swift`
  - Tab 1: **Entitäten** → `EntitiesHomeView` (`BrainMesh/Mainscreen/EntitiesHomeView.swift`)
  - Tab 2: **Graph** → `GraphCanvasScreen` (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift`)
  - Tab 3: **Stats** → `GraphStatsView` (`BrainMesh/Stats/GraphStatsView.swift` + Extensions)

### Entities Flow
- Home: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - NavigationStack
  - Search → debounced `.task(id:)` + off-main `EntitiesHomeLoader.shared.loadSnapshot(...)`.
  - Sheets:
    - Add Entity: `AddEntityView` (`BrainMesh/Mainscreen/AddEntityView.swift`)
    - Graph Picker: `GraphPickerSheet` (`BrainMesh/GraphPickerSheet.swift`)
    - Settings: `SettingsView` (`BrainMesh/Settings/SettingsView.swift`)

- Entity Detail:
  - Route: `EntityDetailRouteView` (`BrainMesh/Mainscreen/EntityDetail/EntityDetailRouteView.swift`)
  - Screen: `EntityDetailView` (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`)
  - Gemeinsame Cards/Sections: `BrainMesh/Mainscreen/NodeDetailShared/*`

- Attribute Detail:
  - Route: `AttributeDetailRouteView` (`BrainMesh/Mainscreen/AttributeDetail/AttributeDetailRouteView.swift`)
  - Screen: `AttributeDetailView` (`BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`)

### Graph Canvas
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ Extensions)
  - Daten laden off-main: `GraphCanvasDataLoader.shared.loadSnapshot(...)` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`).
  - Rendering: `GraphCanvasView+Rendering.swift`.
  - Physics: `GraphCanvasView+Physics.swift` (30 FPS Timer + Sleep when idle).

### Media
- Galerie (Grid/Browser/Viewer): `BrainMesh/PhotoGallery/*`.
- Attachment UI + Preview: `BrainMesh/Attachments/*`.
- „Alle“-Listen für Medien/Anhänge (paged, off-main): `BrainMesh/Attachments/MediaAllLoader.swift` + UI in `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`.

### Security / Graph Lock
- Lock coordinator: `BrainMesh/Security/GraphLockCoordinator.swift`
- Unlock UI: `BrainMesh/Security/GraphUnlockView.swift`
- Lock settings sheet: `BrainMesh/Security/GraphSecuritySheet.swift`
- Wichtig: System modal suppression via `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`) wird in Pickern gesetzt (z.B. `BrainMesh/NotesAndPhotoSection.swift`).

---

## Build & Configuration

### Targets
- App Target: **BrainMesh**
- Test Targets: `BrainMeshTests`, `BrainMeshUITests` (Templates, kaum Inhalt) — siehe `BrainMeshTests/BrainMeshTests.swift` und `BrainMeshUITests/*`.

### Dependencies
- SwiftData (Apple) + CloudKit via SwiftData config.
- Keine externen SPM Dependencies im Repo gefunden (**UNKNOWN** ob lokal via Xcode hinzugefügt, aber nicht in ZIP enthalten).

### Secrets Handling
- Keine `.xcconfig` / Secrets-Dateien gefunden. CloudKit container IDs kommen über Entitlements (`BrainMesh/BrainMesh.entitlements`).

### Entitlements / Capabilities
- iCloud + CloudKit: `BrainMesh/BrainMesh.entitlements`.
- Background mode remote notifications: `BrainMesh/Info.plist` (`UIBackgroundModes`).

---

## Conventions (Naming, Patterns, Do/Don’t)

### Pattern: Off-main Loader + Snapshot
- **Do**: UI ruft Loader in `.task {}` und committed Snapshot in `@State`.
  - Beispiel: `EntitiesHomeView.reload(...)` → `EntitiesHomeLoader.loadSnapshot(...)` (`BrainMesh/Mainscreen/EntitiesHomeView.swift`, `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`).
- **Don’t**: `@Query` auf riesige Tabellen in Hot Paths (Home/Search, Canvas, „Alle“-Listen).

### Pattern: Keine `@Model` über Concurrency Grenzen
- Loader geben DTOs zurück (z.B. `EntitiesHomeRow`, `LinkRowDTO`, `NodePickerRowDTO`).
- UI navigiert über IDs und resolved mit Main-Context.

### Predicate Hygiene
- SwiftData kann bei "komplexen" Predicates in in-memory filtering fallen.
  - Im Projekt wird das explizit vermieden in `BrainMesh/Attachments/MediaAllLoader.swift` (nur AND-Predicates, plus Migration via `AttachmentGraphIDMigration`).
  - An anderen Stellen existieren noch OR-Predicates (z.B. `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`, `BrainMesh/Mainscreen/NodePickerLoader.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`).

### File/Type Organization
- Große Screens werden per Extensions/Split-Dateien modularisiert.
  - Beispiele: `GraphCanvasScreen+*.swift`, `GraphStatsView+*.swift`, `NodeDetailShared+*.swift`.

---

## How to work on this project (Setup + wo anfangen)

### Setup (neuer Dev)
1. Xcode öffnen: `BrainMesh.xcodeproj`.
2. Team/Signing korrekt setzen (iCloud Capabilities benötigen gültige Team-ID).
3. Auf einem Gerät/Simulator mit iOS 26+ starten.
4. Für CloudKit-Sync: iCloud Account am Gerät aktiv + iCloud Drive an.
   - Achtung: In DEBUG crasht die App hart, wenn `ModelContainer` nicht erstellt werden kann (`BrainMesh/BrainMeshApp.swift`).

### Wo anfangen, wenn du ein Feature baust
- UI/Flows: `BrainMesh/ContentView.swift` (Tab routing) und jeweiliger Feature-Ordner.
- Neue Datenabrufe für große Listen:
  - Loader Pattern kopieren (Actor + `Task.detached` + eigener `ModelContext`).
  - Loader in `BrainMesh/BrainMeshApp.swift` via `configure(container:)` registrieren.
- Model Änderungen:
  - Core Models: `BrainMesh/Models.swift`
  - Attachments: `BrainMesh/Attachments/MetaAttachment.swift`
  - Migration/Bootstrap ggf. ergänzen: `BrainMesh/GraphBootstrap.swift` / `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`

### Debug/Profiling Quick Checklist
- UI Freeze?
  - Instruments → Main Thread, SwiftData fetches, predicate translation.
  - Log Kategorien: `BMLog.load`, `BMLog.physics` (`BrainMesh/Observability/BMObservability.swift`).
- „System Picker bricht ab“ (Photos/Hidden Album):
  - Prüfe `systemModals.beginSystemModal/endSystemModal` Aufrufe im jeweiligen Picker host.
  - Siehe Debounce-Lock in `BrainMesh/AppRootView.swift`.

---

## Quick Wins (max. 10, konkret)

1. **GraphID Legacy endgültig beseitigen**
   - Ziel: OR-Predicates (`graphID == gid || graphID == nil`) loswerden.
   - Kandidaten: `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`, `BrainMesh/Mainscreen/NodePickerLoader.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`.

2. **BFS Predicate Translation absichern**
   - `frontierIDs.contains(...)` in `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` kann store-untranslatable sein → in-memory filtering Risiko (**UNKNOWN** bis Profiling).

3. **GraphStatsService splitten**
   - `BrainMesh/Stats/GraphStatsService.swift` (694 Zeilen) in `+Counts`, `+Media`, `+Trends`, `+Structure` teilen.

4. **NodeDetail Sheets entflechten**
   - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` (689 Zeilen) reduzieren; Sheet-States in kleinere „Coordinator“ structs ziehen.

5. **Attachment Deletion zentralisieren**
   - Heute: mehrfach manuelle Cleanup Calls (z.B. `EntitiesHomeView.deleteEntities`).
   - Vorschlag: Service `AttachmentCleanup` überall nutzen + „delete node“ helper.

6. **Persistente „Counts Cache“ Option**
   - Für Stats: optional „last computed“ Snapshot in SwiftData/Defaults speichern; UI zeigt sofort letzte Werte.

7. **Mehr systematische Logging Gates**
   - `BMLog` Kategorien erweitern (z.B. `stats`, `attachments`) + Sampling, um Debug besser zu steuern.

8. **Test-Harness für Predicates**
   - Minimaler Performance-Test, der große DB + typische Queries triggert (Target `BrainMeshTests`).

9. **Einheitliche Graph-Scope Helper**
   - Eine zentrale Funktion „graphPredicate(for gid)“ pro Model (ähnlich `GraphStatsService`), damit weniger Copy/Paste.

10. **Doc: Daten-Limits dokumentieren**
   - Es gibt `maxBytes = 25MB` in Detail Views (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`) — harte Grenze in einem Ort zentralisieren.

---

## Open Questions (UNKNOWN)

- CloudKit Conflict Resolution / Merge Policy: **UNKNOWN** (nicht explizit konfiguriert; SwiftData intern).
- CloudKit Schema (Record Types, Zones): **UNKNOWN** (SwiftData managed, nicht im Repo definiert).
- Exakte iPad/Mac Support Matrix: **UNKNOWN** (nur iOS Target sichtbar im pbxproj; keine separate macOS target section im ZIP geprüft).
