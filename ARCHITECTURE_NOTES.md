# BrainMesh — ARCHITECTURE_NOTES
_Generated: 2026-02-26_
## Big Files List (Top 15 by lines)
Quelle: Line-count über alle `*.swift` in `BrainMesh/`.

1. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411** lines — Off-main Loader: SwiftData fetch → GraphCanvas Snapshot.
2. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410** lines — UI/Flows zum Verwalten von Node-Bildern (Import/Sort/Delete/Share).
3. `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` — **401** lines — Attribute Detail Screen (Details, Notes, Media, Links).
4. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388** lines — Home Tab: Graph Auswahl + Entities Liste + Search + Sheets.
5. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388** lines — Detail Values UI (render/format/edit pinned fields).
6. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **381** lines — Off-main Loader: Entities Liste/Counts/Search Snapshots.
7. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362** lines — Shared Media Gallery UI + actions.
8. `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **357** lines — SF Symbols Picker (große Liste/Filter).
9. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **356** lines — Graph Screen root (State, overlays, selection, load).
10. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344** lines — Gallery UI Section.
11. `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331** lines — Markdown helper UI (toolbar/accessories).
12. `BrainMesh/Attachments/AttachmentImportPipeline.swift` — **326** lines — Import pipeline (files/media) + persistence.
13. `BrainMesh/Mainscreen/BulkLinkView.swift` — **321** lines — Bulk Linking UI/logic.
14. `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — **318** lines — Gallery browser screen.
15. `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — **317** lines — Stats tab main view.

Warum riskant (generell):
- Große Dateien erhöhen Merge-Konflikte und erschweren Performance-Reviews.
- In SwiftUI führen „God Views“ schnell zu **exzessiver View invalidation**, besonders wenn in `body` viel abgeleitet/gesortet wird.
- Media/Import Dateien sind Risiko für **RAM spikes**, **MainActor contention** und **Task lifetime leaks**.

## Hot Path Analyse
### Rendering / Scrolling
- **Graph Canvas Physics tick auf Main RunLoop**
  - Datei: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - Grund: `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` → 30Hz `stepSimulation()` kann UI-Thread belasten (Jank/Scroll stutter, battery).
- **Canvas Drawing / Large node sets**
  - Dateien: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+DrawNodes.swift`, `...+DrawEdges.swift`, `...+Rendering.swift`
  - Grund: Canvas drawing skaliert mit Node/Edge count; wenn pro Tick komplette Arrays iteriert werden → O(n) pro frame.
- **Fetch im Renderpfad (real)**
  - Datei: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.Destination.swift`
  - Grund: `fetchEntity`/`fetchAttribute` wird im `body`/`switch` ausgeführt → potenziell re-fetch pro invalidation.
- **SF Symbols Picker**
  - Datei: `BrainMesh/Icons/AllSFSymbolsPickerView.swift`
  - Grund: sehr große Liste; riskant sind teure Filter/Sorts bei jedem keystroke (prüfen: abgeleitete Arrays in `body`).
