# ARCHITECTURE_NOTES.md

> Fokus: Sync/Storage/Model → Entry Points/Navigation → große Views/Services → Workflows/Refactor.

---

## Big Files List (Top 15 nach Zeilen)

- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift` — **670** Zeilen
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` — **661** Zeilen
- `BrainMesh/Mainscreen/EntityDetail/EntityAttributesAllListModel.swift` — **586** Zeilen
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` — **532** Zeilen
- `BrainMesh/Models.swift` — **515** Zeilen
- `BrainMesh/Onboarding/OnboardingSheetView.swift` — **504** Zeilen
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **491** Zeilen
- `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` — **469** Zeilen
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411** Zeilen
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410** Zeilen
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **397** Zeilen
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **394** Zeilen
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388** Zeilen
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388** Zeilen
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` — **386** Zeilen

Warum riskant (generisch, trifft auf viele dieser Dateien zu):
- große SwiftUI Views → mehr Recompile-Kosten, mehr Merge-Konflikte, schwerere Verantwortlichkeiten
- mehr „hidden work“ in Computed Properties / body-Zweigen
- höheres Risiko, aus Versehen Fetch/Sort/Mapping im Renderpfad zu platzieren

---

## Entry Points + Navigation

### App Start
- `BrainMesh/BrainMeshApp.swift`
  - Erstellt SwiftData Schema + ModelContainer.
  - Setzt `SyncRuntime.storageMode` abhängig von Container-Erfolg.
  - Konfiguriert mehrere Loader/Hydrators via `Task.detached` (utility priority).
  - Injected EnvironmentObjects: `AppearanceStore`, `DisplaySettingsStore`, `OnboardingCoordinator`, `GraphLockCoordinator`, `SystemModalCoordinator`.

### Root Routing
- `BrainMesh/AppRootView.swift`
  - Hostet `ContentView`.
  - ScenePhase Handling:
    - `.active`: Auto-hydrate Images (max 1x/24h), enforce locks, onboarding.
    - `.background`: debounce lock (um Photos Hidden/FaceID transient background zu überleben) → `pendingBackgroundLockTask`.
  - Präsentation:
    - Onboarding: `.sheet(isPresented: $onboarding.isPresented)` → `OnboardingSheetView`.
    - Graph Unlock: `.fullScreenCover(item: $graphLock.activeRequest)` → `GraphUnlockView`.

### Tabs
- `BrainMesh/ContentView.swift`:
  - Entitäten: `EntitiesHomeView`
  - Graph: `GraphCanvasScreen`
  - Stats: `GraphStatsView`
  - Settings: `SettingsView` (in eigenem `NavigationStack`)

---

## Sync / Storage / Model: Hotspots & Tradeoffs

### SwiftData + CloudKit Setup
- `BrainMesh/BrainMeshApp.swift`:
  - CloudKit: `ModelConfiguration(schema:, cloudKitDatabase: .automatic)`.
  - DEBUG: `fatalError` bei Container-Fehler → gut für Dev, aber keine „local-only“ Testpfade.
  - RELEASE: Fallback auf local-only → Risiko: „Sync ist kaputt“ ohne UI-Hinweis; mitigiert durch `SyncRuntime`.

**Tradeoff:**
- Vorteil: CloudKit Sync „for free“ auf Model-Ebene.
- Risiko: Schema-Änderungen/Migrationen sind heikel; `graphID == nil` Altlasten können Query-Performance killen (insbesondere bei externalStorage Data).

### External Storage (Attachments)
- `BrainMesh/Attachments/MetaAttachment.swift`: `fileData` ist `@Attribute(.externalStorage)`.
- Konsequenz:
  - ✅ weniger Druck auf CloudKit record size (Asset-style)
  - ❌ falsche Queries (z.B. OR-Predicates) können SwiftData in in-memory filtering zwingen → potenziell katastrophal, weil `fileData` dann materialisiert wird
- Gegenmaßnahmen in Code:
  - `AttachmentGraphIDMigration` erzwingt „store-translatable“ AND-Predicates (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).
  - `MediaAllLoader` lädt Listen ohne `fileData` zu materialisieren (`BrainMesh/Attachments/MediaAllLoader.swift`).
  - `AttachmentHydrator` materialisiert `fileData` nur bei Bedarf und throttled global (`maxConcurrent: 2`) (`BrainMesh/Attachments/AttachmentHydrator.swift`).

### Disk Caches
- Images: `BrainMesh/ImageStore.swift` (NSCache + Application Support / BrainMeshImages)
- Attachments: `BrainMesh/Attachments/AttachmentStore.swift` (Application Support / BrainMeshAttachments)

**Edge Case:** Cache gelöscht → Hydrators müssen aus SwiftData `Data` erneut materialisieren. Besonders relevant bei großen Medien.

---

## Hot Path Analyse

### Rendering / Scrolling

