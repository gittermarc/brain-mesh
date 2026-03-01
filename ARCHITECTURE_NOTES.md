# ARCHITECTURE_NOTES

Fokus: Wartbarkeit + Performance-Hotspots, mit konkreten Dateipfaden und Refactor-Optionen.
Alles Unklare ist als **UNKNOWN** markiert und in **Open Questions** gesammelt.

## Big Files List (Top 15 nach Zeilen)
Gemessen über `*.swift` im Repo (ohne `__MACOSX`). “Groß” heißt hier meist: viele Verantwortlichkeiten / hoher Churn / Merge-Konflikt-Risiko.

| # | Zeilen | Pfad | Zweck / warum groß | Risiko-Profil |
|---:|---:|---|---|---|
| 1 | 429 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | SF Symbols Picker: Katalog + Suche + Paging-Grid + Selection UX. | UI-Perf + Search-Task/Cancellation; View+VM eng gekoppelt. |
| 2 | 427 | `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` | Import/Export State Machine für GraphTransfer UI (Confirm/Share/FileImporter/Pro-Gating). | Viele Zustände → Race/Cancellation Bugs; user-facing Fehler. |
| 3 | 410 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | Gallery-Management Screen (Paging-Liste, set-main, delete, Viewer-Navigation). | Viele UI-States + async Load; Stale State bei schnellem Wechsel. |
| 4 | 404 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | Entities Home Tab: Graph Switch, Search Debounce, Loader Integration, Layout/Toolbar. | Häufige Invalidations (Search/Settings) + Navigation + State Drift. |
| 5 | 388 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | Details Values Card: Display Values für alle konfigurierten Felder ableiten. | Derived Arrays werden oft neu berechnet → SwiftUI-Invalidations verstärken. |
| 6 | 367 | `BrainMesh/Mainscreen/BulkLinkView.swift` | Bulk-Link UX (Multi-Select, Duplicate Detection, Commit). | Große In-Memory Snapshots + List-Perf + Korrektheit (Duplikate). |
| 7 | 362 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | Detail Media Gallery UI (Grid/Strip, Paging, Thumbnails). | Image-Decoding + Scroll-Perf; Task-Lifetime in Cells. |
| 8 | 345 | `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` | Entity Detail Screen Composition (Hero, Sections, Sheets, Actions). | Viele Dependencies; schnell aus Versehen heavy Work in `body`. |
| 9 | 344 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | Inline Galerie-Sektion (PhotosPicker, Migration, Query, Thumbnails). | `@Query` kann viele Rows laden; Migration läuft beim Öffnen. |
| 10 | 341 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` | „Alle Verbindungen“ Screen (potenziell riesige Link-Mengen). | Große Listen; Fetch/Paging muss strikt bounded/off-main bleiben. |
| 11 | 335 | `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` | Core Import Pipeline (Decode, Validate, Remap IDs, Insert). | Datenintegrität + Performance + Partial-Failure Handling. |
| 12 | 331 | `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` | Markdown Editor Accessory/Toolbar (UIKit Bridging). | UIKit/SwiftUI Coordination, Focus/Input Edge Cases. |
| 13 | 326 | `BrainMesh/Attachments/AttachmentImportPipeline.swift` | Attachment Import (File/Video), Limits, Compression, Persistenz. | Memory Spikes + Long-Running Tasks; Cancellation/Resilience wichtig. |
| 14 | 324 | `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift` | Galerie Viewer (Paging, Gestures, Thumbnails). | Decode/Caching; schnelles Swipen + Cancellation. |
| 15 | 322 | `BrainMesh/Pro/ProCenterView.swift` | Pro Center / Paywall Navigation + StoreKit Product UI. | StoreKit Async + Entitlement-Wechsel; UI-Churn. |

## Hot Path Analyse

### Rendering / Scrolling (SwiftUI Invalidations + expensive work)
1. **GraphCanvas Physik + Canvas Rendering ist der #1 CPU-Hotspot**
   - 30-FPS Timer + O(n²) Pair-Loop (Repulsion/Collision): `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
   - Canvas wird durch häufige `positions`-State Updates neu gerendert: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`
   - Konkreter Grund:
     - Pair-Loop skaliert schlecht (Quadratisch).
     - Positions-Updates invalidieren regelmäßig die View (Canvas re-draw).
   - Bereits vorhandene Mitigation:
     - “Sleep when idle” (`physicsIdleTicks`, `stopSimulation()`): `GraphCanvasView+Physics.swift`
     - “Spotlight physics” (nur relevante Nodes sim): `physicsRelevant` in `GraphCanvasView.swift`

2. **Große Listen mit komplexen Row-Views**
   - Entities Home (List/Grid) mit Search-getriebenem Reload: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
     - Trigger: `.task(id: taskToken)` reagiert auf Graph/Search/Settings.
     - Fetch ist off-main (`EntitiesHomeLoader`), aber Recomposition ist häufig.
   - “Alle Verbindungen” Screen kann sehr groß werden:
     - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`
     - Risiko: unbounded Rendering ohne Paging = schlechter Scroll + hoher Memory.

