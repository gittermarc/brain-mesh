//
//  EntityDestinationRouteView.swift
//  BrainMesh
//
//  Query-based route view used for link destinations.
//  (Avoids SwiftData fetches inside SwiftUI body.)
//

import SwiftUI
import SwiftData

struct EntityDestinationRouteView: View {
    @Query private var entities: [MetaEntity]

    init(entityID: UUID) {
        _entities = Query(
            filter: #Predicate<MetaEntity> { e in
                e.id == entityID
            }
        )
    }

    var body: some View {
        if let entity = entities.first {
            EntityDetailView(entity: entity)
        } else {
            NodeMissingView(title: "Entität nicht gefunden")
        }
    }
}
