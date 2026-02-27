# ARCHITECTURE_NOTES

> Fokus: Sync/Storage/Model → Entry Points + Navigation → große Views/Services → Konventionen/Workflows.  
> Regeln: Aussagen sind an konkrete Dateipfade gebunden; Unklares ist **UNKNOWN** und steht in „Open Questions“.

## Big Files List (Top 15 nach Zeilen)
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 Zeilen**
  - Zweck: Entities-Home Snapshot Loader (SwiftData fetches + counts caches + search matching).
  - Risiko: Viele Fetch-Pfade + Cache-Invalidation/TTL; bei falscher Cancellation/Stale-Handling drohen Geister-Updates oder unnötige Arbeit.
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **474 Zeilen**
  - Zweck: Graph-Tab Root Screen (State, Loading, Interaction, Routing).
  - Risiko: Große SwiftUI-View mit vielen States/Sheets -> View invalidation-Risiko + schwer testbar.
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **442 Zeilen**
  - Zweck: GraphCanvas Snapshot Loader (Neighborhood/Global loading, traversal, label/icon caches).
  - Risiko: Komplexe Traversal-Logik + Limits (maxNodes/maxLinks) -> Performance/Correctness Tradeoffs.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 Zeilen**
  - Zweck: Media/Gallery Management UI für Entity/Attribute Detail.
  - Risiko: Viele UI-States + Import/Delete/Rename; kann bei großen Sammlungen scroll/render heavy werden.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388 Zeilen**
  - Zweck: Entities Home Screen (NavigationStack, search, debounce reload, sheets).
  - Risiko: Viele Zustandswechsel (searchText, graph switch, display settings) -> häufige reload Trigger.
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388 Zeilen**
  - Zweck: Darstellung/Editing der Detail-Feldwerte (Card UI).
  - Risiko: Viele Feldtypen + Layout; Risiko für SwiftUI body complexity & invalidations.
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **367 Zeilen**
  - Zweck: UI Flow zum Erstellen vieler Links in einem Schritt.
  - Risiko: Großer Sheet-Flow; Risiko für MainActor-Work wenn Snapshot/Validation heavy ist.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 Zeilen**
  - Zweck: Media Gallery UI (Shared) in Detail Screens.
  - Risiko: Viele Medien + Thumbnails -> memory/scroll hotspot.
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **357 Zeilen**
  - Zweck: Picker für SF Symbols (sehr viele Items).
  - Risiko: Sehr große List/Grid -> CPU/Memory beim Filtern/Scrollen.
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344 Zeilen**
  - Zweck: Photo gallery section UI (Details).
  - Risiko: Thumbnails & navigation; kann viele Bildloads triggern.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **341 Zeilen**
  - Zweck: Connections „All“ View (Links/Relations Listing).
  - Risiko: Viele Connections -> heavy lists + mögliche N+1 fetches (prüfen).
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331 Zeilen**
  - Zweck: Accessory UI für Markdown Editing (Toolbar/Actions).
  - Risiko: Nicht kritisch, aber groß -> Wartbarkeit.
- `BrainMesh/Attachments/AttachmentImportPipeline.swift` — **326 Zeilen**
  - Zweck: Pipeline für Attachment Import (inkl. Video/Bild Processing).
  - Risiko: CPU-intensiv; Task-Lifetimes/Cancel wichtig; Memory pressure möglich.
