# ARCHITECTURE_NOTES

> Stand: 2026-02-18 (basierend auf Repository-Inhalt im ZIP)

## Big Files List (Top 15 Swift-Dateien nach Zeilen)
> Hinweis: Hier sind **Swift Source Files** gelistet (nicht pbxproj/Assets). Zeilenzahlen sind aus dem ZIP gezählt.

| # | Datei | Zeilen | Grober Zweck | Warum riskant |
|---:|---|---:|---|---|
| 1 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | 532 |  |  |
| 2 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 411 |  |  |
| 3 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 408 |  |  |
| 4 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 |  |  |
| 5 | `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` | 361 |  |  |
| 6 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 360 |  |  |
| 7 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 359 |  |  |
| 8 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | 357 |  |  |
| 9 | `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | 348 |  |  |
| 10 | `BrainMesh/Mainscreen/BulkLinkView.swift` | 346 |  |  |
| 11 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | 342 |  |  |
| 12 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | 319 |  |  |
| 13 | `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` | 316 |  |  |
| 14 | `BrainMesh/Icons/IconPickerView.swift` | 309 |  |  |
| 15 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` | 305 |  |  |

### Kurzkommentare zu Zweck/Risiko (konkret)
1. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (532)
   - Zweck: Rendering-Logik + per-frame caches für Canvas (`FrameCache`, label offsets, notes) — siehe File-Header.
   - Risiko: Renderpfad ist Hot Path; große Datei → Compile-Zeit + höheres Risiko für View-Invalidation/Alloc-Spikes.
2. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (411)
   - Zweck: Off-main Snapshot Load für Canvas (SwiftData fetch + Snapshot DTO).
   - Risiko: Fetch/Join-Logik und Snapshotgröße können bei großen Graphen CPU/Memory treiben.
3. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (408)
   - Zweck: Management UI für Medien/Galerie in Detail-Screens.
   - Risiko: Kombiniert UI + Lade-/Aktionen; Scroll/Thumb path kann teuer werden.
4. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` (394)
   - Zweck: Verbindungen (Links) UI für Entity/Attribute.
   - Risiko: Viele Links → lange Listen; Gefahr von heavy sort / zu vielen State-Updates.
5. `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` (361)
   - Zweck: UI-Bausteine für Stats.
   - Risiko: Komponenten-Sammelbecken → Compile-Zeit und unklare Ownership.
6. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` (360)
   - Zweck: Galerie-Grid/Presentation für Detail-Views (MetaAttachment.galleryImage).
   - Risiko: Thumb pipeline + Layout invalidations (adaptive columns, size changes).
7. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` (359)
   - Zweck: Shared UI building blocks, anchors/pills etc.
   - Risiko: zentrale Datei, viele Abhängigkeiten → "kleine Änderung, großer Rebuild".
8. `BrainMesh/Icons/AllSFSymbolsPickerView.swift` (357)
   - Zweck: "Alle SF Symbols…" Picker (potenziell sehr viele Items).
   - Risiko: großer Datenbestand + Search/Filter; wenn nicht strikt lazy → Startup/Memory risk.
9. `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (348)
   - Zweck: Screen-Level State + Routing für Canvas (Graph selection, focus, overlays, etc.).
   - Risiko: viele States → View invalidation; falsche State-Granularität macht Canvas janky.
10. `BrainMesh/Mainscreen/BulkLinkView.swift` (346)
   - Zweck: Bulk-Linking Flow.
   - Risiko: kann große Node-Mengen betreffen → Picker/Fetch/Filtering Hot Path.
11. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` (342)
   - Zweck: Detail-Galerie Section (Attachment contentKind == `.galleryImage`).
   - Risiko: Thumb generation + sheet navigation; große Datenmenge.
12. `BrainMesh/Onboarding/OnboardingSheetView.swift` (319)
   - Zweck: Onboarding Host + Step routing.
   - Risiko: meist niedrig; aber Präsentation kann scenePhase/lock interagieren.
13. `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` (316)
   - Zweck: Browser/Grid für Galerie.
   - Risiko: Scroll performance + thumb caching.
14. `BrainMesh/Icons/IconPickerView.swift` (309)
   - Zweck: Kuratierter Icon Picker + Recents.
   - Risiko: moderat; watch for search/filter allocations.
15. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` (305)
   - Zweck: Highlights/Badges für Details.
   - Risiko: niedrig–moderat (meist Layout/Style).

## Hot Path Analyse

### Rendering / Scrolling
**1) Graph Canvas Physics Loop**
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView.swift`
- Warum Hotspot:
  - Timer-basierte Simulation (`Timer.scheduledTimer` @ 30 FPS) → kontinuierliche CPU-Last.
  - Repulsion/Spring/Collision (typisch O(n²) bei repulsion, abhängig von Implementation in `stepSimulation()`).
  - Viele Dictionary-Lookups (`positions`, `velocities` keyed by `NodeKey`) im Tick → potentiell overhead.
- Risiko/Edge:
  - Große Graphen (Nodes/Edges) können Frames droppen.
  - Wenn `positions`/`velocities` häufig neu kopiert werden (value semantics), kann es zu massiven Copies kommen.

**2) Graph Canvas Rendering**
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- Warum Hotspot:
  - Rendering hängt direkt an `@State` (`positions`, `scale`, `pan`, `selection` etc.).
  - FrameCache baut Dictionaries pro Frame (siehe Headerkommentar).
  - Gefahr von exzessiver View-Invalidation, wenn State zu grob ist oder zu viel im Body hängt.

**3) Attachments / Thumbnails in Listen/Grids**
- Datei: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Warum Hotspot:
  - QuickLookThumbnailing und AVFoundation-Frame extraction sind teuer.
  - Limiter + in-flight dedupe vorhanden (`AsyncLimiter(maxConcurrent: 3)`) → gut.
  - Trotzdem: große Listen → Disk cache pressure + memory cache pressure.

**4) Node Detail: Connections & Media**
- Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
- Warum Hotspot:
  - Viele Links → Sorting + cell work + häufige Updates.
  - Viele `@State`-basierte Sheets können Recomposition triggern.

**5) Home Search (Typing)**
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
- Warum Hotspot:
  - Häufige `.task(id:)` Trigger bei Search/Graph switch.
  - Counts cache TTL ist kurz; gut gegen N+1, aber Fetch/Sort bleibt relevant.

### Sync / Storage
**SwiftData + CloudKit**
- Datei: `BrainMesh/BrainMeshApp.swift`
- Fakten:
  - `ModelConfiguration(... cloudKitDatabase: .automatic)` → Sync in private DB.
  - Release-Fallback auf local-only bei Containerfehler.
- Hotspots:
  - externalStorage Attachments + OR-Predicates → in-memory filtering (explizit in `AttachmentGraphIDMigration.swift` kommentiert).
  - Startup-Migration auf MainActor (`GraphBootstrap.swift` via `AppRootView.bootstrapGraphing()`).

**Hydrators**
- Dateien:
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
- Warum Hotspot:
  - externalStorage reads + disk writes.
  - Limiter vorhanden; Auto-Hydration gedrosselt (24h) in `AppRootView.swift`.

### Concurrency
- `AnyModelContainer` ist `@unchecked Sendable` (definiert in `BrainMesh/Attachments/AttachmentHydrator.swift`).
- Detached `configure(...)` Calls im App init (`BrainMesh/BrainMeshApp.swift`).
- Risiken:
  - `@unchecked Sendable` braucht Audit (Korrektheit hängt an SwiftData Contracts).
  - Detached tasks sind nicht scene-gebunden; sie laufen potenziell weiter, wenn UI weg ist.
  - Cancellation: `.task(id:)` und `Task.sleep` sind cancellable; detached workers nicht automatisch.

## Refactor Map
### Konkrete Splits
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` →
  - `GraphCanvasView+Rendering.FrameCache.swift`
  - `GraphCanvasView+Rendering.LabelPlacement.swift`
  - `GraphCanvasView+Rendering.Notes.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` →
  - `NodeImagesManageView.swift` (Host)
  - `NodeImagesManageView+Grid.swift`
  - `NodeImagesManageView+Actions.swift`