- **EntitiesHome Search**
  - Dateien: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`, `.../EntitiesHomeLoader.swift`
  - Grund: Search/Sort/Counts müssen off-main bleiben; Loader-Snapshot Pattern ist bereits da, aber Invalidation (z.B. `searchText`) kann viele reloads triggern.
### Sync / Storage
- **CloudKit init + fallback semantics**
  - Datei: `BrainMesh/BrainMeshApp.swift`
  - Grund: Release fallback to local-only kann „Sync sieht kaputt aus“ erzeugen; `SyncRuntime` versucht das sichtbar zu machen.
- **iCloud account status**
  - Datei: `BrainMesh/Settings/SyncRuntime.swift`
  - Grund: AccountStatus-Abfrage ist async; UI muss konsistent sein und nicht spammen (Throttle/Cache).
- **Blob storage in SwiftData**
  - Datei: `BrainMesh/Attachments/MetaAttachment.swift`
  - Grund: `fileData: Data?` kann CloudKit sync & migrations schwer machen (große records, memory). Storage policy (data vs localPath) sollte strikt sein.
### Concurrency
- **Off-main fetch pattern (good)**
  - Dateien: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Warum gut: Snapshot DTOs vermeiden `@Model` crossing → weniger crashes/data races.
- **Task.detached ohne klare Cancellation**
  - Datei: `BrainMesh/BrainMeshApp.swift` (AccountStatus refresh), `BrainMesh/AppRootView.swift` (Startup + delayed lock tasks)
  - Risiko: Detached Tasks leben länger als View-Lifecycle; müssen idempotent sein.
- **Import Pipelines**
  - Dateien: `BrainMesh/Attachments/AttachmentImportPipeline.swift`, `BrainMesh/Images/ImageImportPipeline.swift`
  - Risiko: große Data-Verarbeitung; wenn auf MainActor oder ohne Backpressure → UI hängt.

## Refactor Map
### Konkrete Splits
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` → Split nach Subviews
  - `AttributeDetailView+Header.swift`
  - `AttributeDetailView+DetailsCards.swift`
  - `AttributeDetailView+Media.swift`
  - `AttributeDetailView+Links.swift`
  - Nutzen: bessere Testbarkeit, weniger Rebuild in `body`.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` → Split nach Aktionen
  - `NodeImagesManageView+Grid.swift`
  - `NodeImagesManageView+Import.swift`
  - `NodeImagesManageView+Actions.swift`
  - Nutzen: reduziert State-Explosion, klarere Responsibility.
- `BrainMesh/Attachments/AttachmentImportPipeline.swift` → Pipeline in Steps zerlegen
  - `AttachmentImportPipeline+Pick.swift`
  - `AttachmentImportPipeline+Persist.swift`
  - `AttachmentImportPipeline+Transcode.swift` (falls Video)
  - Nutzen: cancellation/backpressure leichter.
### Cache-/Index-Ideen
- **Node Resolver Cache**
  - Ziel: `NodeDestinationView` nicht im `body` fetchen.
  - Idee: `NodeResolver` (MainActor) mit LRU/`@State` caching; oder `@Query`/`@State` + `.task(id:)` to fetch once.
- **GraphCanvas spatial index**
  - Ziel: Hit-testing/selection nicht linear über alle Nodes.
  - Idee: simple grid binning (cell → nodeIDs), invalidiert bei node movement.
- **Stats Snapshot caching**
  - Ziel: Stats Tab schnell öffnen ohne live recompute.
  - Idee: persistierte `GraphStatsSnapshot` entity oder in-memory cache keyed by (graphID, lastChangeToken).
  - Status: **UNKNOWN**, ob schon vorhanden.
- **Media thumbnails cache**
  - Ziel: Gallery/Manage Views ohne re-decode.
  - Idee: `ImageStore` disk cache + in-memory NSCache keyed by attachmentID+variant.
### Vereinheitlichungen
- **Graph scoping predicates** zentralisieren
  - Heute: `graphID` optional, predicates verteilt.
  - Vorschlag: `GraphScope` helper (graphID) + `FetchDescriptorFactory`.
- **Loader/DTO Standard**
  - Konvention: `*Snapshot` value-only, `@unchecked Sendable` nur wenn nötig; preferred: echte `Sendable` structs.
- **DI light**
  - Nicht gleich ein Framework: simple `EnvironmentKey` für Services (ImageStore, Resolver, Pipelines) statt Singletons.

## Risiken & Edge Cases
- **Datenverlust / Duplikate**: Release-Fallback auf local-only kann zu Divergenz führen, wenn User später CloudKit wieder aktiv hat. (Regel definieren: merge? reset? warn user?)
- **SwiftData + CloudKit Schema Changes**: `graphID` optional ist migrations-freundlich, aber ohne explizite Migrationsplanung → Risiko bei großen Umbrüchen.
- **Large attachments**: `fileData` sync kann CloudKit limits treffen (**UNKNOWN**, ob client-seitig enforced).
- **Multi-device conflicts**: Links/Details/Attachments können gleichzeitig editiert werden → Conflict resolution **UNKNOWN**.
- **GraphCanvas performance**: Bei großen Graphen droht O(n) pro frame + Battery drain.

## Observability / Debuggability
- Logger: `BrainMesh/Observability/BMObservability.swift` (`BMLog.load/expand/physics`).
- Empfehlung:
  - Repro-Checkliste in Tickets: Graph size (nodes/edges), device model, iCloud status, storageMode (SyncRuntime).
  - Add signposts um expensive sections (GraphCanvas stepSimulation, snapshot builds, stats compute).

## Open Questions (UNKNOWN)
- CloudKit/SwiftData conflict handling explizit? (Policies, UI hints)
- Attachments: welche Größen-/Typ-Limits sind gewollt und enforced?
- Stats: existiert ein persistierter snapshot oder wird live aggregiert?
- Gibt es planned features wie sharing/collab/export/import? Wo ist der canonical flow?
- Security: ist Passcode hashing/iterations policy final? (nur aus Model-Feldern ableitbar)

## First 3 Refactors I would do (P0)
### P0.1 — Remove fetch-in-body in NodeDestinationView
- **Ziel:** Keine SwiftData-Fetches im `body`; stabile Navigation ohne wiederholte DB hits.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.Destination.swift`
- **Risiko:** Niedrig (mechanisch). Navigation/Empty-State testen.
- **Erwarteter Nutzen:** Weniger Render-Jitter, weniger Fetch-Spam bei State-Changes.
### P0.2 — GraphCanvas Physics budgeting + lifecycle cancellation
- **Ziel:** 30Hz Simulation nur wenn nötig; stoppen bei background; weniger Battery/Jank.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift` (start/stop hooks)
  - `BrainMesh/AppRootView.swift` (ScenePhase hooks falls nötig)
- **Risiko:** Mittel (Feintuning kann „feel“ ändern).
- **Erwarteter Nutzen:** Spürbar smoother UI bei großen Graphen, bessere Akkulaufzeit.
### P0.3 — Attachment storage policy + pipeline hardening
- **Ziel:** Große Dateien nicht als `Data` dauerhaft im Model halten; klare Regeln `fileData` vs `localPath`; bessere Cancellation.
- **Betroffene Dateien:**
  - `BrainMesh/Attachments/MetaAttachment.swift`
  - `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - `BrainMesh/Images/ImageImportPipeline.swift`
- **Risiko:** Mittel–hoch (Migration bestehender Attachments, Sync-Effekte).
- **Erwarteter Nutzen:** Weniger Speicher-/Sync-Probleme, stabilere Imports, weniger CloudKit-Limits.
