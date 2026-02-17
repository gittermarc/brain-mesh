# BrainMesh — PROJECT_CONTEXT (Start Here)

## TL;DR
BrainMesh ist eine SwiftUI-App für iOS/iPadOS, um **Wissensgraphen** („Graphen“) aus **Entitäten** und **Attributen** aufzubauen, per **Links** zu verbinden und optional mit **Medien/Anhängen** zu ergänzen. Persistenz läuft über **SwiftData** mit **CloudKit Sync** via `ModelConfiguration(..., cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`. Mindest-OS: **iOS/iPadOS 26.0** (Xcode-Projektsetting).

---

## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph)**: Container/Scope. Aktiver Graph in `@AppStorage("BMActiveGraphID")`.
  - Dateien: `BrainMesh/Models.swift`, `BrainMesh/GraphSession.swift`, `BrainMesh/GraphPickerSheet.swift`
- **Entität (MetaEntity)**: Haupt-„Node“-Typ (Name, Notizen, optionales Bild/Icon). Scope über `graphID` (optional).
  - Datei: `BrainMesh/Models.swift`
- **Attribut (MetaAttribute)**: Sekundärer Node-Typ; gehört zu einer Entität via SwiftData-Relationship.
  - Datei: `BrainMesh/Models.swift`
- **Link (MetaLink)**: Verbindung zwischen Nodes. **Nicht als SwiftData-Relationships modelliert**, sondern als `sourceID/targetID` plus `sourceKindRaw/targetKindRaw`.
  - Datei: `BrainMesh/Models.swift`
- **Anhang (MetaAttachment)**: Datei/Video/Galerie-Bild an einem Node (`ownerKindRaw + ownerID`). Schwere Nutzlast in `fileData` als `@Attribute(.externalStorage)`.
  - Datei: `BrainMesh/Attachments/MetaAttachment.swift`
- **Hydration**: Aufbau **lokaler Disk-Caches** aus den (synchronisierten) SwiftData-`Data`-Feldern.
  - Bilder: `BrainMesh/ImageHydrator.swift`, `BrainMesh/ImageStore.swift`
  - Anhänge: `BrainMesh/Attachments/AttachmentHydrator.swift`, `BrainMesh/Attachments/AttachmentStore.swift`
- **System-Modal-Guard**: Verhindert Auto-Lock/Unlock-„Loop“ mit Photos Hidden Album + Face ID.
  - Datei: `BrainMesh/Support/SystemModalCoordinator.swift`, genutzt in `BrainMesh/AppRootView.swift`
- **Graph Lock**: Pro-Graph Schutz (Biometrie und/oder Passwort); Enforcement u.a. bei App-Backgrounding.
  - Dateien: `BrainMesh/Security/GraphLockCoordinator.swift`, `BrainMesh/Security/GraphUnlockView.swift`, `BrainMesh/AppRootView.swift`

---

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhängigkeiten)

- **App Entry & Composition**
  - `BrainMesh/BrainMeshApp.swift` erzeugt `ModelContainer` (CloudKit automatic) und injiziert EnvironmentObjects.
  - `BrainMesh/AppRootView.swift` orchestriert Startup (Bootstrap, Lock-Enforcement, Cache-Hydration) + `scenePhase` Handling.
  - `BrainMesh/ContentView.swift` ist der **Tab-Root** (Home / Graph / Stats).

- **UI Feature-Module**
  - **Home / CRUD**: `BrainMesh/Mainscreen/*` (Entitäten, Attribute, Links, Detail-Screens).
  - **Graph Canvas**: `BrainMesh/GraphCanvas/*` (Rendering + Physik + Loader + Inspector).
  - **Fotos / Galerie**: `BrainMesh/PhotoGallery/*` + Shared Media-Bausteine in `BrainMesh/Mainscreen/NodeDetailShared/*`.
  - **Graph Picker / Multi-Graph**: `BrainMesh/GraphPicker/*` + `BrainMesh/GraphPickerSheet.swift`.
  - **Stats**: `BrainMesh/Stats/*` (Loader + Service + Dashboard UI).
  - **Settings**: `BrainMesh/Settings/*` (Wartung/Cache + Darstellung).
  - **Security**: `BrainMesh/Security/*` (Lock/Unlock + Crypto).

