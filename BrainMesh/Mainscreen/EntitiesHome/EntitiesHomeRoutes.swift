//
//  EntitiesHomeRoutes.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct EntityDetailRouteView: View {
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
            ContentUnavailableView {
                Label("Entität nicht gefunden", systemImage: "questionmark.square.dashed")
            } description: {
                Text("Diese Entität existiert nicht mehr oder wurde auf einem anderen Gerät gelöscht.")
            }
        }
    }
}
