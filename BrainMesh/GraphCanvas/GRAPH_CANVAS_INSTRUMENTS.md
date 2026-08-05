# Graph Canvas – Geräteprofiling

Referenz für eine reale Gerätevalidierung: ungefähr 169 Nodes, 433 Links,
1.330 Indexquellen und knapp 400 Medien. Die Canvas-Darstellung behält ihr
Produktionslimit; die größere Physik-/Indexlast wird in den dafür vorgesehenen
synthetischen beziehungsweise Suchindex-Szenarien geprüft.

## Time Profiler

- Release-/Profile-Build auf einem realen iPhone verwenden.
- Nach `GraphPhysicsSimulationActor`, `GraphPhysicsEngine.step` und
  `PhysicsStep` filtern.
- Prüfen, dass Force-, Spatial-Grid-, Integration- und Stability-Arbeit nicht
  unter dem Main Thread erscheint.
- Graph-Tab verlassen, App in den Hintergrund schicken und kontrollieren, dass
  keine weiteren Physics-Step-Samples entstehen.

## SwiftUI

- View Body und View Properties für `GraphCanvasScreen` und
  `GraphCanvasView` aufzeichnen.
- Chat-Draft und Streaming im Root-Chat beziehungsweise Inspector ändern und
  prüfen, dass dies keinen Body-Update des gesamten `GraphCanvasScreen`
  auslöst.
- `SnapshotPublish` mit Canvas-Invalidierungen korrelieren; interne Ticks ohne
  relevante Positionsänderung dürfen keine zusätzliche UI-Publikation erzeugen.

## Core Animation

- Hitches, Frame Duration und Commit-Latenz während Zoom, Pan, Dragging und
  Pinning erfassen.
- Die drei adaptiven Phasen 30/20/12 FPS getrennt betrachten. Ein niedrigeres
  Physics-Publish-Ziel ist kein Core-Animation-Frame-Drop.
- Beim Tabwechsel sicherstellen, dass kein verborgener Canvas weiter Frames
  anfordert.

## Allocations

- Heap-Wachstum über mindestens einen Graphwechsel sowie wiederholtes
  Hinzufügen/Entfernen von Nodes prüfen.
- Auf wiederholte Dictionary-Allokationen innerhalb von `PhysicsStep` achten;
  dort sollen die zusammenhängenden Workspace-Arrays wiederverwendet werden.
- Nach `MemoryPressure` kontrollieren, dass Grid- und Suggestions-Caches
  freigegeben werden und keine Tick-/Worker-Tasks verwaisen.

## Main Thread / Hangs

- Main Thread Checker und Hangs-Instrument parallel zum Time Profiler nutzen.
- Main-Actor-Arbeit soll auf Gesten, sichtbaren View-State, dynamische
  Frame-Vorbereitung und die Übernahme fertiger Positions-Snapshots begrenzt
  sein.
- Graphwechsel, Drag-Ende, Background/Foreground und schneller Wechsel zwischen
  Graph- und Chat-Tab gezielt wiederholen.

Diese Datei dokumentiert Messpunkte, keine gemessenen Geräteergebnisse.
