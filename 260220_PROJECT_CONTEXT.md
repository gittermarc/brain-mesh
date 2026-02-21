# PROJECT_CONTEXT.md — BrainMesh (Start Here)

## TL;DR
BrainMesh ist eine SwiftUI‑App für iOS (Deployment Target **iOS 26.0**) zum Aufbau von Wissens‑Graphen: **Graphen** enthalten **Entitäten**, **Attribute**, **Links** und **Medien/Anhänge**. Persistenz läuft über **SwiftData** mit **CloudKit Sync** (Private DB, `.automatic`) und lokalen Disk‑Caches für Bilder/Anhänge.

---

## Key Concepts / Domänenbegriffe

- **MetaGraph**: „Workspace“/Kontext für Daten (Multi‑Graph). Sicherheitsoptionen pro Graph (Biometrie/Passwort).  
  Datei: `BrainMesh/Models.swift` (Model) + Graph‑Switching via `@AppStorage("BMActiveGraphID")`.
- **MetaEntity**: Knoten‑Typ „Entität“ (Name, Notizen, Icon, optional Bild).  
  Beziehung: Entität → Attribute, Entität → Detail‑Feld‑Definitionen.
- **MetaAttribute**: Knoten‑Typ „Attribut“ (Name, Notizen, Icon, optional Bild), gehört optional zu einer Entität (`owner`).
- **MetaLink**: Kante zwischen zwei Nodes (Quelle/Ziel als `(kind, id)` + denormalisierte Labels für schnelles Rendering).  
  Datei: `BrainMesh/Models.swift`, Relabeling: `BrainMesh/Mainscreen/LinkCleanup.swift`.
- **Details (Custom Fields)**: Frei konfigurierbare Felder pro Entität (Schema) + Werte pro Attribut.  
  Definition: `MetaDetailFieldDefinition` (Schema)  
  Value: `MetaDetailFieldValue` (typed storage)
- **Attachments**: Dateien/Videos/Gallery‑Bilder an Entitäten/Attribute (nicht als SwiftData‑Relationship, sondern `(ownerKindRaw, ownerID)`).  
  Model: `BrainMesh/Attachments/MetaAttachment.swift`  
  Disk‑Cache: `BrainMesh/Attachments/AttachmentStore.swift`
- **Hydration**: Hintergrundjobs, die SwiftData‑Daten in lokale Cache‑Files „materialisieren“ (Bilder/Anhänge), um UI‑Stalls zu vermeiden.  
  Beispiele: `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`

---

## Architecture Map (Layer/Module → Verantwortung → Abhängigkeiten)

**1) UI (SwiftUI Views)**  
- Root Tabs: `BrainMesh/ContentView.swift`  
- Screens: `BrainMesh/Mainscreen/**`, `BrainMesh/GraphCanvas/**`, `BrainMesh/Stats/**`, `BrainMesh/Settings/**`  
- Navigation: `NavigationStack` in einzelnen Tabs/Screens, Sheets/Full‑Screen‑Covers via Coordinators.

⬇️ nutzt

