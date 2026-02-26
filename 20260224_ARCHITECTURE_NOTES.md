# ARCHITECTURE_NOTES.md

## Scope & Leitplanken
- Quelle: Code-Scan des ZIP (keine externe Doku).
- Fokus-Priorität: **(1) Sync/Storage/Model**, **(2) Entry Points + Navigation**, **(3) große Views/Services**, **(4) Workflows/Conventions**.
- Regel: Alles, was ich nicht eindeutig im Code gesehen habe, ist **UNKNOWN** und landet in „Open Questions“.

---

## Architecture Snapshot (in 60 Sekunden)
- **Entry**: `BrainMesh/BrainMesh/BrainMeshApp.swift` erstellt SwiftData `ModelContainer` mit CloudKit (`cloudKitDatabase: .automatic`) und hängt ihn via `.modelContainer(...)` an.
- **Root**: `BrainMesh/BrainMesh/AppRootView.swift` kapselt Startup‑Tasks + Lock/Onboarding + ScenePhase‑Handling (inkl. Debounce‑Lock, um Photos/FaceID‑Picker nicht zu unterbrechen).
- **Main Navigation**: `BrainMesh/BrainMesh/ContentView.swift` → `TabView` (Entities / Graph / Stats / Settings).
- **Performance Pattern**: Off‑main Loader/Services liefern Snapshot‑DTOs; Konfiguration zentral in `BrainMesh/BrainMesh/Support/AppLoadersConfigurator.swift`.

---

## Big Files List (Top 15 nach Zeilen)
> Warum das relevant ist: große Dateien sind Merge‑Hotspots, erhöhen Compile‑Time und machen „kleine Änderungen“ riskanter (seiteneffekt‑reich).

| # | Pfad | Zeilen |
|---:|---|---:|
| 1 | `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` | 635 |
| 2 | `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | 532 |
| 3 | `BrainMesh/BrainMesh/Onboarding/OnboardingSheetView.swift` | 504 |
| 4 | `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 491 |
| 5 | `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 411 |
| 6 | `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 |
| 7 | `BrainMesh/BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` | 401 |
| 8 | `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 |
| 9 | `BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | 388 |
| 10 | `BrainMesh/BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | 388 |
| 11 | `BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | 381 |
| 12 | `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 362 |
| 13 | `BrainMesh/BrainMesh/Icons/AllSFSymbolsPickerView.swift` | 357 |
| 14 | `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | 356 |
| 15 | `BrainMesh/BrainMesh/Mainscreen/BulkLinkView.swift` | 346 |

### Kurzkommentar pro Datei (Zweck + Risiko)
1. `.../EntityAttributesAllListModel.swift`  
   Zweck: Snapshot‑Model für „Entity → All Attributes“ (Row building, Search‑Index, pinned chips, Sort).  
   Risiko: viele Zustände/Cache‑Branching + SwiftData Lookups; kleine Änderungen können Sort/Filter/Pinning ungewollt beeinflussen.
2. `.../GraphCanvasView+Rendering.swift`  
   Zweck: per‑Frame Rendering (Canvas) inkl. Edge/Node Drawing, Labels, Notes, FrameCaches.  
   Risiko: Hot path pro Frame; jede zusätzliche Berechnung skaliert mit `nodes * edges`.
3. `.../OnboardingSheetView.swift`  
   Zweck: komplettes Onboarding‑UI/Flow in einer Datei.  
   Risiko: UI‑Kopplung, schwer testbar, Merge‑Konflikte.
4. `.../NodeDetailShared+Core.swift`  
   Zweck: Shared Detail‑UI (Hero Card etc.).  
   Risiko: viele UI concerns + Media/Async‑Loading; Änderungen wirken auf Entity- und Attribute‑Detail.
5. `.../GraphCanvasDataLoader.swift`  
   Zweck: heavy fetch + BFS Neighborhood Load, off-main, Budgets.  
   Risiko: Query/Predicate‑Änderungen können DB‑Kosten massiv ändern; BFS‑Budget/Cancel muss stabil bleiben.