#### Graph Canvas Render Loop
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- Konkrete Gründe:
  - Per-frame Schleifen über `drawEdges` + `nodes` (Canvas drawing).
  - Pro Frame werden `GraphicsContext.draw(Text(...))`-Operationen für Labels/Icons ausgeführt.
  - `buildFrameCache(...)` baut Dictionaries (`screenPoints`, `labelOffsets`, evtl. notes prefilter) pro Render auf.

**Risiko-Signale:**
- Große Graphen + hohe `maxNodes/maxLinks` (`GraphCanvasScreen.swift`) → FPS drop / Battery.
- Text/Label drawing ist oft der teuerste Teil.

#### Entities Home (List/Grid)
- Dateien:
  - UI: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`, `EntitiesHomeList.swift`, `EntitiesHomeGrid.swift`
  - Data: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Konkrete Gründe:
  - `.task(id: taskToken)` triggert bei Typing + graph switch (debounced 250ms).
  - Loader fetch + optional derived counts (`includeAttributeCounts/includeLinkCounts/includeNotesPreview`).

**Hotspot-Kandidat:**
- `EntitiesHomeLoader.computeAttributeCounts(...)` / `computeLinkCounts(...)` (in `EntitiesHomeLoader.swift`) kann bei großen Graphen teuer sein.
  - Der Loader hat TTL-Caches (8s) – gut, aber Count-Fetches sind immer noch potenziell groß.

#### Entity → Alle Attribute
- Dateien: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift`, `.../EntityAttributesAllListModel.swift`
- Konkrete Gründe:
  - `EntityAttributesAllListModel.rebuild(...)` läuft auf `@MainActor`.
  - `fetchPinnedValuesLookup(...)` führt *pro pinned field* einen Fetch über `MetaDetailFieldValue` aus.
  - `fetchAttributeOwnersWithMedia(...)` kann attachments scannen (je nach Implementierung) um Media flags zu setzen.

**Tradeoff:** UI fühlt sich snappy an, solange dataset moderat; bei sehr vielen Attributes/DetailValues kann „rebuild pro Keystroke“ spürbar werden.

### Sync / Storage

#### GraphID Migrations
- Dateien:
  - `BrainMesh/GraphBootstrap.swift` (Entities/Attributes/Links)
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (Attachments)
- Grund:
  - Queries mit optionalen `graphID`-Konstrukten (OR) sind riskant; Migration reduziert Query-Komplexität.

### Concurrency

#### Detached Tasks im App-Init
- Datei: `BrainMesh/BrainMeshApp.swift`
- Grund:
  - Viele `Task.detached` parallel beim Launch (configure Hydrators/Loaders + account status refresh).

**Risiko:**
- Wenn irgend ein configure-Pfad `ModelContainer` invalid/stateful nutzt → schwer zu debuggen. (Im aktuellen Code wird nur `AnyModelContainer(container)` gesetzt; low risk.)

#### In-flight + Throttling
- Attachment Hydration: `AttachmentHydrator` deduped per id + limiter (`BrainMesh/Attachments/AttachmentHydrator.swift`).
- ImageStore deduped load per path via `InFlightLoader` actor (`BrainMesh/ImageStore.swift`).

---

## Refactor Map (konkret)

> Ziel: compile-time runter, Verantwortlichkeiten klarer, Hot paths „sicher“ (kein Fetch im body, keine unbounded tasks).

### 1) EntityAttributesAllListModel: Data/Compute von UI trennen
- Aktuell:
  - View (`EntityAttributesAllView` in `EntityDetailView+AttributesSection.swift`) + Model (`EntityAttributesAllListModel.swift`) sind stark gekoppelt.
  - Rebuild läuft `@MainActor` und nutzt SwiftData Models direkt.
- Vorschlag (konkreter Cut):
  - `EntityAttributesAllListModel.swift` splitten:
    - `EntityAttributesAllRow.swift` (DTO/Row + SearchIndex building)
    - `EntityAttributesAllPinnedLookup.swift` (Pinned values + Media flags fetch)
    - `EntityAttributesAllSorting.swift` (SortSelection + comparator)
  - Optional: einen **actor Loader** bauen, der `entityID` entgegennimmt und in einem background `ModelContext` value-only Rows lädt.

**Betroffene Dateien:**
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift`
- `BrainMesh/Mainscreen/EntityDetail/EntityAttributesAllListModel.swift`

### 2) GraphCanvas Rendering: Further split + reduce per-frame allocations
- Aktuell: `GraphCanvasView+Rendering.swift` ist sehr groß und baut FrameCaches pro Render.
- Vorschlag:
  - Datei splitten:
    - `GraphCanvasView+EdgeRendering.swift`
    - `GraphCanvasView+NodeRendering.swift`
    - `GraphCanvasView+LabelRendering.swift`
  - Caches stärker inkrementell machen:
    - `screenPoints` nur neu berechnen, wenn `positions`, `pan`, `scale` ändern (nicht jedes Render, falls SwiftUI mehrfach rendert ohne Positionsänderung).

**Betroffene Dateien:**
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- evtl. `BrainMesh/GraphCanvas/GraphCanvasView.swift` (Cache ownership)

### 3) NodeDetailShared: Facade + Unterviews
- Ziel: große Files (`NodeDetailShared+Core.swift`, `+Connections.swift`, etc.) in kleineren Subviews bündeln.
- Vorschlag:
  - `NodeDetailShared` als „Facade View“ behalten.
  - Inhaltliche Sections als eigene Views:
    - `NodeHeaderSectionView`
    - `NodeNotesSectionView`
    - `NodeDetailsSectionView`
    - `NodeConnectionsSectionView`
    - `NodeMediaSectionView`

**Betroffene Dateien:**
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media*.*`