**2) Coordinators / Stores (ObservableObject + AppStorage)**  
- Appearance/Theme: `BrainMesh/Settings/Appearance/AppearanceStore.swift` (+ `AppearanceSettings` Datenstrukturen)  
- Display/Layouts: `BrainMesh/Settings/Display/DisplaySettingsStore.swift` (+ DisplaySettings Views)  
- Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift`  
- Graph Lock: `BrainMesh/Security/GraphLockCoordinator.swift`  
- System Modal Tracking (Photos Picker etc.): `BrainMesh/Support/SystemModalCoordinator.swift`  
- Sync Diagnostics: `BrainMesh/Settings/SyncRuntime.swift`

⬇️ nutzt

**3) Loaders/Hydrators (Actors + background ModelContext, value-only Snapshots)**  
Ziel: **keine SwiftData Fetches im Render‑Pfad** + kontrollierte Concurrency.  
- Entities Home: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` → `EntitiesHomeSnapshot`/`EntitiesHomeRow`  
- Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`  
- Stats: `BrainMesh/Stats/GraphStatsLoader.swift` + `BrainMesh/Stats/GraphStatsService/*`  
- Node Pickers / Connections / Media „Alle“:  
  - `BrainMesh/Mainscreen/NodeDetailShared/NodePickerLoader.swift`  
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`  
  - `BrainMesh/Attachments/MediaAllLoader.swift`  
- Caches/Hydration:  
  - Images: `BrainMesh/ImageStore.swift` (Disk+Mem) + `BrainMesh/ImageHydrator.swift` (SwiftData→Disk)  
  - Attachments: `BrainMesh/Attachments/AttachmentStore.swift` + `BrainMesh/Attachments/AttachmentHydrator.swift`  
  - Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (inkl. `AsyncLimiter`)

⬇️ nutzt

**4) Persistence / Sync (SwiftData + CloudKit)**  
- `BrainMesh/BrainMeshApp.swift`: `ModelContainer` + Schema + CloudKit config, Hintergrund‑Konfiguration der Loader/Hydrators  
- Models: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`

⬇️ nutzt

**5) System Frameworks**  
SwiftUI, SwiftData, CloudKit, LocalAuthentication, UIKit bridging, Photos picker, AVFoundation (Video), UniformTypeIdentifiers, os.log.

---

## Folder Map (Ordner → Zweck)

> Pfade sind relativ zum Target‑Ordner **`BrainMesh/`**.

- `BrainMesh/Attachments/`  
  Attachment Model + Storage/Cache + Hydrators + UI für Anhänge/Media.
- `BrainMesh/GraphCanvas/`  
  Graph‑Canvas Screen, Rendering (GraphicsContext), Physics/Interaction, DataLoader.
- `BrainMesh/GraphPicker/`  
  Graph Auswahl/Wechsel UI.
- `BrainMesh/ImportProgress/`  
  UI für Import/Progress (z.B. Video‑Import, Kompression). **UNKNOWN:** Ob alle Flows konsistent darüber laufen.
- `BrainMesh/Mainscreen/`  
  Hauptfeatures (Entities Home, Entity/Attribute Detail, Details‑Schema, Shared Node‑Detail Komponenten).
- `BrainMesh/Observability/`  
  Leichte Logging/Timing‑Helper (`BMObservability.swift`).
- `BrainMesh/Onboarding/`  
  Onboarding UI + Progress/Coordinator.
- `BrainMesh/PhotoGallery/`  
  Gallery Browser/Viewer für Bilder (Entity/Attribute).
- `BrainMesh/Security/`  
  Graph Lock (Biometrics/Passwort), Unlock UI, Crypto.
- `BrainMesh/Settings/`  
  Settings Screen, Sync Diagnostics, Maintenance (Cache clear/rebuild), Appearance/Display Subtrees.
- `BrainMesh/Stats/`  
  Stats Tab UI + Loader + Service (Counts/Structure/Media/Trends).
- `BrainMesh/Support/`  
  Querschnitt: SystemModalCoordinator, Support UI/Helpers.

---

## Data Model Map (SwiftData Models)

### MetaGraph (`@Model`)
Datei: `BrainMesh/Models.swift`
- `id: UUID`, `createdAt: Date`
- `name`, `nameFolded` (für Suche)
- Security Flags + Password Hash/Salt/Iterations (pro Graph)

### MetaEntity (`@Model`)
Datei: `BrainMesh/Models.swift`
- `id: UUID`, `createdAt: Date`
- `graphID: UUID?` (Multi‑Graph Scope, optional für Migration)
- `name`, `nameFolded`, `notes`
- `iconSymbolName: String?`
- `imageData: Data?` (CloudKit‑sync)
- `imagePath: String?` (lokaler Disk‑Cache Filename)
- Relationships:
  - `attributes: [MetaAttribute]?` (cascade, inverse: `MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (cascade, inverse: `MetaDetailFieldDefinition.owner`)

### MetaAttribute (`@Model`)
Datei: `BrainMesh/Models.swift`
- `id: UUID`, `graphID: UUID?`
- `name`, `nameFolded`, `notes`
- `owner: MetaEntity?` (keine inverse hier; Macro‑Zirkularität vermeiden)
- `iconSymbolName`, `imageData`, `imagePath`
- `searchLabelFolded` (enthält DisplayName `"{{entity}} · {{attribute}}"`, für Suche)
- Relationship:
  - `detailValues: [MetaDetailFieldValue]?` (cascade, inverse: `MetaDetailFieldValue.attribute`)

### MetaLink (`@Model`)
Datei: `BrainMesh/Models.swift`
- `id: UUID`, `createdAt: Date`, `note: String?`
- `graphID: UUID?`
- Denormalisierte Labels: `sourceLabel`, `targetLabel`
- Source/Target: `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`

### Detail Schema + Werte
Datei: `BrainMesh/Models.swift`
- `MetaDetailFieldDefinition`:
  - Scalars: `entityID`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Relationship: `owner: MetaEntity?` (originalName `"entity"`, deleteRule `.nullify`)
- `MetaDetailFieldValue`:
  - Scalars: `attributeID`, `fieldID`
  - Typed values: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - Reference: `attribute: MetaAttribute?`

### Attachments
Datei: `BrainMesh/Attachments/MetaAttachment.swift`
- Owner via Scalars: `ownerKindRaw`, `ownerID` (keine Relationship‑Macros)
- `contentKindRaw` (file / video / galleryImage)
- Metadata: Titel, Filename, UTI, Extension, ByteCount
- Bytes: `fileData` als `@Attribute(.externalStorage)` (CloudKit Asset‑Style)
- Local cache: `localPath`

---

## Sync/Storage (SwiftData / CloudKit / Caches)

### SwiftData + CloudKit
- Container Setup: `BrainMesh/BrainMeshApp.swift`
  - Schema: `{ MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment, MetaDetailFieldDefinition, MetaDetailFieldValue }`
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - DEBUG: CloudKit Container Init‑Failure → `fatalError` (kein Fallback)  
  - RELEASE: Fallback auf local‑only `ModelConfiguration(schema:)`, Tracking über `SyncRuntime`.
- iCloud Diagnostics: `BrainMesh/Settings/SyncRuntime.swift`
  - `CKContainer(identifier: "iCloud.de.marcfechner.BrainMesh").accountStatus()`
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud Service: CloudKit
  - APS env: `development`
- Info.plist: `BrainMesh/Info.plist`
  - `UIBackgroundModes`: `remote-notification` (CloudKit push / background sync hint)
  - `NSFaceIDUsageDescription` (Graph lock)

### Disk Caches
- Entity/Attribute Main Photo:
  - Disk: Application Support / `BrainMeshImages` (`BrainMesh/ImageStore.swift`)
  - Hydration: `BrainMesh/ImageHydrator.swift` (SwiftData `imageData` → deterministic `imagePath = "{{id}}.jpg"` + disk write)
- Attachments:
  - Disk: Application Support / `BrainMeshAttachments` (`BrainMesh/Attachments/AttachmentStore.swift`)
  - Hydration: `BrainMesh/Attachments/AttachmentHydrator.swift` (fetch `fileData` in background + write cache)
  - Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (throttled decode/cache)
- Cache Maintenance UI:
  - `BrainMesh/Settings/SettingsView.swift` (Rebuild Image Cache / Clear Attachment Cache)

### Migration / Legacy Handling
- Multi‑Graph Migration helper: `BrainMesh/GraphBootstrap.swift`
  - `graphID == nil` records werden in Default‑Graph verschoben (Entities/Attributes/Links)
  - `createdAt` default `.distantPast` bei einigen Models, um „neue“ Items nach Migration zu vermeiden.

---

## UI Map (Hauptscreens + Navigation)

### Entry Points
- `BrainMesh/BrainMeshApp.swift` → `AppRootView()`
- `BrainMesh/AppRootView.swift`
  - `ContentView()` als Root Tabs
  - Onboarding Sheet: `OnboardingSheetView` (`BrainMesh/Onboarding/OnboardingSheetView.swift`)
  - Graph Unlock FullScreenCover: `GraphUnlockView` (`BrainMesh/Security/GraphUnlockView.swift`)
  - Startup tasks: Bootstrapping Graph + (rare) auto Image Hydration + Lock Enforcement

### Tabs (`BrainMesh/ContentView.swift`)
1. **Entitäten** → `EntitiesHomeView` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
2. **Graph** → `GraphCanvasScreen` (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift`)
3. **Stats** → `GraphStatsView` (`BrainMesh/Stats/GraphStatsView.swift`)
4. **Einstellungen** → `NavigationStack {{ SettingsView }}` (`BrainMesh/Settings/SettingsView.swift`)

### Navigation / Sheets (Auswahl)
- Entities Home:
  - `NavigationLink` → `EntityDetailView` via `EntityDetailRouteView` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
  - Sheets: AddEntity, GraphPicker, Display Options
- Entity Detail:
  - Attribute → `AttributeDetailView` (`BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`)
  - Medien: Gallery Browser (`BrainMesh/PhotoGallery/*`), Attachments Manager (`BrainMesh/Attachments/*`)
  - Link creation/chooser, bulk link flows
- Graph Canvas:
  - GraphPicker sheet, Focus picker sheet, Inspector sheet (**UNKNOWN:** genauer Host/Datei, falls in Extensions ausgelagert)
  - Selection sheets: Entity/Attribute detail (via `selectedEntity/selectedAttribute`)
- Settings:
  - Details Intro sheet: `DetailsOnboardingSheetView` (`BrainMesh/Settings/SettingsView.swift`)

---

## Build & Configuration

- Xcode Project: `BrainMesh/BrainMesh.xcodeproj`
- Deployment Target: **iOS 26.0** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`)
- Swift Concurrency build settings:
  - `SWIFT_APPROACHABLE_CONCURRENCY = YES`
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  - `SWIFT_VERSION = 5.0` (Project setting; tatsächlicher Toolchain‑Swift ist durch Xcode 26 bestimmt)
- Dependencies:
  - Keine externen SPM Packages im Projektfile sichtbar. **UNKNOWN:** Ob lokale/privat eingebundene Dependencies außerhalb des Repos existieren.

---

## Conventions (Naming, Patterns, Do/Don’t)

### Patterns, die im Projekt „Standard“ sind
- **Graph Scope**: Alle graph‑scopeden Fetches filtern auf `graphID` (oder fallback `nil` für Legacy).
- **Folded Search Strings**: `BMSearch.fold(_:)` + gespeicherte `nameFolded`/`searchLabelFolded` Felder (kein folding im Renderpfad).
- **Value‑Snapshots für Background Loader**:
  - UI navigiert über `id` und resolved `@Model` im Main `ModelContext` (nicht über Actor‑Bound `@Model` Instanzen).
- **Disk I/O off-main**:
  - `Task.detached(priority: .utility)` für cache writes / large fetches.
  - Throttling via `AsyncLimiter` (z.B. Thumbnails/Attachment hydration).

### Do
- Fetches/Sorts für große Listen über Loader (`EntitiesHomeLoader`, `GraphStatsLoader`, `GraphCanvasDataLoader`) statt im `body`.
- Beim Mutieren von SwiftData Models: auf MainActor bleiben, dann `modelContext.save()` (oder `context.save()` im Hintergrund‑Context).

### Don’t
- SwiftData `@Model` Instanzen aus background Actors in SwiftUI State halten.
- Synchronous Disk‑Load (`ImageStore.loadUIImage(path:)`) aus SwiftUI `body` aufrufen.

---

## How to work on this project (Setup + wo anfangen)

### Setup Checklist
- [ ] `BrainMesh.xcodeproj` öffnen
- [ ] Signing/Capabilities: iCloud + CloudKit Container **`iCloud.de.marcfechner.BrainMesh`** aktivieren (`BrainMesh/BrainMesh.entitlements`)
- [ ] Auf Gerät/Simulator mit iCloud login testen (Settings → Sync diagnostics)
- [ ] Erster Start: Default Graph wird erzeugt (`BrainMesh/GraphBootstrap.swift`)

### Wo anfangen (für neue Devs)
- Datenmodell verstehen: `BrainMesh/Models.swift` + `BrainMesh/Attachments/MetaAttachment.swift`
- Root Navigation: `BrainMesh/ContentView.swift`, `BrainMesh/AppRootView.swift`
- Performance‑kritische Loader/Hydrators:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`

### „Feature hinzufügen“ (typischer Workflow)
1. **Model / Schema**
   - Neues `@Model` oder neue Felder an bestehenden Models hinzufügen
   - Schema‑Liste in `BrainMesh/BrainMeshApp.swift` aktualisieren
   - Graph scope konsequent: `graphID` bei neuen Records setzen
2. **Loader, wenn es groß werden kann**
   - Bei Listen/Counts/aggregates: Snapshot‑Loader (value types) ergänzen
3. **UI**
   - Screen/Subview in passendem Ordner (z.B. `BrainMesh/Mainscreen/...`)
   - Navigation: `NavigationLink`/Sheet in Host‑Screen
4. **Cache/Media**
   - Bei Bytes/Bildern: Disk‑Cache via `ImageStore`/`AttachmentStore` statt direkte Data‑Loads im UI
5. **Debug**
   - Logging über `os.Logger` (siehe `BrainMesh/Observability/BMObservability.swift`)

---

## Quick Wins (max 10, konkret)

1. **`GraphSession.swift` entfernen oder integrieren**: aktuell keine Referenzen → Dead Code.  
   Datei: `BrainMesh/GraphSession.swift`
2. **Models.swift splitten** (compile time + Macro‑Hotspot reduzieren): je `@Model` eine Datei + `BMModelSchema.swift` für Schema‑Liste.  
   Datei: `BrainMesh/Models.swift`, `BrainMesh/BrainMeshApp.swift`
3. **Loader‑Instrumentation standardisieren**: `BMDuration` + `BMLog.load` in `EntitiesHomeLoader`/`GraphStatsLoader`/`GraphCanvasDataLoader` konsistent nutzen.  
   Dateien: `BrainMesh/Observability/BMObservability.swift`, Loader‑Files.
4. **Einheitliche Graph‑Scope Helpers**: Helper für `FetchDescriptor`‑Predicate‑Boilerplate (entity/attr/link) reduziert Duplikate.  
   Dateien: `BrainMesh/Mainscreen/LinkCleanup.swift`, diverse Loader.
5. **Counts/Derived Data „opt‑in“ halten**: Attribute/Link‑Counts nur berechnen wenn UI/Sort es wirklich braucht, plus UI‑Hinweis „⚡️ kann Laden verlangsamen“.  
   Dateien: `BrainMesh/Mainscreen/EntitiesHome/*`
6. **Settings Views modularisieren**: `DisplaySettingsView.swift` in Section‑Subviews splitten.  
   Datei: `BrainMesh/Settings/Appearance/DisplaySettingsView.swift`
7. **Details Schema Builder split**: `DetailsSchemaBuilderView.swift` in (List, Editor, Validation) splitten.  
   Datei: `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`
8. **Attachment preview normalization**: `AttachmentStore.ensurePreviewURL` mutiert `localPath`; prüfen, ob Call‑Sites das nur auf MainActor nutzen (der Helper ist `@MainActor`, aber Call‑Sites sollten es respektieren).  
   Datei: `BrainMesh/Attachments/AttachmentStore.swift` + Call‑Sites.
9. **Link label denormalization consistency**: nach Rename wird relabeling via `NodeRenameService` gemacht; sicherstellen, dass *alle* Rename‑Flows diesen Service triggern.  
   Datei: `BrainMesh/Mainscreen/LinkCleanup.swift` + Rename UI.
10. **Minimales Perf‑Harness (Debug)**: Debug‑Option „Log loader durations“ in Settings (nur DEBUG), um Hotspots schneller zu finden.  
    Dateien: `BrainMesh/Settings/*`, `BrainMesh/Observability/*`

---

## Open Questions (UNKNOWNs gesammelt)

- **ImportProgress**: Welche Import‑Flows nutzen `BrainMesh/ImportProgress/*` tatsächlich? (Durchgängigkeit/UX) **UNKNOWN**
- **GraphCanvas Inspector/Sheets**: genaue Files/Struktur für Inspector/Focus Picker (teilweise in Extensions) **UNKNOWN**
- **CloudKit Schema/Migration Strategy**: Gibt es geplante ModelVersioning/Migrations oder CloudKit schema management außerhalb SwiftData? **UNKNOWN**
- **Background Sync Expectations**: Wird Background refresh aktiv genutzt (außer remote-notification), oder ist das nur ein Hint? **UNKNOWN**