6. `.../NodeImagesManageView.swift`  
   Zweck: Bilder verwalten (Picker, Gallery, Import/Compression/Edgecases).  
   Risiko: iOS System Picker Edgecases + potentiell großer Memory/Disk IO.
7. `.../AttributeDetailView.swift`  
   Zweck: Attribute‑Detail‑Screen (Notes/Details/Media/Connections).  
   Risiko: viele Sheets/Sections; leichtes „state explosion“.
8. `.../NodeDetailShared+Connections.swift`  
   Zweck: Connections‑UI + navigation into link creation etc.  
   Risiko: viele List/Query/Action paths.
9. `.../EntitiesHomeView.swift`  
   Zweck: Root Liste + Search + Graph Picker + Display options.  
   Risiko: sehr häufig geöffnet; state/loader integration muss „smooth“ bleiben.
10. `.../NodeDetailsValuesCard.swift`  
    Zweck: Details‑Werte UI (Edit, Chips, pinned).  
    Risiko: Binding-/Sheet‑Komplexität, „heikle Schema‑Mutationen“ (Field defs vs values).
11. `.../EntitiesHomeLoader.swift`  
    Zweck: off-main Snapshot Loader (Search, counts, notes preview).  
    Risiko: Query‑Kosten/Predicate‑Änderungen können UI‑Typing stallen (trotz off-main).
12. `.../NodeDetailShared+MediaGallery.swift`  
    Zweck: Media gallery UI.  
    Risiko: Thumb decode + scroll perf.
13. `.../AllSFSymbolsPickerView.swift`  
    Zweck: großer Icon Picker (viele Items).  
    Risiko: Render/Scroll load + Search perf.
14. `.../GraphCanvasScreen.swift`  
    Zweck: Graph tab state machine (loads, inspector, selection, sheets).  
    Risiko: viele interagierende States; leichtes Regression‑Risiko.
15. `.../BulkLinkView.swift`  
    Zweck: Bulk link creation UI.  
    Risiko: potentially large lists + multi-selection state.

---

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI)
#### Graph Canvas (primärer Render-Hotspot)
**Files**
- `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift`

**Warum Hotspot**
- `GraphCanvasView.renderCanvas(...)` iteriert pro Frame über `drawEdges` und `nodes` und baut/drawt `Path` + `Text` Labels.  
  → Kosten skalieren mit Graphgröße, und laufen *während* Physik/Interaction.