---

## Cache-/Index-Ideen (konkret)

1) **Pinned Values Lookup scopen**
   - `fetchPinnedValuesLookup(...)` könnte zusätzlich nach `graphID` filtern (wenn verfügbar), um cross-graph Daten zu vermeiden.
   - Datei: `BrainMesh/Mainscreen/EntityDetail/EntityAttributesAllListModel.swift`.

2) **Counts precompute für EntitiesHome**
   - Wenn Attribute/Link Counts oft benötigt werden, könnte ein pro-graph „counts table“ (Derived Model) helfen.
   - **Risiko:** zusätzliche Sync/Migration; erst nach Profiling.

3) **GraphCanvas adjacency cache**
   - `LensContext.build(...)` baut adjacency aus `edges` (`GraphCanvasTypes.swift`).
   - Für große `edges` könnte ein cached adjacency in `GraphCanvasScreen` liegen (invalidiert nur, wenn edges ändern).

---

## Risiken & Edge Cases

- **Data Loss / Deletions:**
  - Entity → cascade delete Attributes (`MetaEntity.attributes` deleteRule `.cascade`). (`BrainMesh/Models.swift`)
  - Detail fields / values ebenfalls cascade (`Models.swift`).
  - Attachments sind separat und hängen an ownerID; Lösch-Strategie owner-delete muss Attachments explizit entfernen (**UNKNOWN**: automatische Cleanup-Calls in Delete Flows nicht vollständig geprüft).

- **Legacy `graphID == nil`:**
  - Wenn OR-Predicates reinkommen, kann SwiftData in-memory filtern → besonders gefährlich bei Attachments (external storage). (`AttachmentGraphIDMigration.swift` erklärt das Risiko explizit.)

- **Multi-device / Sync:**
  - `createdAt = .distantPast` für ältere Records (z.B. Graph/Entity) vermeidet „alles neu“ nach Migration.
  - Conflict-Resolution beyond SwiftData/CloudKit: **UNKNOWN**.

- **System Pickers + Security Locks:**
  - `SystemModalCoordinator` + debounce lock in `AppRootView` sind gezielte Fixes für FaceID/Hidden Album Edge Cases.

---

## Observability / Debuggability

- `BMLog` Kategorien (`load`, `expand`, `physics`) in `BrainMesh/Observability/BMObservability.swift`.
- Viele Loader nutzen `os.Logger` (`EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `AttachmentHydrator`, `NodeRenameService`).

**Empfehlung:**
- Bei Hot path Bugs: Duration messen (`BMDuration`) + log start/stop um konkrete ms-Werte zu sehen.

---

## Open Questions (UNKNOWNs)

- Werden Attachments bei Owner-Delete garantiert gelöscht? (Owner wird nicht via Relationship gemanaged; Cleanup muss explizit passieren.)
- Thumbnail Cache policy (Folder, invalidation, size cap) ist nicht vollständig dokumentiert.
- Gibt es geplante CloudKit Sharing/Collaboration Features? (kein `CKShare` Code gefunden)

---

## First 3 Refactors I would do (P0)

### P0.1 — Entity → Alle Attribute: Loader + value-only Rows
- **Ziel:** Typing/Search bleibt flüssig bei vielen Attributes/DetailValues; weniger MainActor Arbeit.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/EntityDetail/EntityAttributesAllListModel.swift`
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift`
- **Risiko:** Mittel (weil UI/Sort/Filter + pinned values + media flags betroffen).
- **Erwarteter Nutzen:** Spürbar weniger UI stalls; klarere Trennung von SwiftData fetch und UI.

### P0.2 — GraphCanvas Rendering: per-frame allocations reduzieren
- **Ziel:** FPS stabilisieren bei großen Graphen; Battery sparen.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - ggf. `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (Cache Ownership)
- **Risiko:** Mittel (Rendering-Bugs möglich; visuelle Regression-Tests nötig).
- **Erwarteter Nutzen:** Mehr Headroom für `maxNodes/maxLinks`, bessere Responsiveness beim Panning/Zoom.

### P0.3 — NodeDetailShared modularisieren
- **Ziel:** Compile-Zeiten runter, Verantwortlichkeiten klarer, weniger Merge-Konflikte.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- **Risiko:** Niedrig–Mittel (primär UI-Split; Logik sollte identisch bleiben).
- **Erwarteter Nutzen:** bessere Wartbarkeit; schnellere Iteration auf Detail-UI.