- **Daten & Sync**
  - SwiftData-Modelle: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
  - CloudKit: konfiguriert über `ModelConfiguration(..., cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
  - Legacy-Migration in Default-Graph: `BrainMesh/GraphBootstrap.swift` (+ Attachments: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).

- **Off-Main Loader / Background Work**
  - Canvas-Snapshot-Laden: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (actor + `Task.detached` + neuer `ModelContext`).
  - Stats-Snapshot-Laden: `BrainMesh/Stats/GraphStatsLoader.swift` (actor + detached work).
  - “Alle Medien” Laden: `BrainMesh/Attachments/MediaAllLoader.swift` (actor + detached work).
  - Attachment-Hydration (Disk-Cache): `BrainMesh/Attachments/AttachmentHydrator.swift` (actor + Concurrency-Limiter).
  - Image-Disk-Cache: `BrainMesh/ImageHydrator.swift` (getriggert in `AppRootView`).

---

## Folder Map (Ordner → Zweck)
Projekt-Top-Level:
- `BrainMesh/` — App-Target Sources (SwiftUI + SwiftData).
- `BrainMesh.xcodeproj/` — Xcode-Projekt-Konfiguration.
- `BrainMeshTests/`, `BrainMeshUITests/` — Test-Targets (aktuell sehr klein).

Innerhalb `BrainMesh/`:
- `Appearance/` — `AppearanceStore` + Display-Konfiguration/Presets.
- `Attachments/` — Attachment-Modell (`MetaAttachment`), Disk-Cache, Hydration, “Alle Medien”, Import-Helpers.
- `GraphCanvas/` — Interaktiver Graph-Canvas (Render + Physik) + Snapshot-Loader.
- `GraphPicker/` — Graph-Auswahl und -Management (Create/Rename/Delete/Lock-Settings).
- `Icons/` — SF Symbols Katalog/Icon Picker Utilities (Prewarm in `AppRootView`).
- `Images/` — Image Picking/Import (PhotosPicker, Resize, etc.).
- `ImportProgress/` — Progress UI/State für lange Imports.
- `Mainscreen/` — Home-Tab + Entity/Attribute Detail-Flows + Shared NodeDetail-Sections.
- `Observability/` — Logging/Timing Helpers (`BMLog`, `BMDuration`).
- `Onboarding/` — Onboarding UI + Fortschrittsberechnung.
- `PhotoGallery/` — Reusable Gallery/Browser Views.
- `Security/` — Graph Lock/Unlock + Passwort-Hashing.
- `Settings/` — Settings UI + Cache-Wartung.
- `Support/` — App-weite Helper (`SystemModalCoordinator`).

---

## Data Model Map (Entities, Relationships, wichtige Felder)

### MetaGraph (`BrainMesh/Models.swift`)
- `id: UUID`
- `name: String`
- `createdAt: Date`
- Schutz:
  - `isProtected: Bool`
  - Biometrics-Flags (`lockBiometricsEnabled`, etc.)
  - Passwort: `passwordSaltB64`, `passwordHashB64`, `passwordIterations`, `isPasswordConfigured`

### MetaEntity (`BrainMesh/Models.swift`)
- `id: UUID`
- `name: String`
- `nameFolded: String` (normalisiert für Suche)
- `createdAt: Date`
- `notes: String`
- `graphID: UUID?` (nil = legacy/global)
- Darstellung:
  - `iconSymbolName: String?`
  - `imagePath: String?` (lokaler Cache-Pfad, nicht authoritative)
  - `imageData: Data?` (authoritative, synced; Storage-Details **UNKNOWN**)
- Relationship:
  - `attributes: [MetaAttribute]` (inverse: `MetaAttribute.owner`)

### MetaAttribute (`BrainMesh/Models.swift`)
- `id: UUID`
- `name: String`
- `nameFolded: String`
- `createdAt: Date`
- `notes: String`
- `graphID: UUID?`
- Darstellung:
  - `iconSymbolName: String?`
  - `imagePath: String?`
  - `imageData: Data?` (Storage-Details **UNKNOWN**)
- Relationship:
  - `owner: MetaEntity?` (inverse: `MetaEntity.attributes`)

### MetaLink (`BrainMesh/Models.swift`)
- `id: UUID`
- `createdAt: Date`
- `graphID: UUID?`
- Source/Target sind **IDs + Kinds**, keine Relationships:
  - `sourceKindRaw: String`, `sourceID: UUID`
  - `targetKindRaw: String`, `targetID: UUID`
- `label: String?`
- `note: String?`

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- `id: UUID`
- `createdAt: Date`
- `graphID: UUID?` (Migration existiert)
- Ownership:
  - `ownerKindRaw: String` (`entity` / `attribute`)
  - `ownerID: UUID`
- Content:
  - `contentKindRaw: String` (`file` / `video` / `galleryImage`)
  - `title: String`
  - `originalFilename: String?`
  - `contentTypeIdentifier: String?`
  - `fileExtension: String?`
  - `byteCount: Int`
- Storage/Caching:
  - `localPath: String?` (Disk-Cache für Preview/Open)
  - `fileData: Data?` (`@Attribute(.externalStorage)`; authoritative, synced)
  - `previewImageData: Data?` (Thumbnail/Preview)

---

## Sync/Storage
- **Primary Store**: SwiftData + CloudKit automatic (`BrainMesh/BrainMeshApp.swift`).
  - CloudKit Container aus Entitlements: `BrainMesh/BrainMesh.entitlements` (`iCloud.de.marcfechner.BrainMesh`).
- **Lokale Caches (nicht authoritative)**:
  - Image Disk-Cache: `BrainMesh/ImageStore.swift` (via `ImageHydrator`).
  - Attachment Disk-Cache: `BrainMesh/Attachments/AttachmentStore.swift` (via `AttachmentHydrator` + UI).
- **Migration / Legacy**
  - Default-Graph erstellen + Legacy `graphID == nil` in Default-Graph migrieren:
    - `BrainMesh/GraphBootstrap.swift`
  - Attachment `graphID` Migration (Performance-Guard):
    - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- **Offline-Verhalten**: **UNKNOWN** (nicht explizit im Code modelliert). Erwartung: SwiftData persistiert lokal und sync’t später, aber Konflikt-/Merge-Details sind hier nicht definiert.

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)

### Root + Tabs
- Entry: `BrainMesh/BrainMeshApp.swift` → `BrainMesh/AppRootView.swift`
- Tabs: `BrainMesh/ContentView.swift`
  - **Home**: `BrainMesh/Mainscreen/EntitiesHomeView.swift` (NavigationStack)
  - **Graph**: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (NavigationStack)
  - **Stats**: `BrainMesh/Stats/GraphStatsView.swift` (NavigationStack)

### Wichtige Flows (Auswahl)
- Graph wählen/verwalten:
  - Sheet: `BrainMesh/GraphPickerSheet.swift`
  - UI: `BrainMesh/GraphPicker/*`
- Entity/Attribute Details:
  - Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (+ Splits)
  - Attribute: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` (+ Splits)
  - Shared: `BrainMesh/Mainscreen/NodeDetailShared/*`
- Medien/Anhänge:
  - Galerie: `BrainMesh/PhotoGallery/*`
  - Bilder verwalten: `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - Anhänge verwalten: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` (`NodeAttachmentsManageView`)
  - “Alle Medien”: `BrainMesh/Attachments/MediaAllView.swift` + `BrainMesh/Attachments/MediaAllLoader.swift`
- Security/Lock:
  - Coordinator: `BrainMesh/Security/GraphLockCoordinator.swift`
  - Unlock UI: `BrainMesh/Security/GraphUnlockView.swift` (fullScreenCover in `AppRootView`)
- Onboarding:
  - Sheet: `BrainMesh/Onboarding/OnboardingSheetView.swift` (über `AppRootView`)

---

## Build & Configuration
- Projekt: `BrainMesh.xcodeproj`
- Bundle ID:
  - App: `de.marcfechner.BrainMesh` (aus `BrainMesh.xcodeproj/project.pbxproj`)
- Mindest-OS: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (aus `BrainMesh.xcodeproj/project.pbxproj`)
- Devices: `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud CloudKit enabled
  - Container: `iCloud.de.marcfechner.BrainMesh`
  - APS env: `development` (für App Store später Production erforderlich)
- Info.plist: `BrainMesh/Info.plist`
  - `NSFaceIDUsageDescription`
  - `UIBackgroundModes` enthält `remote-notification`
- Dependencies:
  - Keine externen SPM-Packages gefunden (Imports sind Apple Frameworks).
- Secrets Handling:
  - Keine `.xcconfig` oder Secrets-Files im Archiv entdeckt (**UNKNOWN**, ob außerhalb des Repos existierend).

---

## Conventions (Naming, Patterns, Do/Don’t)
- Split-Pattern:
  - Große Views splitten als `Foo.swift` + `Foo+Section.swift` (z.B. `GraphCanvasScreen+*.swift`, `EntityDetailView+*.swift`).
- Sichtbarkeit:
  - State, der in Extensions genutzt wird, **nicht `private`** setzen (siehe Kommentare z.B. in `GraphStatsView.swift` / `GraphCanvas`).
- „Keine schweren Fetches im Render-Pfad“:
  - Loader-Pattern nutzen (`GraphCanvasDataLoader`, `GraphStatsLoader`, `MediaAllLoader`) und UI-State einmalig committen.
- SwiftData Predicates:
  - Vorsicht bei Predicates, die In-Memory-Fallback auslösen, besonders mit großen `Data` / `.externalStorage`.
  - Konkretes Beispiel/Begründung: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
- Concurrency:
  - Heavy SwiftData Work in `Task.detached` mit frischem `ModelContext` und `autosaveEnabled = false`.

---

## How to work on this project (Setup Steps + wo anfangen)
1. `BrainMesh.xcodeproj` in Xcode 26 öffnen.
2. Signing & Capabilities:
   - Team + Bundle ID `de.marcfechner.BrainMesh`.
   - iCloud/CloudKit aktivieren und Container `iCloud.de.marcfechner.BrainMesh` sicherstellen.
3. Auf iOS 26+ Simulator/Device starten.
4. First Run:
   - `GraphBootstrap.ensureAtLeastOneGraph(...)` erstellt Default-Graph, falls keiner existiert (`BrainMesh/GraphBootstrap.swift`).
   - Ist der aktive Graph geschützt, erscheint Unlock Flow (`BrainMesh/Security/GraphUnlockView.swift`).
5. Performance Debug:
   - `BMLog` Kategorien (`BrainMesh/Observability/BMObservability.swift`) + Physics Logs im Canvas.

Wo anfangen (neuer Dev):
- Modelle verstehen: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`.
- Startup/Lock verstehen: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`.
- Loader/Hydrator verstehen: `GraphCanvasDataLoader`, `GraphStatsLoader`, `MediaAllLoader`, `AttachmentHydrator`.

---

## Quick Wins (max 10, konkret)
1. **`graphID == nil` bei Entities/Attributes/Links migrieren** (analog Attachments), um `gid == nil || ...` Predicates zu reduzieren:
   - Touchpoints: `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Mainscreen/EntitiesHomeView.swift`, `BrainMesh/Mainscreen/NodePickerView.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Stats/GraphStatsService.swift`.
2. Loader-Phasen mit `BMDuration` + `BMLog` messen (Fetch/Map/Postprocess):
   - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/Attachments/MediaAllLoader.swift`.
3. Cancellation konsequent prüfen (auch mitten in großen Loops):
   - `GraphCanvasDataLoader.swift`, `GraphStatsService.swift`, `MediaAllLoader.swift`.
4. Home-Search/Fetchen off-main (Loader wie Stats/Canvas):
   - `BrainMesh/Mainscreen/EntitiesHomeView.swift`.
5. GraphCanvas Limits/Presets als UI-Option anbieten („Smooth“ vs „Large graphs“):
   - `BrainMesh/GraphCanvas/GraphCanvasScreen+Inspector.swift`.
6. Zentraler „Graph Scope“-Helper (statt Copy/Paste der Scoping-Logik):
   - Vorschlag: `BrainMesh/Support/GraphScope.swift`.
7. Attachment-Preview/Thumbnail Caching prüfen (falls Decoding bottleneck wird):
   - `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`.
8. ImageHydrator: nicht nur 24h, sondern auch „already hydrated“/Volumen beachten:
   - `BrainMesh/ImageHydrator.swift`.
9. SystemModalGuard: sicherstellen, dass jede Picker-Route begin/end korrekt setzt:
   - `BrainMesh/Images/*`, `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media*.swift`.
10. Kleine DI-Struktur (nur wenn Testbarkeit wichtiger wird):
   - Start: Loader/Hydrator in `BrainMesh/BrainMeshApp.swift` / `BrainMesh/AppRootView.swift`.