- `GraphCanvasScreen` ändert `positions/velocities` häufig (Physik‑Ticks). Das triggert viele Re-renders; der Screen hält deshalb Derived Caches (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`), um per-render compute zu reduzieren (Kommentar im Code).

**Was schon gut ist**
- Per‑Frame Cache (`FrameCache`) in `GraphCanvasView+Rendering.swift` + vorgezogene Derived State in `GraphCanvasScreen`.
- Budgets (`maxNodes`, `maxLinks`) + Spotlight/Lens reduziert Relevanzset (siehe `GraphCanvasScreen.recomputeDerivedState()`).

**Risiken / Edgecases**
- „Mehr UI“ im Canvas (Badges, zusätzliche Text‑Layouts) skaliert brutal.
- Jede neue Predicate/Loader‑Änderung, die `nodes/edges` stark wachsen lässt, verschlechtert Rendering.

**Konkrete Hebel**
- Mehr Culling: konsequenter `lens.isHidden`/distance‑basiertes „skip label / skip note“.
- Strict Budgeting: `maxNodes/maxLinks` auch als Settings/Perf‑Preset exponieren (teilweise bereits State).
- Rendering‑Split in kleinere, testbare Functions: edges vs nodes vs labels vs notes.

#### Entities Home (häufig geöffnet, scroll/search)
**File**
- `BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`

**Warum potenzieller Hotspot**
- `.task(id: taskToken)` triggert bei Search/Graph/Flags; UI zeigt währenddessen `ProgressView`.  
  Vorteil: Debounce 250ms + off-main loader.
- Sort findet im View statt (`rows = sortOption.apply(to: snapshot.rows)`) – O(n log n) auf MainActor, aber typischerweise akzeptabel, solange `rows` nicht riesig werden.

**Konkrete Hebel**
- Wenn `rows` sehr groß werden: Sort in Loader verschieben oder in 2‑Stufen (prefetch + stable keyed sort). (Nur, falls notwendig.)

---

### 2) Sync / Storage (SwiftData/CloudKit)
#### SwiftData Container + CloudKit Mode
**File**
- `BrainMesh/BrainMesh/BrainMeshApp.swift`

**Was passiert**
- Schema wird explizit aufgebaut und CloudKit aktiviert (`ModelConfiguration(..., cloudKitDatabase: .automatic)`).
- In Debug: CloudKit‑Fehler crashen (`fatalError`).  
- In Release: Fallback auf lokalen Container, `SyncRuntime.storageMode = .localOnly`.

**Warum kritisch**
- Fallback kann zu „scheinbar funktionierendem“ App‑State ohne Sync führen (Divergenz).  
  Das ist teilweise mitigiert via `SyncRuntime` (UI‑Anzeige), aber UX‑Risiko bleibt, wenn User es übersieht.

**Konkrete Hebel**
- StorageMode im UI prominenter (z.B. Banner bei `.localOnly`). (UX‑Entscheidung.)

#### External Storage (Attachments) + Predicate-Fallen
**Files**
- `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`
- `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`

**Warum Hotspot**
- `fileData` ist `.externalStorage`. In-memory filtering (z.B. durch nicht-translatable Predicates) ist laut Kommentar katastrophal.  
- Deshalb existiert eine gezielte Migration: `graphID == nil` Attachments werden auf die aktuelle GraphID gehoben, um AND‑Predicates zu erlauben.

**Konkrete Hebel**
- Audit: alle Attachment‑Fetches auf store‑translatability (kein OR, keine optional‑Tricks).
- Bei neuen Queries: erst `graphID` migrieren (wie bestehend), dann strikt `a.graphID == gid` filtern.

#### Local Cache Hydration (Images/Attachments)
**Files**
- `BrainMesh/BrainMesh/ImageHydrator.swift`
- `BrainMesh/BrainMesh/ImageStore.swift`
- `BrainMesh/BrainMesh/Attachments/AttachmentHydrator.swift` (**UNKNOWN**: nicht im Detail gelesen, aber vorhanden)

**Warum potenzieller Hotspot**
- Hydrator scannt Entities/Attributes mit `imageData != nil` und schreibt deterministische JPEGs auf Disk + setzt `imagePath` (mit `context.save()` wenn changes).
- Bewusst off-main + throttled (run-once-per-launch & min. 24h in `AppRootView`).

**Risiken**
- Große Datenmengen: scan kann lange laufen (wenn viele `imageData != nil`).
- Disk pressure: große Caches (ImageStore hat `cacheSizeBytes()`; das hilft fürs Debugging).

---

### 3) Concurrency / Task Lifetimes
#### Loader Pattern (gut & konsistent)
**Files**
- `BrainMesh/BrainMesh/Support/AppLoadersConfigurator.swift`
- `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- `BrainMesh/BrainMesh/Stats/GraphStatsLoader.swift`
- `BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`

**Was gut ist**
- Background `ModelContext` wird in `Task.detached` erstellt (`context.autosaveEnabled = false`).
- UI bekommt Snapshot DTO (value-only), commit in einem Rutsch.
- Cancellation ist teilweise explizit (z.B. `GraphStatsLoader.loadPerGraphCounts` nutzt `Task.checkCancellation()`).

**Worauf man achten muss**
- Keine `@Model` Instanzen in `Task.detached` übergeben (Hinweis als Kommentar in mehreren Loader‑Files).
- Task‑Multiplikation: UI‑`.task(id:)` + zusätzliche `Task { ... }` Calls können sich überlappen; teure Operationen sollten cancellable sein (gutes Beispiel: `GraphCanvasScreen.loadTask`).

#### AppRoot ScenePhase Debounce (Edgecase‑Fix)
**File**
- `BrainMesh/BrainMesh/AppRootView.swift`

**Konkreter Grund**
- iOS Photos „Hidden Album“ kann FaceID prompten und dabei ScenePhase kurz zu `.background` flippen; sofortiges Lock würde Picker abbrechen.  
  Fix: Debounced lock + grace polling über `systemModals.isSystemModalPresented`.

**Risiko**
- Änderungen an Lock/ScenePhase‑Logik können diesen Fix wieder kaputt machen (Regression = nervig, schwer reproduzierbar).

---

## Refactor Map

### A) Splits (mechanisch, risikoarm)
1) `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` (635 Zeilen)
   - Ziel: Verantwortlichkeiten trennen (Cache, Row builder, Sorting, pinned details, published state).
   - Vorschlag:
     - `EntityAttributesAllListModel.swift` (Facade + Published + scheduleRebuild)
     - `EntityAttributesAllListModel+RowBuilder.swift`
     - `EntityAttributesAllListModel+Sorting.swift`
     - `EntityAttributesAllListModel+Cache.swift`
     - `EntityAttributesAllListModel+Lookups.swift` existiert bereits → beibehalten
