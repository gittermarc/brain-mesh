# ARCHITECTURE_NOTES.md

> Generated: 2026-03-01  
> Scope: Codebase scan of `BrainMesh/` (SwiftUI + SwiftData + CloudKit)

## Big Files List (Top 15 nach Zeilen)
(Quelle: `.swift` Line-Count, ohne `__MACOSX/`)

- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 Zeilen**
  - Zweck: Actor-Loader für EntitiesHome: Fetch + Search + Counts-Caching (Attribute/Links) → DTO-Snapshot
  - Warum riskant: Viele Verantwortlichkeiten (Fetch, Cache, Counts, Search-Matching). Fehler hier wirken sofort auf Tippen/Suche/Startzeit.
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **442 Zeilen**
  - Zweck: Actor-Loader für GraphCanvas: Global-Load + Neighborhood-BFS + Render-Caches (Labels/Icons/Images)
  - Warum riskant: CPU/Memory-Spike bei großen Graphen; BFS pro Hop; IN-Predicate/Frontier-Listen; falsche Limits → UI-Stalls.
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **429 Zeilen**
  - Zweck: Kompletter SF Symbols Picker (Grid + Suche + Paging/LoadMore) inkl. ViewModel-Integration
  - Warum riskant: Scroll-/Search-Performance (viele Items), Task/Cancellation-Races, Speicher durch große Symbol-Listen.
- `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` — **427 Zeilen**
  - Zweck: @MainActor ViewModel für Export/Inspect/Import (.bmgraph), Progress, Alerts, Pro-Limits/Replace-Flow
  - Warum riskant: Viele States/Flows in einer Klasse; Risiko für UI-Race (Importer/Exporter/Sheets), schwer testbar.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 Zeilen**
  - Zweck: Galerie-Management (List-Style) für Entity/Attribute Details: Import, Thumbnails, Reorder/Delete
  - Warum riskant: Viele UI-Zustände + Import-Pipeline + Disk/Photos Interop; Risiko für View-Rehosting/Sheet-Dismiss-Bugs.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **404 Zeilen**
  - Zweck: Entities Home Tab: NavigationStack + Search + Toolbar/Sheets + Loader-Orchestrierung
  - Warum riskant: Viel UI-State + Reload-Logik; Risiko für Over-fetch oder UI-Flicker bei schneller Interaktion.
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388 Zeilen**
  - Zweck: Details-Values UI: rendern + editieren der MetaDetailFieldValue für Attribute (Card + Editors)
  - Warum riskant: Komplexe Binding-/Editor-Logik, potenziell viele Fields → Render-Kosten/Invalidation.
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **367 Zeilen**
  - Zweck: Bulk-Link Flow: mehrere Verbindungen in einem Schritt erstellen, Duplicate-Checks, Picker-UX
  - Warum riskant: Viele Seiteneffekte (Insert Links), potentielle O(n*m) Duplicate-Checks, UI-State Explosion.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 Zeilen**
  - Zweck: Media-Gallery in Node Details: Paging/Preview/Viewer Requests, vermeidet @Query 'load everything'
  - Warum riskant: Paging/Prefetch Bugs → Memory; Attachment-Hydration/Thumbnailing im Scroll-Pfad.
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` — **359 Zeilen**
  - Zweck: GraphCanvas Overlays: MiniMap, Chips, Inspector-UI, Sheets/Peek-Flows
  - Warum riskant: Viele Overlay-Zweige → hohe View-Invalidation; Risiko: State-Kopplung an Physics-Ticks.
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` — **345 Zeilen**
  - Zweck: Entity Detail Screen: Hero + Sections (Details/Notes/Media/Connections) + Sheets/Actions
  - Warum riskant: Viele Sheets/Flows; ScrollView mit vielen Cards; Gefahr: Arbeit in .onAppear ohne Cancellation.
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344 Zeilen**
  - Zweck: Detail-only Foto-Galerie (MetaAttachment.galleryImage): Picker, Import, Strip, Browser/Viewer
  - Warum riskant: PhotosUI Import + Kompression + SwiftData externalStorage; Risiko für UI-Stalls bei großen Imports.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **341 Zeilen**
  - Zweck: 'Alle Verbindungen' Screen (Outgoing/Incoming) + Search/Filter + Navigation
  - Warum riskant: Kann sehr viele LinkRows zeigen; unbounded fetch in Loader → Memory/Scroll.
