# ARCHITECTURE_NOTES — BrainMesh

> Fokus (Priorität): 1) Sync/Storage/Model, 2) Entry Points + Navigation, 3) große Views/Services, 4) Konventionen/Workflows

---

## Big Files List (Top 15 nach Zeilen)
> Stand: Repository-Scan (Swift-Dateien). Gesamt: **184** Swift-Dateien, ca. **27,604** LOC.

- `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift` — **725** lines
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` — **629** lines
- `BrainMesh/Mainscreen/EntitiesHomeView.swift` — **625** lines
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` — **532** lines
- `BrainMesh/Models.swift` — **515** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **478** lines
- `BrainMesh/Settings/Appearance/AppearanceModels.swift` — **430** lines
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **408** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **394** lines
- `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` — **362** lines
- `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` — **361** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **360** lines
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **357** lines
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **346** lines

### Warum diese Liste wichtig ist
- Große SwiftUI-Dateien sind *Compile-Time Hotspots* (Incremental Builds) und erhöhen Merge-Konflikte.
- Große “God Views” erhöhen die Wahrscheinlichkeit von:
  - SwiftUI Invalidations, die schwer zu debuggen sind
  - “accidental” Work im Renderpfad
  - schwer testbarer Logik (weil UI + State + IO vermischt)

---

## Big Files — Kurz-Annotation (Zweck + Risiko)
1. `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift` (~725)
   - Zweck: UI für definierbare Detail-Felder pro Entität (Templates, Add/Edit, Reorder/Delete).
   - Risiko: sehr viel SwiftUI-State + Sheet/Alert-Routing in einem File; hohe Compile-Zeit; Logik schwer isolierbar.
2. `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` (~629)
   - Zweck: UIKit-bridged Markdown Editor (UITextView) inkl. Toolbar/Selection/Linking.
   - Risiko: komplexe Delegate/Responder-Kette; potenzielle MainActor-Contention; schwer zu testen; hoher “SwiftUI<->UIKit” Overhead.
3. `BrainMesh/Mainscreen/EntitiesHomeView.swift` (~625)
   - Zweck: Entities Tab inkl. Search, Sort, Graph-Switch, Add/Delete, Load-Task Token/Debounce.
   - Risiko: viel State + UX-Flow in einem File; Gefahr, dass UI-Änderungen aus Versehen Fetch/Compute-Pfade beeinflussen.
4. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (~532)
   - Zweck: Canvas-Rendering (Nodes/Edges, labels, selection/highlight, caches).
   - Risiko: Renderpfad/Frame-Overhead; allocations pro Frame; große “view extension” erschwert Profiling.
5. `BrainMesh/Models.swift` (~515)
   - Zweck: Kernmodelle + Convenience-Accessors + Details-Schema (Definition/Value).
   - Risiko: hoher “schema churn”: kleine Model-Änderungen invalidieren viele Builds; erhöht Macro-Risiko.
6. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` (~478)
   - Zweck: Shared Detail UI/Logic für Entity + Attribute (Header, notes, actions, common sections).
   - Risiko: sehr viele Abhängigkeiten; UI invalidations schwer nachzuvollziehen.
7. `BrainMesh/Settings/Appearance/AppearanceModels.swift` (~430)
   - Zweck: Appearance settings model + defaults + presets.
   - Risiko: “central config” → viele Views abhängig → große invalidation surface.
8. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (~411)
   - Zweck: BFS/Expand Loader für GraphCanvas (batched fetch, maxDepth/hops).
   - Risiko: kann bei großen Graphen teuer werden; muss strikt off-main bleiben; caching/invalidations kritisch.
9. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (~408)
   - Zweck: “Alle Fotos” / Gallery Manage UI (pagination, set main, delete, thumbnails).
   - Risiko: Grid/Thumbnail loads; Gefahr von MainThread-Decodes, wenn Cache/Hydration nicht greift.
10. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` (~394)
   - Zweck: Connections UI (Links) + “Alle” Liste + Add/Bulk flows.
   - Risiko: Link-Listen können groß sein; Gefahr von fetch/compute im UI path.
11. `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` (~362)
   - Zweck: Actor Loader: Query + search fold + optional counts; caching.
   - Risiko: correctness/caching invalidation; unbedingt thread-safe halten.
12. `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` (~361)
   - Zweck: Stats-Card UI.
   - Risiko: große SwiftUI view-bodies; compile-time.
13. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` (~360)
   - Zweck: Media grid + “All photos” routing + counts.
   - Risiko: Thumbnail/hydration coupling.
14. `BrainMesh/Icons/AllSFSymbolsPickerView.swift` (~357)
   - Zweck: großes SF Symbols Picker UI.
   - Risiko: große Listen + search/filter; potentiell heavy UI updates.
15. `BrainMesh/Mainscreen/BulkLinkView.swift` (~346)
   - Zweck: Bulk link creation/cleanup.
   - Risiko: batch-DB ops; muss progress/cancellation sauber handhaben.

---


## Entry Points + Navigation Notes (Tradeoffs / Risiken)
### App Entry
- `BrainMesh/BrainMeshApp.swift`
  - baut `ModelContainer` + startet `Task.detached` Konfiguration für Loader/Hydratoren.
  - injiziert zentrale `EnvironmentObject`s: `AppearanceStore`, `OnboardingCoordinator`, `GraphLockCoordinator`, `SystemModalCoordinator`, `SyncRuntime`.

### Root Lifecycle
- `BrainMesh/AppRootView.swift`
  - Single place für: Startup (Graph bootstrap + migration), Onboarding auto-present, Auto-Lock, Auto-Hydration.
  - Tradeoff: viel Verantwortung in einem Root View; dafür sind die Cross-Cutting Concerns “an einem Ort”.

### Navigation Pattern
- Jede Haupt-Tab-View hat ihren eigenen `NavigationStack` (z.B. `EntitiesHomeView`, `GraphCanvasScreen`, `GraphStatsView`).
  - Vorteil: Navigation History pro Tab getrennt.
  - Risiko: verschachtelte Stacks in Sheets (`GraphCanvasScreen` öffnet Details in `.sheet` und packt dort wieder `NavigationStack`) → kann zu “Navigation bugs” führen (Back-button Verhalten, toolbar duplication).

### Modal Pattern
- Onboarding: `.sheet(isPresented:)` in `AppRootView`.
- Graph unlock: `.fullScreenCover(item:)` in `AppRootView` — bewusst global, weil “Blocking”.
- System pickers: über `SystemModalCoordinator` wird “Lock/Foreground work” gedrosselt (`AppRootView` + `Support/SystemModalCoordinator.swift`).


## Hot Path Analyse

### Rendering / Scrolling (SwiftUI)
#### 1) Graph Canvas: Physics + Rendering
**Files**
- `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView.swift`

**Warum Hot Path**
- Physics tick läuft **30 FPS** via `Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true)` (`GraphCanvasView+Physics.swift`).
- Physik enthält einen **O(n²) Pair Loop** über `simNodes` (Repulsion + Collision) pro Tick (`GraphCanvasView+Physics.swift`).
- Jeder Tick schreibt `positions`/`velocities` → SwiftUI invalidiert Renderpfad.
- Rendering erfolgt über `Canvas` (`GraphCanvasView.renderCanvas(in:size:)` in `GraphCanvasView.swift`) und nutzt große Logik in `GraphCanvasView+Rendering.swift`.

**Was bereits gut ist**
- “Sleep when idle”: Timer stoppt nach ~3 Sekunden stillstand (`physicsIdleTicks` / `stopSimulation()`) (`GraphCanvasView+Physics.swift`).
- “Spotlight physics”: `physicsRelevant` begrenzt Simulation auf relevante Nodes (reduziert n²).

**Risiken**
- Große Graphen (viele Nodes) → n² kollabiert schnell.
- Allocations/Set/Array-Build pro Frame in Rendering-Extension: **UNKNOWN** wie viel pro Frame allokiert wird (ohne Instruments-Profiling).

**Konkrete Hebel**
- Renderpfad in “precomputed draw commands” aufteilen (siehe Refactor Map).
- Physics: spatial hashing / grid-binning statt n² (wenn wirklich notwendig) — High risk, nur wenn Profiling bestätigt.

#### 2) Entities Home: List + Derived Counts
**Files**
- `BrainMesh/Mainscreen/EntitiesHomeView.swift`
- `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`

**Warum Hot Path**
- Große Lists + Search + Sort + optional LinkCounts/AttributeCounts.
- UI triggert `reload()` via Task Token + Debounce (`debounceNanos = 250ms`) in `EntitiesHomeView`.
- Loader baut Snapshot off-main, aber je nach SortOption kann zusätzliche DB-Arbeit anfallen (`EntitiesHomeLoader`).

**Was bereits gut ist**
- Debounce + Cancellation reduziert “typing floods”.
- Optionaler includeLinks in Token: verhindert unnötige Count-Fetches, wenn UI sie nicht braucht.

**Risiken**
- Wenn in Zukunft neue Sorts (z.B. “#Links”) hinzugefügt werden: Gefahr, dass `fetchCount`/joins pro Entity zu teuer werden.
- UI kann “tapping delete” viele `AttachmentCleanup`/`LinkCleanup` ops triggern (loop über Entities) (`EntitiesHomeView.deleteEntityIDs`).

**Konkrete Hebel**
- Persisted denormalized counts (z.B. `entityAttributeCount`, `entityLinkCount`) → nur wenn wirklich notwendig.
- Batching deletes + progress UI für mass deletes.

#### 3) Node Detail: Markdown + Media
**Files**
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- `BrainMesh/PhotoGallery/*`, `BrainMesh/Attachments/*`

**Warum Hot Path**
- MarkdownTextView ist UIKit-Bridge: Typing/Selection sind “always on main”.
- Media grids: thumbnails + decoding + on-demand hydration.
- Attachment thumbnails: `QLThumbnailGenerator`/`AVAssetImageGenerator` sind teuer (siehe `AttachmentThumbnailStore.swift`).

**Was bereits gut ist**
- Attachment/Image hydration laufen off-main und concurrency-limited (`ImageHydrator`, `AttachmentHydrator`, `AsyncLimiter`).
- `SystemModalCoordinator` verhindert disruptive Locks während Pickern (reduziert UI resets) (`Support/SystemModalCoordinator.swift` + `AppRootView.swift`).

**Risiken**
- “decode on main” wenn irgendwo `UIImage(data:)`/`Data(contentsOf:)` in body landet (**nicht gefunden in Kernpfad**, aber future risk).
- MarkdownTextView: accessory view / keyboard interactions sind fehleranfällig (siehe Historie in Project Conversations).

---

### Sync / Storage (CloudKit + Caches + Trigger)
#### 1) Container Setup + Fallback
**File**
- `BrainMesh/BrainMeshApp.swift`

**Warum Hot Path**
- Wenn CloudKit-Konfiguration fehlschlägt:
  - DEBUG: `fatalError` → harter Crash.
  - RELEASE: fallback local-only → App läuft, aber “Sync ist weg” (muss UX signalisieren).

**Konkrete Hebel**
- DEBUG: statt fatalError optional ein “local-only debug mode” per launch arg (**Change in behavior**, risk).
- Sichtbarkeit: Settings zeigen bereits Status (`SyncRuntime`). Quick win: prominenter Hinweis im UI, wenn local-only aktiv.

#### 2) Image/Attachment Hydration
**Files**
- `BrainMesh/ImageHydrator.swift`
- `BrainMesh/Attachments/AttachmentHydrator.swift`
- `BrainMesh/AppRootView.swift`

**Warum Hot Path**
- Hydratoren scannen potenziell viele Records und schreiben auf Disk.
- `AppRootView.autoHydrateImagesIfDue()` läuft beim Foreground (aber throttled: 24h + once-per-launch) (`AppRootView.swift`).

**Risiken**
- Große Media-Libraries: disk IO + SwiftData fetch costs.
- Invalidation: Wenn `imagePath/localPath` gesetzt wird, können Views refreshen (beabsichtigt, aber kann “bursty” sein).

**Konkrete Hebel**
- Mehr “incremental cursor”: Hydrator speichert last processed ID/Date, nicht nur “run once”.
- Settings-Button “Hydration jetzt” + progress (Teilweise vorhanden: **UNKNOWN** ob UI existiert, nicht im Detail geprüft).

---

### Concurrency (MainActor, Task lifetimes, cancellation, thread safety)
#### Patterns, die du schon nutzt (gut)
- `Task.detached` + eigener `ModelContext` aus `AnyModelContainer` (Loader/Hydrator) — reduziert MainActor contention.
- Actor-level caches (`EntitiesHomeLoader`) — serialisiert und thread-safe.
- UI cancellation via `Task` handle (`EntitiesHomeView` hat Task Token Pattern; GraphCanvas hat Timer stop/sleep).

#### Risiko-Punkte
- “Detached tasks” ohne dedupe/guard können parallel laufen:
  - z.B. mehrere Hydrations (teilweise guarded: `runOncePerLaunch` in `ImageHydrator`).
- MainActor-heavy loops:
  - GraphCanvas physics tick und positions writes sind auf MainActor (weil Timer). Das ist korrekt für UI-state, aber CPU-lastig.

---

## Refactor Map

### A) Konkrete Splits (Datei → neue Dateien)
1) `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`
- Ziel: UI-Routing klein halten; Actions testbar machen.
- Vorschlag:
  - `DetailsSchemaBuilderView.swift` (Routing, State, toolbar/sheets)
  - `DetailsSchemaBuilder+TemplatesSection.swift`
  - `DetailsSchemaBuilder+FieldsSection.swift`
  - `DetailsSchemaActions.swift` (applyTemplate, moveFields, deleteFields, pinned limit checks)
- Risiko: niedrig-mittel (UI refactor); Benefit: Compile-Time + Lesbarkeit.

2) `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift`
- Vorschlag:
  - `MarkdownTextView.swift` (SwiftUI wrapper)
  - `MarkdownTextView+UITextView.swift` (subclass + layout)
  - `MarkdownTextView+Toolbar.swift` (Undo/Redo/link prompt/format actions)
  - `MarkdownTextView+MarkdownUtils.swift` (sanitize/preview formatting)
- Risiko: mittel (UIKit subtle), aber sehr großer Wartbarkeits-ROI.

3) `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- Vorschlag:
  - `GraphCanvasRenderer.swift` (pure drawing functions; takes snapshot structs)
  - `GraphCanvasRenderCache.swift` (edge cache, text layout cache)
  - `GraphCanvasView+Rendering.swift` nur als “bridge” (calls renderer)
- Risiko: mittel (perf sensitive) — aber lässt sich gut A/B testen.

4) `BrainMesh/Models.swift`
- Vorschlag: pro Model eigene Datei + ein `Models/` Folder.
  - `Models/MetaGraph.swift`, `Models/MetaEntity.swift`, `Models/MetaAttribute.swift`, `Models/MetaLink.swift`, `Models/MetaDetailFields.swift`
  - `Attachments/MetaAttachment.swift` bleibt.
- Risiko: niedrig (reine Split); Benefit: Macro/Compile scope reduziert.

### B) Cache-/Index-Ideen
1) Search Index Cache (folded strings)
- Ausgangslage:
  - `nameFolded` existiert für Entity/Attribute, `searchLabelFolded` für Attribute (`Models.swift`).
  - EntitiesHomeLoader nutzt `BMSearch.fold(searchText)` und cached Snapshots.
- Idee:
  - für Links/Connections optional “folded labels”/index in Loader cache (nicht im Model, sonst churn).
- Risiko: niedrig.

2) Link label denormalization
- Ist-Stand:
  - `MetaLink` speichert `sourceLabel/targetLabel`, Update via `NodeRenameService` (`LinkCleanup.swift`).
- Risiko:
  - Stale labels, wenn Rename Flow nicht überall triggert (z.B. Bulk rename).
- Idee:
  - zentraler `NodeRenameService` Hook bei jeder “save name” Action (checklist).

3) Attachment thumbnails
- Ist-Stand:
  - `AttachmentThumbnailStore` cached thumbnails, concurrency-limited (`Attachments/AttachmentThumbnailStore.swift`).
- Idee:
  - persist thumbnail to disk cache (wenn nicht schon) + memory LRU; invalidation bei delete.

### C) Vereinheitlichungen (Patterns, Services, DI)
- “Loader registry”: statt in `BrainMeshApp` viele `Task.detached` Blöcke, ein `AppServices.bootstrap(container:)`.
- Einheitliches `GraphScope` Helper:
  - `GraphScope.resolve(record.graphID, activeGraphID)` statt überall `graphID ?? activeGraphID`.
- Einheitliche “cleanup on delete” API:
  - `NodeDeletionService.deleteEntity(...)` / `.deleteAttribute(...)` kapselt LinkCleanup + AttachmentCleanup.

---

## Risiken & Edge Cases
- **GraphID nil legacy:** Migration in `GraphBootstrap` wirkt, aber jede neue Query muss entscheiden, ob `nil` erlaubt ist.
- **Duplicate Records:** `attributesList/detailFieldsList/detailValuesList` de-dupen. Das ist ein Symptom; Ursachen bleiben **UNKNOWN**.
- **Graph Delete:** `GraphDeletionService` löscht graph + entities + links + orphan attachments (siehe `BrainMesh/GraphPicker/GraphDeletionService.swift`). Risiko: orphan cleanup muss vollständig bleiben.
- **CloudKit local-only fallback:** Release kann “silent” local-only laufen, wenn CloudKit Setup bricht → Daten “fehlen” auf anderen Geräten.
- **Auto-lock vs system pickers:** current Lösung (debounce + SystemModalCoordinator) ist gut, aber state machine bleibt fragil, wenn neue System-Modals dazukommen.

---

## Observability / Debuggability
- Logging:
  - `BMLog` categories (`BrainMesh/Observability/BMObservability.swift`)
  - Graph physics loggt rolling window alle 60 ticks (`GraphCanvasView+Physics.swift`).
- Repro-Strategien:
  - GraphCanvas performance: Graph mit 200+ Nodes erzeugen → FPS + physics logs beobachten.
  - Hydration: viele Attachments (Videos) importieren → Settings/foreground → disk cache beobachtbar (Application Support).
  - Lock/Picker: Hidden album in Photos öffnen → FaceID prompt → prüfen, ob App nicht lockt (AppRootView debounce logic).

---

## Open Questions (UNKNOWN)
- Nutzung der Security-Felder in `MetaEntity`/`MetaAttribute` (nur Graph ist klar “protected” via GraphPicker/GraphLock).
- Gibt es weitere Sync-Strategien außer SwiftData-Default (z.B. CK subscriptions)? (keine CKSubscription Nutzung gefunden)
- Wie groß werden reale GraphCanvas-Graphs (typischer Node Count)? → entscheidet, ob n² Physik refactor nötig ist.
- Gibt es bekannte “duplicate record” Ursachen (SwiftData bug, import bug, migration)? Nur dedupe-Workarounds sichtbar.
- Gibt es UX-Flow, der `NodeRenameService` nicht triggert und daher stale link labels erzeugt?

---

## First 3 Refactors I would do (P0)
### P0.1 — `Models.swift` splitten + `GraphScope` Helper einführen
- Ziel: Compile-Time und Schema-Churn reduzieren; graphID-handling konsistenter machen.
- Betroffene Dateien:
  - `BrainMesh/Models.swift` → neue Dateien unter `BrainMesh/Models/*`
  - **NEW:** `BrainMesh/Support/GraphScope.swift` (kleiner Helper)
  - `BrainMesh/BrainMeshApp.swift` (Schema-Liste bleibt, nur Imports/paths ändern)
- Risiko: **niedrig** (Split-only, keine Logikänderung) + minimaler Helper.
- Erwarteter Nutzen:
  - spürbar bessere Incremental Builds
  - weniger Merge-Konflikte im Model-Bereich
  - weniger “graphID ?? activeGraphID” Copy/Paste

### P0.2 — `DetailsSchemaBuilderView` in Routing + Actions + Sections splitten
- Ziel: Wartbarkeit/Lesbarkeit + gezieltere Tests/Reviews.
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`
  - **NEW:** `DetailsSchemaBuilder+TemplatesSection.swift`, `DetailsSchemaBuilder+FieldsSection.swift`, `DetailsSchemaActions.swift`
- Risiko: **niedrig–mittel** (UI refactor, aber in sich geschlossen).
- Erwarteter Nutzen:
  - weniger SwiftUI-Compile Schmerzen
  - schnelleres Einbauen neuer Field-Typen/Templates
  - weniger “State spaghetti”

### P0.3 — GraphCanvas Rendering entkoppeln (Renderer + Cache)
- Ziel: Renderpfad isolieren, allocations pro Frame reduzieren, Profiling einfacher machen.
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - **NEW:** `GraphCanvasRenderer.swift`, `GraphCanvasRenderCache.swift`
- Risiko: **mittel** (perf-sensitive; muss visuell identisch bleiben).
- Erwarteter Nutzen:
  - klarer Frame-Budget (bessere FPS bei größeren Graphen)
  - weniger SwiftUI invalidations durch kleinere view extensions
  - leichteres Unit-/Snapshot-Testing der Renderlogik (pure functions)

