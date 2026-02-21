# BrainMesh — ARCHITECTURE_NOTES

## Scope & Method
Diese Notizen basieren auf dem aktuellen ZIP-Stand (Dateipfade relativ zu `BrainMesh/`). Fokus strikt nach Priorität:
1) Sync/Storage/Model (SwiftData/CloudKit)
2) Entry Points + Navigation
3) Große Views/Services (Wartbarkeit/Performance)
4) Konventionen + Workflows

Alles, was nicht eindeutig aus dem Code ablesbar ist, ist als **UNKNOWN** markiert und in „Open Questions“ gesammelt.

---

## 1) Entry Points + Navigation
### App Entry
- `BrainMesh/BrainMeshApp.swift`
  - `@main` App
  - Erstellt SwiftData `ModelContainer` mit CloudKit (`ModelConfiguration(... cloudKitDatabase: .automatic)`)
  - Setzt `SyncRuntime.storageMode` (`cloudKit` oder Release-Fallback `localOnly`)
  - Startet `SyncRuntime.refreshAccountStatus()` detached
  - Konfiguriert alle Loader via `AppLoadersConfigurator.configureAllLoaders(with:)`

### Root Navigation
- `BrainMesh/AppRootView.swift`
  - Hosted `ContentView()` und globales App-Lifecycle-Handling:
    - Startup: Graph bootstrap + enforce lock + auto image hydration (24h throttle) + onboarding auto show
    - ScenePhase: debounced background-lock (Workaround gegen Photos/Hidden Album FaceID-Glitches)
  - Global overlays:
    - Onboarding `.sheet` → `BrainMesh/Onboarding/OnboardingSheetView.swift`
    - Unlock `.fullScreenCover` → `BrainMesh/Security/GraphUnlockView.swift`

- `BrainMesh/ContentView.swift`
  - `TabView`:
    - `EntitiesHomeView()`
    - `GraphCanvasScreen()`
    - `GraphStatsView()`
    - `SettingsView()` in `NavigationStack`

---

## 2) Sync/Storage/Model (SwiftData/CloudKit)

### Model schema
- Hauptschema in `BrainMesh/BrainMeshApp.swift`:
  - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`
- Modelle:
  - `BrainMesh/Models.swift` (Graph/Entity/Attribute/Link/Details)
  - `BrainMesh/Attachments/MetaAttachment.swift` (Attachments, `.externalStorage`)

### Storage mode + Diagnostics
- `BrainMesh/Settings/SyncRuntime.swift`
  - `storageMode`: `.cloudKit` vs `.localOnly` (Release fallback)
  - `refreshAccountStatus()` liest `CKContainer.accountStatus()` für Container `iCloud.de.marcfechner.BrainMesh`

### Graph scoping + Migration
- Scoping über `graphID: UUID?` (optional) in nahezu allen Records.
- Migration/Bootstrap:
  - `BrainMesh/GraphBootstrap.swift`
    - `ensureAtLeastOneGraph()`
    - `migrateLegacyRecordsIfNeeded()` setzt `graphID` für `MetaEntity/MetaAttribute/MetaLink` wenn `nil`.
  - Attachments: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (existiert; Details **UNKNOWN** ohne tieferes Lesen)

### Local caches + Hydration
- Images:
  - Cache: `BrainMesh/ImageStore.swift` (Disk: AppSupport/BrainMeshImages, Memory: NSCache)
  - Hydration: `BrainMesh/ImageHydrator.swift` (actor)
    - incremental pass: scan `imageData != nil`, schreibt deterministische JPEGs und setzt `imagePath`
    - run-once-per-launch guard + 24h throttle über `BMImageHydratorLastAutoRun` (`AppRootView.swift`)
- Attachments:
  - Cache: `BrainMesh/Attachments/AttachmentStore.swift` (Disk: AppSupport/BrainMeshAttachments)
  - Hydration: `BrainMesh/Attachments/AttachmentHydrator.swift`
    - `ensureFileURL(...)`: disk check → fetch `MetaAttachment.fileData` in background `ModelContext` → write cache
  - Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` + `AsyncLimiter` (im selben File)