2) `BrainMesh/BrainMesh/Onboarding/OnboardingSheetView.swift`
   - Ziel: Sections/Steps als Subviews → weniger Merge‑Konflikte.
3) `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
   - Ziel: Picker/Import Pipeline/Presentation separieren.

### B) Cache-/Index Ideen (mit Invalidation)
> Nur Ideen; nicht als Fakten interpretieren. Wo SwiftData‑Features unklar sind: **UNKNOWN**.

1) Pinned Values: Mehrfach‑Fetch pro pinned field (`EntityAttributesAllListModel+Lookups.fetchPinnedValuesLookup`)
   - Idee: Single fetch über „fieldID in pinnedFieldIDs“ + „attributeID in visibleAttributeIDs“.
   - Invalidation: bei Schema‑Änderung (Fields) oder Value‑Edit.
   - **UNKNOWN**: ob SwiftData Predicate `fieldIDs.contains(v.fieldID)` zuverlässig store‑translatable ist.
2) „Has Media“ Gruppierung: `fetchAttributeOwnersWithMedia` lädt alle Attachments der GraphID + filtert in-memory.
   - Idee A: Predicate auf `ownerID in attributeIDs` (wenn möglich).
   - Idee B: Denormalisiertes Flag `hasMedia` am Attribut (funktional; höheres Risiko).
3) Stats: `attachmentBytes` summiert per Fetch aller Attachments.
   - Idee: Cache `attachmentBytes` pro graphID (revision‑basiert), Invalidations bei Attachment Upsert/Delete.
   - **UNKNOWN**: beste Stelle für Revision Counter im aktuellen Codebase.

### C) Vereinheitlichungen (Patterns/DI)
- Viele `.shared` Singletons (Loader/Hydrator/Stores). Das ist ok, aber:
  - Konvention: jede Singleton‑Komponente hat `configure(container:)` und ist idempotent.
  - Optional: kleine `LoaderRegistry`/`AppServices` Struktur in `Support`, um Abhängigkeiten expliziter zu machen. (**UNKNOWN**: ob gewünscht.)

---

## Risiken & Edge Cases
- **CloudKit init fallback (Release)**: kann still „lokal-only“ werden → Sync‑Divergenz.  
  Files: `BrainMesh/BrainMesh/BrainMeshApp.swift`, `BrainMesh/BrainMesh/Settings/SyncRuntime.swift`.
- **ExternalStorage + Predicates**: OR/optional predicates können in-memory filtering triggern (Attachment‑Blob‑Hölle).  
  File: `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
- **System Picker / FaceID**: ScenePhase‑Debounce ist ein gezielter Fix; nicht kaputt refactoren.  
  File: `BrainMesh/BrainMesh/AppRootView.swift`.