3. **Image-heavy Grids / Galleries**
   - Viewer + Thumbnail-Decoding: `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
   - Konkreter Grund: “decode onAppear” + schnelles Scrollen ohne Cancellation → Ghost-Work / wasted CPU.

4. **Derived Arrays im Render-Pfad**
   - `NodeDetailsValuesCard.rows` mappt Felder → Display Values: `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
   - Konkreter Grund: bei häufigen Invalidations (Tippen/Sheets/Toggles) wird dieses Mapping wiederholt ausgeführt.

### Sync / Storage (CloudKit + Disk I/O)
1. **CloudKit Enablement + Local-only Fallback**
   - Setup: `BrainMesh/BrainMeshApp.swift` (`ModelConfiguration(... cloudKitDatabase: .automatic)`)
   - Release fallback auf local-only bei Fehler.
   - Risiko: “Sync wirkt kaputt”, wenn nicht sichtbar (UI versucht es über `BrainMesh/Settings/SyncRuntime.swift`).

2. **Local Cache Hydration (Disk Writes + Background Fetches)**
   - Images: `BrainMesh/ImageHydrator.swift` scannt Records mit `imageData != nil` und schreibt deterministische JPEGs.
   - Attachments: `BrainMesh/Attachments/AttachmentHydrator.swift` fetch’t `fileData` off-main und schreibt Cache-Files.
   - Beide nutzen `Task.detached` + `AsyncLimiter` Throttling:
     - Limiter: `BrainMesh/Support/AsyncLimiter.swift`
     - Verkabelung: `BrainMesh/Support/AppLoadersConfigurator.swift`
   - Risiko: wenn zu aggressiv getriggert (Foreground-Spam), trotzdem Background-CPU-Spikes möglich.

3. **Attachment Payload Größe**
   - `MetaAttachment.fileData` nutzt `@Attribute(.externalStorage)` (`BrainMesh/Attachments/MetaAttachment.swift`).
   - Hilft bei Record-Size, aber große Attachments bedeuten trotzdem Transfer + Cache-Writes.

### Concurrency (MainActor contention, Task lifetimes, cancellation)
1. **Startup “fire-and-forget” Work**
   - `BrainMesh/BrainMeshApp.swift`: detached Task für `SyncRuntime.shared.refreshAccountStatus()`.
   - `BrainMesh/Support/AppLoadersConfigurator.swift`: `Task(priority: .utility)` für Loader-Konfiguration.
   - Risiko: globale Tasks laufen unabhängig vom UI-Kontext; Cancel existiert, aber weiterhin “global-ish”.

