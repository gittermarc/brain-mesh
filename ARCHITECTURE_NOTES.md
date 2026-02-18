# BrainMesh — ARCHITECTURE_NOTES

_Last updated: 2026-02-18 (auto-generated from repository state in BrainMesh.zip)_

## Big Files List (Top 15 nach Zeilen)
> Quelle: line-count Scan über `BrainMesh/BrainMesh/*.swift` (nur App-Target, ohne Tests).

| # | Datei | Zeilen | Grober Zweck | Warum riskant / teuer |
|---:|---|---:|---|---|
| 1 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | 532 | Canvas-Rendering, Labels/Notes/Hit-Testing | Viele Zeichenoperationen + potenziell per-frame Rechenarbeit → Scroll/Zoom/Rerender Hot Path |
| 2 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 478 | Shared Detail UI (Hero, Pills, Layout-Bausteine) | Viele UI-Bausteine in einer Datei → hoher Compile Impact, Risiko bei Änderungen |
| 3 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 411 | Off-main Snapshot Loader für Canvas | Mehrere Fetch-Strategien + Filter/Limit Logik → leicht Performance/Correctness Bugs |
| 4 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 408 | Manage UI für Node-Bilder (Import, Auswahl, Delete) | Viel UI-State + Import/IO → leicht unbounded Tasks / UI-Races |
| 5 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 | Connections UI + Router/Navigation | Enthält Router, Preview, Detail → mischt Verantwortungen; enthält Fetch im body (siehe Hot Paths) |
| 6 | `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` | 361 | Stats Cards (UI) | Viele Komponenten in einem File → wächst schnell, schwer testbar |
| 7 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 360 | Gallery Grid/Thumbs für Node Medien | Grid + Thumbnails → viele cell tasks möglich; Performance sensibel |
| 8 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | 357 | „Alle SF Symbols…“-Picker + Search | Sehr große Datenmenge (Symbols); braucht paging/lazy + debounce, sonst UI Stall |
| 9 | `BrainMesh/Mainscreen/BulkLinkView.swift` | 346 | Bulk-Link Workflow | Mehrstufiger Flow + Validierung + Fetches → riskant für Regressionen |
| 10 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | 342 | PhotoGallery Section im Detail | Grid + Image/Thumb loading → Scroll-Performance sensibel |
| 11 | `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | 325 | Canvas Screen (State + Routing) | Viele Subviews/Overlays; State-Explosion führt zu Invalidations |
| 12 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | 319 | Onboarding Sheet (mehrere Steps) | Viel UI/State; leicht UI-State Bugs |
| 13 | `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` | 316 | Gallery Browser (Grid/Navigation) | Scroll/Grid + Preview; kann viele Thumbnail-Requests erzeugen |
| 14 | `BrainMesh/Icons/IconPickerView.swift` | 309 | Kuratierter Icon Picker + Recents + Entry | Search/Recents/Sections; schnell wachsender UI-Code |
| 15 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` | 305 | Highlights/KPIs in Detail | Viele Derived Values → riskant für Recompute im Renderpfad |


## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI)
#### Graph Canvas (höchster Multiplikator)
- **Per-frame Rendering**: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - Nutzt `Canvas` (Zeichen-API). Das ist schnell, aber nur wenn Vorbereitung/Caches stabil sind.
  - Risiko-Gründe (konkret):
    - „per-frame“ Positions-/Label-Offset Berechnung (wenn nicht konsequent gecached).
    - Viele `GraphNode`/`GraphEdge` → mehr Zeichenoperationen; Notes/Labels multiplizieren Aufwand.