- `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — **335 Zeilen**
  - Zweck: Import-Pipeline: Decode/Validate/Remap/Insert; Modes (asNewGraphRemap/replace)
  - Warum riskant: Datenintegrität (dangling IDs), Performance bei großen Dumps, CloudKit-Sync-Druck nach Bulk-Insert.
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331 Zeilen**
  - Zweck: Markdown Notes Editor Zubehör: Toolbar, Snippets, Formatting
  - Warum riskant: UI-Komplexität; Fokus/Keyboard-Races; Performance wenn Notes sehr lang sind.

## Hot Path Analyse

### Rendering / Scrolling

#### GraphCanvas: 30 FPS Physics + häufige Re-Renders
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` + `GraphCanvasScreen+*.swift`
- Warum Hotspot:
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` tickt 30 FPS (`GraphCanvasView+Physics.swift`) und ändert `positions/velocities`.
  - SwiftUI invalidiert bei State-Updates häufig; Canvas zeichnet dann erneut.
- Bereits vorhandene Mitigation:
  - Render-Caches in `GraphCanvasScreen.swift` (`labelCache`, `imagePathCache`, `iconSymbolCache`, `drawEdgesCache`, `lensCache`).
  - Simulation-Gate: `simulationAllowed` in `GraphCanvasView.swift` (nur wenn Screen sichtbar + App aktiv).
  - MiniMap Throttle: `miniMapPositionsSnapshot` in `GraphCanvasScreen.swift` (reduziert Redraw-Frequenz).
- Risiken / Edge:
  - Große Graphen + hohe `maxNodes/maxLinks` → CPU-Spikes und Battery drain.
  - Overlay-States im selben Screen (`GraphCanvasScreen+Overlays.swift`) können Re-Render-Kaskaden verstärken.

#### EntitiesHome: Suche/Reload im Tipp-Pfad
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Warum Hotspot:
  - Search-Text ändert sich schnell; erzeugt häufige Reloads.
  - Optionales Laden von Counts (Attribute/Links) kann teuer sein (graph-weit).
- Bereits vorhandene Mitigation:
  - Debounce (`debounceNanos = 250_000_000`) + Cancellation Handling in `EntitiesHomeView.swift`.
  - Counts-Cache mit TTL in `EntitiesHomeLoader.swift` (`countsCacheTTLSeconds = 8`).
  - DTO Snapshot (keine @Model Objekte über Actor-Grenzen).
- Risiken / Edge:
  - Cache invalidation ist zeitbasiert, nicht eventbasiert → temporär stale Counts.
  - Wenn LinkCounts in großen Graphen benötigt werden, ist `computeLinkCounts(...)` potenziell O(n) über viele Links.

#### Node Details: Media/Attachments/Gallery im Scroll-Pfad
- Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
- Warum Hotspot:
  - Galerie/Attachments können große externalStorage blobs nachziehen.
  - Thumbnails/Preview-URLs sind Disk I/O + (ggf.) Data materialization.
- Bereits vorhandene Mitigation:
  - Attachment cache hydration ist global throttled (`AttachmentHydrator.hydrateLimiter maxConcurrent: 2`).
  - Gallery QueryBuilder (keine unbounded OR predicates), siehe `PhotoGallery/PhotoGallerySection.swift` → `PhotoGalleryQueryBuilder.galleryImagesQuery(...)`.
- Risiken / Edge:
  - “Visible cells call ensureFileURL” kann bei sehr schnellen Scrolls viele Requests erzeugen → auch wenn deduped, entsteht Druck auf I/O.

#### Connections “Alle”: unbounded Link-Liste
- Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`
- Warum Hotspot:
  - Loader fetcht ohne `fetchLimit` alle Links (outgoing + incoming).
- Konkreter Grund:
  - **Unbounded fetch** → Memory + lange Sort/Map in einer Session.
- Hinweis:
  - Für viele User ok; aber bei “2.000 Links” wird es spürbar.

### Sync / Storage

#### SwiftData + CloudKit Setup
- Datei: `BrainMesh/BrainMeshApp.swift`
- Verhalten:
  - Schema ist manuell gelistet (Models müssen hier ergänzt werden).
  - CloudKit-Config: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - DEBUG: CloudKit-Init-Fehler führen zu `fatalError(...)`.
  - RELEASE: Fallback local-only + `SyncRuntime.shared.setStorageMode(.localOnly)`.
- Risiken:
  - Unterschiedliches Verhalten DEBUG vs RELEASE kann Bugs verstecken (z.B. Sync-Probleme erscheinen erst in Release).
  - SwiftData Schema-Änderungen ohne Plan können CloudKit-Schema drift verursachen (**UNKNOWN**: ob/wie Schema-Migration gehandhabt wird).

#### External Storage: MetaAttachment.fileData
- Dateien:
  - `BrainMesh/Attachments/MetaAttachment.swift` (`@Attribute(.externalStorage) var fileData: Data?`)
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- Warum kritisch:
  - OR predicates wie `(graphID == nil || graphID == gid)` können zu in-memory filtering führen; bei externalStorage ist das “katastrophal” (siehe Kommentar in `AttachmentGraphIDMigration.swift`).
- Mitigation:
  - Migration setzt legacy attachments `graphID` nach, damit Queries als `a.graphID == gid` formuliert werden können.