- `BrainMesh/Mainscreen/BulkLinkView.swift` →
  - `BulkLinkView.swift` (Host)
  - `BulkLinkView+Selection.swift`
  - `BulkLinkView+Actions.swift`

### Cache-/Index-Ideen
- Canvas snapshot caches (label/icon/imagePath) in `GraphCanvasDataLoader.swift`: prüfen, ob incremental updates möglich sind (z.B. Icon ändern ohne full reload).
- Thumbnail Disk-Cache: eigener “Clear thumbnails cache” Button (Settings) + optional Größenlimit.
- `*Folded` Felder: sicherstellen, dass Search überall diese nutzt (statt runtime folding).

### Vereinheitlichungen
- `AsyncLimiter` extrahieren nach `BrainMesh/Support/AsyncLimiter.swift`.
- `AnyModelContainer` extrahieren nach `BrainMesh/Support/SwiftDataContainerBridge.swift`.
- Optional: `Bootstrap.configureBackgroundWorkers(container:)` um `BrainMeshApp.swift` init zu entlasten.

## Risiken & Edge Cases
- Migrationen (`GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`) sind correctness-kritisch; Fehler zeigen sich als "Daten weg" (eigentlich nur falsch gefiltert).
- Erststart ohne Cache: Hydrators/Thumbnails brauchen Zeit; UI sollte Cache misses gut darstellen (Placeholder).
- CloudKit Record Size: `imageData` muss klein bleiben; Attachments sind externalStorage (ok).
- ScenePhase/FaceID: `SystemModalCoordinator.swift` schützt vor Picker-Resets während FaceID prompts.

## Observability/Debuggability
- `BrainMesh/Observability/BMObservability.swift`: Logger + `BMDuration`.
- Empfehlung:
  - Duration logs um Thumbnail generation / Canvas load / Expand BFS erweitern (Debug only).
  - Repro-Checklisten in einem DEV_NOTES.md (optional).

## Open Questions (UNKNOWN)
- Dataset-Größen & Zielgeräte (iPhone SE vs Pro Max) sind unbekannt → Performance-Budgets schwer zu setzen.
- Sharing/Collab: keine CKShare-Layer gefunden (aktuell private DB).
- Entity/Attribute Lock Fields: existieren im Model, aber UI nutzt nur Graph-Lock.
- Test-Coverage der Migration/Loader: nicht analysiert (kann ergänzt werden).

## First 3 Refactors I would do (P0)
### P0.1 — Utilities konsolidieren (AsyncLimiter + AnyModelContainer)
- **Ziel:** Utilities sind aktuell in Feature-Dateien "versteckt"; Reuse/Ownership verbessern.
- **Betroffene Dateien:**
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Neu: `BrainMesh/Support/AsyncLimiter.swift`, `BrainMesh/Support/SwiftDataContainerBridge.swift`
- **Risiko:** niedrig.
- **Erwarteter Nutzen:** Klarheit + schnellere Navigation im Code + weniger Coupling.

### P0.2 — NodeImagesManageView split
- **Ziel:** Wartbarkeit + gezieltere Performance-Tuning-Punkte im Medien-Management.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - optional: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- **Risiko:** niedrig–mittel.
- **Erwarteter Nutzen:** geringere Compile-Zeit, weniger Merge-Konflikte, saubere Ownership.

### P0.3 — GraphCanvas Rendering modularisieren
- **Ziel:** Render-Hot-Path isolieren, safer edits, besseres Profiling.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - optional: `BrainMesh/GraphCanvas/GraphCanvasView.swift`
- **Risiko:** mittel.
- **Erwarteter Nutzen:** bessere Wartbarkeit + einfacher, gezielt zu optimieren.