### Risiken (Storage)
- `.externalStorage` für Attachments: gut gegen Record-Size-Druck, aber:
  - **Risk**: große Videos/Files können trotzdem in iCloud/Network problematisch sein; UI muss klaren Fortschritt/Fehler zeigen.
  - In `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` gibt es eine 25MB-Grenze (`maxBytes = 25 * 1024 * 1024`).
- Release-Fallback auf lokal-only:
  - **Risk**: user denkt „Sync aktiv“, wenn UI das nicht klar zeigt. Gegenmaßnahme existiert (SyncRuntime UI).

---

## 3) Big Files List (Top 15 nach Zeilen)
(Quelle: `wc -l` über alle `*.swift` im ZIP)

1. `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` — **630**
2. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` — **532**
3. `BrainMesh/Models.swift` — **515**
4. `BrainMesh/Onboarding/OnboardingSheetView.swift` — **504**
5. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **491**
6. `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` — **469**
7. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411**
8. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **409**
9. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **397**
10. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **394**
11. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388**
12. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388**
13. `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` — **386**
14. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362**
15. `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` — **361**

Warum riskant:
- große Files erhöhen Incremental-Compile-Zeiten, erschweren Reviews und erhöhen „unintended coupling“.
- einige davon liegen außerdem auf Hot Paths (Rendering/Loading/Scrolling).

---

## 4) Hot Path Analyse

### 4.1 Rendering / Scrolling
#### Graph Canvas Rendering
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - **Hotspot-Grund**: per-frame Loops über `drawEdges` und `nodes`, plus `buildFrameCache(...)` pro Frame.
  - **Symptome**: FPS drops bei vielen Nodes/Edges, hoher CPU.
  - **Bereits enthaltene Optimierungen**: frame cache, label offset cache, outgoing note prefilter (Header-Kommentar im File).
  - **Hebel**:
    - Allocation pressure weiter senken (z.B. Dictionaries wiederverwenden oder in persistenten caches halten).
    - Zeichenlogik stärker „early-exit“ (Lens/Visibility) + bessere Batch-Strategien.
    - Physics tick throttling (siehe `GraphCanvasView+Physics.swift`) **UNKNOWN**: genaue Tick-Strategie ohne Detailanalyse.

#### Entity/Attribute Detail Screens
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - **Hotspot-Grund**: ScrollView + viele Sections + Media/Connections/Attributes; `onAppear` triggert async reload.
  - **Risiko**: exzessive View invalidation bei häufigen `@State` Updates (z.B. mediaPreview, expanded sections).
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - analoges Risiko.

#### „Alle Attribute“ (EntityAttributesAll)
- `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`
  - **Hotspot-Grund**: Modell baut/transformiert große Datenmengen für List/Grouping/Pinning.
  - **Typische Failure Modes**: „tippen/search ruckelt“, weil bei jeder Textänderung neu gefetcht/neu gebaut wird.

### 4.2 Sync / Storage
#### Container Init + Fallback
- `BrainMesh/BrainMeshApp.swift`
  - **Hotspot-Grund**: Cold start; CloudKit init kann blockieren/fehlschlagen.
  - DEBUG fatalError kann Entwicklung blockieren, ist aber gewollt.

#### Hydration (Images/Attachments)
- `BrainMesh/ImageHydrator.swift`
  - **Hotspot-Grund**: iteriert über *alle* Entities/Attributes mit `imageData != nil`.
  - **Mitigation**: run-once-per-launch + 24h throttle + limiter (maxConcurrent 1).
- `BrainMesh/Attachments/AttachmentHydrator.swift`
  - **Hotspot-Grund**: fetch external storage bytes + disk write; kann bei vielen sichtbaren Zellen stampeden.
  - **Mitigation**: global limiter (maxConcurrent 2) + inFlight per attachmentID.

### 4.3 Concurrency
#### Pattern: Actor Loader + value snapshot
- Gute Beispiele:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- **Wichtig**: UI navigiert über IDs, nicht über `@Model` Instanzen (siehe Kommentar in `EntitiesHomeRow`).

#### MainActor contention
- Potenzielle Stellen:
  - `.onAppear { Task { @MainActor in await reloadMediaPreview() } }` (EntityDetail) → prüfen, ob intern heavy work macht.
  - `SettingsView` maintenance tasks (rebuild caches) → sicherstellen, dass UI-State nur minimal am MainActor aktualisiert wird.

---

## 5) Refactor-/Optimierungshebel (konkret)

### 5.1 Konkrete Splits (Wartbarkeit + Compile-Time)
- `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` (630)
  - Ziel: incremental rebuild + Cache/Index isolieren.
  - Vorschlag: Split in
    - `EntityAttributesAllListModel.swift` (API/State)
    - `EntityAttributesAllListModel+Cache.swift` (pinned lookups, rowsByID)
    - `EntityAttributesAllListModel+Rebuild.swift` (invalidations)

- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (532)
  - Ziel: Rendering in kleinere, testbare Units.
  - Vorschlag: `GraphCanvasRenderer.swift` (pure functions) + `GraphCanvasRenderCache.swift`.
  - Risiko: medium (perf-sensitive, regressions möglich).

- `BrainMesh/Models.swift` (515)
  - Ziel: Models + helpers trennen.
  - Vorschlag:
    - `Models+Core.swift` (MetaGraph/Entity/Attribute/Link)
    - `Models+Details.swift` (DetailFieldDefinition/Value, DetailFieldType)
    - `Models+Search.swift` (BMSearch, folded fields)
  - Risiko: low (rein organisatorisch).

### 5.2 Cache-/Index-Ideen (Performance)
- EntitiesHome counts
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`:
    - Aktuell: `computeAttributeCounts`/`computeLinkCounts` fetcht alle Attributes/Links und scannt in-memory.
    - Hebel:
      1) Denormalisierte Counts in `MetaEntity` (z.B. `attributeCountCached`, `linkCountCached`) und nur bei Mutationen updaten.
      2) „Relevant IDs“ Query: falls SwiftData `#Predicate` zuverlässig `ids.contains(uuid)` unterstützt (iOS26?), dann server-side filtern.
      3) TTL cache erhöhen oder „search session“ cache (solange foldedSearch nicht leer ist) statt 8s.
    - Risiken: Datenkonsistenz bei Multi-Device Sync; braucht klare Invalidations.