2. **View-getriebene Debounce-Tasks**
   - Beispiel: `.task(id: taskToken)` + `Task.sleep` Debounce in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`.
   - Gut, solange konsequent mit Cancellation/Stale-Guards gearbeitet wird; Copy/Paste Fehler sind wahrscheinlich.

3. **`@unchecked Sendable` als Escape-Hatch**
   - `GraphCanvasSnapshot` ist `@unchecked Sendable` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift`).
   - `GraphTransferViewModel` ist `@unchecked Sendable` (`BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift`).
   - Risiko: Korrektheit hängt an Disziplin (value-only snapshots, keine Referenzen über Actor-Grenzen).

## Refactor Map (konkrete Splits)

### 1) Große SwiftUI Composition Files in stabile Partials splitten (Low Risk)
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Vorschlag:
    - `EntitiesHomeView+Body.swift` (Layout/State/Composition)
    - `EntitiesHomeView+Loading.swift` (Task/Debounce/Reload)
    - `EntitiesHomeView+Toolbar.swift` (Toolbar/Menus/Sheets)
  - Nutzen: weniger Merge-Konflikte, Task-Lifetimes leichter auditierbar.

- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` und `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Split nach Sektionen:
    - `+Header`, `+Details`, `+Links`, `+Media`, `+Sheets`
  - Nutzen: Render-Pfad (body) wird sauberer; weniger Risiko “Fetch/Heavy work im body”.

- `BrainMesh/Icons/AllSFSymbolsPickerView.swift`
  - Split:
    - View (UI)
    - VM/Loader (Paging/Search Engine) als eigene Einheit
  - Nutzen: Paging/Search testbarer; View bleibt klein.

### 2) Derived Work in `body` cachen / in Adapter auslagern (Medium Risk, guter Perf-Win)
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - Problem: `fields.map(...)` + `DetailsFormatting.displayValue(...)` wird oft neu berechnet.
  - Option: kleines Cache-Objekt (Key: AttributeID + OwnerID + Schema-Revision).
  - Nutzen: weniger CPU beim Tippen/Sheet-Wechsel.

### 3) Unbounded `@Query`-Collections → explizites Paging (Medium Risk, hoher Payoff)
- Kandidaten:
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift` (UI zeigt `prefix(12)`, aber `@Query` kann mehr laden)
  - `BrainMesh/Attachments/AttachmentsSection.swift` (unbounded `@Query`)
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`
- Ansatz:
  - Loader-Actor + `fetchLimit` + Cursor/Offset (ähnlich wie `NodeImagesManageView` Paging: `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`).
- Nutzen: planbarer Memory, stabiler Scroll, weniger “load storms”.