- **Physik-Timer (30fps)**: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` → stetige Arbeit, auch wenn UI wenig verändert.
  - Konkreter Aufwand: **O(n²)** Pair-Loop für Repulsion/Collision (`for i in 0..<simNodes.count { for j in i+1..<simNodes.count { ... } }`).
  - Positive Gegenmaßnahmen im Code:
    - Pair-loop ist i<j (nicht doppelt).
    - „Spotlight“-Mode reduziert `simNodes` (relevant set).
    - Sleep/Idle Mechanik (`physicsIsSleeping`, `physicsIdleTicks`).
  - **Risiko**: wenn Timer-Lifecycle nicht strikt an View-Lifecycle/ScenePhase gekoppelt ist → Background CPU/Battery.

#### Entity/Attribute Detail Screens (sehr häufig geöffnet)
- **Fetch im `body` (Renderpfad)**: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - `NodeLinkDetailRouter.body` ruft `modelContext.fetch(...)` direkt beim Rendern auf (siehe Snippet).  
  - Konkreter Grund: *„Fetch im body“* → bei jeder Invalidierung potentiell wieder Fetch; schwer vorherzusagen.
  - Snippet (9 Zeilen):
```swift
var body: some View {
    switch kind {
    case .entity:
        if let e = fetchEntity(id: id) { EntityDetailView(entity: e) }
    case .attribute:
        if let a = fetchAttribute(id: id) { AttributeDetailView(attribute: a) }
    }
}
```

#### Gallery / Attachments
- **Thumbnail Pipeline**: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
  - Konkrete Gründe:
    - QuickLookThumbnailing / AVAssetImageGenerator kann teuer sein.
    - Viele Zellen können gleichzeitig Thumbnails anfordern → wird durch `AsyncLimiter(maxConcurrent: 3)` gedrosselt (gut).
  - Beobachtung: Request-Size/Scale Variabilität kann Cache-Hit-Rate drücken (siehe „Refactor Map“).

### 2) Sync / Storage (SwiftData + CloudKit + Cache)
#### SwiftData CloudKit Setup
- `BrainMesh/BrainMeshApp.swift`
  - `ModelConfiguration(... cloudKitDatabase: .automatic)` → Sync ist „automatisch“; keine direkten CloudKit APIs im Projekt gefunden (`import CloudKit` kommt nicht vor).
  - Entitlements & Background Mode sind gesetzt: `BrainMesh/BrainMesh.entitlements`, `BrainMesh/Info.plist`.

#### Externe Blobs / In-memory Filtering Risiko
- **Attachments**: `MetaAttachment.fileData` ist `@Attribute(.externalStorage)` (`BrainMesh/Attachments/MetaAttachment.swift`).
  - Das ist gut für lokale DB/CloudKit, aber extrem empfindlich gegenüber **in-memory filtering** in SwiftData.
  - Explizit adressiert durch `AttachmentGraphIDMigration.swift`:
    - Motivation im Header: OR-Predicates wie `(gid == nil || a.graphID == gid)` können SwiftData „store-translatable“ brechen.
    - Strategie: migrate legacy `graphID == nil` → dann Query ohne OR.

#### Startup Migration auf MainActor
- `BrainMesh/AppRootView.swift` → `bootstrapGraphing()` ruft `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` auf.
  - Konkreter Grund: läuft `@MainActor` im Startup → wenn Legacy-Daten groß sind, kann das einen spürbaren Cold-Start-Stall verursachen.
  - Gegenmaßnahme existiert teilweise: Loader/Hydrator laufen off-main, aber diese Migration nicht.

#### Images (Entity/Attribute)
- `MetaEntity.imageData` / `MetaAttribute.imageData` sind **nicht** external storage (`BrainMesh/Models.swift`).
  - Risiko: große Bilddaten könnten DB/CloudKit belasten (Record size, Write amplification).
  - **UNKNOWN**: Ob Import-Pipeline Bilddaten systematisch klein hält (Compression/Resize).

### 3) Concurrency / Task Lifetimes / MainActor Contention
- **Pattern ist gut**: „Actor Loader + value-only Snapshot DTO“ (z.B. `EntitiesHomeLoader`, `NodePickerLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `NodeConnectionsLoader`).
  - Vorteil: UI bleibt reaktiv; SwiftData Fetches off-main.
- **Sendable-Schulden**: Snapshots sind teils `@unchecked Sendable` (z.B. `GraphCanvasSnapshot`, `GraphStatsSnapshot`).
  - Konkreter Tradeoff: schneller Patch vs. langfristige Safety (Reference-Typen könnten unbemerkt reinrutschen).