#### Image Hydration / Cache
- Dateien:
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/ImageStore.swift`
- Hotspot Gründe:
  - Disk write + optional SwiftData mutations (setzen von `imagePath`) in Bulk.
- Mitigation:
  - Serialisiert (`AsyncLimiter maxConcurrent: 1`) und run-once-per-launch guard (`didRunIncrementalThisLaunch`).
  - Auto-run max. 1x pro 24h via `BMAppStorageKeys.imageHydratorLastAutoRun` (`AppRootView.swift`).

### Concurrency

#### “Actor + configure(container:) + detached fetch” Pattern
- Dateien:
  - `BrainMesh/Support/AnyModelContainer.swift`
  - `BrainMesh/Support/AppLoadersConfigurator.swift`
  - Beispiele Loader: `EntitiesHomeLoader.swift`, `GraphCanvasDataLoader.swift`, `GraphStatsLoader.swift`, `NodeConnectionsLoader.swift`
- Warum gut:
  - SwiftData `ModelContext` wird pro Task erstellt; UI bleibt frei.
  - DTOs verhindern, dass `@Model` Instanzen über Actor-Grenzen wandern.
- Tradeoff:
  - Viele Detached Tasks → schwerer zu debuggen, wenn Cancellation/Token-Guards inkonsistent sind.

#### Stale-result Guards / Cancellation in Views
- Dateien (gute Beispiele):
  - `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (`currentLoadToken`, `lastLoadKey`)
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (`loadTask`, `currentLoadToken`)
  - `BrainMesh/Icons/AllSFSymbolsPickerView.swift` (`onDisappear` → `model.cancelSearch()`)
- Risiko:
  - Wenn ein View eine `.task` startet, aber keine Cancellation/Token-Guard hat, drohen “späte” UI-Updates (Ghost Work).

#### ScenePhase / System Pickers / Auto-Lock Debounce
- Datei: `BrainMesh/AppRootView.swift`
- Konkreter Grund:
  - `.background` kann transient während system pickers/FaceID auftreten; Lock würde Picker dismissen.
- Mitigation:
  - debounced background lock Task mit grace window, plus `SystemModalCoordinator` guard.

## Refactor Map

### Konkrete Splits (Datei → neue Dateien)
Ziel: mechanische Splits (low risk), Compile-Zeiten stabilisieren, Ownership klarer.

1) `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Vorschlag:
  - `.../EntitiesHomeLoader+Fetch.swift` (FetchDescriptor + Search-Matching)
  - `.../EntitiesHomeLoader+Counts.swift` (AttributeCounts, LinkCounts)
  - `.../EntitiesHomeLoader+Cache.swift` (TTL Cache + invalidation)
  - `.../EntitiesHomeDTO.swift` (Row/Snapshot structs)
- Nutzen: Tests/Review einfacher; weniger Merge-Konflikte.

2) `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- Vorschlag:
  - `GraphCanvasDataLoader+Global.swift`
  - `GraphCanvasDataLoader+Neighborhood.swift` (BFS)
  - `GraphCanvasDataLoader+Caches.swift` (label/icon/image caches + note extraction)
- Nutzen: Performance-Änderungen (z.B. BFS) können isoliert reviewed werden.

3) `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift`
- Vorschlag:
  - `GraphTransferViewModel+Export.swift`
  - `GraphTransferViewModel+Import.swift`
  - `GraphTransferViewModel+Replace.swift`
  - `GraphTransferViewModel+Alerts.swift`
- Nutzen: weniger “State spaghetti”; bessere Testbarkeit.