### 4) GraphCanvas Guardrails statt “Big Bang”-Perf-Work (Performance-sensitiv)
- Bereits gesplittet: `GraphCanvasScreen` Partials + `GraphCanvasDataLoader` Partials.
- Nächste (low risk) Schritte:
  - Sicherstellen, dass *jede* Load/Expand Task Cancellation + Stale-Guard hat (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Expand.swift`).
  - Derived-State strikt getrennt halten (bereits in `GraphCanvasScreen+DerivedState.swift`).
- Später (higher risk):
  - Pair-Loop optimieren (Spatial Hash/Grid Binning) in `GraphCanvasView+Physics.swift`.

## Cache-/Index-Ideen (basierend auf aktuellem Code)
- **Links pro Node Index**
  - Links sind raw IDs (`MetaLink.sourceID/targetID` in `BrainMesh/Models/MetaLink.swift`).
  - Idee: Loader-seitiger In-Memory Index (Key: graphID + nodeID) mit TTL.
  - Risiko: Invalidations (Create/Delete/Import) müssen sauber broadcasted werden.

- **Attachment Thumbnail Pipeline**
  - `AttachmentThumbnailStore` existiert (`BrainMesh/Attachments/AttachmentThumbnailStore.swift`).
  - Empfehlung: analog zu `ImageStore` In-Flight De-Dupe (`BrainMesh/ImageStore.swift`) für Thumbnails konsequent nutzen.

## Vereinheitlichungen (Patterns)
- Loader-Pattern: Actor + `configure(container:)` + background `ModelContext` + `Task.checkCancellation()`
  - Referenzen:
    - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
    - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift`
- View-Tasks: Debounce + Cancellation + Stale-Guard standardisieren (Helper statt Copy/Paste).
- Graph Scoping (`graphID`): Regeln an einer Stelle dokumentieren; in Create-Flows enforced.

## Risiken & Edge Cases
- **Import Datenintegrität**
  - Import Core ist groß: `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
  - Tests existieren: `BrainMeshTests/GraphTransferRoundtripTests.swift`
  - Edge Cases: partial import, duplicate IDs, dangling endpoints, replace-mode collisions.
- **Auto-Lock vs System Pickers**
  - `BrainMesh/AppRootView.swift` debounced background lock (Photos/FaceID Edge Case).
  - Jede Änderung hier braucht reale Device-Tests mit Fotos-Picker/Hidden Album.
- **CloudKit Fallback**
  - Local-only fallback kann “split-brain” erzeugen, wenn später iCloud wieder aktiv ist (UX-Frage).
- **Sehr große Graphen**
  - Physik skaliert quadratisch → Limits und klare Feedback-Mechanik sind Pflicht (Limits werden bereits an Loader übergeben, z.B. `GraphCanvasDataLoader.loadSnapshot`).

## Observability / Debuggability
- Logger: `BMLog.load`, `BMLog.expand`, `BMLog.physics` (`BrainMesh/Observability/BMObservability.swift`).
- GraphCanvas Physik loggt Rolling-Window Stats: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`.
- Empfehlung: Settings Toggle “Verbose Performance Logs” + “Last Loader Durations”.

## Open Questions (alles **UNKNOWN**)
- Info.plist: Wird bewusst generiert? Wo werden produktive Keys (z.B. Pro IDs) gesetzt? (**UNKNOWN**, siehe `GENERATE_INFOPLIST_FILE` in `BrainMesh.xcodeproj/project.pbxproj` vs `BrainMesh/Pro/ProEntitlementStore.swift`)
- Collaboration: gibt es geplante Sharing-Flows (CloudKit shared DB)? In diesem ZIP nicht sichtbar (**UNKNOWN**).
- Ziel-Datensatzgröße: welche “Max”-Größen sollen UX-seitig enforced werden (über Loader-Limits hinaus)? (**UNKNOWN**).

## First 3 Refactors I would do (P0)

### P0.1 — `EntitiesHomeView` split (mechanisch)
- **Ziel**: Merge-Konflikte reduzieren, Task/Reload Logik auditierbar machen.
- **Betroffene Dateien**:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - neu: `EntitiesHomeView+Body.swift`, `EntitiesHomeView+Loading.swift`, `EntitiesHomeView+Toolbar.swift`
- **Risiko**: Niedrig (move-only).
- **Erwarteter Nutzen**: bessere Lesbarkeit, Grundlage für spätere Perf-Arbeit (Debounce/Cancellation).

### P0.2 — Guardrails gegen unbounded Loads (Galerie/Anhänge)
- **Ziel**: Detail-Screens dürfen nicht “aus Versehen” 1000+ Attachments ins Memory ziehen.
- **Betroffene Dateien (Startpunkt)**:
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/Attachments/AttachmentsSection.swift`
- **Risiko**: Niedrig→Mittel (Paging/FetchLimit verändert Verhalten; erst “Show more” + Limits).
- **Erwarteter Nutzen**: stabiler Memory, smoother Scroll, weniger Load-Stürme.

### P0.3 — `NodeDetailsValuesCard` Derived Work cachen
- **Ziel**: Mapping `fields → displayValue` nicht bei jeder Invalidierung neu rechnen.
- **Betroffene Dateien**:
  - `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - `BrainMesh/Mainscreen/Details/DetailsFormatting.swift` (falls Bulk-API sinnvoll)
- **Risiko**: Niedrig (rein UI-Ableitung).
- **Erwarteter Nutzen**: weniger Micro-Stutter beim Tippen/Sheet-Wechsel.