- **Startup Configure via Task.detached**: `BrainMesh/BrainMeshApp.swift` startet mehrere detached Tasks (Loader/Hydrators/Services konfigurieren).
  - Risiko: Reihenfolge/Timing (z.B. UI ruft Loader vor `configure`) → im Code meist durch „guard container != nil“ abgefangen (z.B. `ImageHydrator.hydrateIncremental`), aber nicht überall garantiert (**UNKNOWN**: ob alle Loader das sauber abfangen).
- **SystemModal vs Auto-Lock**:
  - `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`) + Logik in `AppRootView` schützt vor „FaceID prompt triggers background“ → verhindert UI Reset in Pickers.
  - Das ist ein bewusstes Concurrency/ScenePhase Edge-Case Handling (gut, aber leicht regressiv).

## Refactor Map

### A) Konkrete Splits (mechanisch, low risk)
1) `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (408)
   - Ziel: UI-State vs Actions vs Import/Picker trennen.
   - Vorschlag:
     - `NodeImagesManageView.swift` (Host + State + Routing)
     - `NodeImagesManageView+Grid.swift` (Grid/Cells)
     - `NodeImagesManageView+Import.swift` (Importer/Picker Handling)
     - `NodeImagesManageView+Actions.swift` (delete/rename helpers)
2) `BrainMesh/Icons/AllSFSymbolsPickerView.swift` (357)
   - Ziel: ViewModel + Paging/Search + UI-Sektionen trennen.
   - Vorschlag:
     - `AllSFSymbolsPickerView.swift` (View)
     - `AllSFSymbolsPickerViewModel.swift` (Model)
     - `AllSFSymbolsPickerSections.swift` (UI helper views)
3) `BrainMesh/Mainscreen/BulkLinkView.swift` (346)
   - Ziel: Flow in Schritte zerlegen (Selection → Preview → Commit).
   - Vorschlag:
     - `BulkLinkView.swift` (Router)
     - `BulkLinkStepSelectionView.swift`
     - `BulkLinkStepPreviewView.swift`
     - `BulkLinkCommitService.swift` (falls Logik zu groß)

### B) Cache-/Index-Ideen (konkret)
- **Thumbnail Request Harmonisierung**: Standardisiere `requestSize` (z.B. 160×160@2) für Gallery/Grids, um Disk-Cache-Hits zu erhöhen.  
  Betroffene Pfade: `BrainMesh/PhotoGallery/*`, `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`, `BrainMesh/Attachments/AttachmentThumbnailStore.swift`.
- **Canvas Link Filtering**: In `GraphCanvasDataLoader.loadGlobal`, erst Nodeset bestimmen, dann Links passend fetchen (statt `fetchLimit` + in-memory Filter).  
  Pfad: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`.
- **Folded-Felder konsequent halten**: Bei Rename/Editing immer `nameFolded`/`searchLabelFolded` aktualisieren (ein zentraler Helper).  
  Pfad: `BrainMesh/Models.swift` + Rename Flows (`LinkCleanup.swift`, **UNKNOWN**: weitere Stellen).

### C) Vereinheitlichungen (Patterns, DI)
- **Service Registry**: `BrainMeshApp.init` konfiguriert viele Singletons/Actors.  
  Refactor: `AppServices.configure(container:)` (1 Datei), um App-Init zu entschlacken und Tests zu erleichtern.  
  Betroffene Pfade: `BrainMesh/BrainMeshApp.swift`, plus die jeweiligen `*.configure(...)`.
- **Navigation Router**: Wo Routing „Fetch im body“ macht (NodeLinkDetailRouter), auf Loader/Query umstellen (siehe P0).

## Risiken & Edge Cases
- **Migration Writes auf MainActor**: `GraphBootstrap.migrateLegacyRecordsIfNeeded` läuft im Startup auf MainActor → potenziell spürbar bei großen DBs.
- **Denormalisierte Link Labels**: Rename muss Links konsistent relabeln; sonst UI-Inkonsistenz.
- **Attachment Blobs**: external storage + falsche Queries = Performance-Katastrophe (in-memory filtering).
- **ScenePhase/FaceID**: Auto-Lock + system modals sind heikel; Regressionen zeigen sich oft nur auf echten Devices.

## Observability / Debuggability
- Vorhanden:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics` (`BrainMesh/Observability/BMObservability.swift`)
- Empfehlungen (konkret, ohne große Umbauten):
  - `BMDuration` um Loader-Pfade erweitern (z.B. GraphCanvasSnapshot load).
  - Optional: `os_signpost` (nicht vorhanden) wäre ein Upgrade, aber nicht zwingend.

## Open Questions (alles als **UNKNOWN**)
- **UNKNOWN**: Wie groß werden `imageData` typischerweise? (Import resize/compress policy nicht eindeutig aus dem Code ableitbar)
- **UNKNOWN**: Gibt es eine definierte Sync-Strategie (z.B. „sync only on Wi‑Fi“) oder verlässt man sich komplett auf `.automatic`?
- **UNKNOWN**: Werden alle `graphID == nil` Records garantiert im Startup migriert (Entities/Attributes/Links ja; Attachments nur on-demand)?
- **UNKNOWN**: Gibt es Performance-Tests/Benchmarks (z.B. 10k nodes) oder nur manuelle Smoke-Tests?
- **UNKNOWN**: Gibt es bekannte SwiftData/CloudKit Konflikt-Strategien (merge policy etc.)? (keine expliziten Policies gefunden)

## First 3 Refactors I would do (P0)

### P0.1 — „Fetch im body“ im Link-Detail-Router entfernen
- **Ziel**: Keine SwiftData Fetches im Renderpfad, weniger unpredictable UI-Stalls.
- **Betroffene Dateien**:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` (NodeLinkDetailRouter)
- **Risiko**: niedrig (nur Routing/Loading-Mechanik)
- **Erwarteter Nutzen**: stabilere Navigation/Detail-Öffnung, weniger re-render Fetches.

### P0.2 — GraphCanvasDataLoader: Link-Fetch so umbauen, dass `fetchLimit` keine Kanten „wegschneidet“
- **Ziel**: Correctness + Performance (weniger in-memory filtering, deterministischer Snapshot).
- **Betroffene Dateien**:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Risiko**: mittel (kann sichtbare Graph-Kanten ändern, wenn vorher Limits maskiert wurden)
- **Erwarteter Nutzen**: konsistentere Canvas-Darstellung, bessere Skalierung bei großen Graphen.

### P0.3 — ImageData Storage-Strategie entscheiden (und technisch absichern)
- **Ziel**: CloudKit/SwiftData „Blob pressure“ reduzieren und Cache/Hydration klarer machen.
- **Betroffene Dateien**:
  - `BrainMesh/Models.swift` (`MetaEntity.imageData`, `MetaAttribute.imageData`)
  - `BrainMesh/ImageHydrator.swift`, `BrainMesh/ImageStore.swift`
  - Import-Pipeline: `BrainMesh/Images/ImageImportPipeline.swift` (**falls relevant**)
- **Risiko**: mittel–hoch (Schema-/Migration-Thema, Datenformat)
- **Erwarteter Nutzen**: weniger Speicher/Sync-Kosten, stabilere Performance bei vielen Bildern.


## Was bereits gut gelöst ist (damit man es nicht „kaputt-refactort“)
- **Off-main Fetch Pattern** ist konsequent eingeführt:
  - Home: `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` + `EntitiesHomeView.swift` (debounced reload per taskToken)
  - Picker: `BrainMesh/Mainscreen/NodePickerLoader.swift` + `NodePickerView.swift`, `NodeMultiPickerView.swift`
  - Canvas: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - Stats: `BrainMesh/Stats/GraphStatsLoader.swift`
  - Connections: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
- **Blob-Handling ist bewusst**:
  - Attachments: `MetaAttachment.fileData` external storage; Thumbnail generation gedrosselt (`AsyncLimiter`).
  - Images: `ImageHydrator` baut lokal deterministische Cache-Dateien (`<UUID>.jpg`) und entkoppelt Disk-I/O vom UI.

## Weitere konkrete Hotspots / Risiken (mit Gründen)

### A) GraphCanvasScreen: State-Explosion & View Invalidation
- Pfad: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ `GraphCanvasScreen+Overlays.swift`, `+Inspector.swift`, `+Layout.swift`)
- Grund:
  - Viele `@State`/Bindings + Overlays (Inspector, Toolbars, Spotlight etc.) → kleine Änderungen können große Teile invalidieren.
  - Canvas + Physics sind sensitiv auf häufige State-Changes.
- Hebel:
  - State bündeln (struct „CanvasUIState“) und Subviews über `EquatableView`/`@Observable` (nur wenn nötig) isolieren.
  - Derived Values (z.B. Display Edges/Nodes) im Loader/Cache halten, nicht im Screen rechnen.

### B) Startup: MainActor Migrations & Initial Work
- Pfad: `BrainMesh/AppRootView.swift` → `bootstrapGraphing()`, `autoHydrateImagesIfDue()`
- Gründe:
  - Graph-Migration ist write-heavy und läuft im Startup auf MainActor (`GraphBootstrap.migrateLegacyRecordsIfNeeded`).
  - Gleichzeitig laufen detached configure tasks in `BrainMeshApp` → mögliche Timing-Races (UI ruft Loader bevor configure fertig).
- Hebel:
  - Migration in einen background `ModelContext` auslagern (analog zu Hydratoren), UI nur „fire-and-forget“.
  - Loader: überall „guard container != nil“ + klarer Error/Retry Pfad (einheitlich).

### C) Link-Denormalisierung: Korrektheit & Maintenance
- Pfade:
  - `BrainMesh/Models.swift` (`MetaLink.sourceLabel/targetLabel`)
  - `BrainMesh/Mainscreen/LinkCleanup.swift` (Relabel/cleanup)
  - `BrainMesh/BrainMeshApp.swift` (configure `NodeRenameService`)
- Gründe:
  - Denormalisierte Labels geben schnelle UI, aber erhöhen Update-Komplexität.
  - Jeder Rename/Relabel Einstieg, der „vergessen“ wird, führt zu inkonsistenten Labels.
- Hebel:
  - Einen zentralen Rename/Relabel Entry Point erzwingen (z.B. `NodeRenameService` API als einzige Stelle).

### D) Attachment Cleanup / Disk Pressure
- Pfade:
  - `BrainMesh/Attachments/AttachmentCleanup.swift`
  - `BrainMesh/Settings/SettingsView.swift` (Clear Attachment Cache)
- Gründe:
  - Disk cache kann wachsen; Clear ist vorhanden, aber **UNKNOWN** ob automatische Retention/Quota existiert.
- Hebel:
  - Optional: „LRU/Quota“ Policy im Store (z.B. max MB) + Periodic cleanup.

### E) SwiftUI Lists/Grids: Thumbnail Task Storm
- Pfade:
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Gründe:
  - Viele Zellen starten Thumbnail requests; Store drosselt, aber UI kann trotzdem „stau“ erzeugen.
- Hebel:
  - Prefetch/Batching (z.B. nur für sichtbare Range) ist in SwiftUI schwer; pragmatisch: requestSize vereinheitlichen + inFlight dedupe (bereits da).

## Refactor Optionen (wenn Performance wichtiger ist als „mechanischer Split“)

### Option 1: Canvas Snapshot stärker „vorberechnen“
- Pfade: `GraphCanvasDataLoader.swift` → `GraphCanvasView+Rendering.swift`
- Idee:
  - Snapshot enthält bereits caches; weiter ausbauen: z.B. „render-ready“ label positions, edge grouping.
- Tradeoff:
  - Mehr Snapshot-Größe vs. weniger per-frame CPU.

### Option 2: MainActor freien: Migrations & schwere Writes in Background Context
- Pfade: `GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`, `ImageHydrator.swift`
- Idee:
  - Eine gemeinsame „MigrationRunner“ Actor + background context.
- Tradeoff:
  - Mehr Komplexität (retry/cancellation), aber bessere Startup-Responsiveness.