- `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — **318 Zeilen**
  - Zweck: Browser UI für Photo Gallery.
  - Risiko: Scroll/gesture heavy; Bild-Caching wichtig.
- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — **317 Zeilen**
  - Zweck: Stats Tab UI (Dashboards).
  - Risiko: Viele KPI Cards/Sections; Risiko für reload + layout cost.

---

## Hot Path Analyse

### 1) Rendering / Scrolling

#### GraphCanvas Simulation (CPU bound)
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Beobachtung:
  - Simulation tickt über `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` (30 Hz).
  - Repulsion/Forces enthalten ein **O(n²)** nested loop über `simNodes`:
```swift
        for i in 0..<simNodes.count {
            let a = simNodes[i].key
            guard let pa = pos[a] else { continue }

            if (i + 1) >= simNodes.count { continue }
            for j in (i + 1)..<simNodes.count {
                let b = simNodes[j].key
                guard let pb = pos[b] else { continue }

                let dx = pa.x - pb.x
```
- Warum Hotspot:
  - Bei vielen Knoten steigen CPU-Kosten quadratisch.
  - 30Hz Timer bedeutet „immer wieder“ Arbeit, auch bei kleinen Interaktionen (je nach `simulationAllowed` Gate).

**Hebel**
- Begrenze `simNodes` aggressiver (z.B. Viewport/Selection-basiert) oder Spatial Hash/Grid für Repulsion.
- „Sleep“/„wake“ Mechanik prüfen: Simulation nur aktiv, wenn wirklich nötig (z.B. während Drag/Zoom oder kurz nach Layout-Change).

#### GraphCanvas Screen: State/Overlays invalidation surface
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift`
- Warum Hotspot:
  - Große Root-View mit vielen `@State`/Sheets/Overlays -> leicht erhöhte Invalidations und schwerer zu isolieren.
  - Der teure Teil (Canvas) reagiert auf viele State-Änderungen; daher ist eine saubere „state island“ Architektur wichtig.

**Hebel**
- Split nach Verantwortung: State/Loading/Toolbar/Overlays in eigene Dateien + klare `View`-Subtrees.
- Canvas-View möglichst nur von minimalem, stabilen State abhängig machen (z.B. `GraphCanvasSnapshot` + Selection).

#### Entities Home: Suche + counts + list rendering
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeList.swift`
- Beobachtung:
  - Reload ist `.task(id: taskToken)` + debounce; Snapshot kommt aus Loader-Actor.
  - Loader hält Cache für Attribute-/Link-Counts (TTL 8s) und macht mehrere Fetches je nach Flags.
- Warum Hotspot:
  - Typing/search + Graph switching erzeugt viele reloads.
  - Counts erfordern (je nach Implementierung) Fetches über viele Objekte (Attribute/Links).

**Hebel**
- Event-driven Cache invalidation (bei Mutationen) statt TTL-only (oder TTL erhöhen), um Tipp-Reloads billiger zu machen.
- Wenn möglich: `fetchCount` statt full fetch (analog zu Stats Service), wo nur Counts gebraucht werden.

#### Media/Photo Galleries (Memory + IO)
- Dateien (repräsentativ, nicht vollständig):
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
- Warum Hotspot:
  - Viele Thumbnails/Bilder -> Memory pressure + Disk IO.
  - Wichtig: keine synchronen Bildloads im Renderpfad (Hinweis in `BrainMesh/ImageStore.swift`).

---

### 2) Sync / Storage (SwiftData + CloudKit)

#### ModelContainer Init + Fallback
- Datei: `BrainMesh/BrainMeshApp.swift`
- Verhalten:
  - CloudKit Konfiguration: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - DEBUG: fatalError bei Init-Fehlern; RELEASE: fallback auf local-only.
- Risiko:
  - **DEBUG**: Crash verhindert weiterführende UI/Diagnose.
  - **RELEASE**: Fallback kann „still“ passieren → User glaubt, Sync läuft (darum `SyncRuntime`).

#### Account Status / Runtime Flag
- Dateien:
  - `BrainMesh/Settings/SyncRuntime.swift`
  - `BrainMesh/Settings/SettingsView+SyncSection.swift`
- Hotspot/Tradeoff:
  - Status wird per `CKContainer.accountStatus()` geholt (async). UI muss das korrekt anzeigen und nicht bei jedem Foreground-Event spammen.

#### externalStorage + Predicate Hygiene
- Datei: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- Kernpunkt aus dem Code-Kommentar:
```swift
//
//  AttachmentGraphIDMigration.swift
//  BrainMesh
//
//  Created by Marc Fechner on 16.02.26.
//
//  Why this exists:
//  Some older MetaAttachment records may have `graphID == nil` (before graph scoping).
//  Using predicates like `(gid == nil || a.graphID == gid)` can force SwiftData to
//  fall back to in-memory filtering, which is catastrophic for externalStorage blobs.
```
- Warum Hotspot:
  - Wenn SwiftData in-memory filtert und dabei externalStorage-Blobs lädt, kann das die App „wegschießen“ (RAM/IO).
- Hebel:
  - Alte Records (graphID nil) aktiv migrieren, damit Queries als „simple AND“ formuliert werden können.
  - Review aller Attachment-Fetches auf `(gid == nil || ...)` Pattern.

#### Migration/Backfills auf MainActor
- Datei: `BrainMesh/GraphBootstrap.swift`
- Beobachtung:
  - `migrateLegacyRecordsIfNeeded` macht full fetch + loop + save.
```swift
        var changed = false

        // Entities
        do {
            let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { e in
                e.graphID == nil
            })
            let ents = try modelContext.fetch(fd)
            for e in ents {
                e.graphID = defaultGraphID
```
- Risiko:
  - Kann Launch/Foreground blockieren, wenn Datenmenge groß ist.
- Hebel:
  - Migration in Background-Task/Actor + Batch saves (z.B. chunked saves) + Progress/Logging.

---

### 3) Concurrency (MainActor, Task lifetimes, cancellation, thread safety)

#### Loader-Pattern (gut, aber konsequent bleiben)
- Beispiele:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` (actor, Snapshot DTOs, eigener `ModelContext`)
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (actor, `Task.checkCancellation()` in Traversal)
- Positiv:
  - Keine `@Model` Objekte werden über Concurrency-Grenzen gereicht.
  - `autosaveEnabled = false` in Loader-Kontexten reduziert Nebenwirkungen.

#### `Task.detached` (Cancellation/Stale-Risiko)
- Datei: `BrainMesh/Stats/GraphStatsLoader.swift`
- Beobachtung: per-Graph counts laufen in `Task.detached`:
```swift
        return try await Task.detached(priority: .utility) { [configuredContainer, graphIDs] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)

            var per: [UUID?: GraphCounts] = [:]

            for gid in graphIDs {
                try Task.checkCancellation()
```
- Warum riskant:
  - Detached Tasks erben keine Cancellation/Actor-Isolation vom Caller.
  - Bei schnellem Tab/Graph-Wechsel kann Arbeit „weiterlaufen“ und später ein stale Ergebnis liefern (je nachdem, wie Resultate konsumiert werden).
- Hebel:
  - In Loader-Actor laufen lassen (kein detached), oder zumindest „stale result guard“ (Token/RequestID) + striktes Cancellation-Handling.

#### `@unchecked Sendable` Tradeoffs
- Dateien:
  - `BrainMesh/Support/AnyModelContainer.swift` (`ModelContainer` wrapped als `@unchecked Sendable`)
  - Snapshot-Typen wie `EntitiesHomeSnapshot`, `GraphCanvasSnapshot`
- Risiko:
  - Compiler kann Safety nicht garantieren; falsche Nutzung kann Data-Races verursachen.
- Hebel:
  - Usage strikt read-only halten (wie Kommentar sagt) + klare Audit-Regeln.
  - Optional: `Sendable` nur für immutable value types; Container-Wrapper nur in Actors halten (nicht frei herumreichen).

---

## Refactor Map

### A) Konkrete Splits (Datei → neue Dateien)
> Ziel: geringere „invalidation surface“, bessere Testbarkeit, weniger Merge-Konflikte.

- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - Vorschlag Split:
    - `GraphCanvasScreen+State.swift` (State, derived state, tokens)
    - `GraphCanvasScreen+Loading.swift` (reload, loader calls, error handling)
    - `GraphCanvasScreen+Toolbar.swift` (toolbar items + actions)
    - `GraphCanvasScreen+Sheets.swift` (sheet routing)
  - Nutzen: Fokus pro Datei, weniger „God View“.

- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - Vorschlag Split nach Feldtyp:
    - `NodeDetailsValuesCard+SingleLineText.swift`
    - `...+MultiLineText.swift`
    - `...+Choice.swift`, `...+Number.swift`, `...+Date.swift`, `...+Toggle.swift`
  - Nutzen: kleinere body-Bäume, bessere Wiederverwendbarkeit.

- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - Vorschlag Split:
    - `NodeImagesManageView+List.swift` (List Rendering)
    - `NodeImagesManageView+Actions.swift` (delete/rename/import)
    - `NodeImagesManageView+Import.swift` (Picker plumbing)
  - Nutzen: weniger State + besseres Ownership-Design.

### B) Cache-/Index-Ideen
- **Links Index (Node → outgoing/incoming)**  
  - Motivation: Connection-Views (z.B. `NodeDetailShared+Connections.AllView`) könnten sonst repetitiv fetchen/filtern.
  - Implementierungsidee:
    - `LinksIndex` Actor: `Dictionary<NodeKey, [LinkID]>` oder direkt `Dictionary<NodeKey, [LinkSnapshot]>`
    - Invalidation: bei Link add/delete; graph-scoped.
  - **UNKNOWN**: Ob bereits ein solcher Index existiert (bitte in `BrainMesh/Support/*` querprüfen, z.B. `DetailsCompletionIndex.swift` ist vorhanden, aber für Details).

- **Counts als fetchCount**  
  - Stats macht es bereits (`BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`).
  - EntitiesHome Counts ggf. ebenfalls über `fetchCount` statt full fetch (wenn möglich mit Predicates, die SwiftData effizient kann).

### C) Vereinheitlichungen (Patterns, Services, DI)
- Einheitliches Loader-Interface:
  - `configure(container:)`
  - `loadSnapshot(request:)` + `RequestID`/Token für stale-guard
  - `invalidateCache(scope:)`
- Logging:
  - alle Loader mit `BMLog.load` + `BMDuration` standardisieren (`BrainMesh/Observability/BMObservability.swift`).
- DI:
  - aktuell: EnvironmentObjects + Loader konfigurieren in `AppLoadersConfigurator.configureAllLoaders(with:)`.
  - **Hebel**: `AppEnvironment` struct (value) + klare dependency graph (weniger global singletons).

---

## Risiken & Edge Cases
- **CloudKit Init / Entitlements**: Fallback auf local-only in Release kann zu „Daten divergieren zwischen Geräten“ führen, wenn ein Gerät im Fallback bleibt.
- **Migration/Backfill**: `GraphBootstrap.swift` läuft auf MainActor; bei großen Datenmengen drohen Freezes beim Launch/Foreground.
- **externalStorage Attachments**: jede Query, die in-memory filtert, kann Blobs laden (siehe `AttachmentGraphIDMigration.swift`).
- **Graph Security**:
  - Passwort-Hash/Salt in Models (`MetaGraph`, `MetaEntity`) — prüfen, ob dies intended ist (Graph vs Entity lock fields doppelt).
  - **UNKNOWN**: Ob Locks wirklich pro Graph oder teils pro Entity gedacht sind (beides existiert im Model).

---

## Observability / Debuggability
- Logging
  - `BrainMesh/Observability/BMObservability.swift` definiert Kategorien (`load`, `expand`, `physics`, …).
  - Empfehlung: in jedem Loader an gleicher Stelle loggen:
    - Request start (graphID, limits)
    - Duration
    - Cancellation vs success vs error
- Repro Steps (für Perf Bugs)
  - GraphCanvas: großer Graph öffnen → Zoom/Drag → CPU beobachten (Simulation/Timer).
  - EntitiesHome: lange Liste → schnell tippen/löschen im Search → counts togglen.
  - Attachments: viele große Dateien importieren → anschließend list/preview scrollen → RAM beobachten.
- **UNKNOWN**: Ob es bereits ein zentrales „Debug Settings“ UI gibt (nicht gefunden).

---

## Open Questions (alles als **UNKNOWN** markiert)
1. **Lock Semantik**: Warum tragen `MetaGraph` **und** `MetaEntity` Lock-Felder? Ist Entity-Lock historisch/obsolet oder tatsächlich genutzt?
2. **Collaboration/Sharing**: Keine `CKShare`/Sharing-Implementierung gefunden. Ist Share/Collab geplant oder bewusst nicht enthalten?
3. **SPM Dependencies via Workspace**: Im `.pbxproj` keine Package-Refs gefunden; falls ein `.xcworkspace` existiert, fehlt er in diesem ZIP.
4. **Tests**: `BrainMeshTests`/`BrainMeshUITests` existieren, aber Abdeckung/Strategie wurde nicht ausgewertet (**UNKNOWN**).

---

## First 3 Refactors I would do (P0)

### P0.1 — Eliminate `Task.detached` in Stats loading (cancellation + stale guards)
- Ziel: Keine „Geister-Loads“ in Stats bei schnellem Graph-/Tab-Wechsel; weniger Hintergrundarbeit.
- Betroffene Dateien:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - (ggf.) `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (Consumption/Token)
- Risiko: niedrig–mittel (Loader-API ändern, aber rein intern).
- Erwarteter Nutzen: spürbar weniger CPU/Battery; deterministisches UI; weniger „stale snapshot“ Bugs.

### P0.2 — Move heavy migrations off MainActor + batch saves
- Ziel: Launch/Foreground Freezes vermeiden, Migration nachvollziehbar machen (Logging/Progress).
- Betroffene Dateien:
  - `BrainMesh/GraphBootstrap.swift`
  - (ggf.) `BrainMesh/AppRootView.swift` (Startup trigger)
- Risiko: mittel (Migration muss korrekt bleiben; Save/Context usage sauber).
- Erwarteter Nutzen: bessere Responsiveness auf großen Datensätzen, weniger „App hängt beim Start“ Reports.

### P0.3 — GraphCanvas Physics scalability guardrails
- Ziel: GraphCanvas bleibt smooth bei großen Graphen (CPU bounded repulsion + 30Hz Timer).
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - (ggf.) `BrainMesh/GraphCanvas/GraphCanvasScreen/*` (simulationAllowed gating)
- Risiko: mittel (Visual/feel kann sich ändern).
- Erwarteter Nutzen: deutlich weniger CPU/Battery, stabilere FPS, weniger thermische Drosselung.

