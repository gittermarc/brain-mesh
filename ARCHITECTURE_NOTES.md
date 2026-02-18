# ARCHITECTURE_NOTES.md

> Ziel: technische Detailnotizen zu Risiken, Hotspots, Tradeoffs und konkreten Refactor-Hebeln.

## 0) Scope / Annahmen
- Analysebasis: SwiftUI + SwiftData Projekt "BrainMesh" im Zip.
- Alles was nicht eindeutig im Code steht ist als **UNKNOWN** markiert und am Ende gesammelt.

---

## 1) Big Files List (Top 15 nach Zeilen)

(automatisch aus dem Repo gezogen; Zeilenanzahl ist `wc -l`)

- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` — **689** lines
- `BrainMesh/Stats/StatsComponents.swift` — **580** lines
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` — **532** lines
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **407** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **394** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **360** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **359** lines
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` — **348** lines
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **342** lines
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **325** lines
- `BrainMesh/Onboarding/OnboardingSheetView.swift` — **319** lines
- `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — **316** lines
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` — **305** lines
- `BrainMesh/Mainscreen/EntitiesHomeView.swift` — **299** lines


### Warum große Dateien riskant sind
- SwiftUI: große `body`/View-Kompositionen → hohe Compile-Zeit, schwer zu testen/ändern.
- Viele Responsibilities in einer Datei → mehr Coupling, mehr Regressions.
- Oft liegen in großen Dateien auch UI + Fetch/State + Sheet-Navigation durcheinander.

---

## 2) Hot Path Analyse

### 2.1 Rendering / Scrolling

#### GraphCanvas Rendering
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (sehr groß)
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift` (Timer/Simulation)
  - `BrainMesh/GraphCanvas/GraphCanvasView+Gestures.swift`
  - `BrainMesh/GraphCanvas/MiniMapView.swift`
- Gründe (Hotspot):
  - **30 FPS Timer** (`Timer.scheduledTimer(withTimeInterval: 1/30, ...)`) treibt `stepSimulation()` → potentiell hoher CPU‑Druck, besonders bei vielen Nodes/Edges. (`GraphCanvasView+Physics.swift`)
  - Pair‑Loop Repulsion O(n²) (optimiert auf i<j, aber bleibt quadratisch); es gibt zwar "Spotlight relevant" Filter, aber worst-case bleibt teuer.
  - Canvas/Path-Rendering kann bei vielen Edges GPU/CPU belasten; invalidations sind teuer, wenn State-Maps (`positions`, `velocities`) häufig mutieren.

#### Thumbnails / Media Grids
- Dateien:
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Gründe (Hotspot):
  - Viele `.task(id:)` pro Tile → potentiell Hunderte parallel startende Tasks.
  - Gute Gegenmaßnahmen sind vorhanden:
    - `AttachmentThumbnailStore` hat `inFlight` Dedupe + `AsyncLimiter(maxConcurrent: 3)` (throttling).
  - **Risiko bleibt**: Disk I/O + QuickLook + Video Frame Generation sind teuer; UI kann stottern, wenn MainActor zu oft `thumbnail = img` setzt.

#### EntitiesHome (Search)
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
- Gründe (Hotspot):
  - Search wird on-change getriggert → viele Reloads.
  - Gute Gegenmaßnahme: `EntitiesHomeLoader` lädt off-main und liefert Snapshot‑Arrays.
  - Offene Kante: **Debounce** / Cancelation Dedupe im View (teilweise vorhanden; prüfen).

---

### 2.2 Sync / Storage

#### SwiftData + CloudKit
- Datei: `BrainMesh/BrainMeshApp.swift`
- Verhalten:
  - `ModelConfiguration(..., cloudKitDatabase: .automatic)` → private CloudKit DB.
  - In Release Fallback auf lokal ohne CloudKit.
- Hotspot/Tradeoffs:
  - **External storage** (`MetaAttachment.fileData`) + CloudKit Assets kann in großen Datenmengen zu:
    - langsamen Syncs
    - erhöhtem Speicher/Netzwerk
    - potenziellen Limits führen (**UNKNOWN** genaue Limits/Fehlerbilder).