4) `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- Vorschlag:
  - Extract `NodeImagesManageList`, `NodeImagesManageActions`, `NodeImagesManageImportController` (Views vs Actions trennen).
- Nutzen: reduzierte Re-Render Fläche; klarere Verantwortlichkeit.

### Cache-/Index-Ideen
(Alle Vorschläge sind “opt-in”, um Datenrisiko zu vermeiden.)

- **Event-driven cache invalidation** für EntitiesHome counts:
  - Heute: TTL 8s (`EntitiesHomeLoader.swift`).
  - Option: invalidate Cache direkt bei Link/Attribute create/delete (zentraler “Mutations Service”) → weniger recompute, konsistentere Counts.
  - Risiko: du brauchst eine saubere Stelle, die *alle* Mutationen sieht (**UNKNOWN** ob es so einen zentralen Service geben soll).

- **GraphCanvas adjacency prefetch**:
  - Heute: Neighborhood BFS fetch pro Hop (`GraphCanvasDataLoader.swift`).
  - Option: einmal alle relevanten Links für `frontier ∪ visited` fetchen und in-memory expanden (reduziert Store roundtrips).
  - Risiko: kann mehr Memory auf einmal ziehen; braucht gute Limits.

- **Attachment thumbnail caching**:
  - Es existiert ein Thumbnail-Store (siehe `BrainMesh/Attachments/AttachmentThumbnailStore.swift`).
  - Prüfen, ob Thumbnail-Generierung ausschließlich on-demand und throttled läuft (sonst: background precompute nur bei WiFi/Charging, falls nötig) (**UNKNOWN** Policy).

### Vereinheitlichungen (Patterns, Services, DI)
- **Loader orchestration standardisieren**:
  - Einheitliches Pattern: `loadTask?.cancel()` + `token guard` + `isRefreshing` State.
  - Ziel: weniger “späte” Updates, weniger Copypasta.
- **Singletons bündeln**:
  - Aktuell viele `static let shared` Actors.
  - Option: `AppEnvironment` (struct) im Root als single source of truth, um Testability zu erhöhen.
  - Risiko: größerer Umbau; nicht P0.

## Risiken & Edge Cases
- **CloudKit init fail**:
  - DEBUG crasht, RELEASE fällt auf local-only zurück (`BrainMeshApp.swift`).
  - Risiko: unterschiedliche Datenbanken → “Warum sync’t es nicht?” Support-Fall.
- **Datenvolumen (Attachments/Images)**:
  - `MetaAttachment.fileData` externalStorage: gut für CloudKit, aber Queries müssen sauber bleiben (`AttachmentGraphIDMigration.swift`).
  - `EntityDetailView.swift` setzt `maxBytes = 25MB` als Guard, aber Enforcement ist verteilt (Import-Pipelines prüfen) → Gefahr inkonsistenter Regeln.
- **Denormalisierte Link Labels**:
  - `MetaLink.sourceLabel/targetLabel` müssen bei Rename konsistent bleiben; sonst zeigt UI alte Labels an.
- **Multi-Device Konflikte**:
  - SwiftData/CloudKit löst Konflikte, aber App-spezifische invariants (z.B. link label sync) müssen robust sein (**UNKNOWN** ob conflict-resolution bewusst getestet wird).
- **Lock/Unlock UX**:
  - Background/Foreground + system pickers: Debounce existiert (`AppRootView.swift`), aber neue modale Flows müssen `SystemModalCoordinator` korrekt markieren.

## Observability / Debuggability
- `BrainMesh/Observability/BMObservability.swift`:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics`
  - `BMDuration` für schnelle Timing-Messungen (DispatchTime based)
- Praktische Debug-Tipps:
  - Loader Timing: direkt um `Task.detached` Blocks `BMDuration` nutzen und in `BMLog.load` loggen.
  - GraphCanvas: tick max/avg wird bereits in `GraphCanvasView.swift` gesammelt (`physicsTickAccumNanos`, `physicsTickMaxNanos`).

## Open Questions (**UNKNOWN**)
- Wie wird **SwiftData Schema Evolution** geplant? (nur automatic migrations oder explizite Versionierung/Tests?)
- Soll der DEBUG-`fatalError` bei CloudKit-Init bewusst bleiben oder soll DEBUG ebenfalls fallbacken (um Verhalten zu vereinheitlichen)?
- Gibt es ein Ziel für **maximale Attachment-/Image-Größen** (pro File / pro Graph) und ist das überall enforced?
- Gibt es eine Roadmap für **Collaboration/Sharing**? (Im Repo keine `CKShare` Nutzung gefunden.)

## First 3 Refactors I would do (P0)

### P0.1 — “Alle Verbindungen” paginieren (unbounded fetch kill)
- Ziel: Node mit sehr vielen Links öffnet sich schnell, ohne Memory-Spike.
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`
- Risiko: Niedrig bis mittel (UX-Änderung; braucht “Load more” + stabilen Sort).
- Erwarteter Nutzen:
  - deutlich bessere Worst-Case Performance; weniger UI-Stalls bei “2.000 Links”.

### P0.2 — EntitiesHomeLoader split + Count-Compute isolieren
- Ziel: Wartbarkeit erhöhen und Count-Strategien (Cache/Invalidation) leichter iterieren können.
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - optional: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (nur Anpassungen an APIs)
- Risiko: Niedrig (mechanischer Split, API bleibt gleich).
- Erwarteter Nutzen:
  - schnellere Reviews, weniger Merge-Konflikte, klarere Hotspot-Optimierung.

### P0.3 — GraphCanvasDataLoader split + BFS klar abgrenzen
- Ziel: Neighborhood-Loading separat tunen (Limits, Predicate, Prefetch) ohne das Global-Loading zu tangieren.
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+LoadScheduling.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Loading.swift`
- Risiko: Niedrig (Split) bis mittel (falls BFS-Verhalten angepasst wird).
- Erwarteter Nutzen:
  - Performance-Tuning wird gezielter; weniger Angst vor Regressionen im Canvas.