- **Graph Scope Migration**: `GraphBootstrap` migriert Entities/Attributes/Links; Attachments extra; Details‑Models haben `graphID`, aber Migration ist **UNKNOWN**.  
  Files: `BrainMesh/BrainMesh/GraphBootstrap.swift`, `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`, `BrainMesh/BrainMesh/Models/DetailsModels.swift`.

---

## Observability / Debuggability
- Loader nutzen `os.Logger` (`GraphCanvasDataLoader`, `GraphStatsLoader`, `ImageHydrator`, etc.).
- Vorschlag (klein, konkret):
  - Pro Hotspot eine Logger‑Category + optional `signpost` (Graph load, stats compute, hydration pass).
  - Debug‑Menü in Settings (falls vorhanden) wäre nice-to-have, aber **UNKNOWN** ob gewünscht.

---

## Open Questions (UNKNOWN)
- Gibt es eine explizite Push/Notification‑Handling‑Schicht? Info.plist hat `remote-notification`, aber im Code‑Scan keine AppDelegate/UNUserNotificationCenter Hooks gefunden.
- Wie werden Konflikte im SwiftData/CloudKit Sync behandelt/kommuniziert? (Default vs custom.)
- Existieren Telemetry/Analytics (außer `os.Logger`)? Ich sah nur `BrainMesh/BrainMesh/Observability/BMObservability.swift` (klein).
- Haben `MetaDetailFieldDefinition/MetaDetailFieldValue` Legacy‑Daten ohne `graphID`? (Migration unklar.)
- Gibt es iPad-spezifische UI (Split View etc.)? (Nicht explizit gesehen.)

---

## First 3 Refactors I would do (P0)

### P0.1 — Split: EntityAttributesAllListModel (größter Merge-/Compile-Hotspot)
- **Ziel**: Verantwortlichkeiten trennen; Lookups/Sort/Row building isolieren; Regression-Risiko senken.
- **Betroffene Dateien**
  - `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`
  - optional neu: `...+RowBuilder.swift`, `...+Sorting.swift`, `...+Cache.swift`
  - bleibt: `EntityAttributesAllListModel+Lookups.swift`
- **Risiko**: niedrig–mittel (viele UI‑Abhängigkeiten; aber mechanischer Split möglich).
- **Erwarteter Nutzen**: bessere Orientierung + weniger Merge-Konflikte; leichteres Profiling der Lookups.

### P0.2 — Split + Harden: NodeImagesManageView (Picker-Edgecases isolieren)
- **Ziel**: Medien-/Picker‑Flow modularisieren; system picker/FaceID Edgecases lokal halten.
- **Betroffene Dateien**
  - `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - evtl. Mitspieler: `BrainMesh/BrainMesh/ImageHydrator.swift`, `BrainMesh/BrainMesh/ImageStore.swift`, `BrainMesh/BrainMesh/Attachments/*` (nur falls direkte Abhängigkeiten bestehen)
- **Risiko**: mittel (PhotoPicker/Permissions sind „bissig“; Regression sichtbar).
- **Erwarteter Nutzen**: weniger „alles in einer Datei“, sauberere Verantwortlichkeiten, besser testbare Steps.

### P0.3 — Graph Canvas Render-Pipeline weiter isolieren (ohne Verhalten zu ändern)
- **Ziel**: Rendering‑Code in kleinere Units aufteilen + klarere Grenzen zwischen „Compute“ und „Draw“.
- **Betroffene Dateien**
  - `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - optional: weitere Splits (z.B. `+DrawEdges.swift`, `+DrawNodes.swift`, `+Labels.swift`, `+Notes.swift`)
- **Risiko**: niedrig (wenn strikt mechanisch + gleiche Inputs/Outputs).
- **Erwarteter Nutzen**: Hotspot wird besser verständlich; Micro‑Optimierungen werden leichter (z.B. „skip label“ Regeln), weniger Angst vor Änderungen.