#### Attachment Preview / Hydration
- Dateien:
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/Attachments/MediaAllLoader.swift`
  - `BrainMesh/Attachments/AttachmentStore.swift`
- Gründe (Hotspot):
  - `fileData` kann groß sein; Laden triggert Disk Write in App Support.
  - Gute Gegenmaßnahmen:
    - Hydrator arbeitet off-main, mit limiter/throttle.
    - `MediaAllLoader` vermeidet in Predicates OR/Optional-Tricks (wichtig für store translation).

---

### 2.3 Concurrency / MainActor Contention

#### Off-main Loader Pattern (gut, aber mit Fallstricken)
- Pattern:
  - `actor` hält `AnyModelContainer`.
  - `Task.detached` erstellt neuen `ModelContext`, `autosaveEnabled = false`.
  - Ergebnis als DTO/Snapshot → UI committet "in einem Rutsch".
- Dateien (Beispiele):
  - `GraphCanvasDataLoader`, `GraphStatsLoader`, `EntitiesHomeLoader`, `NodePickerLoader`, `NodeConnectionsLoader`, `MediaAllLoader`
- Risiken:
  - **@unchecked Sendable** Snapshots (`GraphCanvasSnapshot`, `GraphStatsSnapshot`): korrekt, solange nur Value Types drin sind. Bei Änderungen schnell gefährlich.
  - Cancellation: manchmal geprüft (`Task.checkCancellation()`), manchmal nicht überall.
  - Doppelte Loads: wenn UI schnell wechselt (Graph wechseln, Search tippen) → alte Tasks können später state überschreiben, wenn nicht "commit-atomic".
    - GraphCanvas commit ist sauber in `GraphCanvasScreen+Loading.swift`.
    - Stats nutzt `loadTask?.cancel()`.

#### MainActor heavy Work
- `AppRootView.swift`
  - `scenePhase` Handling + GraphLock + Onboarding + Modal tracking.
  - Gefahr: zu viele side effects auf `scenePhase` Wechseln (besonders mit transient background during FaceID).

---

## 3) Refactor Map

### 3.1 Konkrete Splits (hoher Nutzen, geringes Risiko)

#### A) `NodeDetailShared+SheetsSupport.swift` zerlegen
- Ist aktuell die größte Datei (Top 1).
- Symptome:
  - Sheet/Navigation/State-Management gebündelt → schwer zu ändern.
  - Compile-time bremst.
- Vorschlag (Dateien):
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` → split into:
    - `NodeDetailShared+Sheets.Core.swift` (state, routing enum, entry points)
    - `NodeDetailShared+Sheets.Media.swift` (Media/Gallery sheets)
    - `NodeDetailShared+Sheets.Attachments.swift` (Attachment manage + preview)
    - `NodeDetailShared+Sheets.Links.swift` (AddLink/BulkLink/Connections)
    - `NodeDetailShared+Sheets.Helpers.swift` (small builders)
- Risiko: **low** (reiner Move + kleinere API Anpassungen).

#### B) `StatsComponents.swift` in Komponentenfiles
- Datei: `BrainMesh/Stats/StatsComponents.swift`
- Vorschlag:
  - `StatsComponents+Cards.swift`, `StatsComponents+Charts.swift`, `StatsComponents+Typography.swift`
- Risiko: low.

#### C) PhotoGallery Browser: UI vs Loading trennen
- Dateien: `PhotoGalleryBrowserView.swift`, `PhotoGallerySection.swift`
- Vorschlag:
  - Thumbnail loading helper / view model herausziehen (dedupe, cancellation).
- Risiko: low-medium (UI behavior).

---

### 3.2 Cache-/Index-Ideen (wenn Daten wachsen)

#### Link Counts / Attribute Counts (Anti N+1)
- Problem: in Listen pro Row `entity.attributesList.count` oder Link count zu berechnen → kann N+1 triggern.
- Lösung (bereits als PR-Idee erwähnt):
  - Batch count fetch (Dictionary über IDs) + in Row nur lookup.
- Relevante Datei: `EntitiesHomeView.swift` (Row UI) + Loader (`EntitiesHomeLoader.swift`).