- GraphCanvas neighborhood loader
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`:
    - BFS macht pro Hop einen Link-Fetch mit `frontierIDs.contains(...)`.
    - Hebel: einmaliger Link-Fetch (bis `maxLinks`), BFS rein in-memory.
    - Risiko: memory/CPU; muss mit Limits sauber abgesichert bleiben.

- Detail fields
  - `MetaDetailFieldValue` typed storage ist gut; aber UI-Rendering der Detail-Cards könnte value lookups cachen.
  - Betroffene UI: `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`.

### 5.3 Vereinheitlichungen (Patterns, Services, DI)
- `AnyModelContainer` ist aktuell in `BrainMesh/Attachments/AttachmentHydrator.swift`, wird aber app-weit genutzt.
  - Hebel: in `BrainMesh/Support/AnyModelContainer.swift` verschieben.
- `AsyncLimiter` liegt am File-Ende von `AttachmentThumbnailStore.swift`, wird aber auch in `ImageHydrator.swift` genutzt.
  - Hebel: `BrainMesh/Support/AsyncLimiter.swift`.
- „Loader konfigurieren“: `AppLoadersConfigurator` ist der zentrale Ort → behalten; optional ein Registry-Pattern, falls Loader-Zahl weiter wächst.

---

## 6) Risiken & Edge Cases
- **Migration/graphID**:
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded` deckt Entities/Attributes/Links ab.
  - Attachments/Details: separate Migrationen existieren oder müssen ergänzt werden (**UNKNOWN**: ob DetailFields/Values jemals legacy ohne graphID existieren).
- **Multi-Device + denormalisierte Labels in Links**:
  - `MetaLink` speichert `sourceLabel/targetLabel`. Beim Rename muss das konsistent aktualisiert werden.
  - Service existiert: `NodeRenameService` (konfiguriert in `AppLoadersConfigurator.swift`), Details **UNKNOWN**.
