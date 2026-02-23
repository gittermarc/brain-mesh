# BrainMesh — ARCHITECTURE_NOTES
_Generated: 2026-02-22_

Prioritäten (in dieser Reihenfolge): (1) Sync/Storage/Model, (2) Entry Points + Navigation, (3) große Views/Services, (4) Konventionen/Workflows.  
Alles Unklare ist als **UNKNOWN** markiert und im Abschnitt “Open Questions” gesammelt.

## 1) Sync / Storage / Model (SwiftData + CloudKit)

### 1.1 SwiftData Schema + Container Setup
- Einstieg: `BrainMesh/BrainMeshApp.swift`
  - Schema ist **explizit** zusammengesetzt: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`.
  - CloudKit-Konfiguration: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
    - Kommentar sagt “private DB”, tatsächlich ist es `.automatic` → **siehe Open Questions**.
  - Fehlerverhalten:
    - **DEBUG**: CloudKit-Init-Fehler → `fatalError` (kein Fallback).
    - **Release**: Fallback auf lokal-only `ModelConfiguration(schema: schema)` + `SyncRuntime.shared.setStorageMode(.localOnly)`.

### 1.2 Entitlements / Info.plist / Runtime Status
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - `com.apple.developer.icloud-container-identifiers`: `iCloud.de.marcfechner.BrainMesh`
  - `com.apple.developer.icloud-services`: `CloudKit`
  - `aps-environment`: `development`
- Info.plist: `BrainMesh/Info.plist`
  - `UIBackgroundModes = remote-notification`
  - `NSFaceIDUsageDescription` (Graph unlock)
- Runtime-Status: `BrainMesh/Settings/SyncRuntime.swift`
  - `StorageMode`: `.cloudKit` vs `.localOnly`
  - iCloud Account Status via `CKContainer(identifier: …).accountStatus()`

### 1.3 Datenmodell-Tradeoffs (bewusst so gebaut)
- Denormalisierte Links: `BrainMesh/Models.swift` (`MetaLink`)
  - Kanten speichern `(sourceKindRaw, sourceID, sourceLabel)` und `(targetKindRaw, targetID, targetLabel)` + `note`.
  - Vorteil: Rendering/Listen brauchen keine Join-Fetches.
  - Risiko: Labels können stale werden → siehe `NodeRenameService` (`BrainMesh/Mainscreen/LinkCleanup.swift`).
- Scalar-Owner statt Relationships (teilweise):
  - `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`) nutzt `(ownerKindRaw, ownerID)` + `fileData` externalStorage.
  - `MetaDetailFieldValue.attribute` und `MetaAttribute.owner` sind **ohne** explizite `@Relationship` Macro definiert (Kommentar: Macro-Zirkularität). Das ist ein Wartbarkeits-/Migrationsrisiko.

### 1.4 Graph Scoping + Migration (graphID)
- Viele Modelle haben `graphID: UUID?` (für Multi-Graph, sanfte Migration).
- Migration: `BrainMesh/GraphBootstrap.swift`
  - `ensureAtLeastOneGraph` (Default-Graph)
  - `migrateLegacyRecordsIfNeeded`: füllt `graphID` bei alten Records (`MetaEntity`, `MetaAttribute`, `MetaLink`) und speichert.
- Zeitstempel: `createdAt` default `.distantPast` (u.a. `MetaGraph`, `MetaEntity`), um Migration nicht als “neu erstellt” aussehen zu lassen.

### 1.5 Local Caches + Hydration
- Images:
  - Synced payload: `imageData` (in `MetaEntity`/`MetaAttribute`)
  - Local cache pointer: `imagePath` (deterministischer Name `<uuid>.jpg`)
  - Hydrator: `BrainMesh/ImageHydrator.swift`
    - actor, `AsyncLimiter(maxConcurrent: 1)` (seriell)
    - detached task: fetch Records mit `imageData != nil`, schreibt JPEG über `ImageStore`, setzt `imagePath`, speichert context nur bei Änderungen.
  - Trigger:
    - `AppRootView.autoHydrateImagesIfDue()` (`BrainMesh/AppRootView.swift`): max 1× pro 24h, run-once-per-launch guard.
- Attachments:
  - Model: `BrainMesh/Attachments/MetaAttachment.swift` (`@Attribute(.externalStorage) var fileData`)
  - Cache: `BrainMesh/Attachments/AttachmentStore.swift` (AppSupport-Cache)
  - Hydrator: `BrainMesh/Attachments/AttachmentHydrator.swift`
    - `AsyncLimiter(maxConcurrent: 2)`
    - `inFlight` dedupe pro Attachment ID
    - fetch `fileData` in background `ModelContext`, schreibt Cache-Datei, liefert URL

### 1.6 Offline / Multi-Device / Konflikte
- SwiftData/CloudKit Default-Verhalten ist framework-managed.
- App-spezifisch sichtbar:
  - Release kann **silent** auf local-only fallen → Risiko “User glaubt Sync läuft”.
  - Kein eigener CloudKit-Operation-Layer gefunden (kein `CKModifyRecordsOperation`, keine CKShare etc).

## 2) Entry Points + Navigation

### 2.1 App Entry + Root Orchestration
- `BrainMesh/BrainMeshApp.swift`
  - baut ModelContainer, setz EnvObjects (`AppearanceStore`, `DisplaySettingsStore`, `OnboardingCoordinator`, `GraphLockCoordinator`, `SystemModalCoordinator`)
  - `Task.detached` bei Launch: `SyncRuntime.refreshAccountStatus()`
  - `AppLoadersConfigurator.configureAllLoaders(with:)` off-main
- `BrainMesh/AppRootView.swift`
  - `ContentView()` als Root
  - Startup Flow:
    - `bootstrapGraphing()` → default graph + legacy migration
    - `enforceLockIfNeeded()`
    - `autoHydrateImagesIfDue()` (throttled)
    - `maybePresentOnboardingIfNeeded()`
  - ScenePhase Handling:
    - Debounced background-lock, um System Picker nicht zu killen (`SystemModalCoordinator`)

### 2.2 Root Tabs + Hauptnavigation
- `BrainMesh/ContentView.swift`
  - `TabView`:
    - `EntitiesHomeView()` (NavigationStack)
    - `GraphCanvasScreen()` (NavigationStack)
    - `GraphStatsView()`
    - `SettingsView(showDoneButton: false)` (NavigationStack)

### 2.3 Wichtige Flows / Sheets
- Entities Home:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
    - Sheets: `AddEntityView`, `EntitiesHomeDisplaySheet`, `GraphPickerSheet`
- Detail Screens:
  - Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - Attribute: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Shared: `BrainMesh/Mainscreen/NodeDetailShared/*`
- Graph Canvas:
  - Host: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ Extensions)
  - Controls: Inspector (`GraphCanvasScreen+Inspector.swift`), Details Peek (`GraphCanvasScreen+DetailsPeek.swift`)
- Onboarding:
  - Sheet: `BrainMesh/Onboarding/OnboardingSheetView.swift`
  - Präsentation: `.sheet` in `AppRootView`
- Security:
  - Unlock: `GraphUnlockView` als `fullScreenCover(item:)` in `AppRootView`

## 3) Große Views / Services (Wartbarkeit / Performance)

## Big Files List: Top 15 Dateien nach Zeilen
| # | Lines | File |
|---:|---:|---|
| 1 | 630 | `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` |
| 2 | 532 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` |
| 3 | 515 | `BrainMesh/Models.swift` |
| 4 | 510 | `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift` |
| 5 | 504 | `BrainMesh/Onboarding/OnboardingSheetView.swift` |
| 6 | 491 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` |
| 7 | 469 | `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` |
| 8 | 411 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` |
| 9 | 410 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` |
| 10 | 401 | `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` |
| 11 | 397 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` |
| 12 | 394 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` |
| 13 | 388 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` |
| 14 | 388 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` |
| 15 | 362 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` |

### Warum riskant (kurz, konkret)
- `EntityAttributesAllListModel.swift`
  - **Grund**: `@MainActor` Snapshot Builder; filter/sort/rebuild kann auf Main laufen.
  - **Hotspot-Typ**: exzessive View invalidation / MainActor contention bei großen Attribute-Mengen.
- `GraphCanvasView+Rendering.swift`
  - **Grund**: Render-Pfad; loops über `drawEdges` + `nodes`; per-frame `buildFrameCache` baut Dictionaries neu.
  - **Hotspot-Typ**: render/scroll path CPU + allocations.
- `Models.swift`
  - **Grund**: Schema + Denormalisierung; `didSet` side-effects; jede Feldänderung kann Search-Index/Labels updaten.
  - **Risiko**: Migrations-/Sync-Risiko bei Änderungen.
- `DetailsValueEditorSheet.swift`
  - **Grund**: viele Field-Typen + Completion; hoher Change-Rate.
  - **Hotspot-Typ**: komplexer State + UI churn.
- `GraphCanvasDataLoader.swift`
  - **Grund**: BFS + mehrere Fetches; Predicates mit `contains(frontierIDs)` / `contains(visibleIDs)`.
  - **Hotspot-Typ**: Fetch-Strategie skaliert mit Node-/Link-Menge.

## 4) Hot Path Analyse

### 4.1 Rendering / Scrolling
#### Graph Physics
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- Konkreter Grund:
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` → 30 FPS
  - `repulsion + collisions` nutzt nested loop `for i in 0..<simNodes.count { for j in (i+1)..<simNodes.count { ... } }`
  - Das ist **O(n²)** pro Tick.
- Risiko:
  - bei vielen Nodes CPU-Spike, Frame Drops, Battery drain
  - jede Positionsänderung triggert SwiftUI Re-render (auch wenn ein Teil gecached ist)

#### Graph Rendering
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- Konkreter Grund:
  - per Frame loops über `drawEdges` + `nodes`
  - `buildFrameCache(...)` erstellt pro Frame neue Dictionaries:
    - `screenPoints: [NodeKey: CGPoint]`
    - `labelOffsets: [NodeKey: CGPoint]`
    - optional `outgoingNotesByTarget`
- Risiko:
  - Allocation churn + hashing cost
  - Skalierung mit `edges.count + nodes.count`

#### Entities Home Search/List
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Konkreter Grund:
  - `.task(id: taskToken)` mit debounce (250ms) → häufige Cancels/Reloads beim Tippen
  - Loader macht mehrere Fetches (Entity-name match + Attribute-name match)
  - Counts sind optional; wenn aktiviert:
    - `computeAttributeCounts(...)` fetch’t **alle** `MetaAttribute` im Graph und zählt ownerIDs in Swift (Iteration über komplette Attribut-Menge).
    - `computeLinkCounts(...)` fetch’t **alle** `MetaLink` im Graph und zählt pro Entity (Iteration über komplette Link-Menge).
- Risiko:
  - “heavy sort / heavy scan” bei großen Graphen, auch wenn Search nur wenige Entities zurückgibt
  - TTL-Cache ist kurz (8s), daher Burst-Spikes möglich

#### Fetch im body (Navigation Destinations)
- Datei: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
- Konkreter Grund:
  - `NodeDestinationView.body` ruft `fetchEntity(...)` / `fetchAttribute(...)` und darin `modelContext.fetch(fd)` auf.
- Risiko:
  - Fetch bei SwiftUI invalidations; schwer vorhersehbar, kann mehrfach laufen

### 4.2 Sync / Storage (CloudKit + Caches)
- `BrainMesh/BrainMeshApp.swift`
  - Release-Fallback local-only: Risiko “Sync wirkt kaputt/unsichtbar”
  - Debug fatal: gut fürs frühe Finden von Entitlement/Signing Bugs
- `BrainMesh/Settings/SyncRuntime.swift`
  - iCloud account status ≠ “Sync funktioniert” (nur Vorbedingung). Das ist korrekt, aber Erwartungsmanagement in UI wichtig.
- `BrainMesh/ImageHydrator.swift`
  - positiv: strict throttling + detach + context.autosaveEnabled=false
  - Risiko: große Datenmengen → langer Hintergrundlauf; aber AppRootView throttled stark (1×/24h)
- `BrainMesh/Attachments/AttachmentHydrator.swift`
  - positiv: `inFlight` dedupe + limiter(2)
  - Risiko: cache-miss stampede ist mitigiert, aber Preview UI muss “URL nil” sauber handeln

### 4.3 Concurrency
- Gut:
  - Viele Loader/ Hydratoren nutzen `Task.detached` + neuen `ModelContext` (thread-sicherer als shared context).
  - Cancellation wird oft gecheckt (`Task.checkCancellation`, `Task.isCancelled`) in Schleifen.
- Risiken / Hotspots:
  - `@MainActor` rebuilds mit großen Collections (z.B. `EntityAttributesAllListModel`) → MainActor contention möglich.
  - Detached Tasks: Cancellation ist nicht automatisch konsistent überall; muss aktiv gepflegt werden.

## 5) Refactor Map (konkret)

### 5.1 Konkrete Splits (Datei → neue Dateien)
- `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` →
  - `EntityAttributesAllListModel.swift` (Public API + @Published)
  - `EntityAttributesAllListModel+Cache.swift` (Cache struct + invalidation keys)
  - `EntityAttributesAllListModel+Pinned.swift` (pinned fields/values/chips)
  - `EntityAttributesAllListModel+FilterSort.swift` (filter/sort/group pipelines)
- `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift` →
  - `DetailsValueEditorSheet.swift` (Routing/Sheet host)
  - `DetailsValueEditor+Text.swift`
  - `DetailsValueEditor+Number.swift`
  - `DetailsValueEditor+DateToggleChoice.swift`
  - `DetailsValueEditor+Completion.swift` (UI + Integration `DetailsCompletionIndex`)
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` →
  - `NodeDestinationView.swift` (separat) + Umbau weg von Fetch-in-body

### 5.2 Cache-/Index-Ideen (was cachen, Keys, Invalidations)
- EntitiesHome Counts (P0-ish):
  - Heute: TTL 8s (`EntitiesHomeLoader`)
  - Hebel: invalidation-getrieben
    - invalidate on: add/delete attribute, add/delete link, rename entity (wenn sort/preview davon abhängt)
  - Optional: counts fetch nur für `relevantEntityIDs` statt Vollscan (heute Vollscan + filter in Swift)
- GraphCanvas Rendering:
  - Reuse dictionaries (capacity behalten) statt per-frame neu alloc
  - `keyByIdentifier` (Mapping) nur rebuild, wenn NodeSet sich ändert (heute per frame)
- DetailsCompletionIndex:
  - BuildCache nicht auf MainActor fetchen; stattdessen background `ModelContext` reinreichen (analog Loader pattern)

### 5.3 Vereinheitlichungen (Patterns, Stores, DI)
- Standardisiere Loader-Signatur:
  - `configure(container:)` + `loadSnapshot(...) -> DTO`
  - alle SwiftData Fetches in detached task + frischem `ModelContext`
- Vereinheitliche Logging:
  - `BMLog` Kategorien (`Observability/BMObservability.swift`) überall für “load/expand/physics”
- Zentralisiere graph-scoped predicate builder:
  - aktuell drift-gefährdet (mehrere Stellen bauen `FetchDescriptor` mit/ohne `graphID`)

## 6) Risiken & Edge Cases
- Datenverlust/Verwirrung:
  - Release local-only fallback → User erstellt Daten lokal und erwartet Sync.
  - Empfehlung: sichtbarer Banner/Badge wenn `.localOnly` (Settings allein reicht oft nicht).
- Migration:
  - Schema-Änderungen in `Models.swift` + Schema-Liste in `BrainMeshApp.swift` → CloudKit/SwiftData Migration Verhalten ist **UNKNOWN** (keine custom Migration Layer).
- Denormalisierte Labels:
  - `MetaLink.sourceLabel/targetLabel` können stale werden wenn Rename-Flow `NodeRenameService` nicht triggert.
- Large Graph:
  - O(n²) Physik + per-frame rendering → Node/Link caps sind wichtig (`GraphCanvasScreen`: `maxNodes`, `maxLinks`)
- System Picker / FaceID:
  - Lock im falschen Moment dismiss’t Picker; Debounce-Mechanik in `AppRootView` ist korrekt, muss bei Änderungen geschützt werden.

## 7) Observability / Debuggability
- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics`
  - `BMDuration` Timer (z.B. Physics Tick Timing)
- Praktische Repro/Debug-Checkliste:
  - Graph: großer Graph → zoom/pan/select; physics tick durations beobachten
  - Entities: schnell tippen → Loader cancels, Counts toggles an/aus
  - Details: Editor öffnen für Feld mit vielen Werten → Completion Index Load beobachten
  - Attachments: neues Device/Cache leer → ensureFileURL Pfad

## Open Questions (UNKNOWN)
- CloudKit DB selection: `.automatic` in `BrainMeshApp.swift`, aber Text in `Settings/SyncRuntime.swift` sagt “Private DB”. Absicht **UNKNOWN**.
- Remote notification usage: `UIBackgroundModes = remote-notification` in `Info.plist`, aber keine Handler/Subscriptions im Code gefunden. Zweck **UNKNOWN**.
- Migration strategy: außer `GraphBootstrap` graphID-fill keine orchestrierten Migrations. Erwartetes Prod-Verhalten **UNKNOWN**.

## First 3 Refactors I would do (P0)

### P0.1 — Fetch-in-body eliminieren (Navigation Destination)
- Ziel: deterministische Navigation ohne “fetch bei invalidation”
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` (NodeDestinationView)
- Risiko: Low (lokal), aber Navigation testen (push/pop, state restore)
- Erwarteter Nutzen:
  - weniger unnötige Fetches
  - weniger MainActor contention
  - stabilere Navigation bei UI Updates

### P0.2 — EntitiesHome Counts: Vollscan vermeiden
- Ziel: Counts (Attribute/Links) nicht mehr “fetch all + iterate” pro Search/Toggle
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` (`computeAttributeCounts`, `computeLinkCounts`)
- Risiko: Medium (Counts correctness + Cache invalidation tricky)
- Erwarteter Nutzen:
  - deutlich bessere Skalierung bei großen Graphen
  - spürbar flüssiger beim Tippen/Filtern

### P0.3 — GraphCanvas Render Cache: Allocations runter
- Ziel: pro-frame allocations reduzieren (FrameCache / keyByIdentifier)
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - ggf. `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (State für reusable buffers)
- Risiko: Medium (Rendering correctness; subtle bugs möglich)
- Erwarteter Nutzen:
  - weniger CPU/GC pressure, stabilere FPS
  - bessere Battery/thermals bei großen Graphen