#### GraphCanvas neighborhood: `Array.contains` in Predicates
- Datei: `GraphCanvasDataLoader.swift`
- Problem:
  - Predicates wie `entityIDs.contains(e.id)` und `(visibleIDs.contains(l.sourceID) || ...)` können je nach SwiftData Übersetzung **in-memory filtering** auslösen.
  - Da Loader off-main läuft, blockt es nicht die UI direkt, kann aber trotzdem sehr teuer werden.
- Optionen:
  - Begrenzung: maxNodes ist klein (default 140), daher in Praxis evtl. ok.
  - Alternativ: 2‑Stufen fetch (IDs→fetch by graphID + in-memory filter) mit strengem fetchLimit.
  - Oder eigene "EdgeIndex" Tabelle (**bigger change**).

---

### 3.3 Vereinheitlichungen (Patterns/DI)
- Loader konfigurieren:
  - Aktuell in `BrainMeshApp.init()` mehrfach `Task.detached { await X.shared.configure(container:) }`.
  - Vorschlag: zentraler `AppServices`/`LoaderRegistry` der das bündelt.
  - Nutzen: weniger Boilerplate, weniger Race-Risiko (Loader not configured).
- Logging:
  - `BMLog` ist gut; evtl. Kategorien erweitern (sync, thumbnails, attachments).

---

## 4) Risiken & Edge Cases
- Datenverlust-Risiko:
  - Attachment Cache ist nur Preview. Aber `fileData` selbst ist im SwiftData Store.
  - Migrationen (`GraphBootstrap`, `AttachmentGraphIDMigration`) laufen "best effort" (try? / ignore errors) → Gefahr: still failing.
- Offline:
  - UI scheint nicht explizit Offline‑State zu zeigen.
- Multi‑Device:
  - Graph Lock State sync't vermutlich über CloudKit (Model Feld), aber Schutz/Keying ist **UNKNOWN**.
- Performance:
  - GraphCanvas O(n²) Physik: bei großen Graphen kann das trotz idle sleep zu CPU-Spikes führen.

---

## 5) Observability / Debuggability
- Logger/Timing:
  - `BrainMesh/Observability/BMObservability.swift` (`BMLog`, `BMDuration`).
  - GraphCanvas loggt loadGraph ms und Physics rolling window.
- Repro Hinweise (praktisch):
  - GraphCanvas: Node/Edge Counts hochziehen (>= 1k edges) → CPU/scroll check.
  - Media: 200+ Attachments in einem Owner → Thumbnail throttling check.
  - EntitiesHome: 10k Entities → Search tippen, prüfen ob UI "butterweich".

---

## 6) Open Questions (UNKNOWN)
- SwiftData/CloudKit Konfliktauflösung (Merge Policy, last-writer-wins?)
- CloudKit Asset Limits / Verhalten bei sehr großen Attachments
- Security: Passcode Hashing/Key storage (Keychain?) für Graph Lock
- Background remote-notification: wird es aktiv genutzt oder nur für CloudKit? (kein expliziter Push code gefunden)
- Unit/UI Test Coverage: **UNKNOWN** (Tests existieren als Targets, Inhalte nicht geprüft)

---

## 7) First 3 Refactors I would do (P0)

### P0.1 — Split: NodeDetailShared Sheets Support
- **Ziel:** Compile-Time runter, Verantwortlichkeiten trennen, weniger Regressions beim Sheet-Navigation ändern.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift`
  - plus neue Files wie `NodeDetailShared+Sheets.*.swift`
- **Risiko:** low (mechanischer Split, keine Logikänderung)
- **Erwarteter Nutzen:** hoch (Wartbarkeit + schnelleres iterieren im Detail-Screen)

### P0.2 — EntitiesHome: Counts/Badges ohne N+1
- **Ziel:** Home Listing bleibt schnell bei großen DBs; keine Relationship-Counts pro Row.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
- **Risiko:** low (UI bleibt gleich; nur Datenaufbereitung)
- **Erwarteter Nutzen:** hoch (Scroll + Search + Rendering stabil)

### P0.3 — GraphCanvas neighborhood predicates audit + guardrails
- **Ziel:** Verhindern, dass SwiftData bei `Array.contains` Predicates in In‑Memory Filtering fällt.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Risiko:** medium (falscher Umbau kann Ergebnis ändern oder mehr DB calls erzeugen)
- **Erwarteter Nutzen:** mittel bis hoch (bei sehr großen Link-Tabellen)