- **Cache coherence**:
  - Image/Attachment cache files können „stale“ werden, wenn `imagePath/localPath` nicht passt.
  - Settings bietet rebuild/clear; wichtig für Support.
- **System picker + Lock**:
  - `AppRootView` hat debounce/grace window gegen Auto-Lock während System-Modals.
  - Risiko: Race Conditions (ScenePhase flips) → schwer zu testen, aber Code adressiert bekannte iOS-Edge.

---

## 7) Observability / Debuggability
- Logger/timing: `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load/expand/physics`
  - `BMDuration` für günstige Duration-Messung.
- Empfehlung:
  - Loader-Durations zentral loggen (EntitiesHome/Canvas/Stats) inklusive `graphID`, node/link counts.
  - UI-Repro Steps für Perf-Probleme dokumentieren (z.B. „Graph mit 2k Links öffnen, Zoom, Selection, Search“).

---

## 8) Open Questions (UNKNOWN)
- Wird `UIBackgroundModes: remote-notification` aktiv genutzt? Kein Code im Repo gefunden.
- Gibt es eine definierte CloudKit Schema/Migrationsstrategie über „automatic“ hinaus? (SwiftData-managed → Details UNKNOWN).
- Wie wird Link-Label Denormalisierung synchronisiert, wenn mehrere Devices gleichzeitig renamen? (Service existiert, aber Mechanik nicht geprüft).
- Unterstützt die App Share/Collab (CKShare)? Kein Code gefunden.
- Verlässlichkeit von `#Predicate` + `Array.contains(UUID)` in iOS 26: teils genutzt, teils kommentiert als „nicht zuverlässig“ (Vergleich `EntitiesHomeLoader.fetchEntities` vs `GraphCanvasDataLoader.loadNeighborhood`).

---

## 9) First 3 Refactors I would do (P0)

### P0.1 — EntityAttributesAllListModel: Incremental rebuild statt Full rebuild
- **Ziel**: Tippen/Search bleibt flüssig; keine kompletten Rebuilds bei jeder Textänderung.
- **Betroffene Dateien**:
  - `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`
  - (neu) `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel+Cache.swift`
  - (neu) `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel+Rebuild.swift`
- **Risiko**: niedrig–mittel (Logik-Invalidation; UI muss behavior-identisch bleiben)
- **Erwarteter Nutzen**: deutlicher FPS-/Latency-Gewinn in „Alle Attribute“ + weniger Energieverbrauch.

### P0.2 — EntitiesHomeLoader: Counts-Strategie skalierbar machen
- **Ziel**: Attribute-/Link-Counts optional anzeigen, ohne „fetch all“ in großen Graphen.
- **Betroffene Dateien**:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (Flags + UI-Hinweise bleiben)
  - Optional: Model-Erweiterung `BrainMesh/Models.swift` (denormalisierte Count-Felder) **ONLY IF** gewünscht.
- **Risiko**: mittel (Konsistenz, Sync, Invalidations)
- **Erwarteter Nutzen**: Home Search/Scroll bleibt stabil, auch bei sehr großen Graphen.

### P0.3 — Concurrency Utilities zentralisieren (AsyncLimiter + AnyModelContainer)
- **Ziel**: Wiederverwendbare Concurrency-Bausteine an einem Ort; geringere Kopplung an Attachments.
- **Betroffene Dateien**:
  - Move: `AnyModelContainer` aus `BrainMesh/Attachments/AttachmentHydrator.swift` → `BrainMesh/Support/AnyModelContainer.swift`
  - Move: `AsyncLimiter` aus `BrainMesh/Attachments/AttachmentThumbnailStore.swift` → `BrainMesh/Support/AsyncLimiter.swift`
  - Update Imports/Refs: `AttachmentHydrator.swift`, `ImageHydrator.swift`, `AttachmentThumbnailStore.swift`
- **Risiko**: niedrig (rein organisatorisch)
- **Erwarteter Nutzen**: bessere Wartbarkeit, klarere Ownership, weniger „why is this type in Attachments?“ Überraschungen.
